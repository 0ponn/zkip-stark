/-
Soundness oracle for the production circuit (fused predicate + Merkle membership).

The circuit must CONSTRAIN both `attributeValue > threshold` and membership of
that value's leaf under the public root. Negative and boundary cases are the
real test: a vacuous circuit would let every case "verify".
-/

import ZkIpProtocol.STARKIntegration
import ZkIpProtocol.MerkleCommitment
import ZkIpProtocol.FusedCircuit
import ZkIpProtocol.Advertisement
import ZkIpProtocol.Api
import Lean.Data.Json

namespace Tests.Validation
open ZkIpProtocol
open Lean (Json)

/-- One committed attribute: a depth-0 tree whose root is `leafHash leaf` and
whose path is empty. Prove and verify `attr > threshold` against it. -/
def proveVerify (attr threshold : Nat) : IO Bool := do
  let leaves := #[attrLeafBytes attr]
  let root ← buildMerkleTree leaves
  let some path := generateProof leaves 0 | throw (IO.userError "no path for index 0")
  match ← generateSTARKProof threshold root leaves[0]! path with
  | none => return false
  | some proof => verifySTARKProof proof threshold root

/-- Eight committed attributes (depth 3); the certificate is for index 2 (2500 > 1000). -/
def eightLeafCertificate : IO ZKCertificate := do
  let attrs : Array Nat := #[500, 1500, 2500, 3500, 4500, 5500, 6500, 7500]
  let ixon : Ixon := { id := 7, attributes := attrs.map IPAttribute.performance,
                       merkleRoot := ByteArray.empty, timestamp := 0 }
  let some cert ← generateCertificateWithSTARK ixon { threshold := 1000, operator := ">" } 2
    | throw (IO.userError "eightLeafCertificate: generation failed")
  pure cert

def leakCheck : IO Unit := do
  let cert ← eightLeafCertificate
  let secret := natToBytes8BE 2500
  if cert.proof.publicInputs.any (· == secret) then
    throw (IO.userError "LEAK: private attribute present in proof.publicInputs")
  if cert.proof.publicInputs.size != fusedClaimSize then
    throw (IO.userError s!"claim has {cert.proof.publicInputs.size} entries, expected {fusedClaimSize}")
  IO.println "✓ no leak: attribute absent from the 12-element public claim"

def bindingCheck : IO Unit := do
  let cert ← eightLeafCertificate
  if ← verifySTARKProof cert.proof 2000 cert.commitment then
    throw (IO.userError "verify accepted a different threshold")
  if !(← verifySTARKProof cert.proof 1000 cert.commitment) then
    throw (IO.userError "verify rejected the correct threshold")
  IO.println "✓ verify binds to the threshold"

/-- The commitment is bound: flipping one root byte must fail verification,
through both the raw verifier and the library entry point. -/
def commitmentSwapCheck : IO Unit := do
  let cert ← eightLeafCertificate
  let swapped := cert.commitment.set! 0 (cert.commitment.get! 0 ^^^ 0x01)
  if ← verifySTARKProof cert.proof 1000 swapped then
    throw (IO.userError "verify accepted a certificate with a different commitment")
  if ← verifyCertificate { cert with commitment := swapped } then
    throw (IO.userError "verifyCertificate accepted a swapped commitment")
  if !(← verifyCertificate cert) then
    throw (IO.userError "verifyCertificate rejected the honest certificate")
  IO.println "✓ commitment is bound: one flipped root byte fails verification"

/-- `claim[1]` must be the fused entry's funIdx. Rewrite it to another value. -/
def funIdxBindingCheck : IO Unit := do
  let cert ← eightLeafCertificate
  let fs ← fusedSystem
  let tampered := cert.proof.publicInputs.set! 1 (natToBytes8BE (fs.funIdx + 1))
  if ← verifySTARKProof { cert.proof with publicInputs := tampered } 1000 cert.commitment then
    throw (IO.userError "verify accepted a claim for a different function index")
  IO.println "✓ verify binds to the fused entry's funIdx"

def outOfRangeGuardCheck : IO Unit := do
  let leaves := #[attrLeafBytes 5]
  let root ← buildMerkleTree leaves
  let some path := generateProof leaves 0 | throw (IO.userError "no path")
  match ← generateSTARKProof (2 ^ 32) root leaves[0]! path with
  | some _ => throw (IO.userError "threshold 2^32 should be rejected before the prover")
  | none => IO.println "✓ threshold >= 2^32 rejected before the prover"
  if ← verifySTARKProof default (2 ^ 32) root then
    throw (IO.userError "verify accepted threshold 2^32")
  IO.println "✓ verify rejects threshold >= 2^32"

