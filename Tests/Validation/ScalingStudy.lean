/-
M3 Task 3: scaling-study harness (batch K -> GPU crossover).

Sweeps the batch-count knob `merkleBatchEntry k` (M3 Task 2, `ZkIpProtocol/
MerkleCircuit.lean`) over K ∈ {1, 2, 4, 8} on the SAME depth-3, 8-leaf tree
BatchDisclosure.lean uses (K=8 discloses all 8 committed leaves), and for each
K: executes once to pull the `Aiur.computeStats` trace totals (circuits,
totalWidth, uniqueRows, rows+cacheHits, fftCost — same fields M3.2 printed),
then times MEDIAN-of-N (N=5) full prove + verify wall-clock runs, each
preceded by one untimed warm-up run (absorbs JIT/lazy-init cost, same pattern
as CpuBaseline.lean).

Merkle DEPTH is NOT re-swept here: M3.1 (`Tests/Validation/MerkleCircuitPath.lean`,
`.superpowers/sdd/m3-task-1-report.md`) already measured depth 3/5/8 (+ odd-count)
on the single-item circuit and found prove time flat (~340-550ms) across depth —
depth does not grow the trace. M3.2 found the opposite for K: batching grows the
trace ~linearly. So K is the one real trace-growing lever left to characterize
for the GPU crossover question, which is what this harness does.

