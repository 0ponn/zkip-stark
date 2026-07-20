/-
M2b Task 2, steps 2-3: single-level in-circuit Blake3 Merkle membership check.

`merkle_single` binds one Merkle level to a PUBLIC root:
  - public args  : 8x u32 root words (little-endian), r0..r7
  - private IO   : leaf bytes (channel 0), 32-byte sibling (channel 1),
                   direction byte (channel 2; 0 => acc left, 1 => sib left)
  - in-circuit   : acc = leafHash(leaf) = blake3(0x00 ++ leaf);
                   node = nodeHash with the M2a fold direction;
                   assert each recomposed node word == the public root word; out 1.

The expected root is computed OFF-circuit with the M2a reference
(`ZkIpProtocol.leafHash`/`nodeHash`), so a passing proof means the in-circuit
recomputation matches the reference scheme bit-for-bit.

POSITIVE: honest leaf+sibling+direction whose reference node == public root
=> execute succeeds (output 1) and prove/verify OK, for BOTH directions.
NEGATIVE (witness-side, rejected at execute): wrong sibling, flipped direction,
or wrong public root word all violate the in-circuit assert_eq.
NEGATIVE (verify-side): an honest proof verified against a tampered-root claim
is rejected by `verify`.
-/

import ZkIpProtocol.Blake3Circuit
import ZkIpProtocol.MerkleCircuit
import ZkIpProtocol.MerkleCommitment
import Ix.Aiur.Compiler
import Ix.Aiur.Protocol

open Aiur

namespace Tests.Validation.MerkleCircuitSingle

def commitmentParameters : Aiur.CommitmentParameters := { logBlowup := 1, capHeight := 0 }
def friParameters : Aiur.FriParameters :=
  { logFinalPolyLen := 0, maxLogArity := 1, numQueries := 100
    commitProofOfWorkBits := 20, queryProofOfWorkBits := 0 }

def merkleToplevel : Except Aiur.Global Aiur.Source.Toplevel := do
  let t ← IxVM.core.merge IxVM.byteStream
  let t ← t.merge IxVM.blake3
  t.merge ZkIpProtocol.MerkleCircuit.merkleCircuit

