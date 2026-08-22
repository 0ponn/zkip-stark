import ZkIpProtocol.CoreTypes

namespace Tests
open ZkIpProtocol

def testHashIsNotIdentity : IO Unit := do
  let input : ByteArray := ByteArray.mk #[1, 2, 3, 4]
  let out := Hash.hash input
  -- Blake3 digest is 32 bytes and must differ from the input.
  if out == input then
    throw (IO.userError "hash is identity — commitment is void")
  if out.size != 32 then
    throw (IO.userError s!"expected 32-byte digest, got {out.size}")
  IO.println "✓ hash is Blake3-32, not identity"

def testHashDeterministicAndDistinct : IO Unit := do
  let a : ByteArray := ByteArray.mk #[0]
  let b : ByteArray := ByteArray.mk #[1]
  if Hash.hash a != Hash.hash a then
    throw (IO.userError "hash not deterministic")
  if Hash.hash a == Hash.hash b then
    throw (IO.userError "distinct inputs collided")
  IO.println "✓ hash deterministic and collision-distinct"

end Tests

def main : IO Unit := do
  Tests.testHashIsNotIdentity
  Tests.testHashDeterministicAndDistinct
  IO.println "All hash tests passed"
