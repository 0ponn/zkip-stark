import Ix.Aiur.Bytecode

namespace ZkIpProtocol

open Aiur

/-- Application Binary Interface (ABI) for circuit public inputs -/
structure CircuitABI where
  funIdx : Aiur.Bytecode.FunIdx
  privateInputCount : Nat
  publicInputCount : Nat
  outputCount : Nat
  claimSize : Nat
  deriving Repr

namespace CircuitABI

/-- Calculate claim size from ABI -/
def totalClaimSize (abi : CircuitABI) : Nat :=
  2 + abi.privateInputCount + abi.publicInputCount + abi.outputCount

end CircuitABI

end ZkIpProtocol
