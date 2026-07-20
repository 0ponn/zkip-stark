/-
M2b Task 1 (SPIKE): invoke ix's Aiur Blake3 gadget in-circuit and prove its
digest EQUALS the reference `Blake3.Rust.hash` (the Blake3 the M2a scheme
commits with).

For input lengths 0, 1, 32, 65 (65 = a node preimage `0x01 ++ 32 ++ 32`):
  1. compile the merged `core + byteStream + blake3` toplevel,
  2. `execute` `blake3_test` over an IO buffer carrying the bytes on channel 0,
  3. assert the recomposed 32-byte digest == `(Blake3.Rust.hash bytes).val`,
  4. `prove` + `verify` the STARK, and check the claim binds that digest.

This is the load-bearing fact for M2b: the in-circuit gadget computes the SAME
Blake3 as the off-circuit commitment scheme.
-/

import ZkIpProtocol.Blake3Circuit
import Ix.Aiur.Compiler
import Ix.Aiur.Protocol
import Blake3.Rust

open Aiur
open ZkIpProtocol.Blake3Circuit

namespace Tests.Validation.Blake3CircuitSpike

/-- Commitment/FRI params matching ix's own hash test suite (`Tests/Aiur/Common.lean`). -/
def commitmentParameters : Aiur.CommitmentParameters := { logBlowup := 1, capHeight := 0 }
def friParameters : Aiur.FriParameters :=
  { logFinalPolyLen := 0, maxLogArity := 1, numQueries := 100
    commitProofOfWorkBits := 20, queryProofOfWorkBits := 0 }

/-- The four spike inputs. 65 bytes = a Merkle node preimage: a `0x01` domain
tag followed by two 32-byte child digests. -/
def spikeInputs : List (String × Array UInt8) :=
  let child0 : Array UInt8 := (Array.range 32).map (fun i => UInt8.ofNat i)
  let child1 : Array UInt8 := (Array.range 32).map (fun i => UInt8.ofNat (i + 100))
  [ ("len=0",  #[])
  , ("len=1",  #[0x00])
  , ("len=32", (Array.range 32).map (fun i => UInt8.ofNat i))
  , ("len=65 (node 0x01 ++ 32 ++ 32)", #[0x01] ++ child0 ++ child1) ]

def hex (b : ByteArray) : String :=
  b.data.foldl (fun s x => s ++ String.ofList ((Nat.toDigits 16 (x.toNat + 256)).drop 1)) ""

def runTests : IO Unit := do
  IO.println "=== M2b Blake3 in-circuit spike ==="
  -- Build once: merge, compile, resolve the entry, build the AiurSystem.
  let toplevel ← match blake3Toplevel with
    | .ok t => pure t
    | .error g => throw (IO.userError s!"toplevel merge failed on clashing name: {g}")
  let compiled ← match toplevel.compile with
    | .ok c => pure c
    | .error e => throw (IO.userError s!"compile failed: {e}")
  let funIdx ← match compiled.getFuncIdx entryName with
    | some i => pure i
    | none => throw (IO.userError s!"entry {entryName} not found after compile")
  let system := AiurSystem.build compiled.bytecode commitmentParameters friParameters
  IO.println s!"toplevel merged + compiled; blake3_test funIdx={funIdx}"

  for (label, inputBytes) in spikeInputs do
    let ioBuffer := hashBytesIOBuffer inputBytes
    let args : Array Aiur.G := #[]   -- bytes arrive via IO, not as function args
    let reference : ByteArray := (Blake3.Rust.hash ⟨inputBytes⟩).val

    -- (a) Pure interpreter: honest witness / digest extraction.
    let (execOutput, _execIO, _qc) ← match compiled.bytecode.execute funIdx args ioBuffer with
      | .ok r => pure r
      | .error e => throw (IO.userError s!"[{label}] execute failed: {e}")
    let digest := digestOfOutput execOutput
    if execOutput.size != 32 then
      throw (IO.userError s!"[{label}] output not 32 field elements: {execOutput.size}")
    if digest != reference then
      throw (IO.userError s!"[{label}] in-circuit digest != reference Blake3\n  circuit:   {hex digest}\n  reference: {hex reference}")
    IO.println s!"[{label}] execute digest == reference Blake3  ({hex digest})"

    -- (b) Full STARK: prove + verify, and confirm the claim binds this digest.
    let (claim, proof, _io) := AiurSystem.prove system funIdx args ioBuffer
    let expectedOutput := reference.data.map Aiur.G.ofUInt8
    if claim != buildClaim funIdx args expectedOutput then
      throw (IO.userError s!"[{label}] claim does not match buildClaim over the reference digest")
    let proof := Proof.ofBytes proof.toBytes
    match system.verify claim proof with
    | .ok () => IO.println s!"[{label}] prove/verify OK; claim binds the digest"
    | .error e => throw (IO.userError s!"[{label}] verify failed: {e}")

  IO.println "All Blake3 in-circuit spike checks passed: digest == reference Blake3 for lengths 0,1,32,65."

end Tests.Validation.Blake3CircuitSpike

def main : IO Unit := Tests.Validation.Blake3CircuitSpike.runTests
