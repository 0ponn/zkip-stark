/-
M2b Task 3: fixed-depth (3) multi-level in-circuit Blake3 Merkle membership.

`merkle_path` binds a FULL depth-3 authentication path to a PUBLIC root:
  - public args  : 8x u32 root words (little-endian), r0..r7
  - private IO   : leaf (channel 0); 3 sibling digests (channels 1,2,3);
                   3 direction bytes (channels 4,5,6; 0 => acc left, 1 => sib left)
  - in-circuit   : acc0 = leafHash(leaf) = blake3(0x00 ++ leaf);
                   acc_{i+1} = node_from(acc_i, sib_i, dir_i) for i = 0,1,2
                   (acc_i fed back as bytes via digest_to_stream);
                   assert each recomposed root word (acc3) == public root; out 1.
                   Each dir_i is Boolean-constrained (dir*(dir-1)==0) in node_from.

The path/root are produced OFF-circuit with the M2a scheme
(`buildMerkleTree` + `generateProof` over 8 leaves = depth 3), so a passing
proof means the in-circuit fold matches the M2a reference bit-for-bit.

POSITIVE: for MULTIPLE leaf indices, the honest (leaf, path, root) executes to
output 1 and prove/verify OK; the circuit's public root equals both
`generateProof(...).rootHash` and `buildMerkleTree` (cross-checked vs M2a).
NEGATIVE (execute-rejected): wrong sibling at a level, flipped direction, wrong
leaf, tampered public root word, and a NON-BOOLEAN direction byte (2).
NEGATIVE (verify-side): an honest proof verified against a tampered-root claim.
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

