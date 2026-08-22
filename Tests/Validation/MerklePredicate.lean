/-
M2b Task 4 (the milestone payoff): FUSED predicate + depth-3 Merkle membership.

`merkle_predicate` proves ONE statement in one circuit:
  "I know a private `attr` and a depth-3 Merkle path such that
     attr > threshold  AND  leafHash(encode(attr)) is a member of the tree
     with the public root",
  where `encode(attr)` = `ZkIpProtocol.attrLeafBytes attr` (canonical 4-byte
  little-endian encoding). See `ZkIpProtocol/MerkleCircuit.lean`.

Public args: `threshold` (G) ++ 8x u32 root words (little-endian), r0..r7.
Private IO : attr bytes (channel 0, = the leaf); 3 siblings (channels 1,2,3);
             3 direction bytes (channels 4,5,6; 0 => acc left, 1 => sib left).

THE ATTR↔LEAF BINDING: the same 4 bytes on channel 0 are recomposed in-circuit
into the field `attr` fed to `u32_less_than(threshold, attr)` AND hashed as the
membership leaf `blake3(0x00 ++ bytes)`. So the advertised predicate value and
the committed leaf are the same value — a prover cannot separate them.

The tree/root/paths are built OFF-circuit with the M2a scheme over leaves =
`attrLeafBytes attr_i` (8 leaves = depth 3), so a passing proof means the
in-circuit fold + leaf derivation match the M2a reference bit-for-bit.

POSITIVE: committed attr with attr > threshold executes to 1 and prove/verify.
NEGATIVES (each rejected at execute or verify):
  1. committed attr but attr <= threshold          -> predicate fails.
  2. AD-SWITCH: attr' > threshold advertised in the predicate while the
     committed leaf holds a different (smaller) value -> the derived leaf no
     longer matches the committed leaf, membership breaks. Also: an attr not in
     the tree at all with a real path. THIS is the attack the fusion closes.
  3. wrong sibling / flipped direction / tampered public root word; and a
     verify-side tampered-root claim against an honest proof.
-/

import ZkIpProtocol.Blake3Circuit
import ZkIpProtocol.MerkleCircuit
import ZkIpProtocol.MerkleCommitment
import Ix.Aiur.Compiler
import Ix.Aiur.Protocol

open Aiur

namespace Tests.Validation.MerklePredicate

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

/-- Public args for the fused circuit: `threshold` followed by the 8 root words. -/
def publicArgs (threshold : Nat) (root : ByteArray) : Array Aiur.G :=
  #[Aiur.G.ofNat threshold] ++ rootWords root

