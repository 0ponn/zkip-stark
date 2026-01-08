/-
Financial Vector: Financial metadata structure for car financing eligibility.
Uses ByteArray patterns compatible with core hash units.
-/

import ZkIpProtocol.CoreTypes
import Ix.Aiur.Goldilocks

namespace ZkIpProtocol.Apps.Financing

open Aiur

/-- Goldilocks field element type -/
abbrev G := Aiur.G

/-- Financial metadata vector -/
structure FinancialVector where
  creditScore : Nat
  income : Nat
  debtToIncomeRatio : Nat
  lenderId : ByteArray
  merkleRoot : ByteArray
  deriving Repr, Inhabited

namespace FinancialVector

/-- Convert credit score to field element -/
def creditScoreToField (fv : FinancialVector) : G :=
  G.ofNat fv.creditScore

/-- Convert income to field element -/
def incomeToField (fv : FinancialVector) : G :=
  G.ofNat fv.income

/-- Convert debt-to-income ratio to field element (as percentage * 100, e.g., 30% = 3000) -/
def debtToIncomeToField (fv : FinancialVector) : G :=
  G.ofNat fv.debtToIncomeRatio

/-- Convert lender ID to field elements (first 8 bytes as Nat) -/
def lenderIdToField (fv : FinancialVector) : G :=
  if fv.lenderId.size >= 8 then
    let bytes := fv.lenderId.toList.take 8
    let nat := bytes.foldl (fun acc b => acc * 256 + b.toNat) 0
    G.ofNat nat
  else
    G.ofNat 0

end FinancialVector

/-- Lender eligibility thresholds -/
structure LenderThresholds where
  minIncome : Nat
  minCreditScore : Nat
  maxDebtToIncome : Nat
  lenderId : ByteArray
  deriving Repr, Inhabited

namespace LenderThresholds

/-- Convert thresholds to field elements -/
def minIncomeToField (lt : LenderThresholds) : G :=
  G.ofNat lt.minIncome

def minCreditScoreToField (lt : LenderThresholds) : G :=
  G.ofNat lt.minCreditScore

def maxDebtToIncomeToField (lt : LenderThresholds) : G :=
  G.ofNat lt.maxDebtToIncome

def lenderIdToField (lt : LenderThresholds) : G :=
  if lt.lenderId.size >= 8 then
    let bytes := lt.lenderId.toList.take 8
    let nat := bytes.foldl (fun acc b => acc * 256 + b.toNat) 0
    G.ofNat nat
  else
    G.ofNat 0

end LenderThresholds

end ZkIpProtocol.Apps.Financing
