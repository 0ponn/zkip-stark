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

/-- Most attributes one commitment may hold. Every path is `keyedDepth` (32)
levels whatever the tree size, so this bounds work, not what a proof shows. -/
def maxAttributes : Nat := 2 ^ 16

/-- Batch sizes the circuit has entries for (`merkle_predicate_batchK`). -/
def entrySizes : Array Nat := #[1, 2, 4, 8]

/-- Most disclosures one certificate can carry. -/
def maxDisclosures : Nat := 8

/-- Smallest entry size that holds `k ≥ 1` disclosures. -/
def entrySizeFor (k : Nat) : Option Nat :=
  if k == 0 then none else entrySizes.find? (k ≤ ·)

/-- `xs` padded to `n` entries by repeating its last element. The prover and
the verifier pad identically, so the padding is part of the public claim. -/
def padTo {α : Type} [Inhabited α] (xs : Array α) (n : Nat) : Array α :=
  xs ++ Array.replicate (n - xs.size) xs.back!

/-- Compiled fused circuit plus the prover/verifier system built for it. -/
structure FusedSystem where
  bytecode : Aiur.Bytecode.Toplevel
  system : Aiur.AiurSystem
  /-- `funIdx` of `merkle_predicate_batchK`, aligned with `entrySizes`. -/
  funIdxs : Array Aiur.Bytecode.FunIdx

/-- One batch entry and the fixed trace shape its proofs are padded to. -/
structure FusedEntry where
  size : Nat
  funIdx : Aiur.Bytecode.FunIdx
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

/-- Claim length of entry size `n`: `[0, funIdx] ++ n · [threshold, a0..a7]
++ [r0..r7] ++ [1]`. -/
def claimSize (n : Nat) : Nat := 2 + 9 * n + 8 + 1

/-- Claim length of a single-disclosure certificate. -/
def fusedClaimSize : Nat := claimSize 1

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

