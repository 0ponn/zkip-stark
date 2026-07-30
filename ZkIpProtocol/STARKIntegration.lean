/-
STARK Proof Integration using Ix's Aiur system.
Converts PredicateCircuit to Aiur bytecode and generates actual STARK proofs.
-/

import ZkIpProtocol.MerkleCommitment
import ZkIpProtocol.CoreTypes
import ZkIpProtocol.DebugLogger
import Ix.Aiur.Protocol
import Ix.Aiur.Bytecode
import Ix.Aiur.Term
import Ix.Aiur.Simple
import Ix.Aiur.Compile

namespace ZkIpProtocol

open Aiur
open Aiur.Bytecode
open ZkIpProtocol

/-- Goldilocks field element type -/
abbrev G := Aiur.G

/-- PredicateCircuit: Circuit structure for predicate checking -/
structure PredicateCircuit where
  attributeValue : Nat
  merkleRoot : ByteArray
  threshold : Nat
  operator : String
  merkleProof : MerkleProof
  output : Bool
  deriving Repr, Inhabited

namespace PredicateCircuit

/-- Verify Merkle commitment in circuit -/
def verifyMerkleCommitment (circuit : PredicateCircuit) : Bool :=
  circuit.merkleProof.rootHash == circuit.merkleRoot

end PredicateCircuit

/-- Application Binary Interface (ABI) for circuit public inputs -/
structure CircuitABI where
  funIdx : Bytecode.FunIdx
  privateInputCount : Nat
  publicInputCount : Nat
  outputCount : Nat
  claimSize : Nat
  deriving Repr

namespace CircuitABI

/-- Calculate claim size from ABI -/
def totalClaimSize (abi : CircuitABI) : Nat :=
  2 + abi.privateInputCount + abi.publicInputCount + abi.outputCount

end CircuitABI

/-- Convert PredicateCircuit to Aiur bytecode -/
def PredicateCircuit.toAiurBytecode (_circuit : PredicateCircuit) : Except String (Bytecode.Toplevel × CircuitABI) := do
  let mainFunctionName := Global.mk (.mkSimple "predicateCheck")
  let mainFunction : Aiur.Function := {
    name := mainFunctionName
    inputs := [
      ((Aiur.Local.str "merkleRoot"), Aiur.Typ.field),
      ((Aiur.Local.str "threshold"), Aiur.Typ.field),
      ((Aiur.Local.str "attr"), Aiur.Typ.field)
    ]
    output := Aiur.Typ.field
    body := Aiur.Term.ret (Aiur.Term.var (Aiur.Local.str "attr"))
    unconstrained := false
  }

  let toplevel : Aiur.Toplevel := { dataTypes := #[], functions := #[mainFunction] }
  let typedDecls ← Aiur.Toplevel.checkAndSimplify toplevel |>.mapError (fun err => s!"Check failed: {err}")
  let bytecodeToplevel := Aiur.TypedDecls.compile typedDecls

  let abi : CircuitABI := {
    funIdx := 0
    privateInputCount := 1
    publicInputCount := 2
    outputCount := 1
    claimSize := 6
  }
  return (bytecodeToplevel, abi)

/--
  Commitment parameters. Shared by the prover and the verifier so the two
  cannot drift apart.
-/
def commitmentParameters : CommitmentParameters := { logBlowup := 2 }

/--
  FRI parameters. Shared by the prover and the verifier.

  These MUST be identical on both sides. They previously were not: proofs were
  generated with `numQueries := 100` and verified with `numQueries := 20`.
  Defining them once removes that class of bug.
-/
def friParameters : FriParameters := {
  logFinalPolyLen := 0
  numQueries := 100
  proofOfWorkBits := 20
}

/--
  Fixed-width 8-byte big-endian encoding of a `Nat`, the inverse of
  `byteArrayPrefixToNat`.

  `CoreTypes.natToByteArray` produces a *minimal-length* encoding, but every
  reader in this codebase (`verifySTARKProof`, `Api.handleVerify`) requires at
  least 8 bytes and reads exactly the first 8. Those two conventions do not
  round-trip: a claim element below 2^56 serialises to fewer than 8 bytes and is
  then rejected by the reader. Encoding claim elements at fixed width fixes the
  round trip.
-/
def natToByteArray8 (n : Nat) : ByteArray :=
  ⟨#[ ((n >>> 56) % 256).toUInt8,
      ((n >>> 48) % 256).toUInt8,
      ((n >>> 40) % 256).toUInt8,
      ((n >>> 32) % 256).toUInt8,
      ((n >>> 24) % 256).toUInt8,
      ((n >>> 16) % 256).toUInt8,
      ((n >>> 8)  % 256).toUInt8,
      (n % 256).toUInt8 ]⟩

