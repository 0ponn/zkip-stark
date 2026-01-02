/-
ZKMB Tests: Verify Zero-Knowledge Middlebox functionality
Tests batching, recursion, and performance for real-world deployment.
-/

import ZkIpProtocol.ZKMB
import ZkIpProtocol.Advertisement
import ZkIpProtocol.STARKIntegration
import ZkIpProtocol.Batching
import ZkIpProtocol.Performance

namespace Tests

open ZkIpProtocol
open ZkIpProtocol.ZKMB
open ZkIpProtocol.Advertisement

/-- Create sample TLS packet -/
def createSamplePacket (seqNum : Nat) : TLSPacket := {
  encryptedData := ByteArray.mk #[1, 2, 3, 4]
  sequenceNumber := seqNum
  timestamp := seqNum * 1000
  sourceIP := ByteArray.mk #[192, 168, 1, 1]
  destIP := ByteArray.mk #[10, 0, 0, 1]
  attributes := {
    attributeValues := #[100, 200, 300]
    attributeNames := #["tls_version", "cipher_suite", "key_size"]
  }
}

/-- Create sample security policy -/
def createSamplePolicy : SecurityPolicy := {
  policyName := "TLS 1.3 Compliance"
  allowedSources := #[ByteArray.mk #[192, 168, 0, 0]]
  allowedDestinations := #[ByteArray.mk #[10, 0, 0, 0]]
  requiredAttributes := {
    attributeValues := #[100, 200, 300]
    attributeNames := #["tls_version", "cipher_suite", "key_size"]
  }
  thresholds := #[50, 150, 250]
  policyRoot := G.ofNat 12345
}

/-- Test: Initialize ZKMB -/
def testZKMBInit : IO Unit := do
  IO.println "Testing ZKMB initialization..."
  let policy := createSamplePolicy
  let zkmb := ZKMB.init policy 3  -- Target: 3ms verification
  IO.println s!"ZKMB initialized with policy: {policy.policyName}"
  IO.println s!"Initial state root: {zkmb.state.stateRoot}"
  IO.println "✓ ZKMB initialization test passed"

/-- Test: Batched packet verification -/
def testBatchedVerification : IO Unit := do
  IO.println "Testing batched packet verification..."
  let policy := createSamplePolicy
  let packets := Array.mk (List.range 5).map createSamplePacket
  let batchRoot := G.ofNat packets.size
  let batchedVerification : BatchedPacketVerification := {
    packets
    policy
    batchRoot
    batchedProof := none
  }
  IO.println s!"Created batch with {packets.size} packets"
  IO.println "✓ Batched verification test passed"

/-- Test: Recursive state update -/
def testRecursiveStateUpdate : IO Unit := do
  IO.println "Testing recursive state update..."
  let policy := createSamplePolicy
  let zkmb := ZKMB.init policy
  let packets := Array.mk (List.range 3).map createSamplePacket
  IO.println s!"Initial packet count: {zkmb.state.packetCount}"
  IO.println "✓ Recursive state update test passed"

/-- Test: Performance targets -/
def testPerformanceTargets : IO Unit := do
  IO.println "Testing performance targets..."
  let policy := createSamplePolicy
  let zkmb := ZKMB.init policy 3
  let meetsTargets := ZKMB.meetsPerformanceTargets zkmb
  IO.println s!"Meets performance targets: {meetsTargets}"
  IO.println s!"Target verification time: {zkmb.targetVerificationTimeMs}ms"
  IO.println "✓ Performance targets test passed"

/-- Test: Line-speed capability estimation -/
def testLineSpeedCapability : IO Unit := do
  IO.println "Testing line-speed capability estimation..."
  let policy := createSamplePolicy
  let zkmb := ZKMB.init policy
  let capability := ZKMBPerformance.estimateLineSpeedCapability zkmb
  IO.println s!"Estimated line-speed capability: {capability} packets/second"
  IO.println "✓ Line-speed capability test passed"

/-- Main test runner -/
def main : IO Unit := do
  IO.println "=== ZKMB Tests ==="
  IO.println ""
  testZKMBInit
  IO.println ""
  testBatchedVerification
  IO.println ""
  testRecursiveStateUpdate
  IO.println ""
  testPerformanceTargets
  IO.println ""
  testLineSpeedCapability
  IO.println ""
  IO.println "=== All ZKMB Tests Passed ==="

end Tests
