/-
Copyright (c) 2025 ZK-IP Protocol Contributors
Zero-Knowledge Intellectual Property "Advertise & Disclose" Protocol

This module defines IP metadata operations and predicates.
Note: Core types (Ixon, IPAttribute, IPPredicate) are defined in CoreTypes.lean
-/

import ZkIpProtocol.CoreTypes
import Lean.Data.KVMap
import Std.Data.HashMap

namespace ZkIpProtocol

namespace Ixon

/-- Create a new ixon from basic information -/
def new (id : Nat) (attributes : Array IPAttribute) : Ixon := {
  id
  attributes
  merkleRoot := ByteArray.empty  -- Will be computed from full IP data
  timestamp := 0  -- Will be set during commitment
}

/-- Check if an ixon satisfies a predicate -/
def satisfies (ixon : Ixon) (predicate : IPAttribute → Bool) : Bool :=
  ixon.attributes.any predicate

/-- Get attribute value by type -/
def getAttribute (_ixon : Ixon) : IPAttribute → Option Nat
  | .performance n => some n
  | .security n => some n
  | .efficiency n => some n
  | .custom _ n => some n

end Ixon

end ZkIpProtocol
