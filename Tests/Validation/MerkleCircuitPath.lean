/-
M3 Task 1: variable-depth multi-level in-circuit Blake3 Merkle membership.

`merkle_path` binds a FULL authentication path of ANY depth D to a PUBLIC root
via a RECURSIVE in-circuit fold (`merkle_fold`), replacing the old hard-unrolled
depth-3 version:
  - public args  : 8x u32 root words (little-endian), r0..r7
  - private IO   : leaf (channel 0);
                   the path (channel 1) as a flat ByteStream, level 0 (closest
                   to the leaf) first, each level = dir_byte (0 => acc left,
                   1 => sib left) ++ 32 sibling-digest bytes. Length = 33*D.
  - in-circuit   : acc0 = leafHash(leaf) = blake3(0x00 ++ leaf);
                   root = merkle_fold(acc0, path) applies one `node_from` per
                   level, recursing until the stream is exhausted;
                   assert each recomposed root word == public root; out 1.
                   Each dir is Boolean-constrained (dir*(dir-1)==0) in node_from.

Depth is now a pure knob set by the length of the channel-1 witness. The
path/root are produced OFF-circuit with the M2a scheme (`buildMerkleTree` +
`generateProof`), so a passing proof means the recursive fold matches the M2a
`verifyProof` reference bit-for-bit AT EVERY DEPTH.

Coverage:
  - depths 3 / 5 / 8 (perfect trees of 8 / 32 / 256 leaves), several indices;
    full prove/verify on one index per depth, execute-only on the rest.
  - ODD-count tree (5 leaves, depth 3): some paths hit duplicate-last pairing;
    index 4 is the odd node. Confirms the generic fold handles duplicate-last
    with no special casing.
  - NEGATIVES at every depth (execute-rejected): wrong sibling, flipped
    direction, wrong leaf, tampered public root word, non-Boolean direction (2).
  - NEGATIVE (verify-side): honest proof against a tampered-root claim.
-/

import ZkIpProtocol.Blake3Circuit
import ZkIpProtocol.MerkleCircuit
import ZkIpProtocol.MerkleCommitment
import Ix.Aiur.Compiler
import Ix.Aiur.Protocol

open Aiur

namespace Tests.Validation.MerkleCircuitPath

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

/-- IO buffer for a variable-depth path: leaf (ch 0), and the full path (ch 1)
as a flat stream of 33-byte level records `dir ++ 32 sibling bytes`, level 0
first. `sibs`/`dirs` must have equal length (= depth D). -/
def buildIO (leaf : ByteArray) (sibs : Array ByteArray) (dirs : Array UInt8) : Aiur.IOBuffer :=
  let pathBytes : Array Aiur.G := (Array.range sibs.size).foldl
    (fun acc i => (acc.push (Aiur.G.ofUInt8 (dirs[i]!))) ++ (sibs[i]!).data.map Aiur.G.ofUInt8) #[]
  let b0 := (default : Aiur.IOBuffer).extend 0 #[0] (leaf.data.map Aiur.G.ofUInt8)
  b0.extend 1 #[0] pathBytes

def outputOne : Array Aiur.G := #[Aiur.G.ofNat 1]

/-- `n` distinct leaves. The first two bytes little-endian encode the index
(distinct for n < 2^16), followed by a short index-dependent tail so leaves
differ in length too. -/
def mkLeaves (n : Nat) : Array ByteArray :=
  (Array.range n).map (fun i =>
    ⟨#[UInt8.ofNat (i % 256), UInt8.ofNat (i / 256)]
      ++ (Array.range (1 + i % 5)).map (fun j => UInt8.ofNat (i * 3 + j + 1))⟩)

