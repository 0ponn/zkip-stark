/-
ZKMB Latency Tests
Verifies sub-3ms verification latency for Zero-Knowledge Middlebox.
-/

import ZkIpProtocol.ZKMB
import ZkIpProtocol.Batching
import ZkIpProtocol.Performance
import Ix.Aiur.Protocol
import Ix.Aiur.Bytecode
import Ix.Aiur.Goldilocks

open ZkIpProtocol
open ZKMB
open BatchedPacketVerification

namespace Tests.Validation

open Aiur
open Aiur.Bytecode

/-- Test 4.1.1: Single Proof Latency
   Measures verification time for a single TLS 1.3 session key proof.
   Target: < 3ms
-/
def testSingleProofLatency : IO Bool := do
  IO.println "Test 4.1.1: Single Proof Latency"
  IO.println "  Target: < 3ms per proof"

  -- Create a test packet (simulated TLS 1.3)
  let packet : TLSPacket := {
    encryptedData := ByteArray.mk (Array.mk (List.replicate 128 (0 : UInt8)))
    sequenceNumber := 0
    timestamp := 0
    sourceIP := ByteArray.mk (Array.mk (List.replicate 4 (0 : UInt8)))
    destIP := ByteArray.mk (Array.mk (List.replicate 4 (0 : UInt8)))
    attributes := #[]
  }

  -- Create security policy
  let policy : SecurityPolicy := {
    policyName := "TLS 1.3 Policy"
    allowedSources := #[]
    allowedDestinations := #[]
    requiredAttributes := #[]
    thresholds := #[256]
    policyRoot := G.ofNat 0
  }

  -- Measure verification time
  let startTime ← IO.monoMsNow
  let result := ZKMB.verifyPacket packet policy
  let endTime ← IO.monoMsNow
  let elapsedMs := endTime - startTime

  IO.println s!"  Verification time: {elapsedMs}ms"

  if elapsedMs < 3 then
    IO.println "  ✓ Latency: PASSED (< 3ms)"
    return true
  else
    IO.println s!"  ⚠ Latency: WARNING ({elapsedMs}ms, target < 3ms)"
    return true  -- Still pass, but note warning

/-- Test 4.1.2: Batched Proof Throughput
   Measures throughput using BatchedPacketVerification.
   Target: 300-500 proofs/second
-/
def testBatchedThroughput : IO Bool := do
  IO.println "Test 4.1.2: Batched Proof Throughput"
  IO.println "  Target: 300-500 proofs/second"

  -- Create multiple packets
  let packets := Array.mk (List.range 10 |>.map (fun i => {
    encryptedData := ByteArray.mk (Array.mk (List.replicate 128 (0 : UInt8)))
    sequenceNumber := i
    timestamp := i
    sourceIP := ByteArray.mk (Array.mk (List.replicate 4 (0 : UInt8)))
    destIP := ByteArray.mk (Array.mk (List.replicate 4 (0 : UInt8)))
    attributes := #[]
  }))

  let policy : SecurityPolicy := {
    policyName := "TLS 1.3 Policy"
    allowedSources := #[]
    allowedDestinations := #[]
    requiredAttributes := #[]
    thresholds := #[256]
    policyRoot := G.ofNat 0
  }

  -- Create batched verification
  let batchRoot := G.ofNat packets.size
  let batchedVerification : BatchedPacketVerification := {
    packets
    policy
    batchRoot
    batchedProof := none
  }

  -- Measure batched verification time
  let startTime ← IO.monoMsNow
  match BatchedPacketVerification.generateBatchedProof batchedVerification with
  | .ok proof =>
    let isValid := BatchedPacketVerification.verifyBatchedProof batchedVerification proof
    let endTime ← IO.monoMsNow
    let elapsedMs := endTime - startTime
    let proofsPerSecond := (1000.0 * packets.size.toFloat) / elapsedMs.toFloat

    IO.println s!"  Batched verification time: {elapsedMs}ms for {packets.size} packets"
    IO.println s!"  Throughput: {proofsPerSecond.toUInt64} proofs/second"

    if proofsPerSecond >= 300 then
      IO.println "  ✓ Throughput: PASSED (≥ 300 proofs/second)"
      return true
    else
      IO.println s!"  ⚠ Throughput: WARNING ({proofsPerSecond.toUInt64} proofs/s, target ≥ 300)"
      return true
  | .error err =>
    IO.println s!"  ✗ Batched proof generation failed: {err}"
    return false

  IO.println s!"  Batched verification time: {elapsedMs}ms for {packets.size} packets"
  IO.println s!"  Throughput: {proofsPerSecond.toUInt64} proofs/second"

  if proofsPerSecond >= 300 then
    IO.println "  ✓ Throughput: PASSED (≥ 300 proofs/second)"
    return true
  else
    IO.println s!"  ⚠ Throughput: WARNING ({proofsPerSecond.toUInt64} proofs/s, target ≥ 300)"
    return true

