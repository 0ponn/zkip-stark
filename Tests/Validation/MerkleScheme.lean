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

def leaves : Array ByteArray := #[b [1], b [2], b [3], b [4]]

def pathMain : IO Unit := do
  let root ← buildMerkleTree leaves
  for i in [0:leaves.size] do
    let some proof := generateProof leaves i | throw (IO.userError s!"no proof for index {i}")
    if proof.rootHash != root then throw (IO.userError s!"proof root mismatch at {i}")
    if !verifyProof (leaves[i]!) proof then throw (IO.userError s!"valid proof rejected at {i}")
    -- negative: wrong leaf must fail
    if verifyProof (b [99]) proof then throw (IO.userError s!"tampered leaf accepted at {i}")
    -- negative: flip a direction bit (if any) must fail
    if proof.isLeft.size > 0 then
      let bad := { proof with isLeft := proof.isLeft.set! 0 (!proof.isLeft[0]!) }
      if verifyProof (leaves[i]!) bad then throw (IO.userError s!"flipped-direction proof accepted at {i}")
    -- negative: tamper a sibling must fail
    if proof.path.size > 0 then
      let bad := { proof with path := proof.path.set! 0 (b [123]) }
      if verifyProof (leaves[i]!) bad then throw (IO.userError s!"tampered-sibling proof accepted at {i}")
    -- negative: length-mismatched path/isLeft must fail
    if proof.path.size > 0 then
      let bad := { proof with path := proof.path ++ #[b [42]] }
      if verifyProof (leaves[i]!) bad then throw (IO.userError s!"length-mismatched path accepted at {i}")
    if proof.isLeft.size > 0 then
      let bad := { proof with isLeft := proof.isLeft ++ #[false] }
      if verifyProof (leaves[i]!) bad then throw (IO.userError s!"length-mismatched isLeft accepted at {i}")
  IO.println "All Merkle path tests passed"

end Tests.Validation

def main : IO Unit := do
  Tests.Validation.runTests
  Tests.Validation.pathMain
