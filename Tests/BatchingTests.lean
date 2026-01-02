/-
Tests for batched predicate checks.
Verifies multiple attributes against the same Merkle root in a single proof.
-/

import ZkIpProtocol.IPMetadata
import ZkIpProtocol.MerkleCommitment
import ZkIpProtocol.Advertisement
import ZkIpProtocol.Batching
import Ix.Aiur.Goldilocks

namespace Tests

open ZkIpProtocol
open ZkIpProtocol.Advertisement
open Aiur

/-- Test batched predicate checks -/
def testBatchedChecks : IO Unit := do
  IO.println "=== Batched Predicate Checks Test ==="

  -- Setup: Create IP with multiple attributes
  let attributes := #[
    IPAttribute.performance 1500,
    IPAttribute.security 8,
    IPAttribute.efficiency 95
  ]

  -- Serialize attributes for Merkle tree
  let attrBytes : Array ByteArray := attributes.map serializeAttribute
  let merkleRoot := ZkIpProtocol.commitIPData attrBytes

  -- Generate Merkle proofs for all attributes
  let mut merkleProofs : Array ZkIpProtocol.MerkleProof := #[]
  for i in [0:attributes.size] do
    match ZkIpProtocol.generateProof attrBytes i with
    | some proof => merkleProofs := merkleProofs.push proof
    | none => IO.println s!"Failed to generate proof for attribute {i}"

  if merkleProofs.size != attributes.size then
    IO.println "✗ Failed to generate all Merkle proofs"
    return

  -- Create batched circuit
  let circuit : ZkIpProtocol.BatchedPredicateCircuit := {
    merkleRoot
    thresholds := #[1000, 5, 90]  -- performance > 1000, security > 5, efficiency > 90
    operators := #[">", ">", ">"]
    attributeValues := #[1500, 8, 95]  -- All should pass
    merkleProofs
    outputs := #[true, true, true]
  }

  -- Verify Merkle commitments
  if !circuit.verifyMerkleCommitments then
    IO.println "✗ Merkle commitment verification failed"
    return

  IO.println "✓ Merkle commitment verification passed"

  -- Prepare inputs for proof generation
  let publicInputs : Array G := #[G.ofNat (merkleRoot.hash.toNat)] ++
    circuit.thresholds.map (fun t => G.ofNat t)
  let privateInputs : Array G := circuit.attributeValues.map (fun v => G.ofNat v)

  IO.println s!"  Public inputs: {publicInputs.size} elements (merkleRoot + {circuit.thresholds.size} thresholds)"
  IO.println s!"  Private inputs: {privateInputs.size} elements ({circuit.attributeValues.size} attribute values)"

  -- Generate batched proof
  IO.println "\n  Generating batched STARK proof..."
  let some batchedProof ← ZkIpProtocol.generateBatchedSTARKProof circuit publicInputs privateInputs
    | do
      IO.println "✗ Failed to generate batched STARK proof"
      return

  IO.println "✓ Batched STARK proof generated successfully"
  IO.println s!"  Proof size: {batchedProof.proofData.size} bytes ({batchedProof.proofData.size / 1024} KB)"
  IO.println s!"  Public inputs in proof: {batchedProof.publicInputs.size} elements"
  IO.println s!"  Verification key ID: {batchedProof.vkId}"

  IO.println "\n=== Batching Efficiency Analysis ==="
  IO.println s!"Batched {circuit.attributeValues.size} attribute checks into single proof"
  IO.println s!"Proof size per attribute: {batchedProof.proofData.size / circuit.attributeValues.size} bytes"
  IO.println "This demonstrates the ABI's ability to support multiple checks efficiently"

end Tests

/-- Run batching tests -/
def main : IO Unit := do
  Tests.testBatchedChecks
  IO.println "\n=== Batching Tests Complete ==="
