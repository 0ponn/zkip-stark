/-
Roundtrip test: generate a STARK proof for a committed attribute and verify
it in the same session, through the library prove/verify pair.
-/

import ZkIpProtocol.STARKIntegration
import ZkIpProtocol.MerkleCommitment

namespace Tests.Validation

open ZkIpProtocol

/-- Three committed attributes in the label-keyed tree; performance (1500)
satisfies `> 1000`. -/
def proveVerifyRoundtrip : IO Unit := do
  IO.println "=== Prove/Verify Roundtrip Test ==="
  let attrs : Array IPAttribute := #[.performance 1500, .security 8, .custom "latency" 95]
  let .ok leaves := keyedLeaves attrs | throw (IO.userError "fixture labels clash")
  let root := keyedRoot leaves
  let path := keyedProof leaves (labelSlot "performance")
  if !verifyProof leaves[0]!.2 path then throw (IO.userError "reference path does not fold to the root")
  IO.println s!"✓ label-keyed tree built (depth {path.path.size})"

  let some proof ← generateSTARKProof 1000 root leaves[0]!.2 path
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

  -- A performance leaf placed in the security slot: the path is valid for the
  -- root, but it does not walk to performance's slot, so the circuit refuses.
  let smuggled : Array (Nat × ByteArray) :=
    #[(labelSlot "performance", attrLeaf "performance" 500), (labelSlot "security", attrLeaf "performance" 2000)]
  let smuggledRoot := keyedRoot smuggled
  let offSlot := keyedProof smuggled (labelSlot "security")
  if !verifyProof smuggled[1]!.2 offSlot then throw (IO.userError "off-slot reference path is wrong")
  if (← generateSTARKProof 1000 smuggledRoot smuggled[1]!.2 offSlot).isSome then
    throw (IO.userError "proved a second performance value from another label's slot")
  IO.println "✓ a value outside its label's slot cannot be proved (one value per label)"

  -- A 16-level path (the pre-M12 depth) is refused.
  let short := { path with path := path.path.extract 0 16, isLeft := path.isLeft.extract 0 16 }
  if (← generateSTARKProof 1000 root leaves[0]!.2 short).isSome then
    throw (IO.userError "proved with a 16-level path")
  IO.println "✓ a path shorter than 32 levels is refused"

  -- Committing a label twice, or two labels in one slot, is refused.
  match keyedLeaves #[.performance 500, .performance 2000] with
  | .ok _ => throw (IO.userError "two performance values committed")
  | .error _ => IO.println "✓ a label committed twice is refused"

end Tests.Validation

def main : IO Unit := do
  Tests.Validation.proveVerifyRoundtrip
  IO.println "\n✓ All roundtrip tests passed"
