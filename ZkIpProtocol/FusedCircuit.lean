/-
The production circuit: `merkle_predicate_batch1` from `MerkleCircuit.lean`,
merged with ix's `core`, `byteStream` and `blake3` toplevels, compiled once
per process and cached together with its `AiurSystem`.

This file also owns the encoders both the prover and the verifier need so
they are defined exactly once: root words, path bytes, IO buffer layout.

Importing this file (transitively `Ix.Aiur.Meta` via `MerkleCircuit`) makes
`G` a syntax token, so any file that imports it must write `Aiur.G`, never a
bare `G` (spike 2026-10-03: `abbrev G := Aiur.G` fails with "unexpected
token 'G'").
-/
import ZkIpProtocol.CoreTypes
import ZkIpProtocol.MerkleCommitment
import ZkIpProtocol.MerkleCircuit
import Ix.IxVM.Core
import Ix.IxVM.ByteStream
import Ix.IxVM.Blake3
import Ix.Aiur.Compiler
import Ix.Aiur.Protocol

namespace ZkIpProtocol

/-- Shared STARK commitment parameters (production). -/
def starkCommitmentParams : Aiur.CommitmentParameters := { logBlowup := 2, capHeight := 0 }

/-- Shared STARK FRI parameters (production). -/
def starkFriParams : Aiur.FriParameters :=
  { logFinalPolyLen := 0, maxLogArity := 1, numQueries := 100
    commitProofOfWorkBits := 20, queryProofOfWorkBits := 0 }

/-- Compiled fused circuit plus the prover/verifier system built for it. -/
structure FusedSystem where
  bytecode : Aiur.Bytecode.Toplevel
  funIdx : Aiur.Bytecode.FunIdx
  system : Aiur.AiurSystem

/-- The merged source toplevel: ix `core` + `byteStream` + `blake3` + our Merkle circuit. -/
def fusedToplevel : Except Aiur.Global Aiur.Source.Toplevel := do
  let t ← IxVM.core.merge IxVM.byteStream
  let t ← t.merge IxVM.blake3
  t.merge MerkleCircuit.merkleCircuit

/-- Entry the production path proves. Variable depth via `merkle_fold`. -/
def fusedEntry : Lean.Name := MerkleCircuit.merkleBatchEntry 1

def buildFusedSystem (c : Aiur.CommitmentParameters) (f : Aiur.FriParameters)
    : Except String FusedSystem := do
  let toplevel ← match fusedToplevel with
    | .ok t => pure t
    | .error g => .error s!"fused toplevel merge failed on clashing name: {g}"
  let compiled ← toplevel.compile
  let funIdx ← match compiled.getFuncIdx fusedEntry with
    | some i => pure i
    | none => .error s!"{fusedEntry} not found after compile"
  pure { bytecode := compiled.bytecode, funIdx, system := Aiur.AiurSystem.build compiled.bytecode c f }

initialize fusedSystemRef : IO.Ref (Option FusedSystem) ← IO.mkRef none

/-- The production system, built on first use and cached for the process. -/
def fusedSystem : IO FusedSystem := do
  if let some s ← fusedSystemRef.get then return s
  match buildFusedSystem starkCommitmentParams starkFriParams with
  | .error e => throw (IO.userError e)
  | .ok s =>
    fusedSystemRef.set (some s)
    return s

/-- `[0, funIdx] ++ [threshold, r0..r7] ++ [1]`. -/
def fusedClaimSize : Nat := 12

/-- The 32-byte root as eight little-endian u32 words, word `i` from bytes `[4i, 4i+3]`. -/
def rootWordNats (root : ByteArray) : Array Nat :=
  (Array.range 8).map fun i =>
    let bt (j : Nat) : Nat := (root.get! (4 * i + j)).toNat
    bt 0 + 0x100 * bt 1 + 0x10000 * bt 2 + 0x1000000 * bt 3

def rootWords (root : ByteArray) : Array Aiur.G := (rootWordNats root).map Aiur.G.ofNat

/-- Public inputs of the fused claim, as Nats so range guards run before `G.ofNat`. -/
def fusedPublicInputs (threshold : Nat) (root : ByteArray) : Array Nat :=
  #[threshold] ++ rootWordNats root

/-- Flat path stream: per level `dir` (1 = sibling on the left) then the 32 sibling bytes. -/
def pathBytes (proof : MerkleProof) : Array Aiur.G :=
  (Array.range proof.path.size).foldl (init := #[]) fun acc j =>
    (acc.push (Aiur.G.ofUInt8 (if proof.isLeft[j]! then 1 else 0)))
      ++ (proof.path[j]!).data.map Aiur.G.ofUInt8

/-- Private witness for `batch_item 0`: channel 0 key `[0]` = leaf bytes, channel 1 key `[0]` = path. -/
def fusedIO (leaf : ByteArray) (proof : MerkleProof) : Aiur.IOBuffer :=
  let b := (default : Aiur.IOBuffer).extend 0 #[Aiur.G.ofNat 0] (leaf.data.map Aiur.G.ofUInt8)
  b.extend 1 #[Aiur.G.ofNat 0] (pathBytes proof)

def outputOne : Array Aiur.G := #[Aiur.G.ofNat 1]

end ZkIpProtocol