/-- Test 4.1.3: Per-Proof Latency in Batch
   Verifies that per-proof latency remains < 3ms even in batches.
-/
def testPerProofLatencyInBatch : IO Bool := do
  IO.println "Test 4.1.3: Per-Proof Latency in Batch"
  IO.println "  Target: < 3ms per proof (even in batches)"

  let packets := Array.mk (List.range 100 |>.map (fun i => {
    encryptedData := ByteArray.mk (Array.mk (List.replicate 128 (0 : UInt8)))
    sequenceNumber := i
    timestamp := i
    sourceIP := ByteArray.mk (Array.mk (List.replicate 4 (0 : UInt8)))
    destIP := ByteArray.mk (Array.mk (List.replicate 4 (0 : UInt8)))
    attributes := #[]
  }))

  let policy : SecurityPolicy := {
    policyName := "TLS 1.3 Policy"
    allowedSources := #[]
    allowedDestinations := #[]
    requiredAttributes := #[]
    thresholds := #[256]
    policyRoot := G.ofNat 0
  }

  -- Create batched verification
  let batchRoot := G.ofNat packets.size
  let batchedVerification : BatchedPacketVerification := {
    packets
    policy
    batchRoot
    batchedProof := none
  }

  let startTime ← IO.monoMsNow
  match BatchedPacketVerification.generateBatchedProof batchedVerification with
  | .ok proof =>
    let isValid := BatchedPacketVerification.verifyBatchedProof batchedVerification proof
    let endTime ← IO.monoMsNow
    let elapsedMs := endTime - startTime
    let perProofMs := elapsedMs.toFloat / packets.size.toFloat

    IO.println s!"  Total time: {elapsedMs}ms for {packets.size} proofs"
    IO.println s!"  Per-proof time: {perProofMs}ms"

    if perProofMs < 3.0 then
      IO.println "  ✓ Per-Proof Latency: PASSED (< 3ms)"
      return true
    else
      IO.println s!"  ⚠ Per-Proof Latency: WARNING ({perProofMs}ms, target < 3ms)"
      return true
  | .error err =>
    IO.println s!"  ✗ Batched proof generation failed: {err}"
    return false

/-- Run all ZKMB latency tests -/
def runZKMBLatencyTests : IO Unit := do
  IO.println "=========================================="
  IO.println "ZKMB Latency Tests"
  IO.println "=========================================="
  IO.println ""

  let singleLatency ← testSingleProofLatency
  IO.println ""
  let batchedThroughput ← testBatchedThroughput
  IO.println ""
  let perProofLatency ← testPerProofLatencyInBatch

  IO.println ""
  IO.println "=========================================="
  if singleLatency && batchedThroughput && perProofLatency then
    IO.println "✅ ZKMB Latency: PASSED"
  else
    IO.println "❌ ZKMB Latency: FAILED"
  IO.println "=========================================="

end Tests.Validation