Output: one SCALING_ROW line per K with the trace metrics + median prove/verify
ms + the raw N=5 sample arrays (docs/superpowers/notes/2026-07-20-scaling-study.md
is built from these numbers — no number in that doc is fabricated or
extrapolated from anywhere but this run's stdout).
-/

import ZkIpProtocol.Blake3Circuit
import ZkIpProtocol.MerkleCircuit
import ZkIpProtocol.MerkleCommitment
import Ix.Aiur.Compiler
import Ix.Aiur.Protocol
import Ix.Aiur.Statistics

open Aiur

namespace Tests.Validation.ScalingStudy

def commitmentParameters : Aiur.CommitmentParameters := { logBlowup := 1, capHeight := 0 }
def friParameters : Aiur.FriParameters :=
  { logFinalPolyLen := 0, maxLogArity := 1, numQueries := 100
    commitProofOfWorkBits := 20, queryProofOfWorkBits := 0 }

def merkleToplevel : Except Aiur.Global Aiur.Source.Toplevel := do
  let t ← IxVM.core.merge IxVM.byteStream
  let t ← t.merge IxVM.blake3
  t.merge ZkIpProtocol.MerkleCircuit.merkleCircuit

/-- Recompose a 32-byte digest into the circuit's 8x u32 (little-endian) public
root words. Identical to BatchDisclosure.lean. -/
def rootWords (root : ByteArray) : Array Aiur.G :=
  (Array.range 8).map (fun i =>
    let bt (j : Nat) : Nat := (root.get! (4 * i + j)).toNat
    Aiur.G.ofNat (bt 0 + 0x100 * bt 1 + 0x10000 * bt 2 + 0x1000000 * bt 3))

def publicArgs (thresholds : Array Nat) (root : ByteArray) : Array Aiur.G :=
  (thresholds.map Aiur.G.ofNat) ++ rootWords root

structure Item where
  leaf : ByteArray
  sibs : Array ByteArray
  dirs : Array UInt8
  deriving Inhabited

def pathBytes (it : Item) : Array Aiur.G :=
  (Array.range it.sibs.size).foldl
    (fun acc j => (acc.push (Aiur.G.ofUInt8 (it.dirs[j]!)))
      ++ (it.sibs[j]!).data.map Aiur.G.ofUInt8) #[]

def buildIO (items : Array Item) : Aiur.IOBuffer :=
  (Array.range items.size).foldl (fun buf i =>
    let it := items[i]!
    let buf := buf.extend 0 #[Aiur.G.ofNat i] (it.leaf.data.map Aiur.G.ofUInt8)
    buf.extend 1 #[Aiur.G.ofNat i] (pathBytes it)) (default : Aiur.IOBuffer)

def outputOne : Array Aiur.G := #[Aiur.G.ofNat 1]

/-- Same 8 committed attrs as BatchDisclosure.lean (perfect depth-3 tree, path
length 3) so K=8 discloses every committed leaf under the one shared root. -/
def attrs : Array Nat := #[500, 1500, 2500, 3500, 4500, 5500, 6500, 7500]

def leaves : Array ByteArray := attrs.map ZkIpProtocol.attrLeafBytes

/-- Sample count per (prove, verify) timing point. N=5, matching CpuBaseline.lean
and the plan's N>=5 requirement. -/
def runs : Nat := 5

/-- Sorted-array median (odd N — CpuBaseline.lean's convention). -/
def median (xs : Array Nat) : Nat := (xs.qsort (· < ·))[xs.size / 2]!

structure Row where
  k : Nat
  circuits : Nat
  totalWidth : Nat
  uniqueRows : Nat
  rowsPlusHits : Nat
  fftCost : Float
  proveTimes : Array Nat
  verifyTimes : Array Nat

def runTests : IO Unit := do
  IO.println "=== M3 Task 3: scaling study (batch K -> GPU crossover) ==="
  let toplevel ← match merkleToplevel with
    | .ok t => pure t
    | .error g => throw (IO.userError s!"toplevel merge failed on clashing name: {g}")
  let compiled ← match toplevel.compile with
    | .ok c => pure c
    | .error e => throw (IO.userError s!"compile failed: {e}")
  let system := AiurSystem.build compiled.bytecode commitmentParameters friParameters

  let treeRoot ← ZkIpProtocol.buildMerkleTree leaves
  IO.println s!"M2a buildMerkleTree shared root computed ({treeRoot.size} bytes)"

  let getItem (index : Nat) : IO (Item × ByteArray) := do
    let some proof := ZkIpProtocol.generateProof leaves index
      | throw (IO.userError s!"no proof for index {index}")
    if proof.rootHash != treeRoot then
      throw (IO.userError s!"[idx {index}] generateProof root != buildMerkleTree root")
    if !ZkIpProtocol.verifyProof (leaves[index]!) proof then
      throw (IO.userError s!"[idx {index}] M2a verifyProof rejected an honest proof")
    let dirs := proof.isLeft.map (fun l => if l then (1 : UInt8) else 0)
    pure ({ leaf := leaves[index]!, sibs := proof.path, dirs }, proof.rootHash)

  -- One (K,D=3) scaling point: build the batch entry, execute once for trace
  -- stats, then N=5 timed prove/verify runs (each preceded by an untimed
  -- warm-up run so JIT/lazy-init doesn't pollute the sample).
  let measureK (k : Nat) : IO Row := do
    let funIdx ← match compiled.getFuncIdx (ZkIpProtocol.MerkleCircuit.merkleBatchEntry k) with
      | some fi => pure fi
      | none => throw (IO.userError s!"batch entry for K={k} not found")
    let idxs : Array Nat := Array.range k
    let thresholds : Array Nat := idxs.map (fun i => attrs[i]! - 250)
    let mut items : Array Item := #[]
    for j in [:k] do
      let (it, root) ← getItem idxs[j]!
      if rootWords root != rootWords treeRoot then
        throw (IO.userError s!"[K={k} item {j}] item root != shared M2a root")
      items := items.push it
    let args := publicArgs thresholds treeRoot
    let io := buildIO items

    let (out, _io, qc) ← match compiled.bytecode.execute funIdx args io with
      | .ok r => pure r
      | .error e => throw (IO.userError s!"[K={k}] execute failed: {e}")
    if out != outputOne then
      throw (IO.userError s!"[K={k}] output != [1]: {out.map (·.val)}")

    let stats := Aiur.computeStats compiled qc
    let circuits := stats.circuits.size
    let totalWidth := stats.circuits.foldl (fun a cs => a + cs.width) 0
    let uniqueRows := stats.circuits.foldl (fun a cs => a + cs.height) 0
    let rowsPlusHits := stats.circuits.foldl (fun a cs => a + cs.height + cs.cacheHits) 0
    let fftCost := stats.totalFftCost
    IO.println s!"[K={k}] TRACE: circuits={circuits} totalWidth={totalWidth} uniqueRows={uniqueRows} rows(+hits)={rowsPlusHits} fftCost={fftCost}"

    IO.println s!"[K={k}] warm-up prove/verify (untimed)..."
    let (warmClaim, warmProof, _io) := AiurSystem.prove system funIdx args io
    match system.verify warmClaim (Proof.ofBytes warmProof.toBytes) with
    | .ok () => pure ()
    | .error e => throw (IO.userError s!"[K={k}] warm-up verify failed: {e}")

    let mut proveTimes : Array Nat := #[]
    let mut verifyTimes : Array Nat := #[]
    for i in [:runs] do
      let t0 ← IO.monoMsNow
      let (claim, proof, _io) := AiurSystem.prove system funIdx args io
      let t1 ← IO.monoMsNow
      if claim != buildClaim funIdx args outputOne then
        throw (IO.userError s!"[K={k}] run {i}: claim != buildClaim over public args")
      let t2 ← IO.monoMsNow
      match system.verify claim (Proof.ofBytes proof.toBytes) with
      | .ok () => pure ()
      | .error e => throw (IO.userError s!"[K={k}] run {i}: verify failed: {e}")
      let t3 ← IO.monoMsNow
      let proveMs := t1 - t0
      let verifyMs := t3 - t2
      IO.println s!"[K={k}] run {i + 1}/{runs}: prove {proveMs} ms, verify {verifyMs} ms"
      proveTimes := proveTimes.push proveMs
      verifyTimes := verifyTimes.push verifyMs

    pure (Row.mk k circuits totalWidth uniqueRows rowsPlusHits fftCost proveTimes verifyTimes)

  let mut rows : Array Row := #[]
  for k in #[1, 2, 4, 8] do
    let row ← measureK k
    rows := rows.push row

  IO.println "=== SCALING SUMMARY (K, D=3 fixed) ==="
  for row in rows do
    let proveMedian := median row.proveTimes
    let verifyMedian := median row.verifyTimes
    IO.println s!"SCALING_ROW K={row.k} circuits={row.circuits} totalWidth={row.totalWidth} uniqueRows={row.uniqueRows} rowsPlusHits={row.rowsPlusHits} fftCost={row.fftCost} proveMedianMs={proveMedian} verifyMedianMs={verifyMedian} proveAllMs={row.proveTimes.toList} verifyAllMs={row.verifyTimes.toList}"

  IO.println "SCALING STUDY PASSED: K=1/2/4/8 all execute out=1, prove/verify OK, trace + timing recorded above."

end Tests.Validation.ScalingStudy

def main : IO Unit := Tests.Validation.ScalingStudy.runTests