/-- Big-endian read of the first 8 bytes of a `ByteArray` as a `Nat`. -/
def byteArrayPrefixToNat (bytes : ByteArray) : Nat :=
  if bytes.size >= 8 then
    (bytes[0]!.toNat <<< 56) + (bytes[1]!.toNat <<< 48) + (bytes[2]!.toNat <<< 40) +
    (bytes[3]!.toNat <<< 32) + (bytes[4]!.toNat <<< 24) + (bytes[5]!.toNat <<< 16) +
    (bytes[6]!.toNat <<< 8) + bytes[7]!.toNat
  else
    0

/--
  Derive the public inputs for a predicate proof from the hashed Merkle root and
  the threshold.

  The prover and the verifier MUST both go through this function. Previously the
  prover built this array inline and the verifier passed `#[]`, so the two sides
  had no agreed notion of what was being proven.

  NOTE: only the first 8 bytes of the root participate. That is a truncation to
  64 bits and is not adequate for binding — see REMEDIATION.md (R1, R2). It is
  preserved here to match the existing wire format rather than to endorse it.
-/
def predicatePublicInputs (merkleRootHash : ByteArray) (threshold : Nat) : Array G :=
  #[ G.ofNat (byteArrayPrefixToNat merkleRootHash), G.ofNat threshold ]

/--
  Check that `expected` appears as a contiguous slice of `claim` starting at
  `offset`.

  Used by the verifier to confirm that the claim inside a proof matches the
  public inputs the *caller* supplied, rather than trusting the proof's own
  account of what it proves.
-/
def claimMatchesPublicInputs (claim : Array G) (offset : Nat) (expected : Array G) : Bool :=
  if offset + expected.size > claim.size then
    false
  else
    (List.range expected.size).all (fun i =>
      match claim[offset + i]?, expected[i]? with
      | some actual, some want => actual.val.toNat == want.val.toNat
      | _, _ => false)

/-- Generate actual STARK proof using Aiur system -/
def generateSTARKProof
  (circuit : PredicateCircuit)
  (publicInputs : Array G)
  (privateInputs : Array G)
  : IO (Option STARKProof) := do
  let (bytecodeToplevel, abi) ← match circuit.toAiurBytecode with
    | .ok result => pure result
    | .error err =>
        debugLog s!"Compilation failed: {err}"
        return none

  debugLog s!"Circuit compiled: funIdx={abi.funIdx}, publicInputs={abi.publicInputCount}, privateInputs={abi.privateInputCount}"

  let system := AiurSystem.build bytecodeToplevel commitmentParameters
  debugLog "AiurSystem built"

  let friParams := friParameters

  let funIdx : Bytecode.FunIdx := abi.funIdx
  let args : Array G := publicInputs ++ privateInputs
  let ioBuffer : IOBuffer := default

  debugLog s!"About to call AiurSystem.prove..."
  debugLog s!"funIdx={funIdx}, args.size={args.size}"
  debugLog s!"publicInputs.size={publicInputs.size}, privateInputs.size={privateInputs.size}"
  debugLog s!"Expected: publicInputs={abi.publicInputCount}, privateInputs={abi.privateInputCount}"

  -- Validate argument order
  if args.size != abi.publicInputCount + abi.privateInputCount then
    debugLog s!"ERROR: Argument count mismatch! Expected {abi.publicInputCount + abi.privateInputCount}, got {args.size}"
    return none

  try
    let (claim, proof, _) := AiurSystem.prove system friParams funIdx args ioBuffer
    debugLog s!"Proof generated successfully! Claim size: {claim.size}"
    let proofBytes := proof.toBytes
    return some {
      -- Fixed width, so the claim survives the round trip back through
      -- `verifySTARKProof`, which reads exactly 8 bytes per element.
      publicInputs := claim.map (fun g => natToByteArray8 g.val.toNat)
      proofData := proofBytes
      vkId := "aiur_vk"
    }
  catch ex =>
    debugLog s!"Stack overflow in generateSTARKProof: {ex}"
    return none

/--
  Verify a STARK proof using the Aiur system.

  NOTE: this function is not yet meaningful. The circuit it verifies against
  (`predicateCheck`) enforces no constraints — its body is `ret attr` — so a
  successful return says only that a well-formed proof exists for a trivially
  true statement. See REMEDIATION.md (R2).

  The checks below are still worth having, because they were absent: the
  verifier previously discarded the caller's `publicInputs` entirely and
  reconstructed the claim from the proof itself, which meant a proof attested to
  whatever it claimed to attest to.
