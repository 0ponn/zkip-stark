import ZkIpProtocol.MerkleCommitment
namespace Tests.Validation
open ZkIpProtocol

def b (xs : List UInt8) : ByteArray := ByteArray.mk xs.toArray

def runTests : IO Unit := do
  -- domain separation: leafHash(x) != nodeHash(x, empty-ish) structurally
  if leafHash (b [1,2]) == nodeHash (b [1,2]) (b []) then
    throw (IO.userError "leaf and node hashes collide — no domain separation")
  -- determinism
  let r1 ← buildMerkleTree #[b [1], b [2], b [3]]
  let r2 ← buildMerkleTree #[b [1], b [2], b [3]]
  if r1 != r2 then throw (IO.userError "root not deterministic")
  if r1.size != 32 then throw (IO.userError s!"root not 32 bytes: {r1.size}")
  -- sensitivity: changing a leaf changes the root
  let r3 ← buildMerkleTree #[b [1], b [2], b [9]]
  if r1 == r3 then throw (IO.userError "root insensitive to leaf change")
  -- known two-leaf tree: root == nodeHash(leafHash a, leafHash b)
  let two ← buildMerkleTree #[b [1], b [2]]
  if two != nodeHash (leafHash (b [1])) (leafHash (b [2])) then
    throw (IO.userError "two-leaf root != nodeHash(leafHash a, leafHash b)")
  IO.println "All Merkle scheme tests passed"

end Tests.Validation

def main : IO Unit :=
  Tests.Validation.runTests
