/-
Main module exporting all ZK-IP Protocol components.
-/

import ZkIpProtocol.IPMetadata
import ZkIpProtocol.MerkleCommitment
import ZkIpProtocol.Advertisement
import ZkIpProtocol.ABAC
import ZkIpProtocol.Disclosure
import ZkIpProtocol.Optimization

namespace ZkIpProtocol

/-- Complete ZK-IP protocol workflow -/
def advertiseAndDisclose
  (ixon : Ixon)
  (predicate : IPPredicate)
  (privateAttribute : Nat)
  (request : DisclosureRequest)
  (env : EnvironmentAttributes)
  (config : OptimizationConfig)
  : IO (Option DisclosureSession) := do
  -- Step 1: Generate ZK certificate (advertisement)
  let certificate := generateOptimizedProof ixon predicate privateAttribute config

  -- Step 2: Verify certificate
  let verified ← verifyCertificate certificate
  if !verified then
    return none

  -- Step 3: Create disclosure manager
  let pdp := PolicyDecisionPoint.default
  let manager := DisclosureManager.new pdp

  -- Step 4: Process disclosure request
  let session := manager.processRequest request ixon env

  -- Step 5: If permitted, initiate disclosure
  match session.state with
  | .permitted =>
    -- TODO: Actual iroh integration
    return some session
  | .denied =>
    IO.println "Disclosure denied by policy"
    return some session
  | _ =>
    return some session

end ZkIpProtocol
