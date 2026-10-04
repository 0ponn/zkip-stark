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

/-- Deepest Merkle path a certificate may use (65,536 attributes). Every proof
is padded to the trace shape of this depth, so the published per-circuit
heights do not reveal the tree size or anything else about the witness. -/
def maxDepth : Nat := 16

/-- Compiled fused circuit plus the prover/verifier system built for it, and
the fixed trace shape every proof is padded to. -/
structure FusedSystem where
  bytecode : Aiur.Bytecode.Toplevel
  funIdx : Aiur.Bytecode.FunIdx
  system : Aiur.AiurSystem
  /-- Per-circuit height floors passed to `AiurSystem.provePadded`. -/
  floors : Array Nat
  /-- The per-circuit log2 heights every proof publishes (`Proof.logDegrees`). -/
  shape : Array Nat

/-- The merged source toplevel: ix `core` + `byteStream` + `blake3` + our Merkle circuit. -/
def fusedToplevel : Except Aiur.Global Aiur.Source.Toplevel := do
  let t ← IxVM.core.merge IxVM.byteStream
  let t ← t.merge IxVM.blake3
  t.merge MerkleCircuit.merkleCircuit

/-- Entry the production path proves. Variable depth via `merkle_fold`. -/
def fusedEntry : Lean.Name := MerkleCircuit.merkleBatchEntry 1

/-- `[0, funIdx] ++ [threshold, a0..a7, r0..r7] ++ [1]`. -/
def fusedClaimSize : Nat := 20

/-- A 32-byte digest as eight little-endian u32 words, word `i` from bytes `[4i, 4i+3]`. -/
def rootWordNats (root : ByteArray) : Array Nat :=
  (Array.range 8).map fun i =>
    let bt (j : Nat) : Nat := (root.get! (4 * i + j)).toNat
    bt 0 + 0x100 * bt 1 + 0x10000 * bt 2 + 0x1000000 * bt 3

def rootWords (root : ByteArray) : Array Aiur.G := (rootWordNats root).map Aiur.G.ofNat

/-- Public inputs of a `merkle_predicate_batchK` claim, as Nats so range
guards run before `G.ofNat`: per item its threshold and attribute id words,
then the shared root words. -/
def batchPublicInputs (items : Array (Nat × ByteArray)) (root : ByteArray) : Array Nat :=
  items.flatMap (fun (threshold, attrId) => #[threshold] ++ rootWordNats attrId) ++ rootWordNats root

/-- Public inputs of the production (K = 1) claim. -/
def fusedPublicInputs (threshold : Nat) (attrId root : ByteArray) : Array Nat :=
  batchPublicInputs #[(threshold, attrId)] root

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

/-- Per-circuit heights of one synthetic `maxDepth` witness with
pairwise-distinct siblings and the given direction pattern, leaf value and
threshold. -/
def syntheticHeights (system : Aiur.AiurSystem) (funIdx : Aiur.Bytecode.FunIdx)
    (isLeft : Nat → Bool) (label : String) (attr threshold : Nat) : Array Nat :=
  let leaf := attrLeaf label attr
  let path := (Array.range maxDepth).map (fun j => leafHash (attrLeaf label (j + 1)))
  let dirs := (Array.range maxDepth).map isLeft
  let root := pathRoot leaf path dirs
  let proof : MerkleProof := { rootHash := root, path, isLeft := dirs }
  let args := (fusedPublicInputs threshold (attrIdOf label) root).map Aiur.G.ofNat
  Aiur.AiurSystem.traceHeights system funIdx args (fusedIO leaf proof)

/-- The fixed trace shape: per-circuit maximum over synthetic `maxDepth`
witnesses. A Merkle level costs a different number of rows depending on
whether the sibling is on the left or the right (the node preimage is built
in a different order), so all-left and all-right paths bound every mix;
extreme leaf bytes and thresholds cover the predicate side. Aiur's memory and
calls are content-addressed, so distinct siblings give the most rows. Proofs
whose heights still differ are refused by `generateSTARKProof`. -/
def calibrationHeights (system : Aiur.AiurSystem) (funIdx : Aiur.Bytecode.FunIdx) : Array Nat :=
  let patterns : List (Nat → Bool) := [fun _ => true, fun _ => false, (· % 2 == 0)]
  -- The leaf is a fixed 36 bytes for every label; two labels confirm the
  -- shape does not depend on which attribute is proved.
  let predicates : List (String × Nat × Nat) :=
    [("performance", 2 ^ 32 - 1, 0), ("custom/x", 0x14030201, 7), ("security", 0x8f8e8d8c, 0x8f8e8d8b)]
  let runs := patterns.flatMap fun dir => predicates.map fun (label, attr, thr) =>
    syntheticHeights system funIdx dir label attr thr
  match runs with
  | [] => #[]
  | first :: rest => rest.foldl (fun acc h => acc.zipWith (fun a b => max a b) h) first

def buildFusedSystem (c : Aiur.CommitmentParameters) (f : Aiur.FriParameters)
    : Except String FusedSystem := do
  let toplevel ← match fusedToplevel with
    | .ok t => pure t
    | .error g => .error s!"fused toplevel merge failed on clashing name: {g}"
  let compiled ← toplevel.compile
  let funIdx ← match compiled.getFuncIdx fusedEntry with
    | some i => pure i
    | none => .error s!"{fusedEntry} not found after compile"
  let system := Aiur.AiurSystem.build compiled.bytecode c f
  let floors := calibrationHeights system funIdx
  pure { bytecode := compiled.bytecode, funIdx, system, floors, shape := floors.map Nat.log2 }

initialize fusedSystemRef : IO.Ref (Option FusedSystem) ← IO.mkRef none

/-- The production system, built on first use and cached for the process. -/
def fusedSystem : IO FusedSystem := do
  if let some s ← fusedSystemRef.get then return s
  match buildFusedSystem starkCommitmentParams starkFriParams with
  | .error e => throw (IO.userError e)
  | .ok s =>
    fusedSystemRef.set (some s)
    return s


end ZkIpProtocol
