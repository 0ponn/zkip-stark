/-
Tests for STARK proof integration using ix's Aiur system: certificate
generation and verification through the library entry points, plus the
performance profiler.
-/

import ZkIpProtocol.MerkleCommitment
import ZkIpProtocol.Advertisement
import ZkIpProtocol.STARKIntegration
import ZkIpProtocol.Performance

namespace Tests

open ZkIpProtocol

def testIxon : Ixon := {
  id := 1
  attributes := #[IPAttribute.performance 1500, IPAttribute.security 8, IPAttribute.efficiency 95]
  merkleRoot := ByteArray.empty
  timestamp := 1000
}

def testPredicate : IPPredicate := { operator := ">", threshold := 1000 }

/-- Certificate for attribute 0 (1500 > 1000) verifies; a swapped commitment does not. -/
def testCertificateRoundTrip : IO Unit := do
  IO.println "=== Certificate Round Trip ==="
  let some cert ← generateCertificateWithSTARK testIxon testPredicate 0
    | throw (IO.userError "certificate generation failed")
  IO.println s!"✓ certificate: {cert.proof.proofData.size} proof bytes, {cert.proof.publicInputs.size} claim elements"
  if !(← verifyCertificate cert) then throw (IO.userError "honest certificate failed to verify")
  IO.println "✓ verifyCertificate accepts the honest certificate"
  let swapped := { cert with commitment := cert.commitment.set! 0 (cert.commitment.get! 0 ^^^ 0x01) }
  if ← verifyCertificate swapped then throw (IO.userError "swapped commitment verified")
  IO.println "✓ verifyCertificate rejects a swapped commitment"

/-- Performance profiling of the fused circuit on the same fixture. -/
def testPerformanceProfiling : IO Unit := do
  IO.println "\n=== Performance Profiling ==="
  analyzeCircuitComplexity
  let leaves := testIxon.attributes.map (·.leaf)
  let root ← buildMerkleTree leaves
  let some path := generateProof leaves 0 | throw (IO.userError "no path for index 0")
  let metrics ← profileSTARKProof testPredicate.threshold root leaves[0]! path
  printMetrics metrics
  if metrics.proofVerifyTimeMs == 0 then throw (IO.userError "profiler: verification failed")

end Tests

def main : IO Unit := do
  Tests.testCertificateRoundTrip
  Tests.testPerformanceProfiling
  IO.println "\n=== STARK Tests Complete ==="
