/-
Tests for minimal constant-returning circuit.
This test isolates FFI issues from circuit logic complexity.
Moved from STARKIntegration.lean for production cleanup.
-/

import ZkIpProtocol.STARKIntegration
import ZkIpProtocol.CoreTypes
import Ix.Aiur.Goldilocks
import Ix.Aiur.Protocol

namespace Tests

open ZkIpProtocol
open Aiur

/-- Minimal constant-returning circuit to isolate FFI issues -/
def PredicateCircuit.toAiurBytecodeMinimal : Except String (Bytecode.Toplevel × CircuitABI) := do
  let mainFunctionName := Global.mk (.mkSimple "constantReturn")
  -- Simplest possible circuit: no inputs, returns constant 1
  let mainFunction : Aiur.Function := {
    name := mainFunctionName
    inputs := []  -- No inputs at all
    output := Aiur.Typ.field
    body := Aiur.Term.ret (Aiur.Term.data (Aiur.Data.field (G.ofNat 1)))
    unconstrained := false
  }

  let toplevel : Aiur.Toplevel := { dataTypes := #[], functions := #[mainFunction] }
  let typedDecls ← Aiur.Toplevel.checkAndSimplify toplevel |>.mapError (fun err => s!"Check failed: {err}")
  let bytecodeToplevel := Aiur.TypedDecls.compile typedDecls

  let abi : CircuitABI := {
    funIdx := 0
    privateInputCount := 0
    publicInputCount := 0
    outputCount := 1
    claimSize := 2  -- functionChannel + funIdx only
  }
  return (bytecodeToplevel, abi)

/-- Test minimal constant circuit -/
def testMinimalCircuit : IO (Option STARKProof) := do
  let (bytecodeToplevel, abi) ← match PredicateCircuit.toAiurBytecodeMinimal with
    | .ok result => pure result
    | .error err =>
        IO.eprintln s!"[TEST] Minimal circuit compilation failed: {err}"
        return none

  IO.eprintln s!"[TEST] Minimal circuit compiled successfully"
  IO.eprintln s!"[TEST] ABI: funIdx={abi.funIdx}, publicInputs={abi.publicInputCount}, privateInputs={abi.privateInputCount}"

  let commitmentParams : CommitmentParameters := { logBlowup := 2 }
  let system := AiurSystem.build bytecodeToplevel commitmentParams
  IO.eprintln s!"[TEST] AiurSystem built successfully"

  let friParams : FriParameters := {
    logFinalPolyLen := 0
    numQueries := 100
    proofOfWorkBits := 20
  }
  IO.eprintln s!"[TEST] FRI params: logFinalPolyLen={friParams.logFinalPolyLen}, numQueries={friParams.numQueries}"

  let funIdx : Bytecode.FunIdx := abi.funIdx
  let args : Array G := #[]  -- No inputs for minimal circuit
  let ioBuffer : IOBuffer := default

  IO.eprintln s!"[TEST] About to call AiurSystem.prove..."

  try
    let (claim, proof, _) := AiurSystem.prove system friParams funIdx args ioBuffer
    IO.eprintln s!"[TEST] Proof generated successfully! Claim size: {claim.size}"
    let proofBytes := proof.toBytes
    IO.eprintln s!"[TEST] Proof bytes size: {proofBytes.size}"
    return some {
      publicInputs := claim.map (fun g =>
        let val := g.val.toNat
        natToByteArray val
      )
      proofData := proofBytes
      vkId := "aiur_vk_minimal"
    }
  catch ex =>
    IO.eprintln s!"[TEST] Stack overflow in minimal circuit: {ex}"
    return none

end Tests
