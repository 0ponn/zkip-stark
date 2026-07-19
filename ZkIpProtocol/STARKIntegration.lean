/-
STARK Proof Integration using Ix's Aiur system.
Converts PredicateCircuit to Aiur bytecode and generates actual STARK proofs.
-/

import ZkIpProtocol.MerkleCommitment
import ZkIpProtocol.CoreTypes
import ZkIpProtocol.DebugLogger
import Ix.Aiur.Protocol
import Ix.Aiur.Stages.Bytecode
import Ix.Aiur.Stages.Source
import Ix.Aiur.Stages.Simple
import Ix.Aiur.Compiler

namespace ZkIpProtocol

open Aiur
open Aiur.Bytecode
open ZkIpProtocol

/-- Goldilocks field element type -/
abbrev G := Aiur.G

/-- Shared STARK commitment parameters -/
def starkCommitmentParams : CommitmentParameters := { logBlowup := 2, capHeight := 0 }

/-- Shared STARK FRI parameters -/
def starkFriParams : FriParameters := {
  logFinalPolyLen := 0
  maxLogArity := 1
  numQueries := 100
  commitProofOfWorkBits := 20
  queryProofOfWorkBits := 0
}

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

/-- Calculate claim size from ABI.

    The claim layout is `[functionChannel, funIdx] ++ args ++ output`
    (see `generateSTARKProof`); `args` carries only the public inputs, since
    private IO-witness inputs (like `attr`) never land in `args` or the
    claim. `privateInputCount` does NOT contribute here. -/
def totalClaimSize (abi : CircuitABI) : Nat :=
  2 + abi.publicInputCount + abi.outputCount

end CircuitABI

/-- Convert PredicateCircuit to Aiur bytecode.

    The circuit CONSTRAINS the predicate `attr > threshold`. It is the manual
    `Source.Term` encoding of the Aiur surface program

        pub fn predicate_check(threshold: G) -> G {
          let attr = io_read(0, 0, 1);
          assert_eq!(u32_less_than(threshold, attr[0]), 1);
          1
        }

    `attr` is read from private IO channel 0 (offset 0, length 1) rather than
    taken as a function argument, so it never lands in the claim
    (`[channel, funIdx] ++ args ++ output`) or the emitted proof. The prover
    supplies it out-of-band via `IOBuffer` (see `generateSTARKProof`).

    `u32_less_than(threshold, attr)` is 1 iff `threshold < attr` (i.e.
    `attr > threshold`); `assert_eq!(…, 1)` binds that to hold, so an honest
    prover cannot satisfy the trace for a false predicate and no proof exists
    for it. Output is the constant `1`.

    (Authored via explicit `Term` constructors rather than the `⟦ … ⟧` DSL
    because `Ix.Aiur.Meta` registers `G` as a syntax token, which would clash
    with the pervasive `abbrev G := Aiur.G` in this non-module file.) -/
