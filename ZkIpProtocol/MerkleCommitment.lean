-- ZkIpProtocol/MerkleCommitment.lean
import ZkIpProtocol.CoreTypes

namespace ZkIpProtocol

/-- Domain-separated leaf hash: Blake3(0x00 ++ b). -/
def leafHash (b : ByteArray) : ByteArray :=
  Hash.hash (ByteArray.mk #[0x00] ++ b)

/-- Domain-separated internal node hash: Blake3(0x01 ++ l ++ r). -/
def nodeHash (l r : ByteArray) : ByteArray :=
  Hash.hash ((ByteArray.mk #[0x01] ++ l) ++ r)

/-- Pair up one level of the tree, duplicating the last node on an odd count. -/
def combineLevel : List ByteArray → List ByteArray
  | [] => []
  | [x] => [nodeHash x x]
  | x :: y :: rest => nodeHash x y :: combineLevel rest

/-- Repeatedly combine levels until a single root remains. `fuel` bounds the
    number of rounds; the level size roughly halves each round (needing only
    ~log2 n rounds), so seeding `fuel` with the level size is always enough. -/
def combineFuel : Nat → List ByteArray → ByteArray
  | _, [] => Hash.hash ByteArray.empty
  | _, [x] => x
  | 0, xs => xs.headD ByteArray.empty
  | fuel + 1, xs => combineFuel fuel (combineLevel xs)

/--
  Verified Merkle Tree construction, domain-separated Blake3.
  Leaves are hashed with `leafHash`, internal nodes combined with `nodeHash`.
  Odd node counts at a level duplicate the last node. Empty input hashes
  `ByteArray.empty` directly (documented edge case).
--/
def buildMerkleTree (data : Array ByteArray) : IO ByteArray := do
  let leaves := (data.map leafHash).toList
  return combineFuel leaves.length leaves

end ZkIpProtocol