/-- Off-circuit reference node for one level (M2a scheme). `dir = true` means the
sibling is on the left of the pairing (matches `verifyProof`'s `sibIsLeft`). -/
def expectedNode (leaf sib : ByteArray) (dir : Bool) : ByteArray :=
  let acc := ZkIpProtocol.leafHash leaf
  if dir then ZkIpProtocol.nodeHash sib acc else ZkIpProtocol.nodeHash acc sib

/-- Recompose a 32-byte digest into the circuit's 8x u32 (little-endian) public
root words. -/
def rootWords (root : ByteArray) : Array Aiur.G :=
  (Array.range 8).map (fun i =>
    let b (j : Nat) : Nat := (root.get! (4 * i + j)).toNat
    Aiur.G.ofNat (b 0 + 0x100 * b 1 + 0x10000 * b 2 + 0x1000000 * b 3))

/-- IO buffer: leaf (channel 0), sibling (channel 1), direction byte (channel 2). -/
def buildIO (leaf sib : ByteArray) (dir : UInt8) : Aiur.IOBuffer :=
  (((default : Aiur.IOBuffer).extend 0 #[0] (leaf.data.map Aiur.G.ofUInt8)).extend
      1 #[0] (sib.data.map Aiur.G.ofUInt8)).extend
      2 #[0] #[Aiur.G.ofUInt8 dir]

def outputOne : Array Aiur.G := #[Aiur.G.ofNat 1]

def runTests : IO Unit := do
  IO.println "=== M2b Task 2: single-level in-circuit Merkle membership ==="
  let toplevel ← match merkleToplevel with
    | .ok t => pure t
    | .error g => throw (IO.userError s!"toplevel merge failed on clashing name: {g}")
  let compiled ← match toplevel.compile with
    | .ok c => pure c
    | .error e => throw (IO.userError s!"compile failed: {e}")
  let funIdx ← match compiled.getFuncIdx ZkIpProtocol.MerkleCircuit.merkleSingleEntry with
    | some i => pure i
    | none => throw (IO.userError "entry merkle_single not found after compile")
  let system := AiurSystem.build compiled.bytecode commitmentParameters friParameters
  IO.println s!"merged + compiled; merkle_single funIdx={funIdx}"

  let leaf : ByteArray := ⟨(Array.range 40).map (fun i => UInt8.ofNat (i + 7))⟩
  let sib  : ByteArray := ⟨(Array.range 32).map (fun i => UInt8.ofNat (i + 200))⟩

  -- Helper: expect `execute` to succeed with output [1] and prove/verify to pass.
  let positive (label : String) (dir : Bool) : IO (Array Aiur.G) := do
    let dirByte : UInt8 := if dir then 1 else 0
    let root := expectedNode leaf sib dir
    let rw := rootWords root
    let io := buildIO leaf sib dirByte
    let (out, _io, _qc) ← match compiled.bytecode.execute funIdx rw io with
      | .ok r => pure r
      | .error e => throw (IO.userError s!"[{label}] honest execute failed: {e}")
    if out != outputOne then
      throw (IO.userError s!"[{label}] honest output != [1]: {out.map (·.val)}")
    let (claim, proof, _io) := AiurSystem.prove system funIdx rw io
    if claim != buildClaim funIdx rw outputOne then
      throw (IO.userError s!"[{label}] claim != buildClaim over public root")
    match system.verify claim (Proof.ofBytes proof.toBytes) with
    | .ok () => IO.println s!"[{label}] positive: execute out=1, prove/verify OK; root bound"
    | .error e => throw (IO.userError s!"[{label}] honest verify failed: {e}")
    pure rw

  -- Helper: `execute` MUST be rejected (assert_eq violated => cannot witness).
  let expectExecReject (label : String) (rw : Array Aiur.G) (io : Aiur.IOBuffer) : IO Unit := do
    match compiled.bytecode.execute funIdx rw io with
    | .ok (out, _, _) =>
      throw (IO.userError s!"[{label}] NEGATIVE WRONGLY ACCEPTED at execute: out={out.map (·.val)}")
    | .error _ => IO.println s!"[{label}] negative rejected at execute (assert_eq violated)"

  -- POSITIVE, both fold directions.
  let rw0 ← positive "dir=0 (acc left)" false
  let _ ← positive "dir=1 (sib left)" true

  -- NEGATIVE (witness-side): wrong sibling, correct public root.
  let sibBad : ByteArray := ⟨sib.data.set! 5 0xFF⟩
  expectExecReject "wrong sibling" rw0 (buildIO leaf sibBad 0)

  -- NEGATIVE (witness-side): flipped direction, correct public root for dir=0.
  expectExecReject "flipped direction" rw0 (buildIO leaf sib 1)

  -- NEGATIVE (witness-side): honest witness, tampered public root word.
  let rwBad : Array Aiur.G := rw0.set! 3 ((rw0.getD 3 (Aiur.G.ofNat 0)) + Aiur.G.ofNat 1)
  expectExecReject "wrong public root word" rwBad (buildIO leaf sib 0)

  -- NEGATIVE (verify-side): honest proof, tampered-root claim.
  let (_c, proof0, _io) := AiurSystem.prove system funIdx rw0 (buildIO leaf sib 0)
  let tamperedClaim := buildClaim funIdx (rw0.set! 3 ((rw0.getD 3 (Aiur.G.ofNat 0)) + Aiur.G.ofNat 1)) outputOne
  match system.verify tamperedClaim (Proof.ofBytes proof0.toBytes) with
  | .ok () => throw (IO.userError "NEGATIVE WRONGLY ACCEPTED: tampered-root claim verified")
  | .error _ => IO.println "tampered-root claim: rejected at verify"

  IO.println "SINGLE-LEVEL PASSED: node binds to public root; wrong sibling / direction / root all rejected."

end Tests.Validation.MerkleCircuitSingle

def main : IO Unit := Tests.Validation.MerkleCircuitSingle.runTests
