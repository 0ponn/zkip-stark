/-
Performance Profiling for ZK-IP Protocol
Measures constraint count, proof generation time, and proof size.
-/

import ZkIpProtocol.Advertisement
import ZkIpProtocol.STARKIntegration
import ZkIpProtocol.MerkleCommitment
import Ix.Aiur.Protocol
import Ix.Aiur.Stages.Bytecode
import Ix.Aiur.Goldilocks

namespace ZkIpProtocol

open Aiur
open Aiur.Bytecode

/-- Performance metrics for a STARK proof -/
structure ProofMetrics where
  /-- Number of constraints in the circuit -/
  constraintCount : Nat
  /-- Proof generation time in milliseconds -/
  proofGenTimeMs : Nat
  /-- Proof verification time in milliseconds -/
  proofVerifyTimeMs : Nat
  /-- Proof size in bytes -/
  proofSizeBytes : Nat
  /-- Claim size (number of field elements) -/
  claimSize : Nat
  /-- Estimated constraint count from proof size (2^log2) -/
  estimatedConstraints : Nat
  deriving Repr

namespace ProofMetrics

/-- Estimate constraint count from proof size -/
def estimateConstraintsFromProofSize (proofSizeBytes : Nat) : Nat :=
  -- Rough heuristic: STARK proofs scale with constraint count
  -- For Goldilocks field, each constraint contributes ~8-16 bytes to proof
  -- This is a rough estimate based on FRI structure
  let bytesPerConstraint := 8  -- Conservative estimate
  proofSizeBytes / bytesPerConstraint

/-- Calculate constraint count from bytecode -/
def countConstraints (bytecodeToplevel : Bytecode.Toplevel) : Nat :=
  -- Count operations across all functions
  let countOpsInFunction (func : Bytecode.Function) : Nat :=
    func.body.ops.size
  bytecodeToplevel.functions.foldl (fun acc func => acc + countOpsInFunction func) 0

end ProofMetrics

/-- Profile proof generation and verification of the fused circuit for one
committed leaf. -/
def profileSTARKProof (threshold : Nat) (root : ByteArray) (leaf : ByteArray) (path : MerkleProof)
    : IO ProofMetrics := do
  let fs ← fusedSystem
  let constraintCount := ProofMetrics.countConstraints fs.bytecode
  let system := fs.system
  let args := (fusedPublicInputs threshold (leaf.extract 0 32) root).map Aiur.G.ofNat
  let ioBuffer := fusedIO leaf path
  let startTime ← IO.monoMsNow
  let (claim, proof, _) := Aiur.AiurSystem.prove system fs.funIdx args ioBuffer
  let endTime ← IO.monoMsNow
  let proofGenTimeMs := endTime - startTime

  -- Step 4: Measure proof size
  let proofBytes := proof.toBytes
  let proofSizeBytes := proofBytes.size

  -- Step 5: Measure verification time
  let verifyStartTime ← IO.monoMsNow
  match Aiur.AiurSystem.verify system claim proof with
  | .ok () =>
    let verifyEndTime ← IO.monoMsNow
    let proofVerifyTimeMs := verifyEndTime - verifyStartTime

    return {
      constraintCount
      proofGenTimeMs
      proofVerifyTimeMs
      proofSizeBytes
      claimSize := claim.size
      estimatedConstraints := ProofMetrics.estimateConstraintsFromProofSize proofSizeBytes
    }
  | .error err =>
    IO.eprintln s!"Verification failed during profiling: {err}"
    return {
      constraintCount
      proofGenTimeMs
      proofVerifyTimeMs := 0
      proofSizeBytes
      claimSize := claim.size
      estimatedConstraints := ProofMetrics.estimateConstraintsFromProofSize proofSizeBytes
    }

/-- Print performance metrics -/
def printMetrics (metrics : ProofMetrics) : IO Unit := do
  IO.println "=== Performance Metrics ==="
  IO.println s!"Constraint Count (from bytecode): {metrics.constraintCount}"
  IO.println s!"Estimated Constraints (from proof size): {metrics.estimatedConstraints}"
  IO.println s!"Proof Generation Time: {metrics.proofGenTimeMs} ms"
  IO.println s!"Proof Verification Time: {metrics.proofVerifyTimeMs} ms"
  IO.println s!"Proof Size: {metrics.proofSizeBytes} bytes ({metrics.proofSizeBytes / 1024} KB)"
  IO.println s!"Claim Size: {metrics.claimSize} field elements"
  IO.println s!"Proof Generation Throughput: {if metrics.proofGenTimeMs > 0 then metrics.constraintCount * 1000 / metrics.proofGenTimeMs else 0} constraints/second"
  IO.println s!"Verification Throughput: {if metrics.proofVerifyTimeMs > 0 then metrics.constraintCount * 1000 / metrics.proofVerifyTimeMs else 0} constraints/second"

/-- Analyze the fused circuit's complexity. -/
def analyzeCircuitComplexity : IO Unit := do
  let fs ← fusedSystem
  let bytecodeToplevel := fs.bytecode
  let constraintCount := ProofMetrics.countConstraints bytecodeToplevel
  IO.println "=== Circuit Complexity Analysis ==="
  IO.println s!"Entry: {fusedEntry} (funIdx {fs.funIdx}), claim size {fusedClaimSize} field elements"
  IO.println s!"Function Count: {bytecodeToplevel.functions.size}"
  IO.println s!"Total Operations: {constraintCount}"
  for idx in [0:bytecodeToplevel.functions.size] do
    let func := bytecodeToplevel.functions[idx]!
    IO.println s!"  Function {idx}: ops={func.body.ops.size} inputSize={func.layout.inputSize} auxiliaries={func.layout.auxiliaries} lookups={func.layout.lookups}"

end ZkIpProtocol
