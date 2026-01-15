/-
Tests for Financing Eligibility Protocol using STARK proofs.
Verifies proof generation for lender eligibility checks.
-/

import ZkIpProtocol.Apps.Financing.FinancialVector
import ZkIpProtocol.Apps.Financing.LenderCircuits
import ZkIpProtocol.Core.STARKIntegration
import Ix.Aiur.Goldilocks

namespace Tests

open ZkIpProtocol.Apps.Financing
open Aiur

/-- Goldilocks field element type -/
abbrev G := Aiur.G

/-- Test financial vector -/
def testFinancialVector : FinancialVector := {
  creditScore := 750
  income := 75000
  debtToIncomeRatio := 2500  -- 25% (scaled by 100)
  lenderId := ByteArray.mk #[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
  merkleRoot := ByteArray.empty
}

/-- Test lender thresholds -/
def testLenderThresholds : LenderThresholds := {
  minIncome := 50000
  minCreditScore := 700
  maxDebtToIncome := 3000  -- 30% (scaled by 100)
  lenderId := ByteArray.mk #[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
}

/-- Test lender circuit -/
def testLenderCircuit : LenderCircuit := {
  financialVector := testFinancialVector
  thresholds := testLenderThresholds
  incomeWitness := FinancialVector.incomeToField testFinancialVector
  creditScoreWitness := FinancialVector.creditScoreToField testFinancialVector
  debtToIncomeWitness := FinancialVector.debtToIncomeToField testFinancialVector
  lenderIdWitness := FinancialVector.lenderIdToField testFinancialVector
  output := true
}

/-- Test circuit compilation -/
def testCircuitCompilation : IO Unit := do
  IO.println "=== Financing Circuit Compilation Test ==="
  
  match testLenderCircuit.toAiurBytecode with
  | .ok (bytecode, abi) =>
    IO.println "✓ Circuit compiled successfully"
    IO.println s!"  Function index: {abi.funIdx}"
    IO.println s!"  Public inputs: {abi.publicInputCount}"
    IO.println s!"  Private inputs: {abi.privateInputCount}"
    IO.println s!"  Outputs: {abi.outputCount}"
    IO.println s!"  Claim size: {abi.claimSize}"
  | .error err =>
    IO.println s!"✗ Circuit compilation failed: {err}"

/-- Test eligibility verification -/
def testEligibilityVerification : IO Unit := do
  IO.println "\n=== Eligibility Verification Test ==="
  
  let bindingOk := LenderCircuit.verifyLenderIdBinding testLenderCircuit
  let incomeOk := LenderCircuit.verifyIncomeThreshold testLenderCircuit
  let creditOk := LenderCircuit.verifyCreditScoreThreshold testLenderCircuit
  let debtOk := LenderCircuit.verifyDebtToIncomeThreshold testLenderCircuit
  let allOk := LenderCircuit.verifyEligibility testLenderCircuit
  
  IO.println s!"  Lender ID binding: {if bindingOk then "✓" else "✗"}"
  IO.println s!"  Income threshold: {if incomeOk then "✓" else "✗"}"
  IO.println s!"  Credit score threshold: {if creditOk then "✓" else "✗"}"
  IO.println s!"  Debt-to-income threshold: {if debtOk then "✓" else "✗"}"
  IO.println s!"  Overall eligibility: {if allOk then "✓ ELIGIBLE" else "✗ NOT ELIGIBLE"}"
  
  if !allOk then
    IO.println "✗ Eligibility verification failed"
  else
    IO.println "✓ Eligibility verification passed"

/-- Test STARK proof generation -/
def testSTARKProofGeneration : IO Unit := do
  IO.println "\n=== STARK Proof Generation Test ==="
  
  -- Prepare public inputs
  let lenderIdField := LenderThresholds.lenderIdToField testLenderThresholds
  let minIncomeField := LenderThresholds.minIncomeToField testLenderThresholds
  let minCreditScoreField := LenderThresholds.minCreditScoreToField testLenderThresholds
  let maxDebtToIncomeField := LenderThresholds.maxDebtToIncomeToField testLenderThresholds
  
  let publicInputs : Array G := #[
    lenderIdField,
    minIncomeField,
    minCreditScoreField,
    maxDebtToIncomeField
  ]
  
  -- Prepare private inputs
  let incomeWitness := FinancialVector.incomeToField testFinancialVector
  let creditScoreWitness := FinancialVector.creditScoreToField testFinancialVector
  let debtToIncomeWitness := FinancialVector.debtToIncomeToField testFinancialVector
  let lenderIdWitness := FinancialVector.lenderIdToField testFinancialVector
  let isValid := G.ofNat 1  -- Witness for validity
  
  let privateInputs : Array G := #[
    incomeWitness,
    creditScoreWitness,
    debtToIncomeWitness,
    lenderIdWitness,
    isValid
  ]
  
  IO.println s!"  Public inputs: {publicInputs.size} elements"
  IO.println s!"  Private inputs: {privateInputs.size} elements"
  
  IO.println "\n  Generating STARK proof..."
  let some proof ← LenderCircuit.generateLenderEligibilityProof
    testLenderCircuit
    publicInputs
    privateInputs
    | do
      IO.println "✗ Failed to generate STARK proof"
      return
  
  IO.println "✓ STARK proof generated successfully"
  IO.println s!"  Proof size: {proof.proofData.size} bytes"
  IO.println s!"  Public inputs in proof: {proof.publicInputs.size} elements"
  IO.println s!"  Verification key ID: {proof.vkId}"

/-- Run all financing tests -/
def main : IO Unit := do
  testCircuitCompilation
  testEligibilityVerification
  testSTARKProofGeneration
  IO.println "\n=== All Financing Tests Complete ==="

end Tests
