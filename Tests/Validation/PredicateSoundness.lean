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

/-- The attribute id every fixture here commits under. -/
def perfId : ByteArray := attrIdOf "performance"

/-- `cert` with its first disclosure rewritten by `f`. -/
def withFirst (cert : ZKCertificate) (f : Disclosure → Disclosure) : ZKCertificate :=
  { cert with disclosures := cert.disclosures.modify 0 f }

/-- Attributes with distinct labels: `performance` at index `perfAt`,
`custom/a<i>` elsewhere (the keyed tree holds one value per label). -/
def labelled (values : Array Nat) (perfAt : Nat := 0) : Array IPAttribute :=
  (Array.range values.size).map fun i =>
    if i == perfAt then .performance values[i]! else .custom s!"a{i}" values[i]!

/-- One committed attribute (performance) in the label-keyed tree, its proof. -/
def oneLeaf (attr : Nat) : IO (ByteArray × ByteArray × MerkleProof) := do
  let .ok leaves := keyedLeaves #[.performance attr] | throw (IO.userError "keyedLeaves failed")
  pure (keyedRoot leaves, leaves[0]!.2, keyedProof leaves leaves[0]!.1)

/-- One committed attribute. Prove and verify `attr > threshold` against it. -/
def proveVerify (attr threshold : Nat) : IO Bool := do
  let (root, leaf, path) ← oneLeaf attr
  match ← generateSTARKProof threshold root leaf path with
  | none => return false
  | some proof => verifySTARKProof proof threshold perfId root