/-- u32 boundary: attr = 2^32 - 1 against threshold 2^32 - 2 proves. -/
def u32BoundaryCheck : IO Unit := do
  if !(← proveVerify (2 ^ 32 - 1) (2 ^ 32 - 2)) then
    throw (IO.userError "boundary attr 2^32-1 > 2^32-2 failed to prove/verify")
  IO.println "✓ u32 boundary proves"

def certificateGuardsCheck : IO Unit := do
  let ixon : Ixon := { id := 1, attributes := #[.performance 1500], merkleRoot := ByteArray.empty, timestamp := 0 }
  if (← generateCertificateWithSTARK ixon { threshold := 2 ^ 32, operator := ">" } 0).isSome then
    throw (IO.userError "threshold 2^32 certified")
  let big : Ixon := { ixon with attributes := #[.performance (2 ^ 32)] }
  if (← generateCertificateWithSTARK big { threshold := 1000, operator := ">" } 0).isSome then
    throw (IO.userError "attribute 2^32 certified")
  if (← generateCertificateWithSTARK ixon { threshold := 1000, operator := ">=" } 0).isSome then
    throw (IO.userError "operator >= certified; circuit only proves >")
  if (← generateCertificateWithSTARK ixon { threshold := 1000, operator := ">" } 3).isSome then
    throw (IO.userError "out-of-range attributeIndex certified")
  let wrongRoot : Ixon := { ixon with merkleRoot := ByteArray.mk (Array.replicate 32 0) }
  if (← generateCertificateWithSTARK wrongRoot { threshold := 1000, operator := ">" } 0).isSome then
    throw (IO.userError "mismatched client root certified")
  IO.println "✓ certificate guards: range, operator, index, client root"

def noMockCertificateCheck : IO Unit := do
  let ixon : Ixon := { id := 1, attributes := #[.performance 500], merkleRoot := ByteArray.empty, timestamp := 0 }
  match ← generateCertificateWithSTARK ixon { threshold := 1000, operator := ">" } 0 with
  | some cert => throw (IO.userError s!"false predicate certified (vkId={cert.proof.vkId})")
  | none => IO.println "✓ false predicate yields no certificate"

/-- Depth coverage through the library path: 1 leaf (depth 0), 5 leaves (odd,
duplicated last node), 8 (perfect), 16. Each proves index `n-1` and verifies,
and a swapped commitment fails. -/
def depthCoverageCheck : IO Unit := do
  for n in [1, 5, 8, 16] do
    let attrs := (Array.range n).map (fun i => 1001 + i)
    let ixon : Ixon := { id := n, attributes := attrs.map IPAttribute.performance,
                         merkleRoot := ByteArray.empty, timestamp := 0 }
    let some cert ← generateCertificateWithSTARK ixon { threshold := 1000, operator := ">" } (n - 1)
      | throw (IO.userError s!"depth coverage: {n} leaves failed to certify")
    if !(← verifyCertificate cert) then throw (IO.userError s!"depth coverage: {n} leaves failed to verify")
    let swapped := { cert with commitment := cert.commitment.set! 31 (cert.commitment.get! 31 ^^^ 0x01) }
    if ← verifyCertificate swapped then throw (IO.userError s!"depth coverage: {n} leaves verified a swapped root")
    let depth := ((generateProof (attrs.map attrLeafBytes) (n - 1)).map (·.path.size)).getD 0
    IO.println s!"✓ {n} leaves (depth {depth}): certify, verify, swapped root rejected"

/-- Zero-knowledge is live end to end: proving the same committed attribute
twice yields different proof bytes (fresh blinding each time), and both verify.
With the pre-M6 deterministic prover the two proofs were byte-identical. -/
def blindingLiveCheck : IO Unit := do
  let a ← eightLeafCertificate
  let b ← eightLeafCertificate
  if a.proof.proofData == b.proof.proofData then
    throw (IO.userError "two proofs of the same witness are identical: blinding is not active")
  if a.proof.publicInputs != b.proof.publicInputs then
    throw (IO.userError "public claim changed between runs; only the proof should be randomized")
  if !(← verifyCertificate a) || !(← verifyCertificate b) then
    throw (IO.userError "a blinded proof failed to verify")
  IO.println "✓ blinding live: same witness, different proof bytes, identical claim, both verify"

-- API-level checks (handleVerify).

def verifiedField (label : String) (response : HttpResponse) : IO Bool := do
  if response.statusCode != 200 then
    throw (IO.userError s!"{label}: expected HTTP 200, got {response.statusCode}: {response.body}")
  match Json.parse response.body >>= (·.getObjValAs? Bool "verified") with
  | .ok b => pure b
  | .error e => throw (IO.userError s!"{label}: could not parse response: {e}: {response.body}")

/-- The operator is not in the claim, so the verifier must refuse any operator
other than the one the circuit proves. Relabelling ">" as "<" must fail. -/
def operatorTamperCheck : IO Unit := do
  let cert ← eightLeafCertificate
  let relabelled : ZKCertificate := { cert with predicate := { cert.predicate with operator := "<" } }
  if ← verifyCertificate relabelled then
    throw (IO.userError "verifyCertificate accepted operator \"<\" on a proof of \">\"")
  if ← verifiedField "operatorTamperCheck" (← handleVerify (Json.pretty (certificateToJson relabelled))) then
    throw (IO.userError "handleVerify accepted operator \"<\" on a proof of \">\"")
  IO.println "✓ verify rejects a relabelled operator"

def apiVerifyCheck : IO Unit := do
  let cert ← eightLeafCertificate
  if !(← verifiedField "apiVerifyCheck" (← handleVerify (Json.pretty (certificateToJson cert)))) then
    throw (IO.userError "apiVerifyCheck: valid certificate failed to verify")
  IO.println "✓ API verification: a valid certificate passes handleVerify"

/-- The verify path must guard threshold >= 2^32 before converting with G.ofNat. -/
def apiVerifyThresholdRangeGuardCheck : IO Unit := do
  let cert ← eightLeafCertificate
  let malicious : ZKCertificate := { cert with predicate := { threshold := 2 ^ 32, operator := ">" } }
  if ← verifiedField "apiVerifyThresholdRangeGuardCheck" (← handleVerify (Json.pretty (certificateToJson malicious))) then
    throw (IO.userError "out-of-range threshold (2^32) was accepted")
  IO.println "✓ API verify threshold guard: threshold >= 2^32 rejected"

/-- `handleVerify` must survive garbage `proofData`: `Aiur.Proof.ofBytes` panics
on malformed input and ix builds with `panic = "abort"`, so only the checked
decoder may touch untrusted bytes. -/
def apiVerifyGarbageProofCheck : IO Unit := do
  let cert ← eightLeafCertificate
  let garbage : ZKCertificate := { cert with proof := { cert.proof with proofData := ByteArray.mk #[0] } }
  if ← verifiedField "apiVerifyGarbageProofCheck" (← handleVerify (Json.pretty (certificateToJson garbage))) then
    throw (IO.userError "garbage proofData was accepted")
  IO.println "✓ API verify garbage proof: malformed proofData rejected without aborting the process"

/-- `verifyCertificate` must reject a threshold that `G.ofNat` would wrap:
`T + 2^64` converts to the same field element as `T`. -/
def verifyCertificateThresholdWrapCheck : IO Unit := do
  let cert ← eightLeafCertificate
  let wrapped : ZKCertificate := { cert with predicate := { threshold := 1000 + 2 ^ 64, operator := ">" } }
  if ← verifyCertificate wrapped then
    throw (IO.userError "threshold 1000 + 2^64 wrapped to 1000 and verified")
  IO.println "✓ verifyCertificate rejects a threshold that would wrap under G.ofNat"

-- API-level checks (handleGenerate -> handleVerify).

def genBody (attrs : Array Nat) (threshold : Nat) (index : Nat) (extra : List (String × Json) := []) : String :=
  Json.pretty (Json.mkObj ([
    ("id", (7 : Json)),
    ("attributes", Json.arr (attrs.map fun (v : Nat) => Json.mkObj [("type", Json.str "performance"), ("value", (v : Json))])),
    ("predicate", Json.mkObj [("threshold", (threshold : Json)), ("operator", Json.str ">")]),
    ("attributeIndex", (index : Json))] ++ extra))

def expectStatus (label : String) (body : String) (status : Nat) : IO Json := do
  let r ← handleGenerate body
  if r.statusCode != status then
    throw (IO.userError s!"{label}: expected {status}, got {r.statusCode}: {r.body}")
  match Json.parse r.body with
  | .ok j => pure j
  | .error e => throw (IO.userError s!"{label}: bad JSON: {e}")

def apiRoundTripCheck : IO Unit := do
  let attrs : Array Nat := #[500, 1500, 2500, 3500, 4500, 5500, 6500, 7500]
  let j ← expectStatus "generate" (genBody attrs 1000 2) 200
  let certJson := (j.getObjVal? "certificate").toOption.get!
  if !(← verifiedField "apiRoundTripCheck" (← handleVerify (Json.pretty certJson))) then
    throw (IO.userError "round trip failed to verify")
  IO.println "✓ API round trip: 8 attributes, index 2, > 1000 verifies"
  let some cert := parseZKCertificate certJson | throw (IO.userError "could not parse the returned certificate")
  let swapped := { cert with commitment := cert.commitment.set! 3 (cert.commitment.get! 3 ^^^ 0x80) }
  if ← verifiedField "apiRoundTripCheck/swapped" (← handleVerify (Json.pretty (certificateToJson swapped))) then
    throw (IO.userError "swapped commitment verified through the API")
  IO.println "✓ API verify rejects a swapped commitment"

def apiRejectsCheck : IO Unit := do
  let attrs : Array Nat := #[500, 1500, 2500]
  let _ ← expectStatus "privateAttribute" (genBody attrs 1000 1 [("privateAttribute", (1500 : Json))]) 400
  let _ ← expectStatus "operator >=" (Json.pretty (Json.mkObj [
    ("id", (1 : Json)),
    ("attributes", Json.arr #[Json.mkObj [("type", Json.str "performance"), ("value", (1500 : Json))]]),
    ("predicate", Json.mkObj [("threshold", (1000 : Json)), ("operator", Json.str ">=")])])) 400
  let _ ← expectStatus "attr >= 2^32" (genBody #[2 ^ 32] 1000 0) 400
  let _ ← expectStatus "index out of range" (genBody attrs 1000 3) 400
  let _ ← expectStatus "mismatched merkleRoot" (genBody attrs 1000 1 [("merkleRoot", Json.str ("0x" ++ "".pushn '0' 64))]) 400
  let _ ← expectStatus "false predicate" (genBody attrs 1000 0) 500
  let _ ← expectStatus "malformed attribute entry" (Json.pretty (Json.mkObj [
    ("id", (1 : Json)),
    ("attributes", Json.arr #[Json.mkObj [("type", Json.str "perf"), ("value", (5 : Json))],
                              Json.mkObj [("type", Json.str "security"), ("value", (8 : Json))]]),
    ("predicate", Json.mkObj [("threshold", (1 : Json)), ("operator", Json.str ">")])])) 400
  let _ ← expectStatus "malformed merkleRoot hex" (genBody attrs 1000 1 [("merkleRoot", Json.str "0xZZ")]) 400
  let tooMany := Json.pretty (Json.mkObj [("requests", Json.arr ((Array.range (maxBatchRequests + 1)).map fun _ =>
    (Json.parse (genBody attrs 1000 1)).toOption.get!))])
  let r ← handleBatchCertificates tooMany
  if r.statusCode != 400 then throw (IO.userError s!"batch over cap: expected 400, got {r.statusCode}")
  IO.println "✓ API rejects: privateAttribute, >=, huge attribute, bad index, wrong root, malformed attribute, bad root hex, oversized batch; false predicate is 500"

end Tests.Validation

open Tests.Validation in
def main : IO Unit := do
  if !(← proveVerify 1500 1000) then throw (IO.userError "positive case failed to verify")
  IO.println "✓ positive: 1500 > 1000 verifies (depth 0)"
  if ← proveVerify 500 1000 then throw (IO.userError "NEGATIVE case verified: constraint not binding")
  IO.println "✓ negative: 500 > 1000 rejected"
  if ← proveVerify 1000 1000 then throw (IO.userError "boundary case verified: off-by-one")
  IO.println "✓ boundary: 1000 > 1000 rejected"
  leakCheck
  bindingCheck
  commitmentSwapCheck
  funIdxBindingCheck
  outOfRangeGuardCheck
  u32BoundaryCheck
  certificateGuardsCheck
  noMockCertificateCheck
  apiVerifyCheck
  apiVerifyThresholdRangeGuardCheck
  apiVerifyGarbageProofCheck
  verifyCertificateThresholdWrapCheck
  operatorTamperCheck
  apiRoundTripCheck
  apiRejectsCheck
  depthCoverageCheck
  blindingLiveCheck
  IO.println "All predicate soundness tests passed"