/-- Private witness for `batch_item i`: channel 0 key `[i]` = leaf bytes,
channel 1 key `[i]` = path. -/
def fusedIOItems (items : Array (ByteArray × MerkleProof)) : Aiur.IOBuffer :=
  (Array.range items.size).foldl (init := default) fun b i =>
    let (leaf, proof) := items[i]!
    (b.extend 0 #[Aiur.G.ofNat i] (leaf.data.map Aiur.G.ofUInt8)).extend 1 #[Aiur.G.ofNat i]
      (pathBytes proof)

def fusedIO (leaf : ByteArray) (proof : MerkleProof) : Aiur.IOBuffer :=
  fusedIOItems #[(leaf, proof)]

def outputOne : Array Aiur.G := #[Aiur.G.ofNat 1]

/-- A distinct digest standing in for an untouched subtree of a calibration tree. -/
def fillerDigest (level idx : Nat) : ByteArray :=
  Hash.hash (ByteArray.mk #[0x03] ++ attrLeafBytes level ++ attrLeafBytes idx)

/-- Node at `level` (0 = leaves) and `idx` of a sparse depth-`keyedDepth`
calibration tree whose only real leaves are `leaves` (slot, leaf bytes); every
other subtree is a distinct filler digest, so no sibling repeats. -/
def sparseNode (leaves : Array (Nat × ByteArray)) : Nat → Nat → ByteArray
  | 0, idx => match leaves.find? (·.1 == idx) with
    | some (_, leaf) => leafHash leaf
    | none => fillerDigest 0 idx
  | level + 1, idx =>
    if leaves.any fun (p, _) => p >>> (level + 1) == idx then
      nodeHash (sparseNode leaves level (2 * idx)) (sparseNode leaves level (2 * idx + 1))
    else fillerDigest (level + 1) idx

/-- Authentication path of the leaf at `slot` in a sparse calibration tree. -/
def sparsePath (leaves : Array (Nat × ByteArray)) (slot : Nat) : MerkleProof :=
  { rootHash := sparseNode leaves keyedDepth 0
    path := (Array.range keyedDepth).map fun j => sparseNode leaves j ((slot >>> j) ^^^ 1)
    isLeft := (Array.range keyedDepth).map fun j => (slot >>> j) % 2 == 1 }

/-- Headroom over a calibration witness's raw row count. Rows are
content-addressed, so real witnesses differ from synthetic ones by a few
percent (3% measured at depth 32); a table within 1/8 of a power of two gets the
next one. -/
def calibratedHeight (raw padded : Nat) : Nat :=
  max padded (raw + raw / 8).nextPowerOfTwo

/-- Per-circuit floors from one synthetic witness for entry size `n`: item `i`
gets its own label and predicate from `pred i` (so no two items share a leaf or
a comparison) and sits at its label's slot in a sparse tree whose untouched
subtrees are distinct fillers. Each circuit's padded height, raised by
`calibratedHeight` from its raw row count. -/
def syntheticHeights (bytecode : Aiur.Bytecode.Toplevel) (system : Aiur.AiurSystem)
    (funIdx : Aiur.Bytecode.FunIdx) (n : Nat) (pred : Nat → String × Nat × Nat) : Array Nat :=
  let items := (Array.range n).map pred
  let leaves := items.map fun (label, attr, _) => (labelSlot label, attrLeaf label attr)
  let root := sparseNode leaves keyedDepth 0
  let args := (batchPublicInputs (items.map fun (label, _, t) => (t, attrIdOf label)) root).map
    Aiur.G.ofNat
  let io := fusedIOItems (leaves.map fun (slot, leaf) => (leaf, sparsePath leaves slot))
  let padded := Aiur.AiurSystem.traceHeights system funIdx args io
  -- Raw rows, in the order `traceHeights` reports circuits: constrained
  -- functions, then memory; the preprocessed gadget tables that follow have
  -- fixed heights. Any disagreement with `padded` keeps the padded heights.
  let raw : Array Nat := match bytecode.execute funIdx args io with
    | .error _ => #[]
    | .ok (_, _, qc) =>
      let nf := bytecode.functions.size
      ((Array.range nf).filter (bytecode.functions[·]!.constrained)).map (qc[·]!.uniqueRows)
        ++ (qc.extract nf qc.size).map (·.uniqueRows)
  let aligned := raw.size ≤ padded.size &&
    (Array.range raw.size).all fun i => raw[i]!.nextPowerOfTwo ≤ padded[i]!
  if !aligned then padded else
    (Array.range padded.size).map fun i =>
      if i < raw.size then calibratedHeight raw[i]! padded[i]! else padded[i]!

/-- The fixed trace shape of entry size `n`: per-circuit maximum over
synthetic witnesses. Every path is `keyedDepth` levels and a level costs the
same rows whichever side its sibling is on (`keyed_node`), so the shape does
not depend on which slots are used; extreme leaf bytes and thresholds cover the
predicate side. Aiur's memory and calls are content-addressed, so distinct
siblings, leaves and comparisons give the most rows; a real tree, whose empty
subtrees repeat, uses no more. Proofs whose heights still differ are refused by
the prover. -/
def calibrationHeights (bytecode : Aiur.Bytecode.Toplevel) (system : Aiur.AiurSystem)
    (funIdx : Aiur.Bytecode.FunIdx) (n : Nat) : Array Nat :=
  let label (base : String) (i : Nat) : String := if i == 0 then base else s!"{base}/{i}"
  let preds : List (Nat → String × Nat × Nat) :=
    [fun i => (label "performance" i, 2 ^ 32 - 1 - i, i),
     fun i => (label "custom/x" i, 0x14030201 + i * 0x01010101, 7 + i),
     fun i => (label "security" i, 0x8f8e8d8c + 2 * i, 0x8f8e8d8b + 2 * i)]
  let runs := preds.map fun pred => syntheticHeights bytecode system funIdx n pred
  match runs with
  | [] => #[]
  | first :: rest => rest.foldl (fun acc h => acc.zipWith (fun a b => max a b) h) first

def buildFusedSystem (c : Aiur.CommitmentParameters) (f : Aiur.FriParameters)
    : Except String FusedSystem := do
  let toplevel ← match fusedToplevel with
    | .ok t => pure t
    | .error g => .error s!"fused toplevel merge failed on clashing name: {g}"
  let compiled ← toplevel.compile
  let funIdxs ← entrySizes.mapM fun n =>
    match compiled.getFuncIdx (MerkleCircuit.merkleBatchEntry n) with
    | some i => pure i
    | none => .error s!"{MerkleCircuit.merkleBatchEntry n} not found after compile"
  pure { bytecode := compiled.bytecode, system := Aiur.AiurSystem.build compiled.bytecode c f, funIdxs }

initialize fusedSystemRef : IO.Ref (Option FusedSystem) ← IO.mkRef none
initialize fusedEntriesRef : IO.Ref (Array FusedEntry) ← IO.mkRef #[]

/-- The production system, built on first use and cached for the process. -/
def fusedSystem : IO FusedSystem := do
  if let some s ← fusedSystemRef.get then return s
  match buildFusedSystem starkCommitmentParams starkFriParams with
  | .error e => throw (IO.userError e)
  | .ok s =>
    fusedSystemRef.set (some s)
    return s

/-- Entry size `n` (one of `entrySizes`) with its calibrated shape, calibrated
on first use and cached for the process. -/
def fusedEntryFor (n : Nat) : IO FusedEntry := do
  if let some e := (← fusedEntriesRef.get).find? (·.size == n) then return e
  let fs ← fusedSystem
  let some k := entrySizes.idxOf? n | throw (IO.userError s!"no circuit entry for {n} disclosures")
  let funIdx := fs.funIdxs[k]!
  let floors := calibrationHeights fs.bytecode fs.system funIdx n
  let e : FusedEntry := { size := n, funIdx, floors, shape := floors.map Nat.log2 }
  fusedEntriesRef.modify (·.push e)
  return e

/-- The single-disclosure entry: the production path for one attribute. -/
def fusedEntry1 : IO FusedEntry := fusedEntryFor 1

end ZkIpProtocol
