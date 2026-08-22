/-
0PO-553: single-proof phase profiler (GPU-decision breakdown).

Profiles ONE real `merkle_predicate_batch1` (K=1) proof into phases to settle
whether a GPU is the true unblocker for THIS stack. Corrects an earlier study
that measured only NTT cost and INFERRED the rest was un-accelerable.

Method (least-invasive route — the spans already exist, nothing forked):
  * `multi-stark`'s prover (`stark/prove`) and aiur's `synthesis.rs prove()`
    (`aiur/prove`) already carry `#[tracing::instrument]` / `info_span!` spans;
    `aiur/prove` calls `tracing_texray::examine_current()`, making it the
    examined root over the whole nested `aiur/*` + `stark/*` subtree.
  * ix ships a Lean binding (`Ix.TracingTexray`) over the FFI shim
    (`crates/ffi/src/texray.rs`, `rs_texray_init` / `rs_texray_json_sink`).
    Installing that subscriber + JSON sink BEFORE calling `AiurSystem.prove`
    lands one `{"span","seconds"}` JSONL line per closed examined span — the
    real per-phase durations, measured not inferred.

We prove N times (each preceded by an untimed warm-up), so the sink file holds
N samples per span name; the companion doc-builder averages each. Wall-clock
prove time and the FFI proof-serialization time (`proof.toBytes`) are timed
Lean-side and printed so the span sum can be reconciled against the total.

The spans path is arg 1 (default scratchpad file). No number is fabricated.
-/

import ZkIpProtocol.Blake3Circuit
import ZkIpProtocol.MerkleCircuit
import ZkIpProtocol.MerkleCommitment
import Ix.Aiur.Compiler
import Ix.Aiur.Protocol
import Ix.Aiur.Statistics
import Ix.TracingTexray

open Aiur

namespace Tests.Validation.ProofPhaseProfile

def commitmentParameters : Aiur.CommitmentParameters := { logBlowup := 1, capHeight := 0 }
def friParameters : Aiur.FriParameters :=
  { logFinalPolyLen := 0, maxLogArity := 1, numQueries := 100
    commitProofOfWorkBits := 20, queryProofOfWorkBits := 0 }

def merkleToplevel : Except Aiur.Global Aiur.Source.Toplevel := do
  let t ← IxVM.core.merge IxVM.byteStream
  let t ← t.merge IxVM.blake3
  t.merge ZkIpProtocol.MerkleCircuit.merkleCircuit

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

def attrs : Array Nat := #[500, 1500, 2500, 3500, 4500, 5500, 6500, 7500]
def leaves : Array ByteArray := attrs.map ZkIpProtocol.attrLeafBytes

/-- Prove sample count (each preceded by an untimed warm-up). -/
def runs : Nat := 5

def median (xs : Array Nat) : Nat := (xs.qsort (· < ·))[xs.size / 2]!

