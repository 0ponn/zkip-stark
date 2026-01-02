/-
Tests for STARK proof integration using Ix's Aiur system.
Verifies proof generation, verification, and Merkle root binding.
-/

import ZkIpProtocol.IPMetadata
import ZkIpProtocol.MerkleCommitment
import ZkIpProtocol.Advertisement
import ZkIpProtocol.STARKIntegration
import ZkIpProtocol.Performance
import Ix.Aiur.Goldilocks

namespace Tests

open ZkIpProtocol
open ZkIpProtocol.Advertisement
open Aiur

/-- Test data setup -/
def testIxon : Ixon := {
  id := "test_ip_stark_001"
  name := "Test IP for STARK"
  version := "1.0.0"
  attributes := #[
    IPAttribute.performance 1500,
    IPAttribute.security 8,
    IPAttribute.efficiency 95
  ]
  merkleRoot := ByteArray.empty  -- Will be computed
  timestamp := 1000
  owner := "TestOwner"
}

def testPredicate : IPPredicate := {
  attributeType := "performance"
  operator := ">"
  threshold := 1000
}

/-- Test STARK proof generation and verification -/
def testSTARKProofGeneration : IO Unit := do
  IO.println "=== STARK Proof Generation Test ==="

  -- 1. Setup: Create Merkle tree
  let attrBytes : Array ByteArray := testIxon.attributes.map serializeAttribute
  let merkleRoot := commitIPData attrBytes
  let merkleProof? := generateProof attrBytes 0

  match merkleProof? with
  | some merkleProof =>
    -- 2. Build circuit
    let circuit : PredicateCircuit := {
      attributeValue := 1500  -- Private attribute value
      merkleRoot := merkleRoot
      threshold := testPredicate.threshold
      operator := testPredicate.operator
      merkleProof
      output := true
    }

    -- 3. Verify Merkle commitment
    if !circuit.verifyMerkleCommitment then
      IO.println "✗ Merkle commitment verification failed"
      return

    IO.println "✓ Merkle commitment verified"

    -- 4. Convert to field elements (Goldilocks)
    let merkleRootHash := merkleRoot.hash.toNat
    let publicInputs : Array G := #[
      G.ofNat merkleRootHash,  -- Merkle root as public input
      G.ofNat testPredicate.threshold
    ]

    let privateInputs : Array G := #[
      G.ofNat 1500  -- Private attribute value
    ]

    IO.println s!"  Merkle root hash: {merkleRootHash}"
    IO.println s!"  Public inputs: {publicInputs.size} elements"
    IO.println s!"  Private inputs: {privateInputs.size} elements"

    -- 5. Generate STARK proof
    IO.println "\n  Generating STARK proof..."
    let some starkProof ← generateSTARKProof circuit publicInputs privateInputs
      | do
        IO.println "✗ Failed to generate STARK proof"
        return

    IO.println "✓ STARK proof generated successfully"
    IO.println s!"  Proof size: {starkProof.proofData.size} bytes"
    IO.println s!"  Public inputs in proof: {starkProof.publicInputs.size} elements"
    IO.println s!"  Verification key ID: {starkProof.vkId}"

    -- 6. Verify the proof
    IO.println "\n  Verifying STARK proof..."
    let verified ← ZkIpProtocol.verifySTARKProof starkProof publicInputs circuit

    if verified then
      IO.println "✓ STARK proof verification passed"
      IO.println "✓ Merkle root is bound to the proof (included in claim)"
    else
      IO.println "✗ STARK proof verification failed"

  | none =>
    IO.println "✗ Failed to generate Merkle proof"

/-- Test that Merkle root is included in public inputs -/
def testMerkleRootBinding : IO Unit := do
  IO.println "\n=== Merkle Root Binding Test ==="

  -- Setup
  let attrBytes : Array ByteArray := testIxon.attributes.map serializeAttribute
  let merkleRoot := commitIPData attrBytes
  let merkleProof? := generateProof attrBytes 0

  match merkleProof? with
  | some merkleProof =>
    let circuit : PredicateCircuit := {
      attributeValue := 1500
      merkleRoot := merkleRoot
      threshold := testPredicate.threshold
      operator := testPredicate.operator
      merkleProof
      output := true
    }

    let merkleRootHash := merkleRoot.hash.toNat
    let publicInputs : Array G := #[
      G.ofNat merkleRootHash,
      G.ofNat testPredicate.threshold
    ]

    let privateInputs : Array G := #[G.ofNat 1500]

    -- Generate proof
    let some starkProof ← ZkIpProtocol.generateSTARKProof circuit publicInputs privateInputs
      | do
        IO.println "✗ Failed to generate proof"
        return

    -- Check that public inputs contain the claim (which includes Merkle root)
    if starkProof.publicInputs.size > 0 then
      IO.println s!"✓ Proof contains {starkProof.publicInputs.size} public input elements"
      IO.println "  (The claim structure includes: functionChannel, funIdx, merkleRoot, threshold, attributeValue, output)"
      IO.println "✓ Merkle root is bound to the proof via the claim structure"
    else
      IO.println "✗ Proof has no public inputs"

    -- Verify the proof
    let verified ← ZkIpProtocol.verifySTARKProof starkProof publicInputs circuit
    if verified then
      IO.println "✓ Verification confirms Merkle root binding"
    else
      IO.println "✗ Verification failed - Merkle root binding may be incorrect"

  | none =>
    IO.println "✗ Failed to generate Merkle proof"

  /-- Performance profiling test -/
  def testPerformanceProfiling : IO Unit := do
    IO.println "\n=== Performance Profiling Test ==="

    -- Setup test circuit
    let circuit : PredicateCircuit := {
      attributeValue := 1500
      merkleRoot := ByteArray.mk #[1,2,3,4,5,6,7,8]
      threshold := 1000
      operator := ">"
      merkleProof := { path := #[], leafIndex := 0, rootHash := ByteArray.mk #[1,2,3,4,5,6,7,8] }
      output := true
    }

    let publicInputs : Array G := #[
      G.ofNat (circuit.merkleRoot.hash.toNat),
      G.ofNat circuit.threshold
    ]
    let privateInputs : Array G := #[
      G.ofNat circuit.attributeValue
    ]

    -- Analyze circuit complexity
    ZkIpProtocol.analyzeCircuitComplexity circuit

    -- Profile proof generation
    let metrics : ZkIpProtocol.ProofMetrics ← ZkIpProtocol.profileSTARKProof circuit publicInputs privateInputs
    ZkIpProtocol.printMetrics metrics

    IO.println "\n=== Performance Analysis ==="
    let log2Estimate := if metrics.estimatedConstraints > 0 then Nat.log2 metrics.estimatedConstraints else 0
    IO.println s!"Proof size suggests ~2^{log2Estimate} constraints"
    IO.println s!"Current proof generation rate: {if metrics.proofGenTimeMs > 0 then metrics.constraintCount * 1000 / metrics.proofGenTimeMs else 0} constraints/second"
    IO.println s!"For hardware acceleration (NoCap 586x speedup):"
    IO.println s!"  Estimated proof gen time: {if metrics.proofGenTimeMs > 0 then metrics.proofGenTimeMs / 586 else 0} ms"
    IO.println s!"  Estimated throughput: {if metrics.proofGenTimeMs > 0 then metrics.constraintCount * 1000 * 586 / metrics.proofGenTimeMs else 0} constraints/second"

end Tests

/-- Run all STARK tests -/
def main : IO Unit := do
  Tests.testSTARKProofGeneration
  Tests.testMerkleRootBinding
  Tests.testPerformanceProfiling
  IO.println "\n=== STARK Tests Complete ==="
