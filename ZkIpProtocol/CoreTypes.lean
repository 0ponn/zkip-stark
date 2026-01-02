-- ZkIpProtocol/CoreTypes.lean
-- Leaf-node module: NO imports here

namespace ZkIpProtocol

/-- Manual Repr instance for ByteArray required for Lean 4.24.0 -/
instance : Repr ByteArray where
  reprPrec b _ := "0x" ++ repr b.toList

instance : Inhabited ByteArray := ⟨ByteArray.empty⟩

/-- Hash function type class -/
class Hash (α : Type) where
  hash : α → ByteArray

/-- IP Attribute types for ZKMB and Advertisements -/
inductive IPAttribute where
  | performance (n : Nat)
  | security (n : Nat)
  | efficiency (n : Nat)
  | custom (s : String) (n : Nat)
  deriving Repr, Inhabited

/-- IP Predicate for compliance checking -/
structure IPPredicate where
  threshold : Nat
  operator : String
  deriving Repr, Inhabited

namespace IPPredicate

/-- Evaluate predicate against an attribute -/
def evaluate (pred : IPPredicate) (attr : IPAttribute) : Bool :=
  match attr with
  | .performance n =>
    match pred.operator with
    | ">=" => n >= pred.threshold
    | ">" => n > pred.threshold
    | _ => false
  | .security n =>
    match pred.operator with
    | ">=" => n >= pred.threshold
    | ">" => n > pred.threshold
    | _ => false
  | .efficiency n =>
    match pred.operator with
    | ">=" => n >= pred.threshold
    | ">" => n > pred.threshold
    | _ => false
  | .custom _ n =>
    match pred.operator with
    | ">=" => n >= pred.threshold
    | ">" => n > pred.threshold
    | _ => false

end IPPredicate

/--
  Utility: Convert Nat to ByteArray (Big-endian).
  Uses verified termination to satisfy the Lean 4 compiler.
-/
def natToByteArray (n : Nat) : ByteArray :=
  let rec loop (val : Nat) (acc : List UInt8) : List UInt8 :=
    if h : val = 0 then
      (if acc.isEmpty then [0] else acc)
    else
      -- Recursive call: val / 256 is strictly less than val for val > 0
      loop (val / 256) ((val % 256).toUInt8 :: acc)
  termination_by val
  decreasing_by
    simp_all
    -- Directly apply the division lemma to fix the omega failure
    apply Nat.div_lt_self
    · exact Nat.pos_of_ne_zero h
    · decide
  ⟨(loop n []).toArray⟩

/-- Merkle Proof structure for commitment verification -/
structure MerkleProof where
  rootHash : ByteArray
  path : Array ByteArray
  isLeft : Array Bool
  deriving Repr, Inhabited

/-- STARK Proof structure -/
structure STARKProof where
  publicInputs : Array ByteArray
  proofData : ByteArray
  vkId : String
  deriving Repr, Inhabited

/-- Claim structure: Single definition handles 'mk' automatically -/
structure Claim where
  publicInputs : Array ByteArray
  functionId : Nat
  outputs : Array ByteArray
  deriving Repr, Inhabited

/-- IP Exchange Object Notation (Ixon): The core IP data object -/
structure Ixon where
  id : Nat
  attributes : Array IPAttribute
  merkleRoot : ByteArray
  timestamp : Nat
  deriving Repr, Inhabited

/-- ZK Certificate: The output of a successful verified disclosure -/
structure ZKCertificate where
  ipId : Nat
  commitment : ByteArray
  predicate : IPPredicate
  proof : STARKProof
  timestamp : Nat
  deriving Repr, Inhabited

end ZkIpProtocol
