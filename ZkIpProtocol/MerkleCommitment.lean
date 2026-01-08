-- ZkIpProtocol/MerkleCommitment.lean
import ZkIpProtocol.CoreTypes
import ZkIpProtocol.NoCapFFI

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

    -- Use Hardware FFI for hashing (Soundness First fallback)
    -- For now, hardware is not available, so use software fallback
    let ctx : HardwareCtx := { deviceHandle := 0, isAvailable := false }
    let hash ← NoCapFFI.poseidonHashFFI ctx leftHash rightHash
    return hash

termination_by data.size
decreasing_by
  all_goals (
    simp_all [Array.size_extract]
    omega
  )

end ZkIpProtocol