/-- IO buffer for a depth-3 fused proof: leaf bytes (ch 0), siblings (ch 1,2,3),
direction bytes (ch 4,5,6). `sibs`/`dirs` must each have length 3. -/
def buildIO (leaf : ByteArray) (sibs : Array ByteArray) (dirs : Array UInt8) : Aiur.IOBuffer :=
  let b0 := (default : Aiur.IOBuffer).extend 0 #[0] (leaf.data.map Aiur.G.ofUInt8)
  let bS := (Array.range 3).foldl
    (fun buf i => buf.extend (Aiur.G.ofNat (i + 1)) #[0] ((sibs[i]!).data.map Aiur.G.ofUInt8)) b0
  (Array.range 3).foldl
    (fun buf i => buf.extend (Aiur.G.ofNat (i + 4)) #[0] #[Aiur.G.ofUInt8 (dirs[i]!)]) bS

def outputOne : Array Aiur.G := #[Aiur.G.ofNat 1]

/-- Threshold for every case below. -/
def threshold : Nat := 1000

/-- Eight committed attribute values => a perfect depth-3 tree (path length 3).
Index 0 (`500`) FAILS the predicate (500 <= 1000); the rest PASS. Leaves are the
canonical 4-byte LE encodings the circuit derives in-circuit. -/
def attrs : Array Nat := #[500, 1500, 2500, 3500, 4500, 5500, 6500, 7500]

def leaves : Array ByteArray := attrs.map ZkIpProtocol.attrLeafBytes

def runTests : IO Unit := do
  IO.println "=== M2b Task 4: FUSED predicate + depth-3 Merkle membership (closes ad-switch) ==="
  let toplevel ← match merkleToplevel with
    | .ok t => pure t
    | .error g => throw (IO.userError s!"toplevel merge failed on clashing name: {g}")
  let compiled ← match toplevel.compile with
    | .ok c => pure c
    | .error e => throw (IO.userError s!"compile failed: {e}")
  let funIdx ← match compiled.getFuncIdx ZkIpProtocol.MerkleCircuit.merklePredicateEntry with
    | some i => pure i
    | none => throw (IO.userError "entry merkle_predicate not found after compile")
  let system := AiurSystem.build compiled.bytecode commitmentParameters friParameters
  IO.println s!"merged + compiled; merkle_predicate funIdx={funIdx}"

  -- M2a reference root (cross-check target).
  let treeRoot ← ZkIpProtocol.buildMerkleTree leaves
  IO.println s!"M2a buildMerkleTree root computed ({treeRoot.size} bytes)"

  -- Fetch a real depth-3 proof for `index`: (leaf, sibs, dirs, root).
  let getProof (index : Nat) : IO (ByteArray × Array ByteArray × Array UInt8 × ByteArray) := do
    let some proof := ZkIpProtocol.generateProof leaves index
      | throw (IO.userError s!"no proof for index {index}")
    if proof.path.size != 3 then
      throw (IO.userError s!"expected depth-3 path, got {proof.path.size} at index {index}")
    if proof.rootHash != treeRoot then
      throw (IO.userError s!"[idx {index}] generateProof root != buildMerkleTree root")
    if !ZkIpProtocol.verifyProof (leaves[index]!) proof then
      throw (IO.userError s!"[idx {index}] M2a verifyProof rejected an honest proof")
    let dirs := proof.isLeft.map (fun l => if l then (1 : UInt8) else 0)
    pure (leaves[index]!, proof.path, dirs, proof.rootHash)

  -- POSITIVE: committed attr with attr > threshold. execute out=1 AND prove/verify
  -- AND circuit public root == M2a root. Returns (args, leaf, sibs, dirs) for reuse.
  let positive (index : Nat) : IO (Array Aiur.G × ByteArray × Array ByteArray × Array UInt8) := do
    if !(attrs[index]! > threshold) then
      throw (IO.userError s!"[idx {index}] test bug: attr {attrs[index]!} not > threshold {threshold}")
    let (leaf, sibs, dirs, root) ← getProof index
    let args := publicArgs threshold root
    let io := buildIO leaf sibs dirs
    let (out, _io, _qc) ← match compiled.bytecode.execute funIdx args io with
      | .ok r => pure r
      | .error e => throw (IO.userError s!"[idx {index}] honest execute failed: {e}")
    if out != outputOne then
      throw (IO.userError s!"[idx {index}] honest output != [1]: {out.map (·.val)}")
    let (claim, proof, _io) := AiurSystem.prove system funIdx args io
    if claim != buildClaim funIdx args outputOne then
      throw (IO.userError s!"[idx {index}] claim != buildClaim over public args")
    if rootWords root != rootWords treeRoot then
      throw (IO.userError s!"[idx {index}] circuit public root words != M2a buildMerkleTree root")
    match system.verify claim (Proof.ofBytes proof.toBytes) with
    | .ok () => IO.println s!"[idx {index}] positive (attr={attrs[index]!} > {threshold}): execute out=1, prove/verify OK; root == M2a"
    | .error e => throw (IO.userError s!"[idx {index}] honest verify failed: {e}")
    pure (args, leaf, sibs, dirs)

  -- `execute` MUST be rejected (predicate or membership constraint violated).
  let expectExecReject (label : String) (args : Array Aiur.G) (io : Aiur.IOBuffer) : IO Unit := do
    match compiled.bytecode.execute funIdx args io with
    | .ok (out, _, _) =>
      throw (IO.userError s!"[{label}] NEGATIVE WRONGLY ACCEPTED at execute: out={out.map (·.val)}")
    | .error _ => IO.println s!"[{label}] negative rejected at execute"

  -- POSITIVE across multiple committed indices whose attr > threshold.
  let (args1, leaf1, sibs1, dirs1) ← positive 1
  let _ ← positive 3
  let _ ← positive 7

  -- NEGATIVE 1: committed attr but attr <= threshold (index 0, attr 500).
  -- Honest path/root for index 0; predicate `500 > 1000` fails.
  let (leaf0, sibs0, dirs0, root0) ← getProof 0
  let args0 := publicArgs threshold root0
  expectExecReject "committed attr <= threshold (500 > 1000)" args0 (buildIO leaf0 sibs0 dirs0)

  -- NEGATIVE 2 (THE AD-SWITCH): advertise attr' = 9999 > threshold in the
  -- predicate while the committed leaf at index 0 holds 500. The attacker keeps
  -- index 0's honest siblings/dirs/root but swaps the channel-0 bytes to
  -- encode(9999). Predicate would pass (9999 > 1000), but the in-circuit leaf is
  -- now leafHash(encode(9999)) != the committed leafHash(encode(500)), so the
  -- recomputed root != public root -> membership assert fails. The fusion makes
  -- "right predicate, wrong membership" impossible.
  let adSwitchLeaf := ZkIpProtocol.attrLeafBytes 9999
  expectExecReject "AD-SWITCH: advertise 9999 over committed-500 leaf position"
    args0 (buildIO adSwitchLeaf sibs0 dirs0)

  -- NEGATIVE 2b (AD-SWITCH variant): an attr not in the tree at all (12345 >
  -- threshold), fed with a real (index 3) path/root. Predicate passes, membership
  -- fails because leafHash(encode(12345)) is not the committed leaf at index 3.
  let (_leaf3, sibs3, dirs3, root3) ← getProof 3
  let args3 := publicArgs threshold root3
  let notInTreeLeaf := ZkIpProtocol.attrLeafBytes 12345
  expectExecReject "AD-SWITCH: uncommitted attr 12345 with index-3 path"
    args3 (buildIO notInTreeLeaf sibs3 dirs3)

  -- NEGATIVE 3a: wrong sibling at level 1 (honest index-1 positive as base).
  let sibsBad := sibs1.set! 1 ⟨(sibs1[1]!).data.set! 0 0xFF⟩
  expectExecReject "wrong sibling (level 1)" args1 (buildIO leaf1 sibsBad dirs1)

  -- NEGATIVE 3b: flipped direction at level 0 (0<->1, still Boolean).
  let dirsFlip := dirs1.set! 0 ((1 : UInt8) - dirs1[0]!)
  expectExecReject "flipped direction (level 0)" args1 (buildIO leaf1 sibs1 dirsFlip)

  -- NEGATIVE 3c: tampered public root word (word 4).
  let argsBad := args1.set! 5 ((args1.getD 5 (Aiur.G.ofNat 0)) + Aiur.G.ofNat 1)
  expectExecReject "tampered public root word" argsBad (buildIO leaf1 sibs1 dirs1)

  -- NEGATIVE 3d: non-Boolean direction byte (2) at level 2 => bool constraint.
  let dirsNonBool := dirs1.set! 2 (2 : UInt8)
  expectExecReject "non-Boolean direction (2)" args1 (buildIO leaf1 sibs1 dirsNonBool)

  -- NEGATIVE (length constraint): channel-0 stream length != 4. Supply 5 bytes
  -- (the valid 4 attr bytes + 1 extra) and expect ll==4 assertion to fail.
  let leaf1Extended := ByteArray.mk (leaf1.data.push (0x42 : UInt8))
  expectExecReject "channel-0 length != 4 (5 bytes, ll==4 constraint violated)"
    args1 (buildIO leaf1Extended sibs1 dirs1)

  -- NEGATIVE (verify-side): honest proof, tampered-root claim.
  let (_c, proof1, _io) := AiurSystem.prove system funIdx args1 (buildIO leaf1 sibs1 dirs1)
  let tamperedClaim := buildClaim funIdx (args1.set! 5 ((args1.getD 5 (Aiur.G.ofNat 0)) + Aiur.G.ofNat 1)) outputOne
  match system.verify tamperedClaim (Proof.ofBytes proof1.toBytes) with
  | .ok () => throw (IO.userError "NEGATIVE WRONGLY ACCEPTED: tampered-root claim verified")
  | .error _ => IO.println "tampered-root claim: rejected at verify"

  -- RE-BASELINE: wall-clock prove + verify for the fused (large) circuit.
  let (leafB, sibsB, dirsB, rootB) ← getProof 3
  let argsB := publicArgs threshold rootB
  let ioB := buildIO leafB sibsB dirsB
  let t0 ← IO.monoMsNow
  let (claimB, proofB, _io) := AiurSystem.prove system funIdx argsB ioB
  let t1 ← IO.monoMsNow
  let okB ← match system.verify claimB (Proof.ofBytes proofB.toBytes) with
    | .ok () => pure true
    | .error _ => pure false
  let t2 ← IO.monoMsNow
  IO.println s!"RE-BASELINE merkle_predicate: prove {t1 - t0} ms, verify {t2 - t1} ms, verified={okB}"

  IO.println "PREDICATE PASSED: fused attr>threshold + depth-3 membership binds one private attr; ad-switch (right predicate, wrong membership) rejected; wrong sibling/direction/root/non-Boolean all rejected."

end Tests.Validation.MerklePredicate

def main : IO Unit := Tests.Validation.MerklePredicate.runTests
