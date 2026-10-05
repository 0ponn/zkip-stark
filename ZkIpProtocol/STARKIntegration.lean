/-
STARK proof integration using ix's Aiur system: prove and verify the fused
predicate + Merkle-membership circuit (`FusedCircuit.lean`) and build
certificates from it.

Write `Aiur.G`, never a bare `G`: importing `FusedCircuit` makes `G` a token.
-/

import ZkIpProtocol.MerkleCommitment
import ZkIpProtocol.CoreTypes
import ZkIpProtocol.DebugLogger
import ZkIpProtocol.FusedCircuit
import Ix.Aiur.Protocol
import Ix.Aiur.Compiler

namespace ZkIpProtocol

open Aiur

/-- One disclosure's private witness: its threshold, its 36-byte
`attrLeaf label value` and its Merkle path. -/
structure DisclosureWitness where
  threshold : Nat
  leaf : ByteArray
  path : MerkleProof
  deriving Inhabited

/-- Prove `attr_i > threshold_i` for every committed `leaf_i` under one `root`,
in one proof.

    Each leaf and path travels as private IO witness. The public claim is
    `[0, funIdx] ++ per item [threshold, a0..a7] ++ [r0..r7, 1]`, where `a0..a7`
    are the words of the leaf's first 32 bytes (the attribute id); no value
    reaches it. `items` is padded to the entry size by repeating the last item.

    Range guards run at the Nat level before any `G.ofNat`, and the circuit is
    executed in the Lean interpreter before `AiurSystem.prove`: a violated
    assert returns `.error` here, whereas the Rust prover aborts the process on
    the same condition. -/
def generateDisclosureProof (root : ByteArray) (items : Array DisclosureWitness)
    : IO (Option STARKProof) := do
  let some n := entrySizeFor items.size | return none
  if root.size != 32 then return none
  for it in items do
    if it.threshold ≥ 2 ^ 32 || it.leaf.size != 36 then
      debugLog "generateDisclosureProof: input outside the circuit domain"
      return none
    if it.path.path.size != keyedDepth then
      debugLog s!"generateDisclosureProof: path has {it.path.path.size} levels, the keyed tree has {keyedDepth}"
      return none
  let e ← fusedEntryFor n
  let padded := padTo items n
  let args := (batchPublicInputs (padded.map fun it => (it.threshold, it.leaf.extract 0 32)) root).map
    Aiur.G.ofNat
  let io := fusedIOItems (padded.map fun it => (it.leaf, it.path))
  match e.bytecode.execute e.funIdx args io with
  | .error err =>
    debugLog s!"circuit execution failed (predicate or membership not satisfied): {err}"
    return none
  | .ok _ => pure ()
  try
    let (claim, proof, _) := AiurSystem.provePadded e.system e.funIdx args io e.floors
    -- Every proof must publish its entry's calibrated shape; anything else
    -- would reveal something about this witness, so it is never released.
    if Aiur.Proof.logDegrees proof != e.shape then
      debugLog "generateDisclosureProof: trace shape differs from the calibrated profile; refusing"
      return none
    return some {
      publicInputs := claim.map (fun g => natToBytes8BE g.val.toNat)
      proofData := proof.toBytes
      vkId := "aiur_vk"
    }
  catch ex =>
    debugLog s!"AiurSystem.prove failed: {ex}"
    return none

/-- Single-disclosure `generateDisclosureProof`. -/
def generateSTARKProof (threshold : Nat) (root : ByteArray) (leaf : ByteArray) (path : MerkleProof)
    : IO (Option STARKProof) :=
  generateDisclosureProof root #[{ threshold, leaf, path }]