-/
def verifySTARKProof
  (proof : STARKProof)
  (publicInputs : Array G)
  (circuit : PredicateCircuit)
  : IO Bool := do
  -- An empty proof is not a proof. Reject before doing any work.
  if proof.proofData.isEmpty then
    debugLog "Rejected: empty proof data"
    return false

  let aiurProof := Aiur.Proof.ofBytes proof.proofData
  let (bytecodeToplevel, abi) ← match circuit.toAiurBytecode with
    | .ok result => pure result
    | .error _err => return false

  let system := AiurSystem.build bytecodeToplevel commitmentParameters

  let mut claim : Array G := #[]
  for bytes in proof.publicInputs do
    if bytes.size >= 8 then
      let val := (bytes[0]!.toNat <<< 56) + (bytes[1]!.toNat <<< 48) + (bytes[2]!.toNat <<< 40) +
                 (bytes[3]!.toNat <<< 32) + (bytes[4]!.toNat <<< 24) + (bytes[5]!.toNat <<< 16) +
                 (bytes[6]!.toNat <<< 8) + bytes[7]!.toNat
      claim := claim.push (G.ofNat val)
    else return false

  -- The claim must have the shape this circuit's ABI declares.
  if claim.size != abi.claimSize then
    debugLog s!"Rejected: claim size {claim.size}, expected {abi.claimSize}"
    return false

  -- The claim must agree with the public inputs the CALLER supplied. Aiur lays
  -- the claim out as [functionChannel, funIdx, args..., outputs...], and
  -- `generateSTARKProof` passes args as `publicInputs ++ privateInputs`, so the
  -- caller's public inputs begin at index 2.
  --
  -- Without this check the verifier never consults the Merkle root it was
  -- handed, which is what made `testAdSwitchResistance` unable to fail.
  if !claimMatchesPublicInputs claim 2 publicInputs then
    debugLog "Rejected: claim does not match caller-supplied public inputs"
    return false

  match AiurSystem.verify system friParameters claim aiurProof with
  | .ok () => return true
  | .error _ => return false

/-- Helper: Verify attribute in Merkle tree -/
def verifyAttributeInMerkleTree (root : ByteArray) (_attr : IPAttribute) (proof : MerkleProof) : Bool :=
  -- Simplified verification: just check that the proof root matches the tree root
  -- In production, this would verify the full Merkle path
  proof.rootHash == root

/-- Enhanced certificate generation with actual STARK proofs -/
def generateCertificateWithSTARK
  [Hash ByteArray]
  (ixon : Ixon)
  (predicate : IPPredicate)
  (privateAttribute : Nat)
  (ipData : Array ByteArray)
  (_attributeIndex : Nat)
  : IO (Option ZKCertificate) := do

  -- Generate Merkle proof - use the actual Merkle root from ixon
  let merkleProof : MerkleProof := {
    rootHash := ixon.merkleRoot
    path := #[]
    isLeft := #[]
  }

  -- Verify that privateAttribute satisfies the predicate
  -- Create a synthetic attribute to check predicate evaluation
  let syntheticAttr := IPAttribute.performance privateAttribute
  if !IPPredicate.evaluate predicate syntheticAttr then
    return none

  -- Find matching attribute if available (for Merkle verification)
  -- If no attribute matches, we can still proceed if privateAttribute satisfies predicate
  let attrForMerkle := match ixon.attributes.find? (fun attr =>
    IPPredicate.evaluate predicate attr) with
    | some attr => attr
    | none => syntheticAttr

  if !verifyAttributeInMerkleTree ixon.merkleRoot attrForMerkle merkleProof then
    return none

  let circuit : PredicateCircuit := {
    attributeValue := privateAttribute
    merkleRoot := ixon.merkleRoot
    threshold := predicate.threshold
    operator := predicate.operator
    merkleProof
    output := true
  }

  if !circuit.verifyMerkleCommitment then
    return none

  let publicInputs : Array G :=
    predicatePublicInputs (Hash.hash ixon.merkleRoot) predicate.threshold

  -- WARNING: "private" is aspirational. Aiur's `prove` takes one flat argument
  -- list and places all of it in the public claim, so this value is published.
  -- See REMEDIATION.md (R3).
  let privateInputs : Array G := #[ G.ofNat privateAttribute ]

  -- Attempt proof generation with conditional debug logging
  let starkProof? ← generateSTARKProof circuit publicInputs privateInputs
  match starkProof? with
  | some proof =>
    debugLog "✓ Full STARK proof generated successfully!"
    return some {
      ipId := ixon.id
      commitment := ixon.merkleRoot
      predicate
      proof
      timestamp := ixon.timestamp
    }
  | none =>
    -- Fail closed.
    --
    -- This branch previously returned `some` certificate carrying an empty
    -- `proofData` and `vkId := "mock_vk_generation_failed"`. Callers that
    -- pattern-match on `some` accepted it as a valid certificate, so a proof
    -- failure silently produced a credential-shaped object with no proof in it.
    --
    -- A certificate we could not prove is not a certificate.
    debugLog "✗ STARK proof generation failed — returning none"
    return none

end ZkIpProtocol
