/-
Conditional disclosure state machine.
Integrates ABAC policy evaluation with secure disclosure via iroh p2p.
-/

import ZkIpProtocol.IPMetadata
import ZkIpProtocol.Advertisement
import ZkIpProtocol.ABAC
import Std.Data.HashMap

open Std

namespace ZkIpProtocol

/-- Disclosure request -/
structure DisclosureRequest where
  /-- Requesting subject -/
  subject : SubjectAttributes
  /-- IP identifier -/
  ipId : String
  /-- Requested data chunks -/
  requestedChunks : Array Nat
  /-- Request timestamp -/
  timestamp : UInt64
  deriving Repr

/-- Disclosure state -/
inductive DisclosureState where
  | pending : DisclosureState
  | evaluating : DisclosureState
  | permitted : DisclosureState
  | denied : DisclosureState
  | disclosing : DisclosureState
  | completed : DisclosureState
  | failed : String → DisclosureState
  deriving BEq, Repr

/-- Disclosure session -/
structure DisclosureSession where
  /-- Session identifier -/
  sessionId : String
  /-- Current state -/
  state : DisclosureState
  /-- Disclosure request -/
  request : DisclosureRequest
  /-- IP metadata -/
  ipMetadata : Ixon
  /-- Policy decision -/
  policyDecision : Option PolicyDecision
  /-- Iroh connection identifier (placeholder) -/
  irohConnectionId : Option String

namespace DisclosureSession

/-- Create new disclosure session -/
def new (sessionId : String) (request : DisclosureRequest) (ipMetadata : Ixon) : DisclosureSession := {
  sessionId
  state := .pending
  request
  ipMetadata
  policyDecision := none
  irohConnectionId := none
}

/-- Transition to evaluating state -/
def startEvaluation (session : DisclosureSession) : DisclosureSession := {
  session with state := .evaluating
}

/-- Set policy decision -/
def setPolicyDecision (session : DisclosureSession) (decision : PolicyDecision) : DisclosureSession := {
  session with
    policyDecision := some decision
    state := if decision == .permit then .permitted else .denied
}

/-- Start disclosure -/
def startDisclosure (session : DisclosureSession) (irohId : String) : DisclosureSession := {
  session with
    state := .disclosing
    irohConnectionId := some irohId
}

/-- Complete disclosure -/
def complete (session : DisclosureSession) : DisclosureSession := {
  session with state := .completed
}

/-- Fail disclosure -/
def fail (session : DisclosureSession) (error : String) : DisclosureSession := {
  session with state := .failed error
}

end DisclosureSession

/-- Disclosure manager -/
structure DisclosureManager where
  /-- Policy Decision Point -/
  pdp : PolicyDecisionPoint
  /-- Active sessions -/
  sessions : Std.HashMap String DisclosureSession
  /-- Iroh integration (placeholder - would be actual iroh client) -/
  irohEnabled : Bool
  -- Note: Can't derive Repr due to PolicyDecisionPoint and HashMap not having Repr

namespace DisclosureManager

/-- Create new disclosure manager -/
def new (pdp : PolicyDecisionPoint) : DisclosureManager := {
  pdp
  sessions := Std.HashMap.emptyWithCapacity 8
  irohEnabled := true
}

/-- Process disclosure request -/
def processRequest
  (manager : DisclosureManager)
  (request : DisclosureRequest)
  (ipMetadata : Ixon)
  (env : EnvironmentAttributes)
  : DisclosureSession :=
  let sessionId := request.subject.subjectId ++ "_" ++ request.ipId ++ "_" ++
    (toString request.timestamp.toNat)
  let session := DisclosureSession.new sessionId request ipMetadata

  -- Evaluate policy
  -- Now that ABAC.lean imports IPMetadata, IPAttribute is properly in scope
  let objectAttrs : ObjectAttributes := {
    ipId := toString ipMetadata.id
    classification := "confidential"  -- Would come from metadata
    requiredClearance := 5  -- Would come from metadata
    owner := "unknown"  -- Ixon doesn't have owner field, using placeholder
    attributes := ipMetadata.attributes
  }

  let decision := manager.pdp.evaluate request.subject objectAttrs env

  let session := session.setPolicyDecision decision

  -- If permitted, initiate disclosure
  if decision == .permit then
    if manager.irohEnabled then
      -- TODO: Integrate with actual iroh p2p
      let irohId := "iroh_" ++ sessionId
      session.startDisclosure irohId
    else
      session.startDisclosure "local"
  else
    session

/-- Get session -/
def getSession (manager : DisclosureManager) (sessionId : String) : Option DisclosureSession :=
  manager.sessions.get? sessionId

/-- Add session -/
def addSession (manager : DisclosureManager) (session : DisclosureSession) : DisclosureManager := {
  manager with sessions := manager.sessions.insert session.sessionId session
}

end DisclosureManager

/-- Secure disclosure via iroh (placeholder) -/
def discloseViaIroh (session : DisclosureSession) (chunks : Array ByteArray) : IO Unit :=
  -- TODO: Implement actual iroh p2p integration
  -- This would:
  -- 1. Connect to iroh network
  -- 2. Create encrypted channel
  -- 3. Stream data chunks
  -- 4. Verify delivery
  IO.println s!"[IROH] Disclosing {chunks.size} chunks for session {session.sessionId}"

end ZkIpProtocol
