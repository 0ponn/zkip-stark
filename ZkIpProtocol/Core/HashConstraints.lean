/-
Hash Function Constraints Optimized for NoCap Hash Unit
Implements Poseidon hash as circuit constraints for efficient hardware acceleration.
-/

import ZkIpProtocol.Core.CircuitABI
import ZkIpProtocol.Core.PoseidonConstants
import Ix.Aiur.Protocol
import Ix.Aiur.Bytecode
import Ix.Aiur.Goldilocks
import Ix.Aiur.Term
import Ix.Aiur.Simple
import Ix.Aiur.Compile

namespace ZkIpProtocol

open Aiur
open Aiur.Bytecode
open Aiur.Term

/-- Poseidon hash parameters optimized for NoCap Hash Unit -/
structure PoseidonParams where
  /-- Number of rounds in full rounds -/
  fullRounds : Nat
  /-- Number of rounds in partial rounds -/
  partialRounds : Nat
  /-- State size (width) -/
  width : Nat
  /-- Rate (number of field elements processed per permutation) -/
  rate : Nat
  deriving Repr

namespace PoseidonParams

/-- Standard Poseidon parameters for Goldilocks field -/
def standard : PoseidonParams := {
  fullRounds := 8
  partialRounds := 22
  width := 12
  rate := 8
}

end PoseidonParams

namespace PoseidonDsl

def zeroTerm : Term := Term.data (Data.field (Aiur.G.ofNat 0))
def oneTerm : Term := Term.data (Data.field (Aiur.G.ofNat 1))

def constTerm (g : Aiur.G) : Term :=
  Term.data (Data.field g)

def pow7 (x : Term) : Term :=
  let x2 := Term.mul x x
  let x4 := Term.mul x2 x2
  let x6 := Term.mul x4 x2
  Term.mul x6 x

def addRoundConstants (state : Array Term) (offset : Nat) : Array Term :=
  state.mapIdx (fun i term =>
    let c := PoseidonGoldilocks.roundConstants.getD (offset + i) (Aiur.G.ofNat 0)
    Term.add term (constTerm c)
  )

def linComb (coeffs : Array Aiur.G) (state : Array Term) : Term :=
  Id.run do
    let mut acc := zeroTerm
    for idx in [0:coeffs.size] do
      let coeff := coeffs.getD idx (Aiur.G.ofNat 0)
      let term := Term.mul (constTerm coeff) (state[idx]!)
      acc := Term.add acc term
    return acc

def matMul (matrix : Array (Array Aiur.G)) (state : Array Term) : Array Term :=
  matrix.map (fun row => linComb row state)

def applyFullSbox (state : Array Term) : Array Term :=
  state.map pow7

def poseidonPartialRound (state : Array Term) (roundIdx : Nat) : Array Term :=
  Id.run do
    let t := PoseidonGoldilocks.t
    let cIdx := (PoseidonGoldilocks.nRoundsF / 2 + 1) * t + roundIdx
    let base := (t * 2 - 1) * roundIdx
    let state0 := Term.add (pow7 (state[0]!)) (constTerm (PoseidonGoldilocks.roundConstants.getD cIdx (Aiur.G.ofNat 0)))
    let mut updated := state.set! 0 state0
    let mut s0 := zeroTerm
    for j in [0:t] do
      let coeff := PoseidonGoldilocks.sparseMatrixConstants.getD (base + j) (Aiur.G.ofNat 0)
      s0 := Term.add s0 (Term.mul (constTerm coeff) (updated[j]!))
    for k in [1:t] do
      let coeff := PoseidonGoldilocks.sparseMatrixConstants.getD (base + t + k - 1) (Aiur.G.ofNat 0)
      let term := Term.mul (constTerm coeff) state0
      updated := updated.set! k (Term.add (updated[k]!) term)
    return updated.set! 0 s0

def poseidonPermute12 (state : Array Term) : Array Term :=
  Id.run do
    let t := PoseidonGoldilocks.t
    let nRoundsF := PoseidonGoldilocks.nRoundsF
    let nRoundsP := PoseidonGoldilocks.nRoundsP
    let mut st := addRoundConstants state 0
    let firstHalfRounds := nRoundsF / 2 - 1
    for r in [0:firstHalfRounds] do
      st := applyFullSbox st
      st := addRoundConstants st ((r + 1) * t)
      st := matMul PoseidonGoldilocks.mdsMatrix st
    st := applyFullSbox st
    st := addRoundConstants st ((nRoundsF / 2) * t)
    st := matMul PoseidonGoldilocks.preSparseMatrix st
    for r in [0:nRoundsP] do
      st := poseidonPartialRound st r
    for r in [0:firstHalfRounds] do
      st := applyFullSbox st
      st := addRoundConstants st ((nRoundsF / 2 + 1) * t + nRoundsP + r * t)
      st := matMul PoseidonGoldilocks.mdsMatrix st
    st := applyFullSbox st
    st := matMul PoseidonGoldilocks.mdsMatrix st
    return st

def poseidonHashTerm (inputs : Array Term) : Except String Term := do
  if inputs.size == 0 then
    throw "Cannot hash empty input"
  if inputs.size > PoseidonGoldilocks.rate then
    throw s!"Poseidon input size {inputs.size} exceeds sponge rate {PoseidonGoldilocks.rate}"
  let mut state := Array.replicate PoseidonGoldilocks.t zeroTerm
  for idx in [0:inputs.size] do
    state := state.set! idx (inputs[idx]!)
  let permuted := poseidonPermute12 state
  return permuted[0]!

