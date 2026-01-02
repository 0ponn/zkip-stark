/-
Smoke tests for ZK-IP Protocol core functionality.
Tests Merkle-to-ZK binding and certificate generation/verification.
-/

import ZkIpProtocol.IPMetadata
import ZkIpProtocol.MerkleCommitment
import ZkIpProtocol.Advertisement
import ZkIpProtocol.ABAC

namespace Tests

open ZkIpProtocol
open ZkIpProtocol.Advertisement

/-- Test data setup -/
def testIxon : Ixon := {
  id := "test_ip_001"
  name := "Test IP Component"
  version := "1.0.0"
  attributes := #[
    IPAttribute.performance 1500,
    IPAttribute.security 8,
    IPAttribute.efficiency 95
  ]
  merkleRoot := ByteArray.empty  -- Will be computed from attributes
  timestamp := 1000
  owner := "TestOwner"
}

def testPredicate : IPPredicate := {
  attributeType := "performance"
  operator := ">"
  threshold := 1000
}

/-- Happy Path Test: Prove performance > 1000 and verify Merkle binding -/
def testHappyPath : IO Unit := do
  IO.println "=== Happy Path Test ==="

  -- 1. Serialize attributes to ByteArray for Merkle tree
  let attrBytes : Array ByteArray := testIxon.attributes.map serializeAttribute

  -- 2. Build Merkle tree and get root
  let merkleRoot := commitIPData attrBytes

  -- 3. Generate Merkle proof for performance attribute (index 0)
  let merkleProof? := generateProof attrBytes 0

  match merkleProof? with
  | some proof =>
    -- 4. Verify the attribute is in the Merkle tree
    match testIxon.attributes[0]? with
    | some performanceAttr =>
      let isValid := verifyAttributeInMerkleTree merkleRoot performanceAttr proof

      if isValid then
        IO.println "✓ Merkle proof verification passed"

        -- 5. Generate ZK certificate
        let cert? := Advertisement.generateCertificate
          { testIxon with merkleRoot := merkleRoot }
          testPredicate
          1500  -- Private attribute value (performance)
          attrBytes
          0    -- Attribute index

        match cert? with
        | some cert =>
          IO.println "✓ ZK certificate generated successfully"
          IO.println s!"  Certificate ID: {cert.ipId}"
          IO.println s!"  Commitment: {cert.commitment.size} bytes"

          -- 6. Verify certificate
          let certValid := ZKCertificate.verify cert
          if certValid then
            IO.println "✓ Certificate verification passed"
          else
            IO.println "✗ Certificate verification failed"
        | none =>
          IO.println "✗ Failed to generate certificate"
      else
        IO.println "✗ Merkle proof verification failed"
    | none =>
      IO.println "✗ Failed to get performance attribute"
  | none =>
    IO.println "✗ Failed to generate Merkle proof"

/-- Ad-Switch Attack Test: Attempt to use wrong attribute value -/
def testAdSwitchAttack : IO Unit := do
  IO.println "\n=== Ad-Switch Attack Test ==="

  -- Setup: Create Merkle tree with performance = 1500
  let attrBytes : Array ByteArray := testIxon.attributes.map serializeAttribute
  let merkleRoot := ZkIpProtocol.commitIPData attrBytes
  let merkleProof? := ZkIpProtocol.generateProof attrBytes 0

  match merkleProof? with
  | some proof =>
    -- Attack: Try to use a different private attribute (2000) that satisfies predicate
    -- but is NOT the value committed in the Merkle tree
    match testIxon.attributes[0]? with
    | some performanceAttr =>
      -- First verify the correct attribute passes
      let correctVerify := verifyAttributeInMerkleTree merkleRoot performanceAttr proof
      IO.println s!"Correct attribute verification: {correctVerify}"

      -- Now try to generate certificate with wrong private value
      -- This should fail because verifyAttributeInMerkleTree checks the committed value
      let cert? := Advertisement.generateCertificate
        { testIxon with merkleRoot := merkleRoot }
        testPredicate
        2000  -- Wrong private value (not committed in tree)
        attrBytes
        0

      match cert? with
      | some cert =>
        IO.println "✗ SECURITY ISSUE: Certificate generated with wrong attribute!"
        IO.println "  This indicates the Merkle binding is not working correctly."
      | none =>
        IO.println "✓ Security check passed: Certificate correctly rejected for wrong value"
    | none =>
      IO.println "✗ Failed to get performance attribute"
  | none =>
    IO.println "✗ Failed to generate Merkle proof"

end Tests

/-- Run all tests -/
def main : IO Unit := do
  Tests.testHappyPath
  Tests.testAdSwitchAttack
  IO.println "\n=== Tests Complete ==="
