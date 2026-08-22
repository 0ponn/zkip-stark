/-
M3 Task 2: BATCHED K-attribute disclosure under a SHARED root.

`merkle_predicate_batchK` proves K INDEPENDENT fused statements in ONE proof:
  for each i in 0..K:  attr_i > threshold_i
                       AND leafHash(encode(attr_i)) is a member of the tree
                       with the SAME public root,
  where `encode(attr_i)` = `ZkIpProtocol.attrLeafBytes attr_i`. Each item reuses
  the M2b/M3.1 machinery (predicate + leaf-from-attr + recursive `merkle_fold`
  membership), so the batch is exactly K single-disclosure statements fused under
  one commitment. See `ZkIpProtocol/MerkleCircuit.lean`.

Public args (per batch size K): K thresholds FIRST (t0..t_{K-1}), then the 8
shared root words r0..r7. Private witness (two channels, keyed by item index i):
  channel 0, key [i] : the 4 LE attr bytes (= leaf_i), length-constrained to 4.
  channel 1, key [i] : item i's authentication path as a flat ByteStream
                       (dir ++ 32 sibling bytes per level, level 0 first) — length
                       33*D, fed to `merkle_fold`. Depth D is a per-item knob.

The tree/root/paths are built OFF-circuit with the M2a scheme over leaves =
`attrLeafBytes attr`, so a passing proof means every in-circuit fold + leaf
derivation matches the M2a reference bit-for-bit AND all K items live under the
one committed root.

POSITIVE: K ∈ {1,2,4} committed attrs, each > its threshold -> execute out=1,
prove/verify OK, circuit root == M2a root. Per K, the circuit-statistics trace
row/height totals are printed (the scaling-study data feeding Task 3).
NEGATIVES (each rejected at execute):
  1. batched ad-switch: ONE item advertises an attr NOT committed under root
     (right predicate, wrong membership) -> that item's root binding breaks.
  2. one attr_i <= threshold_i -> that item's predicate fails.
  3. wrong sibling for one item; tampered shared public root word.
  4. truncated/malformed path (length not 33*D) for one item -> merkle_fold
     rejects (folds in the M3.1 minor).
-/

import ZkIpProtocol.Blake3Circuit
import ZkIpProtocol.MerkleCircuit
import ZkIpProtocol.MerkleCommitment
import Ix.Aiur.Compiler
import Ix.Aiur.Protocol
import Ix.Aiur.Statistics

open Aiur

namespace Tests.Validation.BatchDisclosure

def commitmentParameters : Aiur.CommitmentParameters := { logBlowup := 1, capHeight := 0 }
def friParameters : Aiur.FriParameters :=
  { logFinalPolyLen := 0, maxLogArity := 1, numQueries := 100
    commitProofOfWorkBits := 20, queryProofOfWorkBits := 0 }

def merkleToplevel : Except Aiur.Global Aiur.Source.Toplevel := do
  let t ← IxVM.core.merge IxVM.byteStream
  let t ← t.merge IxVM.blake3
  t.merge ZkIpProtocol.MerkleCircuit.merkleCircuit

/-- Recompose a 32-byte digest into the circuit's 8x u32 (little-endian) public
root words. -/
def rootWords (root : ByteArray) : Array Aiur.G :=
  (Array.range 8).map (fun i =>
    let bt (j : Nat) : Nat := (root.get! (4 * i + j)).toNat
    Aiur.G.ofNat (bt 0 + 0x100 * bt 1 + 0x10000 * bt 2 + 0x1000000 * bt 3))

/-- Public args for a K-batch: K thresholds, then the 8 shared root words. -/
def publicArgs (thresholds : Array Nat) (root : ByteArray) : Array Aiur.G :=
  (thresholds.map Aiur.G.ofNat) ++ rootWords root

/-- One disclosed item: leaf bytes + its path (siblings, directions). -/
structure Item where
  leaf : ByteArray
  sibs : Array ByteArray
  dirs : Array UInt8
  deriving Inhabited

