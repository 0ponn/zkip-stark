/-
M2b Task 2, step 1 (SUB-SPIKE): an in-circuit-CONSTRUCTED ByteStream hashes to
the M2a `nodeHash` reference.

`node_hash_test` reads two 32-byte operands (`acc` on channel 0, `sib` on
channel 1) from IO, then builds `0x01 ++ acc ++ sib` IN-CIRCUIT (consing the
`0x01` tag and `list_concat`-ing the operands; the 65-byte blob is NOT read
from IO) and hashes it with the constrained `blake3` gadget. Its digest must
equal `nodeHash acc sib = Blake3(0x01 ++ acc ++ sib)` (the M2a reference).

Verified both via `execute` (pure witness) and a full `prove`/`verify` whose
claim binds the digest. This is the load-bearing unknown for M2b Task 2.
-/

import ZkIpProtocol.Blake3Circuit
import ZkIpProtocol.MerkleCircuit
import ZkIpProtocol.MerkleCommitment
import Ix.Aiur.Compiler
import Ix.Aiur.Protocol

open Aiur

namespace Tests.Validation.MerkleNodeHashSpike

def commitmentParameters : Aiur.CommitmentParameters := { logBlowup := 1, capHeight := 0 }
def friParameters : Aiur.FriParameters :=
  { logFinalPolyLen := 0, maxLogArity := 1, numQueries := 100
    commitProofOfWorkBits := 20, queryProofOfWorkBits := 0 }

/-- Merged toplevel: core + byteStream + blake3 + the Merkle circuit. -/
def merkleToplevel : Except Aiur.Global Aiur.Source.Toplevel := do
  let t ← IxVM.core.merge IxVM.byteStream
  let t ← t.merge IxVM.blake3
  t.merge ZkIpProtocol.MerkleCircuit.merkleCircuit

def digestOfOutput (output : Array Aiur.G) : ByteArray :=
  ⟨output.map (fun g => g.val.toNat.toUInt8)⟩

def hex (b : ByteArray) : String :=
  b.data.foldl (fun s x => s ++ String.ofList ((Nat.toDigits 16 (x.toNat + 256)).drop 1)) ""

def runTests : IO Unit := do
  IO.println "=== M2b Task 2 sub-spike: in-circuit-constructed nodeHash ==="
  let toplevel ← match merkleToplevel with
    | .ok t => pure t
    | .error g => throw (IO.userError s!"toplevel merge failed on clashing name: {g}")
  let compiled ← match toplevel.compile with
    | .ok c => pure c
    | .error e => throw (IO.userError s!"compile failed: {e}")
  let funIdx ← match compiled.getFuncIdx ZkIpProtocol.MerkleCircuit.nodeHashEntry with
    | some i => pure i
    | none => throw (IO.userError "entry node_hash_test not found after compile")
  let system := AiurSystem.build compiled.bytecode commitmentParameters friParameters
  IO.println s!"merged + compiled; node_hash_test funIdx={funIdx}"

  -- Two distinct 32-byte operands.
  let acc : ByteArray := ⟨(Array.range 32).map (fun i => UInt8.ofNat i)⟩
  let sib : ByteArray := ⟨(Array.range 32).map (fun i => UInt8.ofNat (i + 100))⟩

  -- Reference: the M2a nodeHash (Blake3(0x01 ++ acc ++ sib)).
  let reference : ByteArray := ZkIpProtocol.nodeHash acc sib

  let ioBuffer : Aiur.IOBuffer :=
    ((default : Aiur.IOBuffer).extend 0 #[0] (acc.data.map Aiur.G.ofUInt8)).extend
      1 #[0] (sib.data.map Aiur.G.ofUInt8)
  let args : Array Aiur.G := #[]

  -- (a) Pure interpreter.
  let (execOutput, _io, _qc) ← match compiled.bytecode.execute funIdx args ioBuffer with
    | .ok r => pure r
    | .error e => throw (IO.userError s!"execute failed: {e}")
  if execOutput.size != 32 then
    throw (IO.userError s!"output not 32 field elements: {execOutput.size}")
  let digest := digestOfOutput execOutput
  if digest != reference then
    throw (IO.userError s!"in-circuit nodeHash != reference\n  circuit:   {hex digest}\n  reference: {hex reference}")
  IO.println s!"execute: in-circuit-constructed digest == nodeHash reference  ({hex digest})"

  -- (b) Full STARK.
  let (claim, proof, _io) := AiurSystem.prove system funIdx args ioBuffer
  let expectedOutput := reference.data.map Aiur.G.ofUInt8
  if claim != buildClaim funIdx args expectedOutput then
    throw (IO.userError "claim does not match buildClaim over the nodeHash reference")
  match system.verify claim (Proof.ofBytes proof.toBytes) with
  | .ok () => IO.println "prove/verify OK; claim binds the in-circuit nodeHash"
  | .error e => throw (IO.userError s!"verify failed: {e}")

  IO.println "SUB-SPIKE PASSED: in-circuit-constructed ByteStream hashes to nodeHash reference."

end Tests.Validation.MerkleNodeHashSpike

def main : IO Unit := Tests.Validation.MerkleNodeHashSpike.runTests
