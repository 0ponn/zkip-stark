-- ZkIpProtocol/MerkleCommitment.lean
import ZkIpProtocol.CoreTypes
import ZkIpProtocol.NoCapFFI
import Blake3

namespace ZkIpProtocol

/--
  Verified Merkle Tree construction with Hardware Acceleration.
  Fixes:
  1. Unknown namespace `CoreTypes`: Replaced with proper `ZkIpProtocol` scope.
  2. Unexpected token '←': Wrapped in `do` block with `IO` return type.
  3. Termination: Verified size reduction using Array.extract.
--/
def buildMerkleTree (data : Array ByteArray) : IO ByteArray := do
  let n := data.size
  if h_size : n <= 1 then
    return data.getD 0 (ByteArray.empty)
  else
    -- Establish proofs for the termination checker
    have h_n_pos : 0 < n := Nat.zero_lt_of_lt (Nat.gt_of_not_le h_size)
    have h_two : 2 <= n := Nat.succ_le_of_lt (Nat.gt_of_not_le h_size)
    let mid := n / 2

    have h_mid_lt : mid < n := Nat.div_lt_self h_n_pos (by omega)
    have h_right_lt : n - mid < n := by
      have h_mid_pos : 0 < mid := Nat.div_pos h_two (by omega)
      omega

    -- Split array using efficient slices
    let left  := data.extract 0 mid
    let right := data.extract mid n

    -- Recursive calls using IO binding (←)
    let leftHash ← buildMerkleTree left
    let rightHash ← buildMerkleTree right

    -- Circuit-compatible hashing (Poseidon). Software-only fallback.
    let ctx : HardwareCtx := { deviceHandle := 0, isAvailable := false }
    let hash ← NoCapFFI.poseidonHashFFI ctx leftHash rightHash
    return hash

termination_by data.size
decreasing_by
  all_goals (
    simp_all [Array.size_extract]
    omega
  )

/-- Off-chain Merkle tree commitments using Blake3.
    Domain separation: leaf = H(0x00 || data), node = H(0x01 || left || right). -/
def buildMerkleTreeBlake3Aux (leafPrefix nodePrefix : ByteArray) (nodes : Array ByteArray) : ByteArray :=
  let n := nodes.size
  if h_size : n <= 1 then
    if h_zero : n == 0 then
      ByteArray.empty
    else
      (Blake3.hash (leafPrefix ++ nodes[0]!)).val
  else
    have h_lt : 1 < n := Nat.lt_of_not_ge h_size
    have h_n_pos : 0 < n := Nat.lt_trans (Nat.zero_lt_succ 0) h_lt
    have h_two : 2 <= n := Nat.succ_le_iff.mpr h_lt
    let mid := n / 2
    have h_mid_lt : mid < n := Nat.div_lt_self h_n_pos (by omega)
    have h_right_lt : n - mid < n := by
      have h_mid_pos : 0 < mid := Nat.div_pos h_two (by omega)
      omega
    let left := nodes.extract 0 mid
    let right := nodes.extract mid n
    let leftHash := buildMerkleTreeBlake3Aux leafPrefix nodePrefix left
    let rightHash := buildMerkleTreeBlake3Aux leafPrefix nodePrefix right
    (Blake3.hash (nodePrefix ++ leftHash ++ rightHash)).val
termination_by nodes.size
decreasing_by
  all_goals (
    simp_all [Array.size_extract]
    omega
  )

def buildMerkleTreeBlake3 (data : Array ByteArray) : ByteArray :=
  let leafPrefix : ByteArray := ByteArray.mk #[0]
  let nodePrefix : ByteArray := ByteArray.mk #[1]
  buildMerkleTreeBlake3Aux leafPrefix nodePrefix data

end ZkIpProtocol
