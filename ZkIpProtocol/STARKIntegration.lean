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

/-- Prove `attr > threshold` for the committed `leaf` under `root`.

    `leaf` is the 4-byte `attrLeafBytes` of the private value and `path` its
    Merkle path; both travel as private IO witness and never reach the claim.
    The public claim is `[0, funIdx, threshold, r0..r7, 1]`.

    Range guards run at the Nat level before any `G.ofNat`, and the circuit is
    executed in the Lean interpreter before `AiurSystem.prove`: a violated
    assert returns `.error` here, whereas the Rust prover aborts the process on
    the same condition. -/
def generateSTARKProof (threshold : Nat) (root : ByteArray) (leaf : ByteArray) (path : MerkleProof)
    : IO (Option STARKProof) := do
  if threshold ≥ 2 ^ 32 || leaf.size != 4 || root.size != 32 then
    debugLog "generateSTARKProof: input outside the circuit domain"
    return none
  if path.path.size > maxDepth then
    debugLog s!"generateSTARKProof: Merkle depth {path.path.size} exceeds the cap {maxDepth}"
    return none
  let fs ← fusedSystem
  let args := (fusedPublicInputs threshold root).map Aiur.G.ofNat
  let io := fusedIO leaf path
  match fs.bytecode.execute fs.funIdx args io with
  | .error e =>
    debugLog s!"circuit execution failed (predicate or membership not satisfied): {e}"
    return none
  | .ok _ => pure ()
  try
    let (claim, proof, _) := AiurSystem.provePadded fs.system fs.funIdx args io fs.floors
    -- Every proof must publish the calibrated shape; anything else would
    -- reveal something about this witness, so it is never released.
    if Aiur.Proof.logDegrees proof != fs.shape then
      debugLog "generateSTARKProof: trace shape differs from the calibrated profile; refusing"
      return none
    return some {
      publicInputs := claim.map (fun g => natToBytes8BE g.val.toNat)
      proofData := proof.toBytes
      vkId := "aiur_vk"
    }
  catch ex =>
    debugLog s!"AiurSystem.prove failed: {ex}"
    return none

/-- Verify a certificate proof against the certificate's own `threshold` and
    `commitment`. The whole expected claim is derived from those two values,
    so a proof made for any other threshold, root, function or output fails
    before the STARK verifier runs.

    `threshold` is a `Nat` so the u32 guard applies before `G.ofNat`, which
    would otherwise wrap `T + 2^64` to `T`. Untrusted proof bytes only ever go
    through `Proof.ofBytesChecked`: `ofBytes` panics on malformed input and ix
    builds with `panic = "abort"`. -/
def verifySTARKProof (proof : STARKProof) (threshold : Nat) (root : ByteArray) : IO Bool := do
  if threshold ≥ 2 ^ 32 || root.size != 32 then return false
  if proof.publicInputs.size != fusedClaimSize then return false
  if proof.publicInputs.any (·.size != 8) then return false
  let fs ← fusedSystem
  let claim : Array Aiur.G := proof.publicInputs.map (fun b => Aiur.G.ofNat (bytesToNat8BE b))
  let expected : Array Nat := #[0, fs.funIdx] ++ fusedPublicInputs threshold root ++ #[1]
  if claim.map (·.val) != expected.map (fun n => (Aiur.G.ofNat n).val) then return false
  let aiurProof ← match Aiur.Proof.ofBytesChecked proof.proofData with
    | .ok p => pure p
    | .error _ => return false
  -- Certificates in circulation all share one trace shape.
  if Aiur.Proof.logDegrees aiurProof != fs.shape then return false
  match AiurSystem.verify fs.system claim aiurProof with
  | .ok () => return true
  | .error _ => return false

/-- Certificate for `attributes[attributeIndex] > threshold` under the Merkle
    root of all of `ixon`'s attributes.

    The root is always recomputed from the attributes; a non-empty
    `ixon.merkleRoot` that differs is a caller error and yields `none`. The
    certificate's `commitment` is the recomputed root. Only `>` is provable. -/
def generateCertificateWithSTARK (ixon : Ixon) (predicate : IPPredicate) (attributeIndex : Nat)
    : IO (Option ZKCertificate) := do
  if predicate.operator != ">" then return none
  if predicate.threshold ≥ 2 ^ 32 then return none
  if ixon.attributes.any (·.value ≥ 2 ^ 32) then return none
  let leaves := ixon.attributes.map (attrLeafBytes ·.value)
  let root ← buildMerkleTree leaves
  if !ixon.merkleRoot.isEmpty && ixon.merkleRoot != root then return none
  let some leaf := leaves[attributeIndex]? | return none
  let some path := generateProof leaves attributeIndex | return none
  let some proof ← generateSTARKProof predicate.threshold root leaf path | return none
  return some { ipId := ixon.id, commitment := root, predicate, proof, timestamp := ixon.timestamp }

end ZkIpProtocol