/-- IO buffer for a depth-3 path: leaf (ch 0), siblings (ch 1,2,3),
direction bytes (ch 4,5,6). `sibs`/`dirs` must each have length 3. -/
def buildIO (leaf : ByteArray) (sibs : Array ByteArray) (dirs : Array UInt8) : Aiur.IOBuffer :=
  let b0 := (default : Aiur.IOBuffer).extend 0 #[0] (leaf.data.map Aiur.G.ofUInt8)
  let bS := (Array.range 3).foldl
    (fun buf i => buf.extend (Aiur.G.ofNat (i + 1)) #[0] ((sibs[i]!).data.map Aiur.G.ofUInt8)) b0
  (Array.range 3).foldl
    (fun buf i => buf.extend (Aiur.G.ofNat (i + 4)) #[0] #[Aiur.G.ofUInt8 (dirs[i]!)]) bS

def outputOne : Array Aiur.G := #[Aiur.G.ofNat 1]

/-- Eight distinct multi-byte leaves => a perfect depth-3 tree (path length 3). -/
def leaves : Array ByteArray :=
  (Array.range 8).map (fun i => ⟨(Array.range (3 + i)).map (fun j => UInt8.ofNat (i * 16 + j + 1))⟩)

def runTests : IO Unit := do
  IO.println "=== M2b Task 3: multi-level (depth 3) in-circuit Merkle membership ==="
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

  -- M2a reference root (cross-check target).
  let treeRoot ← ZkIpProtocol.buildMerkleTree leaves
  IO.println s!"M2a buildMerkleTree root computed ({treeRoot.size} bytes)"

  -- Fetch a real depth-3 proof for `index`, returning (leaf, sibs, dirs, root).
  let getProof (index : Nat) : IO (ByteArray × Array ByteArray × Array UInt8 × ByteArray) := do
    let some proof := ZkIpProtocol.generateProof leaves index
      | throw (IO.userError s!"no proof for index {index}")
    if proof.path.size != 3 then
      throw (IO.userError s!"expected depth-3 path, got {proof.path.size} at index {index}")
    -- Cross-check M2a: proof root == buildMerkleTree root, and reference verifies.
    if proof.rootHash != treeRoot then
      throw (IO.userError s!"[idx {index}] generateProof root != buildMerkleTree root")
    if !ZkIpProtocol.verifyProof (leaves[index]!) proof then
      throw (IO.userError s!"[idx {index}] M2a verifyProof rejected an honest proof")
    let dirs := proof.isLeft.map (fun l => if l then (1 : UInt8) else 0)
    pure (leaves[index]!, proof.path, dirs, proof.rootHash)

  -- POSITIVE: execute out=1 AND prove/verify AND circuit root == M2a root.
  let positive (index : Nat) : IO (Array Aiur.G × ByteArray × Array ByteArray × Array UInt8) := do
    let (leaf, sibs, dirs, root) ← getProof index
    let rw := rootWords root
    let io := buildIO leaf sibs dirs
    let (out, _io, _qc) ← match compiled.bytecode.execute funIdx rw io with
      | .ok r => pure r
      | .error e => throw (IO.userError s!"[idx {index}] honest execute failed: {e}")
    if out != outputOne then
      throw (IO.userError s!"[idx {index}] honest output != [1]: {out.map (·.val)}")
    let (claim, proof, _io) := AiurSystem.prove system funIdx rw io
    if claim != buildClaim funIdx rw outputOne then
      throw (IO.userError s!"[idx {index}] claim != buildClaim over public root")
    if rw != rootWords treeRoot then
      throw (IO.userError s!"[idx {index}] circuit public root words != M2a buildMerkleTree root")
    match system.verify claim (Proof.ofBytes proof.toBytes) with
    | .ok () => IO.println s!"[idx {index}] positive: execute out=1, prove/verify OK; root == M2a"
    | .error e => throw (IO.userError s!"[idx {index}] honest verify failed: {e}")
    pure (rw, leaf, sibs, dirs)

  -- `execute` MUST be rejected (some assert_eq / bool constraint violated).
  let expectExecReject (label : String) (rw : Array Aiur.G) (io : Aiur.IOBuffer) : IO Unit := do
    match compiled.bytecode.execute funIdx rw io with
    | .ok (out, _, _) =>
      throw (IO.userError s!"[{label}] NEGATIVE WRONGLY ACCEPTED at execute: out={out.map (·.val)}")
    | .error _ => IO.println s!"[{label}] negative rejected at execute"

  -- POSITIVE across multiple leaf indices (0, 3, 5, 7).
  let (rw0, leaf0, sibs0, dirs0) ← positive 0
  let _ ← positive 3
  let _ ← positive 5
  let _ ← positive 7

  -- NEGATIVE (execute): wrong sibling at level 1.
  let sibsBad := sibs0.set! 1 ⟨(sibs0[1]!).data.set! 0 0xFF⟩
  expectExecReject "wrong sibling (level 1)" rw0 (buildIO leaf0 sibsBad dirs0)

  -- NEGATIVE (execute): flipped direction at level 0 (0<->1, still Boolean).
  let dirsFlip := dirs0.set! 0 ((1 : UInt8) - dirs0[0]!)
  expectExecReject "flipped direction (level 0)" rw0 (buildIO leaf0 sibs0 dirsFlip)

  -- NEGATIVE (execute): wrong leaf (index 1's leaf, index 0's path/root).
  expectExecReject "wrong leaf" rw0 (buildIO (leaves[1]!) sibs0 dirs0)

  -- NEGATIVE (execute): tampered public root word.
  let rwBad := rw0.set! 4 ((rw0.getD 4 (Aiur.G.ofNat 0)) + Aiur.G.ofNat 1)
  expectExecReject "wrong public root word" rwBad (buildIO leaf0 sibs0 dirs0)

  -- NEGATIVE (execute): NON-BOOLEAN direction byte (2) at level 2 => bool constraint.
  let dirsNonBool := dirs0.set! 2 (2 : UInt8)
  expectExecReject "non-Boolean direction (2)" rw0 (buildIO leaf0 sibs0 dirsNonBool)

  -- NEGATIVE (verify): honest proof, tampered-root claim.
  let (_c, proof0, _io) := AiurSystem.prove system funIdx rw0 (buildIO leaf0 sibs0 dirs0)
  let tamperedClaim := buildClaim funIdx (rw0.set! 4 ((rw0.getD 4 (Aiur.G.ofNat 0)) + Aiur.G.ofNat 1)) outputOne
  match system.verify tamperedClaim (Proof.ofBytes proof0.toBytes) with
  | .ok () => throw (IO.userError "NEGATIVE WRONGLY ACCEPTED: tampered-root claim verified")
  | .error _ => IO.println "tampered-root claim: rejected at verify"

  IO.println "PATH PASSED: depth-3 membership binds to public root == M2a; wrong sibling / direction / leaf / root / non-Boolean dir all rejected."

end Tests.Validation.MerkleCircuitPath

def main : IO Unit := Tests.Validation.MerkleCircuitPath.runTests
