-- ZkIpProtocol/MerkleCommitment.lean
import ZkIpProtocol.CoreTypes

namespace ZkIpProtocol

/-- Canonical 4-byte little-endian encoding of a u32 attribute value, used as
    the Merkle *leaf bytes* for the fused predicate+membership circuit (M2b Task
    4). The circuit derives the private `attr` field element IN-CIRCUIT from the
    very same 4 bytes read on channel 0, and feeds this derived value to the
    `attr > threshold` predicate. The circuit also hashes these 4 bytes (length-
    constrained to exactly 4 in-circuit) as the membership leaf. A tree committed
    with `attrLeafBytes attrValue` produces roots/paths whose leaf the circuit's
    derived leaf matches bit-for-bit. This is the attr↔leaf binding that closes
    the ad-switch attack: the value advertised by the predicate and the value
    committed in the tree are one and the same. Assumes `n < 2^32` (the u32
    domain the predicate operates over); higher bytes are dropped. -/
def attrLeafBytes (n : Nat) : ByteArray :=
  ByteArray.mk #[
    UInt8.ofNat (n % 256),
    UInt8.ofNat ((n / 256) % 256),
    UInt8.ofNat ((n / 65536) % 256),
    UInt8.ofNat ((n / 16777216) % 256)
  ]

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

/-- One level step for proof generation: given the current level and the (relative)
    index of the target node within it, returns the sibling hash, whether that
    sibling sits on the left of the pairing, and the resulting next level —
    computed with the exact same pairing/duplicate-last-on-odd rule as
    `combineLevel`. -/
def stepLevel : List ByteArray → Nat → ByteArray × Bool × List ByteArray
  | [], _ => (ByteArray.empty, false, [])
  | [x], _ => (x, false, [nodeHash x x])
  | x :: y :: rest, 0 => (y, false, nodeHash x y :: combineLevel rest)
  | x :: y :: rest, 1 => (x, true, nodeHash x y :: combineLevel rest)
  | x :: y :: rest, n + 2 =>
    let (sib, sibLeft, nextRest) := stepLevel rest n
    (sib, sibLeft, nodeHash x y :: nextRest)

/-- Repeatedly step through levels, collecting each round's sibling hash and side,
    until the root level (size ≤ 1) is reached. `fuel` is seeded the same way as
    in `combineFuel` — the level size, always enough for the ~log2 n rounds needed. -/
def proofFuel : Nat → List ByteArray → Nat → List ByteArray × List Bool
  | _, [], _ => ([], [])
  | _, [_], _ => ([], [])
  | 0, _, _ => ([], [])
  | fuel + 1, xs, idx =>
    let (sib, sibLeft, next) := stepLevel xs idx
    let (path, isLeft) := proofFuel fuel next (idx / 2)
    (sib :: path, sibLeft :: isLeft)

/-- Merkle inclusion proof for `data[index]`, walking the same level structure as
    `buildMerkleTree` (leaf hashing, then duplicate-last-on-odd pairing). Returns
    `none` if `index` is out of range. -/
def generateProof (data : Array ByteArray) (index : Nat) : Option MerkleProof :=
  if index < data.size then
    let leaves := (data.map leafHash).toList
    let (path, isLeft) := proofFuel leaves.length leaves index
    some { rootHash := combineFuel leaves.length leaves
           path := path.toArray
           isLeft := isLeft.toArray }
  else
    none

/-- Reference verification: recompute the root from `leaf` and `proof.path`/`isLeft`,
    then compare against `proof.rootHash`. This is the exact fold direction the
    in-circuit membership check (M2b) must match bit-for-bit. -/
def verifyProof (leaf : ByteArray) (proof : MerkleProof) : Bool :=
  if proof.path.size != proof.isLeft.size then
    false
  else
    let acc := (proof.path.zip proof.isLeft).foldl
      (fun acc (sib, sibIsLeft) => if sibIsLeft then nodeHash sib acc else nodeHash acc sib)
      (leafHash leaf)
    acc == proof.rootHash

end ZkIpProtocol
