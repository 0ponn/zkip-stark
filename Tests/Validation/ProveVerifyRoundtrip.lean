/-
Roundtrip test: generate STARK proof and verify it in the same session.
This test should FAIL before the fix (verify returns false due to serialization mismatch)
and PASS after the fix (8-byte big-endian alignment).
-/

import ZkIpProtocol.STARKIntegration
import ZkIpProtocol.MerkleCommitment
import Ix.Aiur.Goldilocks

namespace Tests.Validation

open ZkIpProtocol
open Aiur

/-- Serialize an IP attribute to bytes by its numeric value (mirror from STARKTests) -/
private def attrBytesOf (a : IPAttribute) : ByteArray :=
  natToByteArray (match a with
    | .performance n => n
    | .security n => n
    | .efficiency n => n
    | .custom _ n => n)

/-- Test data setup (mirror from STARKTests) -/
def testIxon : Ixon := {
  id := 1
  attributes := #[
    IPAttribute.performance 1500,
    IPAttribute.security 8,
    IPAttribute.efficiency 95
  ]
  merkleRoot := ByteArray.empty  -- Will be computed
  timestamp := 1000
}

def testPredicate : IPPredicate := {
  operator := ">"
  threshold := 1000
}

/-- Core roundtrip test: prove then verify in the same session -/
def proveVerifyRoundtrip : IO Unit := do
  IO.println "=== Prove/Verify Roundtrip Test ==="

  -- 1. Setup: Create Merkle tree from attributes
  let attrBytes : Array ByteArray := testIxon.attributes.map attrBytesOf
  let merkleRoot ← buildMerkleTree attrBytes
  let merkleProof : MerkleProof := {
    rootHash := merkleRoot
    path := #[]
    isLeft := #[]
  }

  -- 2. Build circuit
  let circuit : PredicateCircuit := {
    attributeValue := 1500
    merkleRoot := merkleRoot
    threshold := testPredicate.threshold
    operator := testPredicate.operator
    merkleProof
    output := true
  }

  IO.println "✓ Circuit constructed"

  -- 3. Verify Merkle commitment
  if !circuit.verifyMerkleCommitment then
    throw (IO.userError "Merkle commitment verification failed")

  IO.println "✓ Merkle commitment verified"

  -- 4. Prepare public and private inputs.
  -- The predicate circuit signature is `predicate_check(threshold, attr)`:
  -- one public input (threshold) and one private input (attr).
  let publicInputs : Array Aiur.G := #[
    G.ofNat testPredicate.threshold
  ]

  let privateInputs : Array Aiur.G := #[
    G.ofNat 1500  -- attribute value
  ]

  IO.println s!"✓ Prepared inputs (public={publicInputs.size}, private={privateInputs.size})"

  -- 5. Generate STARK proof
  IO.println "  Generating STARK proof..."
  let some starkProof ← generateSTARKProof circuit publicInputs privateInputs
    | throw (IO.userError "Failed to generate STARK proof")

  IO.println "✓ STARK proof generated"
  IO.println s!"  Proof size: {starkProof.proofData.size} bytes"
  IO.println s!"  Public inputs in proof: {starkProof.publicInputs.size} elements"

  -- 6. Verify the proof (THIS IS THE KEY TEST)
  IO.println "  Verifying STARK proof..."
  let verified ← verifySTARKProof starkProof publicInputs circuit

  if !verified then
    throw (IO.userError "STARK proof verification FAILED - this is the bug we're fixing!")

  IO.println "✓ STARK proof verification PASSED"
  IO.println "✓ Roundtrip complete: prove + verify successful"

end Tests.Validation

/-- Main test entry point -/
def main : IO Unit := do
  try
    Tests.Validation.proveVerifyRoundtrip
    IO.println "\n✓ All roundtrip tests passed"
  catch ex =>
    IO.println s!"\n✗ Test failed: {ex}"