/-- Flat path stream for one item: `dir ++ 32 sibling bytes` per level, level 0
first (the `merkle_fold` / `merkle_path` layout). -/
def pathBytes (it : Item) : Array Aiur.G :=
  (Array.range it.sibs.size).foldl
    (fun acc j => (acc.push (Aiur.G.ofUInt8 (it.dirs[j]!)))
      ++ (it.sibs[j]!).data.map Aiur.G.ofUInt8) #[]

/-- IO buffer for a K-batch: for each item i, its 4 leaf bytes on channel 0 keyed
by [i], and its flat path on channel 1 keyed by [i]. -/
def buildIO (items : Array Item) : Aiur.IOBuffer :=
  (Array.range items.size).foldl (fun buf i =>
    let it := items[i]!
    let buf := buf.extend 0 #[Aiur.G.ofNat i] (it.leaf.data.map Aiur.G.ofUInt8)
    buf.extend 1 #[Aiur.G.ofNat i] (pathBytes it)) (default : Aiur.IOBuffer)

def outputOne : Array Aiur.G := #[Aiur.G.ofNat 1]

/-- Eight committed attribute values => a perfect depth-3 tree (path length 3).
Leaves are the canonical 4-byte LE encodings the circuit derives in-circuit. -/
def attrs : Array Nat := #[500, 1500, 2500, 3500, 4500, 5500, 6500, 7500]

def leaves : Array ByteArray := attrs.map ZkIpProtocol.attrLeafBytes

def runTests : IO Unit := do
  IO.println "=== M3 Task 2: BATCHED K-attribute disclosure under a shared root ==="
  let toplevel ← match merkleToplevel with
    | .ok t => pure t
    | .error g => throw (IO.userError s!"toplevel merge failed on clashing name: {g}")
  let compiled ← match toplevel.compile with
    | .ok c => pure c
    | .error e => throw (IO.userError s!"compile failed: {e}")
  let system := AiurSystem.build compiled.bytecode commitmentParameters friParameters

  -- M2a reference root: the SHARED commitment all items bind to.
  let treeRoot ← ZkIpProtocol.buildMerkleTree leaves
  IO.println s!"M2a buildMerkleTree shared root computed ({treeRoot.size} bytes)"

  -- Fetch a real depth-3 proof for `index` as an `Item` (leaf, sibs, dirs) plus
  -- the root it recomputes to. Cross-checks it against the M2a reference.
  let getItem (index : Nat) : IO (Item × ByteArray) := do
    let some proof := ZkIpProtocol.generateProof leaves index
      | throw (IO.userError s!"no proof for index {index}")
    if proof.path.size != 3 then
      throw (IO.userError s!"expected depth-3 path, got {proof.path.size} at index {index}")
    if proof.rootHash != treeRoot then
      throw (IO.userError s!"[idx {index}] generateProof root != buildMerkleTree root")
    if !ZkIpProtocol.verifyProof (leaves[index]!) proof then
      throw (IO.userError s!"[idx {index}] M2a verifyProof rejected an honest proof")
    let dirs := proof.isLeft.map (fun l => if l then (1 : UInt8) else 0)
    pure ({ leaf := leaves[index]!, sibs := proof.path, dirs }, proof.rootHash)

  -- `execute` MUST be rejected (some predicate / membership / length constraint
  -- violated) for a negative case.
  let expectExecReject (label : String) (funIdx : Nat)
      (args : Array Aiur.G) (io : Aiur.IOBuffer) : IO Unit := do
    match compiled.bytecode.execute funIdx args io with
    | .ok (out, _, _) =>
      throw (IO.userError s!"[{label}] NEGATIVE WRONGLY ACCEPTED at execute: out={out.map (·.val)}")
    | .error _ => IO.println s!"[{label}] negative rejected at execute"

  -- POSITIVE for a batch of size K over committed indices `idxs` (each attr >
  -- its threshold). Executes (out=1), records circuit-statistics trace totals,
  -- proves + verifies, and cross-checks the shared root == M2a root. Returns the
  -- prove wall-clock ms.
  let positiveBatch (k : Nat) (idxs : Array Nat) (thresholds : Array Nat) : IO Nat := do
    let funIdx ← match compiled.getFuncIdx (ZkIpProtocol.MerkleCircuit.merkleBatchEntry k) with
      | some fi => pure fi
      | none => throw (IO.userError s!"batch entry for K={k} not found")
    let mut items : Array Item := #[]
    for j in [:k] do
      if !(attrs[idxs[j]!]! > thresholds[j]!) then
        throw (IO.userError s!"[K={k}] test bug: attr {attrs[idxs[j]!]!} not > threshold {thresholds[j]!}")
      let (it, root) ← getItem (idxs[j]!)
      if rootWords root != rootWords treeRoot then
        throw (IO.userError s!"[K={k} item {j}] item root != shared M2a root")
      items := items.push it
    let args := publicArgs thresholds treeRoot
    let io := buildIO items
    let (out, _io, qc) ← match compiled.bytecode.execute funIdx args io with
      | .ok r => pure r
      | .error e => throw (IO.userError s!"[K={k}] honest execute failed: {e}")
    if out != outputOne then
      throw (IO.userError s!"[K={k}] honest output != [1]: {out.map (·.val)}")
    -- Scaling-study trace numbers for this K (Task 3 input).
    let stats := Aiur.computeStats compiled qc
    let totalRows := stats.circuits.foldl (fun a cs => a + cs.height + cs.cacheHits) 0
    let totalUnique := stats.circuits.foldl (fun a cs => a + cs.height) 0
    let totalWidth := stats.circuits.foldl (fun a cs => a + cs.width) 0
    IO.println s!"[K={k}] TRACE: circuits={stats.circuits.size} totalWidth={totalWidth} uniqueRows={totalUnique} rows(+hits)={totalRows} fftCost={stats.totalFftCost}"
    let t0 ← IO.monoMsNow
    let (claim, proof, _io) := AiurSystem.prove system funIdx args io
    let t1 ← IO.monoMsNow
    if claim != buildClaim funIdx args outputOne then
      throw (IO.userError s!"[K={k}] claim != buildClaim over public args")
    match system.verify claim (Proof.ofBytes proof.toBytes) with
    | .ok () => IO.println s!"[K={k}] positive: execute out=1, prove/verify OK; shared root == M2a; prove {t1 - t0} ms"
    | .error e => throw (IO.userError s!"[K={k}] honest verify failed: {e}")
    pure (t1 - t0)

  -- Thresholds: each disclosed attr must exceed its own threshold (independent
  -- per-item policy). attr at idx j is `attrs[idxs[j]]`; set threshold below it.
  let ms1 ← positiveBatch 1 #[1] #[1000]
  let ms2 ← positiveBatch 2 #[1, 3] #[1000, 3000]
  let ms4 ← positiveBatch 4 #[1, 3, 5, 7] #[1000, 3000, 5000, 7000]

  -- ===== NEGATIVES (use the K=4 entry as the batched vehicle) =====
  let funIdx4 ← match compiled.getFuncIdx (ZkIpProtocol.MerkleCircuit.merkleBatchEntry 4) with
    | some fi => pure fi
    | none => throw (IO.userError "K=4 batch entry not found")
  let idxs4 : Array Nat := #[1, 3, 5, 7]
  let thr4 : Array Nat := #[1000, 3000, 5000, 7000]
  let honest4 : Array Item ← idxs4.mapM (fun ix => do let (it, _) ← getItem ix; pure it)
  let args4 := publicArgs thr4 treeRoot

  -- NEG 1: batched ad-switch — item 2 advertises attr 99999 (> its threshold
  -- 5000) but its leaf is NOT the committed leaf at idx 5, keeping idx-5's honest
  -- path/root. Predicate passes, membership breaks -> reject.
  let adItems := honest4.set! 2 { honest4[2]! with leaf := ZkIpProtocol.attrLeafBytes 99999 }
  expectExecReject "batched ad-switch (item 2: uncommitted 99999 over idx-5 path)"
    funIdx4 args4 (buildIO adItems)

  -- NEG 2: one attr_i <= threshold_i — item 0 keeps its committed attr (1500) but
  -- we raise its public threshold to 2000 (>= 1500) -> that item's predicate fails.
  let thrFail := thr4.set! 0 2000
  expectExecReject "attr_i <= threshold_i (item 0: 1500 vs threshold 2000)"
    funIdx4 (publicArgs thrFail treeRoot) (buildIO honest4)

  -- NEG 3a: wrong sibling for one item — corrupt item 1's level-1 sibling byte.
  let it1 := honest4[1]!
  let badSibs := it1.sibs.set! 1 ⟨(it1.sibs[1]!).data.set! 0 0xFF⟩
  let wrongSibItems := honest4.set! 1 { it1 with sibs := badSibs }
  expectExecReject "wrong sibling (item 1, level 1)" funIdx4 args4 (buildIO wrongSibItems)

  -- NEG 3b: tampered shared public root word (word 4, i.e. args index 4+4=8).
  let argsBadRoot := args4.set! 8 ((args4.getD 8 (Aiur.G.ofNat 0)) + Aiur.G.ofNat 1)
  expectExecReject "tampered shared public root word" funIdx4 argsBadRoot (buildIO honest4)

  -- NEG 4: truncated/malformed path for one item (M3.1 minor) — drop the last
  -- byte of item 3's flat path so its length != 33*3; merkle_fold's list_take
  -- fails on the short trailing chunk -> reject.
  let it3 := honest4[3]!
  let lastSib := it3.sibs[2]!
  let truncSib : ByteArray := ⟨lastSib.data.pop⟩
  let truncItems := honest4.set! 3 { it3 with sibs := it3.sibs.set! 2 truncSib }
  expectExecReject "truncated path (item 3: sibling < 32 bytes, length != 33*D)"
    funIdx4 args4 (buildIO truncItems)

  -- NEG 5 (non-Boolean direction, per-item): dir byte 2 at item 2 level 0.
  let it2 := honest4[2]!
  let nonBoolItems := honest4.set! 2 { it2 with dirs := it2.dirs.set! 0 (2 : UInt8) }
  expectExecReject "non-Boolean direction (item 2, level 0)" funIdx4 args4 (buildIO nonBoolItems)

  -- NEGATIVE (verify-side): honest K=4 proof against a tampered-root claim.
  let (_c, proofBytes, _io) := AiurSystem.prove system funIdx4 args4 (buildIO honest4)
  let tamperedClaim := buildClaim funIdx4 (args4.set! 8 ((args4.getD 8 (Aiur.G.ofNat 0)) + Aiur.G.ofNat 1)) outputOne
  match system.verify tamperedClaim (Proof.ofBytes proofBytes.toBytes) with
  | .ok () => throw (IO.userError "NEGATIVE WRONGLY ACCEPTED: tampered-root claim verified")
  | .error _ => IO.println "tampered-root claim: rejected at verify"

  IO.println s!"SCALING (prove ms): K=1 {ms1} ms, K=2 {ms2} ms, K=4 {ms4} ms"
  IO.println "BATCH PASSED: K-attribute disclosure binds K independent attr>threshold + membership statements under one shared root; batched ad-switch, attr<=threshold, wrong sibling/root, truncated path, non-Boolean dir all rejected."

end Tests.Validation.BatchDisclosure

def main : IO Unit := Tests.Validation.BatchDisclosure.runTests