/-- Verify a proof against public `(threshold, attribute id)` items and a root.
    The whole expected claim, including the padding, is derived from those
    values, so a proof made for any other threshold, attribute, root, item
    count, function or output fails before the STARK verifier runs.

    `threshold` is a `Nat` so the u32 guard applies before `G.ofNat`, which
    would otherwise wrap `T + 2^64` to `T`. Untrusted proof bytes only ever go
    through `Proof.ofBytesChecked`: `ofBytes` panics on malformed input and ix
    builds with `panic = "abort"`. -/
def verifyDisclosureProof (proof : STARKProof) (items : Array (Nat × ByteArray)) (root : ByteArray)
    : IO Bool := do
  let some n := entrySizeFor items.size | return false
  if root.size != 32 || items.any (fun (t, id) => t ≥ 2 ^ 32 || id.size != 32) then return false
  if proof.publicInputs.size != claimSize n then return false
  if proof.publicInputs.any (·.size != 8) then return false
  let e ← fusedEntryFor n
  let claim : Array Aiur.G := proof.publicInputs.map (fun b => Aiur.G.ofNat (bytesToNat8BE b))
  let expected : Array Nat := #[0, e.funIdx] ++ batchPublicInputs (padTo items n) root ++ #[1]
  if claim.map (·.val) != expected.map (fun n => (Aiur.G.ofNat n).val) then return false
  let aiurProof ← match Aiur.Proof.ofBytesChecked proof.proofData with
    | .ok p => pure p
    | .error _ => return false
  -- Certificates of one entry size all share its trace shape.
  if Aiur.Proof.logDegrees aiurProof != e.shape then return false
  match AiurSystem.verify e.system claim aiurProof with
  | .ok () => return true
  | .error _ => return false

/-- Single-disclosure `verifyDisclosureProof`. -/
def verifySTARKProof (proof : STARKProof) (threshold : Nat) (attrId root : ByteArray) : IO Bool :=
  verifyDisclosureProof proof #[(threshold, attrId)] root

/-- Certificate for `attributes[i] > threshold` for every `(i, predicate)` in
    `requests` (1 to `maxDisclosures`, distinct indices), in one proof under the
    label-keyed Merkle root of all of `ixon`'s attributes.

    The root is always recomputed from the attributes, which must have
    distinct labels in distinct slots (`keyedLeaves`); a non-empty
    `ixon.merkleRoot` that differs is a caller error and yields `none`. The
    certificate's `commitment` is the recomputed root. Only `>` is provable. -/
def generateCertificate (ixon : Ixon) (requests : Array (Nat × IPPredicate))
    : IO (Option ZKCertificate) := do
  if requests.isEmpty || requests.size > maxDisclosures then return none
  let idxs := requests.map (·.1)
  if idxs.toList.eraseDups.length != idxs.size then return none
  if requests.any (fun (_, p) => p.operator != ">" || p.threshold ≥ 2 ^ 32) then return none
  if ixon.attributes.any (·.value ≥ 2 ^ 32) || ixon.attributes.size > maxAttributes then return none
  let .ok leaves := keyedLeaves ixon.attributes | return none
  let root := keyedRoot leaves
  if !ixon.merkleRoot.isEmpty && ixon.merkleRoot != root then return none
  let mut items : Array DisclosureWitness := #[]
  let mut disclosures : Array Disclosure := #[]
  for (i, predicate) in requests do
    let some attr := ixon.attributes[i]? | return none
    let path := keyedProof leaves (labelSlot attr.label)
    items := items.push { threshold := predicate.threshold, leaf := attr.leaf, path }
    disclosures := disclosures.push { attributeLabel := attr.label, predicate }
  let some proof ← generateDisclosureProof root items | return none
  return some { ipId := ixon.id, commitment := root, disclosures, proof, timestamp := ixon.timestamp }

/-- Single-disclosure `generateCertificate`. -/
def generateCertificateWithSTARK (ixon : Ixon) (predicate : IPPredicate) (attributeIndex : Nat)
    : IO (Option ZKCertificate) :=
  generateCertificate ixon #[(attributeIndex, predicate)]

end ZkIpProtocol
