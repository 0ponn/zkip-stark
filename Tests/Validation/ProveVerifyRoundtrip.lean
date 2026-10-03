/-
Roundtrip test: generate a STARK proof for a committed attribute and verify
it in the same session, through the library prove/verify pair.
-/

import ZkIpProtocol.STARKIntegration
import ZkIpProtocol.MerkleCommitment

namespace Tests.Validation

open ZkIpProtocol

/-- Three committed attributes; index 0 (1500) satisfies `> 1000`. -/
def proveVerifyRoundtrip : IO Unit := do
  IO.println "=== Prove/Verify Roundtrip Test ==="
  let leaves := #[1500, 8, 95].map attrLeafBytes
  let root ← buildMerkleTree leaves
  let some path := generateProof leaves 0 | throw (IO.userError "no path for index 0")
  IO.println s!"✓ Merkle tree built (depth {path.path.size})"

  let some proof ← generateSTARKProof 1000 root leaves[0]! path
    | throw (IO.userError "Failed to generate STARK proof")
  IO.println s!"✓ STARK proof generated: {proof.proofData.size} bytes, claim {proof.publicInputs.size} elements"

  if !(← verifySTARKProof proof 1000 root) then
    throw (IO.userError "STARK proof verification FAILED")
  IO.println "✓ STARK proof verification PASSED"

end Tests.Validation

def main : IO Unit := do
  Tests.Validation.proveVerifyRoundtrip
  IO.println "\n✓ All roundtrip tests passed"
