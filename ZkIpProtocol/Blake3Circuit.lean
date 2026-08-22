/-
In-circuit Blake3 (M2b spike helper).

Wraps ix's Aiur Blake3 gadget (`IxVM.blake3`) so this repo can invoke it
standalone. The gadget reads its input bytes from IO channel 0 and returns the
32-byte digest as `[[U8; 4]; 8]` (8 words x 4 bytes). Its output equals the
reference `Blake3.Rust.hash` of the same bytes (the Blake3 the M2a scheme
commits with) — see `Tests/Validation/Blake3CircuitSpike.lean`.

`IxVM.blake3` depends on `IxVM.byteStream` (`ByteStream`, `U64`,
`read_byte_stream`, ...) and `IxVM.core` (list/option primitives, `store`,
`load`), so the three `Source.Toplevel`s must be merged before compilation.
This mirrors ix's own `Tests/Main.lean` `aiur-hashes` runner.
-/

import Ix.IxVM.Core
import Ix.IxVM.ByteStream
import Ix.IxVM.Blake3
import Ix.Aiur.Compiler
import Ix.Aiur.Protocol

namespace ZkIpProtocol.Blake3Circuit

open Aiur

/-- Merged Blake3 toplevel: `core` (lists/options) + `byteStream`
(`U64`, `read_byte_stream`, ...) + the `blake3` gadget with its
`blake3_test` entry. Fails with the clashing `Global` if any two
toplevels define the same name. -/
def blake3Toplevel : Except Aiur.Global Aiur.Source.Toplevel := do
  let t ← IxVM.core.merge IxVM.byteStream
  t.merge IxVM.blake3

/-- Entry function: `blake3_test` reads bytes from IO channel 0
(`io_get_info(0, [0])` + `#read_byte_stream`) and returns their Blake3
digest as `[[U8; 4]; 8]`. -/
def entryName : Lean.Name := `blake3_test

/-- IO buffer carrying `inputBytes` on channel 0 under key `#[0]`, exactly the
shape `blake3_test`'s `io_get_info(0, [0])` expects. Registers
`(channel 0, key #[0]) → { idx := 0, len := inputBytes.size }`. -/
def hashBytesIOBuffer (inputBytes : Array UInt8) : Aiur.IOBuffer :=
  (default : Aiur.IOBuffer).extend 0 #[0] (inputBytes.map Aiur.G.ofUInt8)

/-- Recompose the flattened `[[U8; 4]; 8]` digest (32 `G` field elements, each a
byte, row-major) that `execute`/`prove` surface into a 32-byte `ByteArray`. -/
def digestOfOutput (output : Array Aiur.G) : ByteArray :=
  ⟨output.map (fun g => g.val.toNat.toUInt8)⟩

end ZkIpProtocol.Blake3Circuit