def PredicateCircuit.toAiurBytecode (_circuit : PredicateCircuit)
    : Except String (Bytecode.Toplevel × CircuitABI) := do
  let mainFunctionName := Global.mk (.mkSimple "predicate_check")
  let threshold := Aiur.Source.Term.var (Aiur.Local.str "threshold")
  let attrLocal := Aiur.Local.str "attr"
  let attrVar := Aiur.Source.Term.var attrLocal
  let zero := Aiur.Source.Term.field (Aiur.G.ofNat 0)
  let one := Aiur.Source.Term.field (Aiur.G.ofNat 1)
  -- let attr = io_read(channel: 0, idx: 0, len: 1);
  -- assert_eq!(u32_less_than(threshold, attr[0]), 1); 1
  let attrRead := Aiur.Source.Term.ioRead zero zero 1
  let body := Aiur.Source.Term.let (Aiur.Pattern.var attrLocal) attrRead
    (Aiur.Source.Term.assertEq
      (Aiur.Source.Term.u32LessThan threshold (Aiur.Source.Term.get attrVar 0)) one one)
  let inputs : List (Aiur.Local × Aiur.Typ) :=
    [ ((Aiur.Local.str "threshold"), Aiur.Typ.field) ]
  -- `monoEntry` requires a pointer-free signature proof; discharge it at
  -- runtime via the decidability instance (all inputs/output are `.field`).
  if h : Aiur.Source.sigPointerFree inputs Aiur.Typ.field = true then
    let mainFunction := Aiur.Source.Function.monoEntry mainFunctionName inputs Aiur.Typ.field body h
    let toplevel : Aiur.Source.Toplevel :=
      { dataTypes := #[], typeAliases := #[], functions := #[mainFunction] }
    let compiled ← toplevel.compile
    let funIdx ← match compiled.getFuncIdx mainFunctionName.toName with
      | some idx => pure idx
      | none => .error "predicate_check function not found after compilation"
    let abi : CircuitABI := {
      funIdx
      -- `attr` is a private IO witness, not a function arg: it does not
      -- contribute to `args` or the claim, only to the `IOBuffer`.
      privateInputCount := 1
      publicInputCount := 1
      outputCount := 1
      claimSize := 2 + 1 + 1
    }
    return (compiled.bytecode, abi)
  else
    .error "predicate circuit signature must be pointer-free"

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

  let system := AiurSystem.build bytecodeToplevel starkCommitmentParams starkFriParams
  debugLog "AiurSystem built"

  let funIdx : Bytecode.FunIdx := abi.funIdx
  -- Only public inputs are passed as function args; `privateInputs` (the
  -- secret attribute) is carried out-of-band via the IO buffer on channel 0,
  -- matching the `io_read(0, 0, len)` the circuit body issues. This keeps
  -- private data out of `args` and thus out of the claim
  -- (`[channel, funIdx] ++ args ++ output`).
  let args : Array G := publicInputs
  let ioBuffer : IOBuffer := ⟨.ofList [(G.ofNat 0, privateInputs)], .ofList []⟩

  debugLog s!"About to call AiurSystem.prove..."
  debugLog s!"funIdx={funIdx}, args.size={args.size}"
  debugLog s!"publicInputs.size={publicInputs.size}, privateInputs.size={privateInputs.size}"
  debugLog s!"Expected: publicInputs={abi.publicInputCount}, privateInputs={abi.privateInputCount}"

  -- Validate argument order: `args` carries only public inputs now.
  if args.size != abi.publicInputCount then
    debugLog s!"ERROR: Argument count mismatch! Expected {abi.publicInputCount}, got {args.size}"
    return none
  if privateInputs.size != abi.privateInputCount then
    debugLog s!"ERROR: Private IO witness count mismatch! Expected {abi.privateInputCount}, got {privateInputs.size}"
    return none

  -- Range-check every input against the u32 domain the predicate's
  -- `u32_less_than(threshold, attr)` operates over. The pure Lean bytecode
  -- interpreter below (`execute`) silently truncates out-of-range values via
  -- `UInt32` conversion, so it will NOT catch this; `AiurSystem.prove`'s Rust
  -- synthesis path does the real bounds check (`u32::try_from`) and ABORTS
  -- the process on failure (`ExecError::U32OutOfRange`), which is not a
  -- catchable Lean exception. Reject out-of-range values here, before either.
  if (publicInputs ++ privateInputs).any (fun g => g.n ≥ (2 ^ 32 : Nat)) then
    debugLog s!"ERROR: input value out of u32 range (>= 2^32); refusing to call the prover"
    return none

  -- Honest witness generation: execute the circuit first. If a constraint
  -- (e.g. the `assert_eq!` enforcing `attr > threshold`) is violated, the pure
  -- Lean interpreter returns `.error` here — no proof exists for a false
  -- predicate. This must precede `AiurSystem.prove`, whose Rust synthesis
  -- ABORTS the process (not a catchable Lean exception) on an assert mismatch.
  match bytecodeToplevel.execute funIdx args ioBuffer with
  | .error e =>
    debugLog s!"Circuit execution failed (predicate not satisfied): {e}"
    return none
  | .ok _ => pure ()

  try
    let (claim, proof, _) := AiurSystem.prove system funIdx args ioBuffer
    debugLog s!"Proof generated successfully! Claim size: {claim.size}"
    let proofBytes := proof.toBytes
    return some {
      publicInputs := claim.map (fun g =>
        let val := g.val.toNat
        natToBytes8BE val
      )
      proofData := proofBytes
      vkId := "aiur_vk"
    }
  catch ex =>
    debugLog s!"Stack overflow in generateSTARKProof: {ex}"
    return none

/-- Verify STARK proof using Aiur system.

    Binds verification to the caller's expected `publicInputs`: the claim
    reconstructed from `proof.publicInputs` is checked against `AiurSystem`
    as before, but the proof is only accepted if its own public args (the
    `threshold` at claim position 2, per the `[functionChannel, funIdx] ++
    args ++ output` layout `generateSTARKProof` builds) equal what the
    caller expects. Without this, a proof generated for one threshold would
    verify against a caller expecting a different threshold.

    `publicInputs.size` is required to equal `abi.publicInputCount` (rather
    than just being sliced into the claim): otherwise `publicInputs := #[]`
    would compare a zero-length slice against a zero-length caller array and
    vacuously "match", accepting any threshold. -/
def verifySTARKProof
  (proof : STARKProof)
  (publicInputs : Array G)
  (circuit : PredicateCircuit)
  : IO Bool := do
  let aiurProof := Aiur.Proof.ofBytes proof.proofData
  let (bytecodeToplevel, abi) ← match circuit.toAiurBytecode with
    | .ok (toplevel, abi) => pure (toplevel, abi)
    | .error _err => return false

  -- Reject arity mismatches up front: a caller passing fewer (or more)
  -- public inputs than the circuit's ABI declares must not be able to
  -- vacuously satisfy the claim-slice comparison below.
  if publicInputs.size != abi.publicInputCount then return false

  let system := AiurSystem.build bytecodeToplevel starkCommitmentParams starkFriParams

  let mut claim : Array G := #[]
  for bytes in proof.publicInputs do
    if bytes.size >= 8 then
      let val := (bytes[0]!.toNat <<< 56) + (bytes[1]!.toNat <<< 48) + (bytes[2]!.toNat <<< 40) +
                 (bytes[3]!.toNat <<< 32) + (bytes[4]!.toNat <<< 24) + (bytes[5]!.toNat <<< 16) +
                 (bytes[6]!.toNat <<< 8) + bytes[7]!.toNat
      claim := claim.push (G.ofNat val)
    else return false

  -- The reconstructed claim must have exactly the size the ABI predicts;
  -- otherwise the slice below could silently succeed against a truncated
  -- or padded claim.
  if claim.size != abi.totalClaimSize then return false

  -- `args` (the caller-supplied public inputs, i.e. `threshold`) occupy
  -- claim[2 .. 2 + publicInputs.size); reject up front if they don't match
  -- what the caller expects, before trusting the proof at all. Compared via
  -- `.val : UInt64` (which has `BEq`) since `G` itself has no `BEq` instance.
  let argsStart := 2
  let claimArgs := (claim.extract argsStart (argsStart + publicInputs.size)).map (·.val)
  let expectedArgs := publicInputs.map (·.val)
  if claimArgs != expectedArgs then return false

  match AiurSystem.verify system claim aiurProof with
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

  -- Nat-level range guard, BEFORE any `G.ofNat` conversion. `G.ofNat`
  -- reduces mod the Goldilocks prime (~2^64): a Nat threshold/attribute at
  -- or above that modulus would silently wrap to a small field element,
  -- letting a false Nat-level claim (e.g. threshold = 2^64) sail past the
  -- circuit's `< 2^32` domain check, which only ever sees the
  -- already-wrapped field value. Reject out-of-range Nats here, at the
  -- boundary, before they are ever converted.
  if predicate.threshold ≥ (2 ^ 32 : Nat) || privateAttribute ≥ (2 ^ 32 : Nat) then
    debugLog s!"✗ Rejected: threshold or privateAttribute out of u32 range (>= 2^32)"
    return none

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

  -- Only `threshold` is a public input to the M1 circuit (`predicate_check(threshold) -> G`,
  -- with `attr` read privately via IO channel 0). The Merkle root is NOT part of the circuit's
  -- ABI yet — Merkle-root binding into the STARK claim is a later M2 milestone, not M1. Passing
  -- it here as a second public input would make `args.size != abi.publicInputCount` and
  -- `generateSTARKProof` reject the call before ever reaching the prover.
  let publicInputs : Array G := #[ G.ofNat predicate.threshold ]

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
    -- No fake certificates: a failed real proof means no certificate, not
    -- a mock one with empty `proofData` that would silently "verify" as
    -- if a real proof existed.
    debugLog "✗ Full STARK proof generation failed"
    return none

end ZkIpProtocol