def runTests (spansPath : String) : IO Unit := do
  IO.println "=== 0PO-553: single-proof phase profile (merkle_predicate_batch1, K=1) ==="
  IO.println s!"spans JSONL sink -> {spansPath}"

  -- Install the tracing-texray subscriber + per-span JSON sink BEFORE any
  -- prove. Filter to aiur/,stark/ (default). Streaming off (RSS not needed);
  -- the JSON sink is the machine source we consume.
  TracingTexray.init { streaming := false, trackRam := false }
  TracingTexray.jsonSink spansPath

  let toplevel ← match merkleToplevel with
    | .ok t => pure t
    | .error g => throw (IO.userError s!"toplevel merge failed on clashing name: {g}")
  let compiled ← match toplevel.compile with
    | .ok c => pure c
    | .error e => throw (IO.userError s!"compile failed: {e}")
  let system := AiurSystem.build compiled.bytecode commitmentParameters friParameters

  let treeRoot ← ZkIpProtocol.buildMerkleTree leaves

  let getItem (index : Nat) : IO Item := do
    let some proof := ZkIpProtocol.generateProof leaves index
      | throw (IO.userError s!"no proof for index {index}")
    if proof.rootHash != treeRoot then
      throw (IO.userError s!"[idx {index}] generateProof root != buildMerkleTree root")
    let dirs := proof.isLeft.map (fun l => if l then (1 : UInt8) else 0)
    pure { leaf := leaves[index]!, sibs := proof.path, dirs }

  -- K=1: single-item batch entry, one disclosed leaf, one threshold.
  let k := 1
  let funIdx ← match compiled.getFuncIdx (ZkIpProtocol.MerkleCircuit.merkleBatchEntry k) with
    | some fi => pure fi
    | none => throw (IO.userError s!"batch entry for K={k} not found")
  let thresholds : Array Nat := #[attrs[0]! - 250]
  let items : Array Item := #[← getItem 0]
  let args := publicArgs thresholds treeRoot
  let io := buildIO items

  -- Structural trace stats (same fields ScalingStudy prints).
  let (out, _io, qc) ← match compiled.bytecode.execute funIdx args io with
    | .ok r => pure r
    | .error e => throw (IO.userError s!"execute failed: {e}")
  if out != outputOne then
    throw (IO.userError s!"output != [1]: {out.map (·.val)}")
  let stats := Aiur.computeStats compiled qc
  let circuits := stats.circuits.size
  let totalWidth := stats.circuits.foldl (fun a cs => a + cs.width) 0
  let uniqueRows := stats.circuits.foldl (fun a cs => a + cs.height) 0
  let fftCost := stats.totalFftCost
  IO.println s!"TRACE: circuits={circuits} totalWidth={totalWidth} uniqueRows={uniqueRows} fftCost={fftCost}"

  -- Untimed warm-up (JIT/lazy-init). Its spans land in the sink too; the
  -- doc-builder drops the first sample per span so warm-up doesn't skew the
  -- average.
  IO.println "warm-up prove (untimed)..."
  let (_c, _p, _io) := AiurSystem.prove system funIdx args io

  let mut proveTimes : Array Nat := #[]
  let mut ffiBytesTimes : Array Nat := #[]
  let mut proofBytesLen := 0
  for i in [:runs] do
    let t0 ← IO.monoNanosNow
    let (claim, proof, _io) := AiurSystem.prove system funIdx args io
    let t1 ← IO.monoNanosNow
    -- FFI serialization: proof struct -> bytes (the Lean<->Rust boundary cost).
    -- `.toBytes` is a pure call, so force it inside the window via `.size`
    -- (a bare `let` would only build a thunk and mis-measure as ~0).
    let bytes := proof.toBytes
    let sz := bytes.size
    if sz == 0 then throw (IO.userError "empty proof bytes")
    let t2 ← IO.monoNanosNow
    -- Round-trip check: verify the serialized proof.
    match system.verify claim (Proof.ofBytes bytes) with
    | .ok () => pure ()
    | .error e => throw (IO.userError s!"run {i}: verify failed: {e}")
    proofBytesLen := sz
    let proveUs := (t1 - t0) / 1000
    let ffiUs := (t2 - t1) / 1000
    IO.println s!"run {i + 1}/{runs}: prove {proveUs} us, proof.toBytes {ffiUs} us"
    proveTimes := proveTimes.push proveUs
    ffiBytesTimes := ffiBytesTimes.push ffiUs

  IO.println "=== WALLCLOCK SUMMARY (microseconds) ==="
  IO.println s!"PROFILE proveMedianUs={median proveTimes} ffiBytesMedianUs={median ffiBytesTimes} proofBytes={proofBytesLen} proveAllUs={proveTimes.toList} ffiBytesAllUs={ffiBytesTimes.toList}"
  IO.println s!"PROFILE per-phase span durations were written to {spansPath} ({runs} samples/span + 1 warm-up)"
  IO.println "PHASE PROFILE PASSED: proof executed out=1, verify OK, spans recorded."

end Tests.Validation.ProofPhaseProfile

def main (args : List String) : IO Unit :=
  let spansPath := args.headD "proof-phase-spans.jsonl"
  Tests.Validation.ProofPhaseProfile.runTests spansPath
