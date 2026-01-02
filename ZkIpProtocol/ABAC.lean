/-
ABAC (Attribute-Based Access Control) Policy Decision Point.
Evaluates (SubjectAttributes, ObjectAttributes, Environment) → Permit/Deny
-/

import ZkIpProtocol.IPMetadata
import Std.Data.HashMap

open Std

namespace ZkIpProtocol

/-- Subject attributes -/
structure SubjectAttributes where
  /-- Subject identifier -/
  subjectId : String
  /-- Subject roles -/
  roles : Array String
  /-- Subject permissions -/
  permissions : Array String
  /-- Subject clearance level -/
  clearanceLevel : Nat
  /-- Additional attributes -/
  additional : Std.HashMap String String
  deriving Repr

/-- Object attributes (IP metadata) -/
structure ObjectAttributes where
  /-- IP identifier -/
  ipId : String
  /-- IP classification -/
  classification : String  -- e.g., "public", "confidential", "secret"
  /-- Required clearance level -/
  requiredClearance : Nat
  /-- IP owner -/
  owner : String
  /-- IP attributes -/
  attributes : Array IPAttribute

/-- Environment attributes -/
structure EnvironmentAttributes where
  /-- Current time -/
  timestamp : UInt64
  /-- Network location -/
  networkLocation : String
  /-- Request context -/
  context : String
  /-- Additional environment data -/
  additional : Std.HashMap String String
  deriving Repr

/-- Policy decision result -/
inductive PolicyDecision where
  | permit : PolicyDecision
  | deny : PolicyDecision
  | indeterminate : PolicyDecision
  deriving BEq, Repr

namespace PolicyDecision

def toBool : PolicyDecision → Bool
  | .permit => true
  | .deny => false
  | .indeterminate => false

end PolicyDecision

/-- Policy rule -/
structure PolicyRule where
  /-- Rule name -/
  name : String
  /-- Condition function -/
  condition : SubjectAttributes → ObjectAttributes → EnvironmentAttributes → Bool
  /-- Effect (permit/deny) -/
  effect : PolicyDecision
  /-- Priority (higher = evaluated first) -/
  priority : Nat

namespace PolicyRule

/-- Evaluate rule -/
def evaluate (rule : PolicyRule) (subject : SubjectAttributes)
  (object : ObjectAttributes) (env : EnvironmentAttributes) : Option PolicyDecision :=
  if rule.condition subject object env then
    some rule.effect
  else
    none

end PolicyRule

/-- Policy Decision Point (PDP) -/
structure PolicyDecisionPoint where
  /-- Policy rules -/
  rules : Array PolicyRule
  /-- Default decision -/
  defaultDecision : PolicyDecision := .deny

namespace PolicyDecisionPoint

/-- Evaluate policy -/
def evaluate
  (pdp : PolicyDecisionPoint)
  (subject : SubjectAttributes)
  (object : ObjectAttributes)
  (env : EnvironmentAttributes)
  : PolicyDecision :=
  -- Sort rules by priority (highest first)
  let sortedRules := pdp.rules.qsort (fun r1 r2 => r1.priority > r2.priority)

  -- Evaluate rules in order
  let rec evalRules (rules : Array PolicyRule) (idx : Nat) (currentDecision : PolicyDecision) : PolicyDecision :=
    if h : idx < rules.size then
      match PolicyRule.evaluate rules[idx] subject object env with
      | some effect => effect  -- First matching rule wins
      | none => evalRules rules (idx + 1) currentDecision
    else
      currentDecision
  termination_by rules.size - idx

  evalRules sortedRules 0 pdp.defaultDecision

/-- Check if policy permits access -/
def permits (pdp : PolicyDecisionPoint) (subject : SubjectAttributes)
  (object : ObjectAttributes) (env : EnvironmentAttributes) : Bool :=
  (evaluate pdp subject object env).toBool

/-- Create default PDP with common rules -/
def default : PolicyDecisionPoint :=
  let clearanceRule : PolicyRule := {
    name := "clearance_check"
    condition := fun subject object _env =>
      subject.clearanceLevel >= object.requiredClearance
    effect := .permit
    priority := 100
  }

  let ownerRule : PolicyRule := {
    name := "owner_access"
    condition := fun subject object _env =>
      subject.subjectId == object.owner
    effect := .permit
    priority := 200
  }

  let roleRule : PolicyRule := {
    name := "role_based"
    condition := fun subject object _env =>
      object.classification == "public" ||
      subject.roles.contains "admin"
    effect := .permit
    priority := 50
  }

  {
    rules := #[ownerRule, clearanceRule, roleRule]
    defaultDecision := .deny
  }

end PolicyDecisionPoint

end ZkIpProtocol