/-- Eight committed attributes; the certificate is for index 2 (performance
2500 > 1000). -/
def eightLeafCertificate : IO ZKCertificate := do
  let attrs : Array Nat := #[500, 1500, 2500, 3500, 4500, 5500, 6500, 7500]
  let ixon : Ixon := { id := 7, attributes := labelled attrs 2,
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
  IO.println s!"✓ no leak: attribute value absent from the {fusedClaimSize}-element public claim"

def bindingCheck : IO Unit := do
  let cert ← eightLeafCertificate
  if ← verifySTARKProof cert.proof 2000 perfId cert.commitment then
    throw (IO.userError "verify accepted a different threshold")
  if !(← verifySTARKProof cert.proof 1000 perfId cert.commitment) then
    throw (IO.userError "verify rejected the correct threshold")
  IO.println "✓ verify binds to the threshold"

/-- The commitment is bound: flipping one root byte must fail verification,
through both the raw verifier and the library entry point. -/
def commitmentSwapCheck : IO Unit := do
  let cert ← eightLeafCertificate
  let swapped := cert.commitment.set! 0 (cert.commitment.get! 0 ^^^ 0x01)
  if ← verifySTARKProof cert.proof 1000 perfId swapped then
    throw (IO.userError "verify accepted a certificate with a different commitment")
  if ← verifyCertificate { cert with commitment := swapped } then
    throw (IO.userError "verifyCertificate accepted a swapped commitment")
  if !(← verifyCertificate cert) then
    throw (IO.userError "verifyCertificate rejected the honest certificate")
  IO.println "✓ commitment is bound: one flipped root byte fails verification"

/-- `claim[1]` must be the fused entry's funIdx. Rewrite it to another value. -/
def funIdxBindingCheck : IO Unit := do
  let cert ← eightLeafCertificate
  let e ← fusedEntry1
  let tampered := cert.proof.publicInputs.set! 1 (natToBytes8BE (e.funIdx + 1))
  if ← verifySTARKProof { cert.proof with publicInputs := tampered } 1000 perfId cert.commitment then
    throw (IO.userError "verify accepted a claim for a different function index")
  IO.println "✓ verify binds to the fused entry's funIdx"

def outOfRangeGuardCheck : IO Unit := do
  let (root, leaf, path) ← oneLeaf 5
  match ← generateSTARKProof (2 ^ 32) root leaf path with
  | some _ => throw (IO.userError "threshold 2^32 should be rejected before the prover")
  | none => IO.println "✓ threshold >= 2^32 rejected before the prover"
  if ← verifySTARKProof default (2 ^ 32) perfId root then
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

/-- Tree sizes through the library path: 1, 5, 8 and 16 attributes. Each
proves index `n-1` and verifies, and a swapped commitment fails. -/
def depthCoverageCheck : IO Unit := do
  for n in [1, 5, 8, 16] do
    let attrs := (Array.range n).map (fun i => 1001 + i)
    let ixon : Ixon := { id := n, attributes := labelled attrs (n - 1),
                         merkleRoot := ByteArray.empty, timestamp := 0 }
    let some cert ← generateCertificateWithSTARK ixon { threshold := 1000, operator := ">" } (n - 1)
      | throw (IO.userError s!"depth coverage: {n} leaves failed to certify")
    if !(← verifyCertificate cert) then throw (IO.userError s!"depth coverage: {n} leaves failed to verify")
    let swapped := { cert with commitment := cert.commitment.set! 31 (cert.commitment.get! 31 ^^^ 0x01) }
    if ← verifyCertificate swapped then throw (IO.userError s!"depth coverage: {n} leaves verified a swapped root")
    IO.println s!"✓ {n} attributes (path depth {keyedDepth}): certify, verify, swapped root rejected"

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

/-- Per-circuit log trace heights a certificate's proof publishes. -/
def certLogDegrees (cert : ZKCertificate) : IO (Array Nat) :=
  match Aiur.Proof.ofBytesChecked cert.proof.proofData with
  | .ok p => pure (Aiur.Proof.logDegrees p)
  | .error e => throw (IO.userError s!"certLogDegrees: {e}")

/-- Trace-height leak (M8): every proof must publish the same per-circuit
heights whatever the witness, here varying depth (1, 5, 8, 16 attributes),
attribute value and threshold. -/
def fixedTraceShapeCheck : IO Unit := do
  let cases : List (Array Nat × Nat × Nat) :=
    [ (#[1500], 1000, 0),
      ((Array.range 5).map (1001 + ·), 1000, 4),
      ((Array.range 8).map (fun i => 7 * i + 900), 900, 7),
      ((Array.range 16).map (fun i => 4000000000 - i), 12, 3),
      ((Array.range maxAttributes).map (2000 + ·), 1000, maxAttributes - 1) ]
  let mut reference : Option (Array Nat) := none
  for (attrs, threshold, index) in cases do
    let ixon : Ixon := { id := 1, attributes := labelled attrs index,
                         merkleRoot := ByteArray.empty, timestamp := 0 }
    let some cert ← generateCertificateWithSTARK ixon { threshold, operator := ">" } index
      | throw (IO.userError s!"fixedTraceShapeCheck: {attrs.size} attributes failed to certify")
    if !(← verifyCertificate cert) then
      throw (IO.userError s!"fixedTraceShapeCheck: {attrs.size} attributes failed to verify")
    let degrees ← certLogDegrees cert
    match reference with
    | none => reference := some degrees
    | some r =>
      if r != degrees then
        let diffs := (List.range (max r.size degrees.size)).filterMap fun i =>
          if r[i]? != degrees[i]? then some s!"circuit {i}: {r[i]?} vs {degrees[i]?}" else none
        throw (IO.userError s!"trace heights differ for {attrs.size} attributes: {diffs}")
  IO.println "✓ fixed trace shape: identical per-circuit heights across depth, value and threshold"
  -- One past the cap is refused, not proved at a larger (leaking) shape.
  let over : Ixon := { id := 1, attributes := labelled ((Array.range (maxAttributes + 1)).map (2000 + ·)),
                       merkleRoot := ByteArray.empty, timestamp := 0 }
  if (← generateCertificateWithSTARK over { threshold := 1000, operator := ">" } 0).isSome then
    throw (IO.userError "more than maxAttributes attributes were certified")
  IO.println s!"✓ attribute cap: {maxAttributes + 1} attributes refused"

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
  let relabelled : ZKCertificate := withFirst cert fun d => { d with predicate := { d.predicate with operator := "<" } }
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
  let malicious : ZKCertificate := withFirst cert fun d => { d with predicate := { threshold := 2 ^ 32, operator := ">" } }
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
  let wrapped : ZKCertificate := withFirst cert fun d => { d with predicate := { threshold := 1000 + 2 ^ 64, operator := ">" } }
  if ← verifyCertificate wrapped then
    throw (IO.userError "threshold 1000 + 2^64 wrapped to 1000 and verified")
  IO.println "✓ verifyCertificate rejects a threshold that would wrap under G.ofNat"

-- API-level checks (handleGenerate -> handleVerify).

def genBody (attrs : Array Nat) (threshold : Nat) (index : Nat) (extra : List (String × Json) := []) : String :=
  Json.pretty (Json.mkObj ([
    ("id", (7 : Json)),
    ("attributes", Json.arr ((Array.range attrs.size).map fun i => Json.mkObj
      [("type", Json.str "custom"), ("name", Json.str s!"a{i}"), ("value", Json.num (attrs[i]! : Nat))])),
    ("predicate", Json.mkObj [("threshold", (threshold : Json)), ("operator", Json.str ">")]),
    ("attributeIndex", (index : Json))] ++ extra))

def expectStatus (label : String) (body : String) (status : Nat) : IO Json := do
  let r ← handleGenerate body
  if r.statusCode != status then
    throw (IO.userError s!"{label}: expected {status}, got {r.statusCode}: {r.body}")
  match Json.parse r.body with
  | .ok j => pure j
  | .error e => throw (IO.userError s!"{label}: bad JSON: {e}")

/-- The attribute is bound: a certificate relabelled with another attribute,
or with a label no attribute produces, fails through the library and the API. -/
def attributeRelabelCheck : IO Unit := do
  let cert ← eightLeafCertificate
  let label0 := cert.disclosures[0]!.attributeLabel
  if label0 != "performance" then
    throw (IO.userError s!"certificate names {label0}, expected performance")
  for label in ["security", "efficiency", "custom/performance", "custom/", "bogus"] do
    if ← verifyCertificate (withFirst cert ({ · with attributeLabel := label })) then
      throw (IO.userError s!"certificate relabelled as {label} verified")
  if ← verifiedField "attributeRelabelCheck"
      (← handleVerify (Json.pretty (certificateToJson (withFirst cert ({ · with attributeLabel := "security" }))))) then
    throw (IO.userError "relabelled certificate verified through the API")
  IO.println "✓ attribute is bound: relabelled certificates fail (library and API)"

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
  let _ ← expectStatus "false predicate" (genBody attrs 1000 0) 400
  let _ ← expectStatus "malformed attribute entry" (Json.pretty (Json.mkObj [
    ("id", (1 : Json)),
    ("attributes", Json.arr #[Json.mkObj [("type", Json.str "perf"), ("value", (5 : Json))],
                              Json.mkObj [("type", Json.str "security"), ("value", (8 : Json))]]),
    ("predicate", Json.mkObj [("threshold", (1 : Json)), ("operator", Json.str ">")])])) 400
  let _ ← expectStatus "duplicate label" (Json.pretty (Json.mkObj [
    ("id", (1 : Json)),
    ("attributes", Json.arr #[Json.mkObj [("type", Json.str "performance"), ("value", (500 : Json))],
                              Json.mkObj [("type", Json.str "performance"), ("value", (2000 : Json))]]),
    ("predicate", Json.mkObj [("threshold", (1000 : Json)), ("operator", Json.str ">")]),
    ("attributeIndex", (1 : Json))])) 400
  let _ ← expectStatus "malformed merkleRoot hex" (genBody attrs 1000 1 [("merkleRoot", Json.str "0xZZ")]) 400
  let tooMany := Json.pretty (Json.mkObj [("requests", Json.arr ((Array.range (maxBatchRequests + 1)).map fun _ =>
    (Json.parse (genBody attrs 1000 1)).toOption.get!))])
  -- Built as a plain string: the point is that the handler parses an
  -- oversized request and refuses it, not how the test serializes it.
  let manyAttrs := ",".intercalate ((List.range (maxAttributes + 1)).map fun _ =>
    "{\"type\":\"performance\",\"value\":2000}")
  let _ ← expectStatus "too many attributes"
    ("{\"id\":1,\"attributes\":[" ++ manyAttrs ++
      "],\"predicate\":{\"threshold\":1000,\"operator\":\">\"},\"attributeIndex\":0}") 400
  let r ← handleBatchCertificates tooMany
  if r.statusCode != 400 then throw (IO.userError s!"batch over cap: expected 400, got {r.statusCode}")
  IO.println "✓ API rejects with 400: privateAttribute, >=, huge attribute, bad index, wrong root, false predicate, duplicate label, malformed attribute, bad root hex, oversized batch, too many attributes"
  -- One good and one false entry: 200, each reported in place.
  let r ← handleBatchCertificates (Json.pretty (Json.mkObj [("requests", Json.arr #[
    (Json.parse (genBody attrs 1000 1)).toOption.get!, (Json.parse (genBody attrs 1000 0)).toOption.get!])]))
  let counts := match Json.parse r.body with
    | .ok j => ((j.getObjVal? "succeeded").toOption, (j.getObjVal? "failed").toOption)
    | .error _ => (none, none)
  if r.statusCode != 200 || counts != (some (1 : Json), some (1 : Json)) then
    throw (IO.userError s!"mixed batch: expected 200 with 1 succeeded and 1 failed, got {r.statusCode}: {r.body}")
  IO.println "✓ API batch reports a failing entry in place (1 succeeded, 1 failed)"