def runTests : IO Unit := do
  IO.println "=== M3 Task 1: variable-depth (recursive fold) in-circuit Merkle membership ==="
  let toplevel ← match merkleToplevel with
    | .ok t => pure t
    | .error g => throw (IO.userError s!"toplevel merge failed on clashing name: {g}")
  let compiled ← match toplevel.compile with
    | .ok c => pure c
    | .error e => throw (IO.userError s!"compile failed: {e}")
  let funIdx ← match compiled.getFuncIdx ZkIpProtocol.MerkleCircuit.merklePathEntry with
    | some i => pure i
    | none => throw (IO.userError "entry merkle_path not found after compile")
  let system := AiurSystem.build compiled.bytecode commitmentParameters friParameters
  IO.println s!"merged + compiled; merkle_path funIdx={funIdx}"

  -- `execute` MUST be rejected (some assert_eq / bool constraint violated).
  let expectExecReject (label : String) (rw : Array Aiur.G) (io : Aiur.IOBuffer) : IO Unit := do
    match compiled.bytecode.execute funIdx rw io with
    | .ok (out, _, _) =>
      throw (IO.userError s!"[{label}] NEGATIVE WRONGLY ACCEPTED at execute: out={out.map (·.val)}")
    | .error _ => IO.println s!"[{label}] negative rejected at execute"

  -- Run the full battery for one tree of a given expected depth.
  --   `label`   : human name for the tree
  --   `leaves`  : the tree's leaves
  --   `depth`   : expected path length (asserted per proof)
  --   `posIdx`  : indices to exercise positively (execute + root cross-check)
  --   `proveIdx`: ONE index to additionally full prove/verify (depth witness)
  -- Returns the depth-N wall-clock prove ms for `proveIdx`.
  let runTree (label : String) (leaves : Array ByteArray) (depth : Nat)
      (posIdx : Array Nat) (proveIdx : Nat) : IO Nat := do
    IO.println s!"--- tree {label}: {leaves.size} leaves, depth {depth} ---"
    let treeRoot ← ZkIpProtocol.buildMerkleTree leaves

    -- Fetch a real depth-`depth` proof for `index` => (leaf, sibs, dirs, root).
    let getProof (index : Nat) : IO (ByteArray × Array ByteArray × Array UInt8 × ByteArray) := do
      let some proof := ZkIpProtocol.generateProof leaves index
        | throw (IO.userError s!"[{label}] no proof for index {index}")
      if proof.path.size != depth then
        throw (IO.userError s!"[{label}] expected depth-{depth} path, got {proof.path.size} at index {index}")
      -- Cross-check M2a: proof root == buildMerkleTree root, and reference verifies.
      if proof.rootHash != treeRoot then
        throw (IO.userError s!"[{label} idx {index}] generateProof root != buildMerkleTree root")
      if !ZkIpProtocol.verifyProof (leaves[index]!) proof then
        throw (IO.userError s!"[{label} idx {index}] M2a verifyProof rejected an honest proof")
      let dirs := proof.isLeft.map (fun l => if l then (1 : UInt8) else 0)
      pure (leaves[index]!, proof.path, dirs, proof.rootHash)

    -- POSITIVE (execute-only): out=1 AND circuit root == M2a buildMerkleTree root.
    let positiveExec (index : Nat) : IO (Array Aiur.G × ByteArray × Array ByteArray × Array UInt8) := do
      let (leaf, sibs, dirs, root) ← getProof index
      let rw := rootWords root
      let io := buildIO leaf sibs dirs
      let (out, _io, _qc) ← match compiled.bytecode.execute funIdx rw io with
        | .ok r => pure r
        | .error e => throw (IO.userError s!"[{label} idx {index}] honest execute failed: {e}")
      if out != outputOne then
        throw (IO.userError s!"[{label} idx {index}] honest output != [1]: {out.map (·.val)}")
      if rw != rootWords treeRoot then
        throw (IO.userError s!"[{label} idx {index}] circuit public root words != M2a buildMerkleTree root")
      IO.println s!"[{label} idx {index}] positive: execute out=1; root == M2a"
      pure (rw, leaf, sibs, dirs)

    -- Exercise all positive indices at execute level; negatives reuse the
    -- first positive index's honest witness.
    let baseIdx := posIdx[0]!
    let mut base : Option (Array Aiur.G × ByteArray × Array ByteArray × Array UInt8) := none
    for index in posIdx do
      let r ← positiveExec index
      if base.isNone then base := some r

    -- Full prove/verify on `proveIdx` (proves membership at this depth), timed.
    let (leafP, sibsP, dirsP, rootP) ← getProof proveIdx
    let rwP := rootWords rootP
    let ioP := buildIO leafP sibsP dirsP
    let t0 ← IO.monoMsNow
    let (claim, proof, _io) := AiurSystem.prove system funIdx rwP ioP
    let t1 ← IO.monoMsNow
    if claim != buildClaim funIdx rwP outputOne then
      throw (IO.userError s!"[{label} idx {proveIdx}] claim != buildClaim over public root")
    match system.verify claim (Proof.ofBytes proof.toBytes) with
    | .ok () => IO.println s!"[{label} idx {proveIdx}] prove/verify OK; prove {t1 - t0} ms"
    | .error e => throw (IO.userError s!"[{label} idx {proveIdx}] honest verify failed: {e}")

    -- NEGATIVES at this depth, from the first positive index's honest witness.
    let (rw0, leaf0, sibs0, dirs0) ← match base with
      | some b => pure b
      | none => throw (IO.userError s!"[{label}] no positive index supplied")
    -- wrong sibling at level min(1, depth-1).
    let sl := if depth > 1 then 1 else 0
    let sibsBad := sibs0.set! sl ⟨(sibs0[sl]!).data.set! 0 0xFF⟩
    expectExecReject s!"{label}: wrong sibling (level {sl})" rw0 (buildIO leaf0 sibsBad dirs0)
    -- flipped direction at level 0 (0<->1, still Boolean).
    let dirsFlip := dirs0.set! 0 ((1 : UInt8) - dirs0[0]!)
    expectExecReject s!"{label}: flipped direction (level 0)" rw0 (buildIO leaf0 sibs0 dirsFlip)
    -- wrong leaf: a DIFFERENT leaf than the base index's, with base path/root.
    let otherLeaf := leaves[(baseIdx + 1) % leaves.size]!
    expectExecReject s!"{label}: wrong leaf" rw0 (buildIO otherLeaf sibs0 dirs0)
    -- tampered public root word.
    let rwBad := rw0.set! 4 ((rw0.getD 4 (Aiur.G.ofNat 0)) + Aiur.G.ofNat 1)
    expectExecReject s!"{label}: wrong public root word" rwBad (buildIO leaf0 sibs0 dirs0)
    -- NON-BOOLEAN direction byte (2) at the last level => bool constraint.
    let dirsNonBool := dirs0.set! (depth - 1) (2 : UInt8)
    expectExecReject s!"{label}: non-Boolean direction (2)" rw0 (buildIO leaf0 sibs0 dirsNonBool)

    pure (t1 - t0)

  -- Depth 3 (8 leaves, perfect).
  let _ ← runTree "depth3" (mkLeaves 8) 3 #[0, 3, 5, 7] 0
  -- Depth 5 (32 leaves, perfect).
  let _ ← runTree "depth5" (mkLeaves 32) 5 #[0, 7, 16, 31] 16
  -- ODD-count (5 leaves, depth 3): index 4 is the odd node (duplicate-last).
  let _ ← runTree "odd5" (mkLeaves 5) 3 #[0, 1, 2, 3, 4] 4
  -- Depth 8 (256 leaves, perfect) — the scaling-study data point.
  let ms8 ← runTree "depth8" (mkLeaves 256) 8 #[0, 100, 255] 128

  -- NEGATIVE (verify-side): honest depth-3 proof, tampered-root claim.
  let leaves3 := mkLeaves 8
  let some proof0 := ZkIpProtocol.generateProof leaves3 0
    | throw (IO.userError "no depth-3 proof for verify-side negative")
  let dirs0 := proof0.isLeft.map (fun l => if l then (1 : UInt8) else 0)
  let rw0 := rootWords proof0.rootHash
  let io0 := buildIO (leaves3[0]!) proof0.path dirs0
  let (_c, proofBytes, _io) := AiurSystem.prove system funIdx rw0 io0
  let tamperedClaim := buildClaim funIdx (rw0.set! 4 ((rw0.getD 4 (Aiur.G.ofNat 0)) + Aiur.G.ofNat 1)) outputOne
  match system.verify tamperedClaim (Proof.ofBytes proofBytes.toBytes) with
  | .ok () => throw (IO.userError "NEGATIVE WRONGLY ACCEPTED: tampered-root claim verified")
  | .error _ => IO.println "tampered-root claim: rejected at verify"

  IO.println s!"depth-8 prove time (scaling study): {ms8} ms"
  IO.println "PATH PASSED: variable-depth (3/5/8 + odd-count) membership binds to public root == M2a; wrong sibling / direction / leaf / root / non-Boolean dir all rejected at every depth."

end Tests.Validation.MerkleCircuitPath

def main : IO Unit := Tests.Validation.MerkleCircuitPath.runTests
