/-
Honest CPU proving baseline harness. No GPU. Measures end-to-end STARK
proving and verification wall-clock time of the fused circuit at the
production parameters, so later GPU claims have a real number to beat.
-/

import ZkIpProtocol.MerkleCommitment
import ZkIpProtocol.STARKIntegration

namespace Tests.Validation

open ZkIpProtocol

/-- `n` committed attributes `1001..1000+n`; the proof is for the last index
(`1000+n > 1000`). Returns (threshold, root, leaf, path). -/
def fixture (n : Nat) : IO (Nat × ByteArray × ByteArray × MerkleProof) := do
  let leaves := (Array.range n).map (fun i => attrLeafBytes (1001 + i))
  let root ← buildMerkleTree leaves
  let some path := generateProof leaves (n - 1) | throw (IO.userError s!"no path for index {n - 1}")
  pure (1000, root, leaves[n - 1]!, path)

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

def median (xs : Array Nat) : Nat := (xs.qsort (· < ·))[xs.size / 2]!

/-- Prove/verify timing sweep over tree sizes at the production parameters. -/
def main : IO Unit := do
  let runs := 5
  IO.println "leaves,depth,prove_median_ms,verify_median_ms,proof_bytes"
  for n in [1, 8, 16, 1024] do
    let (threshold, root, leaf, path) ← Tests.Validation.fixture n
    let _ ← Tests.Validation.timeProve threshold root leaf path  -- warm-up (system build on first call)
    let mut proveTimes : Array Nat := #[]
    let mut verifyTimes : Array Nat := #[]
    let mut size := 0
    for _ in [0:runs] do
      let (t, proof) ← Tests.Validation.timeProve threshold root leaf path
      let (v, ok) ← Tests.Validation.timeVerify threshold root proof
      if !ok then throw (IO.userError s!"verification failed at {n} leaves")
      proveTimes := proveTimes.push t
      verifyTimes := verifyTimes.push v
      size := proof.proofData.size
    IO.println s!"{n},{path.path.size},{median proveTimes},{median verifyTimes},{size}"