/-- Several attributes in one certificate: 2, 3 (padded to the 4-entry) and 8
disclosures prove and verify; each disclosure is bound (threshold, attribute,
count and order); bad request lists are refused; one entry size has one
trace shape. -/
def multiDisclosureCheck : IO Unit := do
  let attrs : Array IPAttribute := (Array.range 12).map fun i =>
    if i == 0 then .performance 1000
    else if i == 1 then .security 51 else .custom s!"metric{i}" (7000 + i)
  let ixon : Ixon := { id := 9, attributes := attrs, merkleRoot := ByteArray.empty, timestamp := 0 }
  let gt (t : Nat) : IPPredicate := { threshold := t, operator := ">" }
  let some c3 ← generateCertificate ixon #[(0, gt 900), (1, gt 40), (8, gt 7000)]
    | throw (IO.userError "3 disclosures failed to certify")
  if !(← verifyCertificate c3) then throw (IO.userError "3 disclosures failed to verify")
  if c3.disclosures.map (·.attributeLabel) != #["performance", "security", "custom/metric8"] then
    throw (IO.userError s!"unexpected labels {c3.disclosures.map (·.attributeLabel)}")
  if c3.proof.publicInputs.size != claimSize 4 then
    throw (IO.userError s!"3 disclosures: claim {c3.proof.publicInputs.size}, expected {claimSize 4}")
  IO.println "✓ 3 disclosures (padded to 4) certify and verify, labels in request order"
  let tamper (label : String) (c : ZKCertificate) : IO Unit := do
    if ← verifyCertificate c then throw (IO.userError s!"multi-disclosure tamper accepted: {label}")
  tamper "threshold of disclosure 1" { c3 with disclosures := c3.disclosures.modify 1 fun d =>
    { d with predicate := gt 41 } }
  tamper "attribute of disclosure 2" { c3 with disclosures := c3.disclosures.modify 2 fun d =>
    { d with attributeLabel := "custom/metric5" } }
  tamper "dropped disclosure" { c3 with disclosures := c3.disclosures.pop }
  tamper "reordered disclosures" { c3 with disclosures := #[c3.disclosures[1]!, c3.disclosures[0]!, c3.disclosures[2]!] }
  -- Repeating the last disclosure up to the entry size is how padding works,
  -- so it states nothing new and verifies; every listed disclosure is proved.
  IO.println "✓ each disclosure is bound: threshold, attribute, count and order"
  let some c8 ← generateCertificate ixon ((Array.range 8).map fun i => (i, gt 10))
    | throw (IO.userError "8 disclosures failed to certify")
  if !(← verifyCertificate c8) then throw (IO.userError "8 disclosures failed to verify")
  IO.println "✓ 8 disclosures certify and verify"
  -- One entry size, one shape: two 2-disclosure certificates over very
  -- different trees publish identical heights.
  let some c2a ← generateCertificate ixon #[(1, gt 5), (2, gt 6999)]
    | throw (IO.userError "2 disclosures failed to certify")
  let big : Ixon := { ixon with attributes := labelled ((Array.range maxAttributes).map (4000000000 - ·)) }
  let some c2b ← generateCertificate big #[(maxAttributes - 1, gt 12), (0, gt 3999999998)]
    | throw (IO.userError "2 disclosures over the largest tree failed to certify")
  if !(← verifyCertificate c2a) || !(← verifyCertificate c2b) then
    throw (IO.userError "2 disclosures failed to verify")
  if (← certLogDegrees c2a) != (← certLogDegrees c2b) then
    throw (IO.userError "two 2-disclosure certificates have different trace shapes")
  IO.println "✓ 2 disclosures: same trace shape for a 12-attribute and a 65,536-attribute tree"
  let refuse (label : String) (reqs : Array (Nat × IPPredicate)) : IO Unit := do
    if (← generateCertificate ixon reqs).isSome then throw (IO.userError s!"certified: {label}")
  refuse "no disclosures" #[]
  refuse "duplicate index" #[(0, gt 1), (0, gt 2)]
  refuse "9 disclosures" ((Array.range 9).map fun i => (i, gt 1))
  refuse "one false predicate" #[(0, gt 1), (1, gt 1000)]
  IO.println "✓ refused: empty list, duplicate index, 9 disclosures, one false predicate"

/-- The API accepts a `disclosures` list and refuses malformed ones. -/
def apiMultiDisclosureCheck : IO Unit := do
  let attrs := Json.arr #[
    Json.mkObj [("type", Json.str "performance"), ("value", (1500 : Json))],
    Json.mkObj [("type", Json.str "custom"), ("name", Json.str "uptime"), ("value", (99 : Json))]]
  let disc (i t : Nat) : Json := Json.mkObj [("attributeIndex", (i : Json)),
    ("predicate", Json.mkObj [("threshold", (t : Json)), ("operator", Json.str ">")])]
  let body (ds : Array Json) (extra : List (String × Json) := []) : String :=
    Json.pretty (Json.mkObj ([("id", (3 : Json)), ("attributes", attrs), ("disclosures", Json.arr ds)] ++ extra))
  let j ← expectStatus "two disclosures" (body #[disc 0 1000, disc 1 95]) 200
  let certJson := (j.getObjVal? "certificate").toOption.get!
  if !(← verifiedField "apiMultiDisclosureCheck" (← handleVerify (Json.pretty certJson))) then
    throw (IO.userError "two-disclosure certificate failed to verify through the API")
  let _ ← expectStatus "both request forms" (body #[disc 0 1000]
    [("predicate", Json.mkObj [("threshold", (1 : Json)), ("operator", Json.str ">")])]) 400
  let _ ← expectStatus "duplicate index" (body #[disc 0 1000, disc 0 1200]) 400
  let _ ← expectStatus "nine disclosures" (body ((Array.range 9).map fun _ => disc 0 1)) 400
  let _ ← expectStatus "empty disclosures" (body #[]) 400
  let _ ← expectStatus "one false predicate" (body #[disc 0 1000, disc 1 99]) 400
  IO.println "✓ API: two disclosures certify and verify; both forms, duplicates, 9, empty, false refused with 400"

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
  attributeRelabelCheck
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
  fixedTraceShapeCheck
  multiDisclosureCheck
  apiMultiDisclosureCheck
  IO.println "All predicate soundness tests passed"
