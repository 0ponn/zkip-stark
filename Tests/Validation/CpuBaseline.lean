/-
Honest CPU proving baseline harness. No GPU. Measures end-to-end STARK
proving and verification wall-clock time of the fused circuit at the
production parameters, so later GPU claims have a real number to beat.
-/

import ZkIpProtocol.MerkleCommitment
import ZkIpProtocol.STARKIntegration

namespace Tests.Validation

open ZkIpProtocol

/-- Eight committed attributes (depth 3); the proof is for index 2 (2500 > 1000).
Returns (threshold, root, leaf, path). -/
def fixture : IO (Nat × ByteArray × ByteArray × MerkleProof) := do
  let leaves := #[500, 1500, 2500, 3500, 4500, 5500, 6500, 7500].map attrLeafBytes
  let root ← buildMerkleTree leaves
  let some path := generateProof leaves 2 | throw (IO.userError "no path for index 2")
  pure (1000, root, leaves[2]!, path)

/-- Time one proof generation, returning (elapsed ms, the proof). -/
def timeProve (threshold : Nat) (root leaf : ByteArray) (path : MerkleProof) : IO (Nat × STARKProof) := do
  let t0 ← IO.monoMsNow
  let some proof ← generateSTARKProof threshold root leaf path
    | throw (IO.userError "proof generation returned none")
  let t1 ← IO.monoMsNow
  return (t1 - t0, proof)

/-- Time verification of one proof, returning (elapsed ms, verified?). -/
def timeVerify (threshold : Nat) (root : ByteArray) (proof : STARKProof) : IO (Nat × Bool) := do
  let t0 ← IO.monoMsNow
  let ok ← verifySTARKProof proof threshold root
  let t1 ← IO.monoMsNow
  return (t1 - t0, ok)

end Tests.Validation

def main : IO Unit := do
  let (threshold, root, leaf, path) ← Tests.Validation.fixture

  -- Warm-up: untimed, absorbs the one-time system build.
  IO.println "Warm-up proof generation (untimed)..."
  let _ ← Tests.Validation.timeProve threshold root leaf path

  let runs := 5
  let mut times : Array Nat := #[]
  let mut lastProof : Option ZkIpProtocol.STARKProof := none
  for i in [0:runs] do
    let (t, proof) ← Tests.Validation.timeProve threshold root leaf path
    IO.println s!"  run {i + 1}/{runs}: {t} ms"
    times := times.push t
    lastProof := some proof

  let sorted := times.qsort (· < ·)
  let median := sorted[runs / 2]!
  IO.println s!"CPU proving times (ms): {sorted.toList}"
  IO.println s!"median proving time: {median} ms"

  let some proof := lastProof
    | throw (IO.userError "no proof was generated")
  let (verifyMs, verified) ← Tests.Validation.timeVerify threshold root proof
  IO.println s!"verify time: {verifyMs} ms, proof size: {proof.proofData.size} bytes"
  if verified then
    IO.println "verification: PASSED"
  else
    throw (IO.userError "verification: FAILED")
