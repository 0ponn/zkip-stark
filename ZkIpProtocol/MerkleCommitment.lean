-- ZkIpProtocol/MerkleCommitment.lean
import ZkIpProtocol.CoreTypes

namespace ZkIpProtocol

/-- Canonical 4-byte little-endian encoding of a u32 attribute value: the
    last 4 bytes of the production leaf (`attrLeaf`). The circuit recomposes the
    private `attr` from exactly these bytes and hashes them as part of the
    leaf, so the advertised value and the committed value are one and the same
    (this closes the ad-switch attack). Assumes `n < 2^32`; higher bytes are
    dropped. The legacy `merkle_predicate` spike uses these 4 bytes alone as
    its leaf. -/
def attrLeafBytes (n : Nat) : ByteArray :=
  ByteArray.mk #[
    UInt8.ofNat (n % 256),
    UInt8.ofNat ((n / 256) % 256),
    UInt8.ofNat ((n / 65536) % 256),
    UInt8.ofNat ((n / 16777216) % 256)
  ]

/-- An attribute's public identity, `Blake3(0x02 ++ utf8(label))`: 32 bytes.
    The tag separates it from leaf (0x00) and node (0x01) hashes. -/
def attrIdOf (label : String) : ByteArray :=
  Hash.hash (ByteArray.mk #[0x02] ++ label.toUTF8)

/-- Production leaf bytes: `attrIdOf label ++ attrLeafBytes value` (36 bytes).
    The circuit checks the first 32 bytes against the public attribute id and
    proves the predicate over the last 4, so a certificate names the attribute
    it is about and the value stays private. -/
def attrLeaf (label : String) (value : Nat) : ByteArray :=
  attrIdOf label ++ attrLeafBytes value

/-- The committed leaf of `a`. -/
def IPAttribute.leaf (a : IPAttribute) : ByteArray := attrLeaf a.label a.value

/-- Domain-separated leaf hash: Blake3(0x00 ++ b). -/
def leafHash (b : ByteArray) : ByteArray :=
  Hash.hash (ByteArray.mk #[0x00] ++ b)

/-- Domain-separated internal node hash: Blake3(0x01 ++ l ++ r). -/
def nodeHash (l r : ByteArray) : ByteArray :=
  Hash.hash ((ByteArray.mk #[0x01] ++ l) ++ r)

/-- The root a leaf and its authentication path fold to (sibling on the left
when `isLeft`). Shared by `verifyProof` and the trace-shape calibration. -/
def pathRoot (leaf : ByteArray) (path : Array ByteArray) (isLeft : Array Bool) : ByteArray :=
  (path.zip isLeft).foldl
    (fun acc (sib, sibIsLeft) => if sibIsLeft then nodeHash sib acc else nodeHash acc sib)
    (leafHash leaf)

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
  proof.path.size == proof.isLeft.size && pathRoot leaf proof.path proof.isLeft == proof.rootHash

/-! ### Label-keyed tree (M12)

The production commitment: a sparse Merkle tree over 2^32 slots in which an
attribute's slot is fixed by its label, so a root holds at most one value per
label. The circuit derives the slot from the public attribute id and checks
that the path walks to it. -/

/-- Depth of the label-keyed tree. -/
def keyedDepth : Nat := 32

/-- A label's slot: the first little-endian u32 word of its attribute id (the
public input `a0`). -/
def labelSlot (label : String) : Nat :=
  let id := attrIdOf label
  (id.get! 0).toNat + 0x100 * (id.get! 1).toNat + 0x10000 * (id.get! 2).toNat
    + 0x1000000 * (id.get! 3).toNat

/-- Digests of empty subtrees by level: `E_0 = Blake3(0x04)` (no leaf hashes to
it: leaves are hashed under 0x00) and `E_(l+1) = nodeHash E_l E_l`. -/
def emptyDigests : Array ByteArray :=
  (List.range keyedDepth).foldl (fun acc _ => acc.push (nodeHash acc.back! acc.back!))
    #[Hash.hash (ByteArray.mk #[0x04])]

/-- Root of the subtree at `level` that holds `leaves` (slot, leaf bytes), all
of which lie in that subtree. -/
def keyedNode : Nat → Array (Nat × ByteArray) → ByteArray
  | 0, leaves => match leaves[0]? with
    | some (_, leaf) => leafHash leaf
    | none => emptyDigests[0]!
  | level + 1, leaves =>
    if leaves.isEmpty then emptyDigests[level + 1]! else
      let (left, right) := leaves.partition fun (slot, _) => (slot >>> level) % 2 == 0
      nodeHash (keyedNode level left) (keyedNode level right)

/-- `(slot, leaf bytes)` for each attribute, in order, or an error naming two
attributes that would share a slot: the same label twice, or two labels whose
ids agree in their first 32 bits (about 0.01% for 1,000 labels). -/
def keyedLeaves (attrs : Array IPAttribute) : Except String (Array (Nat × ByteArray)) := do
  let leaves := attrs.map fun a => (labelSlot a.label, a.leaf)
  let bySlot := (Array.range attrs.size).qsort fun i j => leaves[i]!.1 < leaves[j]!.1
  for k in [1:bySlot.size] do
    let i := bySlot[k - 1]!
    let j := bySlot[k]!
    if leaves[i]!.1 == leaves[j]!.1 then
      if attrs[i]!.label == attrs[j]!.label then
        throw s!"attribute {attrs[i]!.label} appears more than once"
      else
        throw s!"attributes {attrs[i]!.label} and {attrs[j]!.label} share a tree slot; rename one"
  return leaves

/-- Root of the label-keyed tree over `leaves` (from `keyedLeaves`). -/
def keyedRoot (leaves : Array (Nat × ByteArray)) : ByteArray :=
  keyedNode keyedDepth leaves

/-- Authentication path to `slot` in the label-keyed tree over `leaves`:
`keyedDepth` siblings, level 0 first; `isLeft` is the slot's bit at each level
(1: the node is a right child, so its sibling is on the left). -/
def keyedProof (leaves : Array (Nat × ByteArray)) (slot : Nat) : MerkleProof := Id.run do
  let mut cur := leaves
  let mut sibs : Array ByteArray := Array.replicate keyedDepth ByteArray.empty
  for k in [0:keyedDepth] do
    let level := keyedDepth - 1 - k
    let bit := (slot >>> level) % 2
    let (mine, other) := cur.partition fun (s, _) => (s >>> level) % 2 == bit
    sibs := sibs.set! level (keyedNode level other)
    cur := mine
  return { rootHash := keyedRoot leaves, path := sibs,
           isLeft := (Array.range keyedDepth).map fun j => (slot >>> j) % 2 == 1 }

end ZkIpProtocol
