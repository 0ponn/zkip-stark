/-
Simple benchmark for Lean/Aiur STARK proof generation
Mirrors the Rust/Plonky2 benchmark for comparison
-/

import ZkIpProtocol.Core.STARKIntegration
import ZkIpProtocol.Performance
import ZkIpProtocol.MerkleCommitment
import Ix.Aiur.Goldilocks

open ZkIpProtocol
open Aiur

def main : IO UInt32 := do
  IO.println "=== CHAP Eligibility Proof Benchmark ==="
  IO.println "Lean/Aiur Implementation"
  IO.println "Field: Goldilocks (p = 2^64 - 2^32 + 1)"
  IO.println ""

  -- Test case matching Rust benchmark:
  -- - merkle_root: hash of committed data
  -- - threshold: 500 (predicate: attribute >= 500)
  -- - attribute_value: 1000 (private, satisfies predicate)
  let merkleRootBytes := ByteArray.mk (Array.mk (List.replicate 8 (0x12 : UInt8)))

  let circuit : PredicateCircuit := {
    attributeValue := 1000  -- Private attribute value
    merkleRoot := merkleRootBytes
    threshold := 500
    operator := ">="
    merkleProof := {
      path := #[]
      rootHash := merkleRootBytes
      isLeft := #[]
    }
    output := true
  }

  IO.println "Test case:"
  IO.println s!"  Merkle root: {merkleRootBytes.size} bytes"
  IO.println s!"  Threshold: {circuit.threshold}"
  IO.println s!"  Attribute (private): {circuit.attributeValue}"
  IO.println s!"  Operator: {circuit.operator}"
  IO.println ""

  -- Convert to field elements (Goldilocks)
  let merkleRootHash := merkleRootBytes.hash.toNat
  let publicInputs : Array Aiur.G := #[
    Aiur.G.ofNat merkleRootHash,
    Aiur.G.ofNat circuit.threshold
  ]
  let privateInputs : Array Aiur.G := #[
    Aiur.G.ofNat circuit.attributeValue
  ]

  IO.println "Running benchmark..."
  IO.println ""

  -- Run profiling
  let metrics ← profileSTARKProof circuit publicInputs privateInputs

  IO.println "=== Results ==="
  IO.println s!"Proof generation:   {metrics.proofGenTimeMs} ms"
  IO.println s!"Proof verification: {metrics.proofVerifyTimeMs} ms"
  IO.println s!"Proof size:         {metrics.proofSizeBytes} bytes (~{metrics.proofSizeBytes / 1024} KB)"
  IO.println s!"Claim size:         {metrics.claimSize} field elements"
  IO.println ""

  -- Run multiple iterations for average
  IO.println "Running 10 iterations for average..."
  let mut totalGen : Nat := 0
  let mut totalVer : Nat := 0

  for _ in [0:10] do
    let m ← profileSTARKProof circuit publicInputs privateInputs
    totalGen := totalGen + m.proofGenTimeMs
    totalVer := totalVer + m.proofVerifyTimeMs
    IO.print "."

  IO.println ""
  IO.println ""
  IO.println "=== Average over 10 iterations ==="
  IO.println s!"Proof generation:   {totalGen / 10} ms"
  IO.println s!"Proof verification: {totalVer / 10} ms"

  return 0
