/-
STARK Round-Trip Integration Tests
Verifies STARK proof generation and verification integrity.
-/

import ZkIpProtocol.STARKIntegration
import ZkIpProtocol.Advertisement
import Ix.Aiur.Protocol
import Ix.Aiur.Bytecode
import Ix.Aiur.Goldilocks

namespace Tests.Validation

open ZkIpProtocol
open Aiur
open Aiur.Bytecode
open Aiur.Goldilocks

/-- Helper: Convert ByteArray to G -/
def byteArrayToG (bytes : ByteArray) : G :=
  if bytes.size >= 8 then
    let val :=
      (bytes[0]!.toNat <<< 56) +
      (bytes[1]!.toNat <<< 48) +
      (bytes[2]!.toNat <<< 40) +
      (bytes[3]!.toNat <<< 32) +
      (bytes[4]!.toNat <<< 24) +
      (bytes[5]!.toNat <<< 16) +
      (bytes[6]!.toNat <<< 8) +
      bytes[7]!.toNat
    G.ofNat val
  else
    G.ofNat 0

/-- Test 1.3.1: Success Case
   Generate a valid proof and verify it succeeds.
-/
def testSuccessCase : IO Bool := do
  IO.println "Test 1.3.1: Success Case (Valid Proof)"

  -- Create valid circuit
  let merkleRootBytes := ByteArray.mk (Array.mk (List.replicate 32 (0 : UInt8)))
  let circuit : PredicateCircuit := {
    attributeValue := 1500
    merkleRoot := merkleRootBytes
    threshold := 1000
    operator := ">="
    merkleProof := {
      path := #[]
      leafIndex := 0
      rootHash := merkleRootBytes
    }
    output := true
  }

  -- Convert to field elements
  let merkleRootG := byteArrayToG merkleRootBytes
  let thresholdG := G.ofNat 1000
  let attributeValueG := G.ofNat 1500

  let publicInputs : Array G := #[merkleRootG, thresholdG]
  let privateInputs : Array G := #[attributeValueG]

  -- Generate proof
  match ← generateSTARKProof circuit publicInputs privateInputs with
  | some proof =>
    IO.println "  ✓ Proof generated successfully"

    -- Verify proof
    let isValid ← verifySTARKProof proof publicInputs circuit
    if isValid then
      IO.println "  ✓ Proof verification: PASSED"
      return true
    else
      IO.println "  ✗ Proof verification: FAILED (valid proof rejected)"
      return false
  | none =>
    IO.println "  ✗ Proof generation failed"
    return false

/-- Test 1.3.2: Soundness Case (False Proof)
   Tamper with witness and verify proof fails.
-/
def testSoundnessCase : IO Bool := do
  IO.println "Test 1.3.2: Soundness Case (Tampered Witness)"

  -- Create valid circuit
  let merkleRootBytes := ByteArray.mk (Array.mk (List.replicate 32 (0 : UInt8)))
  let validCircuit : PredicateCircuit := {
    attributeValue := 1500
    merkleRoot := merkleRootBytes
    threshold := 1000
    operator := ">="
    merkleProof := {
      path := #[]
      leafIndex := 0
      rootHash := merkleRootBytes
    }
    output := true
  }

  -- Convert to field elements
  let merkleRootG := byteArrayToG merkleRootBytes
  let thresholdG := G.ofNat 1000
  let attributeValueG := G.ofNat 1500

  let publicInputs : Array G := #[merkleRootG, thresholdG]
  let privateInputs : Array G := #[attributeValueG]

  -- Generate proof with valid circuit
  match ← generateSTARKProof validCircuit publicInputs privateInputs with
  | some proof =>
    IO.println "  ✓ Valid proof generated"

    -- Create invalid circuit (tampered attribute value)
    let invalidCircuit : PredicateCircuit := {
      validCircuit with
      attributeValue := 500  -- Changed from 1500 to 500 (should fail threshold)
    }

    -- Attempt to verify proof against invalid circuit (with wrong public inputs)
    let invalidAttributeG := G.ofNat 500
    let invalidPrivateInputs : Array G := #[invalidAttributeG]
    -- Note: We're using the same public inputs, but the circuit has different attribute value
    -- This should fail because the proof was generated with attributeValue=1500, not 500
    let isValid ← verifySTARKProof proof publicInputs invalidCircuit
    if isValid then
      IO.println "  ✗ Soundness: FAILED (invalid proof accepted)"
      return false
    else
      IO.println "  ✓ Soundness: PASSED (invalid proof correctly rejected)"
      return true
  | none =>
    IO.println "  ✗ Proof generation failed"
    return false

/-- Test 1.3.3: Claim Consistency
   Verify that the claim structure is consistent between generation and verification.
-/
def testClaimConsistency : IO Bool := do
  IO.println "Test 1.3.3: Claim Consistency"

  let merkleRootBytes := ByteArray.mk (Array.mk (List.replicate 32 (0 : UInt8)))
  let circuit : PredicateCircuit := {
    attributeValue := 1500
    merkleRoot := merkleRootBytes
    threshold := 1000
    operator := ">="
    merkleProof := {
      path := #[]
      leafIndex := 0
      rootHash := merkleRootBytes
    }
    output := true
  }

  let merkleRootG := byteArrayToG merkleRootBytes
  let thresholdG := G.ofNat 1000
  let attributeValueG := G.ofNat 1500

  let publicInputs : Array G := #[merkleRootG, thresholdG]
  let privateInputs : Array G := #[attributeValueG]

  match ← generateSTARKProof circuit publicInputs privateInputs with
  | some proof =>
    -- Check that publicInputs (claim) is not empty
    if proof.publicInputs.size > 0 then
      IO.println "  ✓ Claim structure: PASSED (public inputs present)"
      return true
    else
      IO.println "  ✗ Claim structure: FAILED (no public inputs)"
      return false
  | none =>
    IO.println "  ✗ Proof generation failed"
    return false

/-- Run all STARK round-trip tests -/
def runSTARKRoundTripTests : IO Unit := do
  IO.println "=========================================="
  IO.println "STARK Round-Trip Integration Tests"
  IO.println "=========================================="
  IO.println ""

  let successCase ← testSuccessCase
  IO.println ""
  let soundnessCase ← testSoundnessCase
  IO.println ""
  let claimConsistency ← testClaimConsistency

  IO.println ""
  IO.println "=========================================="
  if successCase && soundnessCase && claimConsistency then
    IO.println "✅ STARK Round-Trip: PASSED"
  else
    IO.println "❌ STARK Round-Trip: FAILED"
  IO.println "=========================================="

end Tests.Validation
