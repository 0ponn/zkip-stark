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

/-- Serialize an IP attribute to bytes by its numeric value (test helper). -/
private def attrBytesOf (a : IPAttribute) : ByteArray :=
  natToByteArray (match a with
    | .performance n => n
    | .security n => n
    | .efficiency n => n
    | .custom _ n => n)

/-- Test data setup -/
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

/-- Test STARK proof generation and verification -/
def testSTARKProofGeneration : IO Unit := do
  IO.println "=== STARK Proof Generation Test ==="

  -- 1. Setup: Create Merkle tree
  let attrBytes : Array ByteArray := testIxon.attributes.map attrBytesOf
  let merkleRoot ← buildMerkleTree attrBytes
  let merkleProof? : Option MerkleProof := some { rootHash := merkleRoot, path := #[], isLeft := #[] }

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

    -- 4. Convert to field elements (Goldilocks).
    -- The M1 circuit `predicate_check(threshold) -> G` takes only `threshold`
    -- as a public input; `attr` is a private IO witness (channel 0). Merkle
    -- root binding into the STARK claim is not implemented in M1 (pending M2).
    let publicInputs : Array Aiur.G := #[
      G.ofNat testPredicate.threshold
    ]

    let privateInputs : Array Aiur.G := #[
      G.ofNat 1500  -- Private attribute value
    ]

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
    else
      IO.println "✗ STARK proof verification failed"

  | none =>
    IO.println "✗ Failed to generate Merkle proof"

/-- PENDING M2: this test used to assert the Merkle root was bound into the
STARK claim. The M1 circuit ABI (`predicate_check(threshold) -> G`) carries
only `threshold` as a public input — there is no Merkle-root binding into the
claim yet, so asserting one here would be a false pass. This now exercises
prove/verify on the real 1-public-input circuit and explicitly labels the
binding as not-yet-implemented rather than claiming it works. -/
def testMerkleRootBinding : IO Unit := do
  IO.println "\n=== Merkle Root Binding Test (PENDING M2 — not yet implemented) ==="

  -- Setup
  let attrBytes : Array ByteArray := testIxon.attributes.map attrBytesOf
  let merkleRoot ← buildMerkleTree attrBytes
  let merkleProof? : Option MerkleProof := some { rootHash := merkleRoot, path := #[], isLeft := #[] }

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

    let publicInputs : Array Aiur.G := #[G.ofNat testPredicate.threshold]
    let privateInputs : Array Aiur.G := #[G.ofNat 1500]

    -- Generate proof
    let some starkProof ← ZkIpProtocol.generateSTARKProof circuit publicInputs privateInputs
      | do
        IO.println "✗ Failed to generate proof"
        return

    IO.println s!"✓ Proof contains {starkProof.publicInputs.size} public input elements"
    IO.println "  PENDING M2: the claim carries only `threshold`; the Merkle root is"
    IO.println "  NOT bound into the STARK claim in M1."

    -- Verify the proof (threshold binding only — see verifySTARKProof)
    let verified ← ZkIpProtocol.verifySTARKProof starkProof publicInputs circuit
    if verified then
      IO.println "✓ Verification passed (bound to threshold only, per M1 scope)"
    else
      IO.println "✗ Verification failed"

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
      merkleProof := { rootHash := ByteArray.mk #[1,2,3,4,5,6,7,8], path := #[], isLeft := #[] }
      output := true
    }

    -- M1 circuit ABI: only `threshold` is a public input; `attr` is private.
    let publicInputs : Array Aiur.G := #[
      G.ofNat circuit.threshold
    ]
    let privateInputs : Array Aiur.G := #[
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
