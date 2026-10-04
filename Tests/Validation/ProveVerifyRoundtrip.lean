/-
Roundtrip test: generate a STARK proof for a committed attribute and verify
it in the same session, through the library prove/verify pair.
-/

import ZkIpProtocol.STARKIntegration
import ZkIpProtocol.MerkleCommitment

namespace Tests.Validation

open ZkIpProtocol

/-- Three committed attributes; index 0 (performance 1500) satisfies `> 1000`. -/
def proveVerifyRoundtrip : IO Unit := do
  IO.println "=== Prove/Verify Roundtrip Test ==="
  let attrs : Array IPAttribute := #[.performance 1500, .security 8, .custom "latency" 95]
  let leaves := attrs.map (·.leaf)
  let root ← buildMerkleTree leaves
  let some path := generateProof leaves 0 | throw (IO.userError "no path for index 0")
  IO.println s!"✓ Merkle tree built (depth {path.path.size})"

  let some proof ← generateSTARKProof 1000 root leaves[0]! path
    | throw (IO.userError "Failed to generate STARK proof")
  IO.println s!"✓ STARK proof generated: {proof.proofData.size} bytes, claim {proof.publicInputs.size} elements"

  if !(← verifySTARKProof proof 1000 (attrIdOf "performance") root) then
    throw (IO.userError "STARK proof verification FAILED")
  IO.println "✓ STARK proof verification PASSED"

  -- The attribute is bound: the same proof read as another attribute fails.
  for label in ["security", "efficiency", "custom/latency"] do
    if ← verifySTARKProof proof 1000 (attrIdOf label) root then
      throw (IO.userError s!"proof for performance verified as {label}")
  IO.println "✓ proof does not verify under any other attribute"

  -- A leaf that claims to be performance but was committed as security is not
  -- in the tree: relabelling the committed security value fails to prove.
  let securityAsPerformance := attrLeaf "performance" 1500
  let some secPath := generateProof leaves 1 | throw (IO.userError "no path for index 1")
  if (← generateSTARKProof 1000 root securityAsPerformance secPath).isSome then
    throw (IO.userError "proved a relabelled leaf")
  IO.println "✓ a value committed under one attribute cannot be proved under another"

end Tests.Validation

def main : IO Unit := do
  Tests.Validation.proveVerifyRoundtrip
  IO.println "\n✓ All roundtrip tests passed"
