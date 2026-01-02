-- ZkIpProtocol/NoCapFFI.lean
import ZkIpProtocol.CoreTypes

namespace ZkIpProtocol

-- Removed 'open CoreTypes' as it does not exist as a namespace

/-- Hardware context for NoCap acceleration -/
structure HardwareCtx where
  deviceHandle : UInt64
  isAvailable : Bool
  deriving Repr, Inhabited

namespace HardwareCtx

/-- Create a hardware context (software fallback default) -/
def create : IO (Option HardwareCtx) := do
  return none

def isValid (ctx : HardwareCtx) : Bool :=
  ctx.isAvailable

end HardwareCtx

namespace NoCapFFI

/-- Poseidon hash using NoCap hardware acceleration (zero-copy) -/
@[extern "nocap_poseidon_hash"]
opaque poseidonHashFFI (ctx : HardwareCtx) (left : @& ByteArray) (right : @& ByteArray) : IO ByteArray

/-- Batch Poseidon hash using NoCap vector lanes -/
@[extern "nocap_poseidon_hash_batch"]
opaque poseidonHashBatchFFI (ctx : HardwareCtx) (pairs : @& Array (ByteArray × ByteArray)) : IO (Array ByteArray)

/-- Batch hash with verification (Soundness First) -/
def poseidonHashBatch
  (ctx : HardwareCtx)
  (pairs : Array (ByteArray × ByteArray))
  (softwareHashes : Array ByteArray)
  : IO (Array ByteArray) := do
  if ctx.isValid then
    let hardwareHashes ← poseidonHashBatchFFI ctx pairs
    if hardwareHashes.size == softwareHashes.size then
      let allMatch := (Array.zip hardwareHashes softwareHashes).all (fun (h, s) => h == s)
      if allMatch then
        return hardwareHashes
    return softwareHashes
  else
    return softwareHashes

end NoCapFFI
end ZkIpProtocol