end PoseidonDsl

/-- Poseidon hash circuit: computes Poseidon hash as circuit constraints -/
structure PoseidonHashCircuit where
  /-- Input: array of field elements to hash -/
  inputs : Array Aiur.G
  /-- Output: hash result (single field element) -/
  output : Aiur.G
  /-- Parameters -/
  params : PoseidonParams

namespace PoseidonHashCircuit

/-- Convert Poseidon hash to Aiur bytecode -/
def toAiurBytecode (circuit : PoseidonHashCircuit) : Except String (Bytecode.Toplevel × CircuitABI) := do
  -- Poseidon hash implementation as circuit constraints
  -- Optimized for NoCap Hash Unit which can accelerate:
  -- - Modular arithmetic operations
  -- - S-box operations (x^7 in Goldilocks)
  -- - Matrix multiplications (MDS matrix)

  let inputSize := circuit.inputs.size
  if inputSize == 0 then
    throw "Cannot hash empty input"
  if inputSize > PoseidonGoldilocks.rate then
    throw s!"Poseidon input size {inputSize} exceeds sponge rate {PoseidonGoldilocks.rate}"

  let mainFunctionName := Aiur.Global.mk (.mkSimple "poseidonHash")

  -- Build function signature: poseidonHash(inputs: [G; n]) -> G
  let rec buildInputs (idx : Nat) (acc : List (Aiur.Local × Aiur.Typ)) : List (Aiur.Local × Aiur.Typ) :=
    if idx >= inputSize then
      acc
    else
      buildInputs (idx + 1) (acc ++ [((Aiur.Local.str s!"input{idx}"), Aiur.Typ.field)])
  termination_by inputSize - idx
  decreasing_by simp_wf; omega

  let inputsList := buildInputs 0 []

  let inputTerms : Array Term := Array.ofFn (fun i : Fin inputSize =>
    Term.var (Aiur.Local.str s!"input{i.val}"))
  let outputTerm ← PoseidonDsl.poseidonHashTerm inputTerms
  let body := Aiur.Term.ret outputTerm

  let outputType := Aiur.Typ.field

  let mainFunction : Aiur.Function := {
    name := mainFunctionName
    inputs := inputsList
    output := outputType
    body
    unconstrained := false
  }

  let toplevel : Aiur.Toplevel := {
    dataTypes := #[]
    functions := #[mainFunction]
  }

  let typedDecls ← Aiur.Toplevel.checkAndSimplify toplevel
    |>.mapError (fun err => s!"Check and simplify failed: {err}")

  let bytecodeToplevel := Aiur.TypedDecls.compile typedDecls

  let abi : CircuitABI := {
    funIdx := 0
    privateInputCount := 0  -- All inputs are public for hash
    publicInputCount := inputSize
    outputCount := 1
    claimSize := 2 + inputSize + 1
  }

  return (bytecodeToplevel, abi)

end PoseidonHashCircuit

/-- Merkle tree hash: optimized for NoCap Hash Unit -/
structure MerkleHashCircuit where
  /-- Left child hash -/
  left : Aiur.G
  /-- Right child hash -/
  right : Aiur.G
  /-- Output: parent hash -/
  output : Aiur.G

namespace MerkleHashCircuit

/-- Convert Merkle hash to Aiur bytecode -/
def toAiurBytecode (_circuit : MerkleHashCircuit) : Except String (Bytecode.Toplevel × CircuitABI) := do
  -- Merkle tree hash: hash(left || right)
  -- Domain separated: H(1 || left || right)
  -- Optimized for NoCap: single Poseidon hash call

  let mainFunctionName := Aiur.Global.mk (.mkSimple "merkleHash")

  let inputsList : List (Aiur.Local × Aiur.Typ) := [
    ((Aiur.Local.str "left"), Aiur.Typ.field),
    ((Aiur.Local.str "right"), Aiur.Typ.field)
  ]

  let leftTerm := Aiur.Term.var (Aiur.Local.str "left")
  let rightTerm := Aiur.Term.var (Aiur.Local.str "right")
  let inputs := #[PoseidonDsl.oneTerm, leftTerm, rightTerm]
  let outputTerm ← PoseidonDsl.poseidonHashTerm inputs
  let body := Aiur.Term.ret outputTerm

  let mainFunction : Aiur.Function := {
    name := mainFunctionName
    inputs := inputsList
    output := Aiur.Typ.field
    body
    unconstrained := false
  }

  let toplevel : Aiur.Toplevel := {
    dataTypes := #[]
    functions := #[mainFunction]
  }

  let typedDecls ← Aiur.Toplevel.checkAndSimplify toplevel
    |>.mapError (fun err => s!"Check and simplify failed: {err}")

  let bytecodeToplevel := Aiur.TypedDecls.compile typedDecls

  let abi : CircuitABI := {
    funIdx := (0 : Bytecode.FunIdx)
    privateInputCount := 0
    publicInputCount := 2
    outputCount := 1
    claimSize := 5  -- functionChannel + funIdx + 2 inputs + 1 output
  }

  return (bytecodeToplevel, abi)

end MerkleHashCircuit

end ZkIpProtocol
