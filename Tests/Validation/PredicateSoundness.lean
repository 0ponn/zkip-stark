/-
Soundness oracle for the predicate circuit.

The predicate circuit must CONSTRAIN `attributeValue > threshold`. A vacuous
circuit (one that constrains nothing) would let every case "verify", so the
negative and boundary cases below are the real test: they must be rejected.

  positive : 1500 > 1000  -> proves AND verifies
  negative :  500 > 1000  -> must NOT verify (ideally fails to prove)
  boundary : 1000 > 1000  -> must NOT verify (off-by-one guard)
-/

import ZkIpProtocol.STARKIntegration
import ZkIpProtocol.MerkleCommitment
import ZkIpProtocol.Api
import Ix.Aiur.Goldilocks
import Lean.Data.Json

namespace Tests.Validation
open ZkIpProtocol Aiur
open Lean (Json)

/-- Build a circuit for a given attr/threshold and run prove -> verify. -/
def proveVerify (attr threshold : Nat) : IO Bool := do
  let merkleRoot ← buildMerkleTree #[]      -- root unused by the predicate in M1
  let circuit : PredicateCircuit :=
    { attributeValue := attr, merkleRoot, threshold,
      operator := ">", merkleProof := { rootHash := merkleRoot, path := #[], isLeft := #[] },
      output := true }
  let publicInputs : Array Aiur.G := #[Aiur.G.ofNat threshold]
  let privateInputs : Array Aiur.G := #[Aiur.G.ofNat attr]
  match ← generateSTARKProof circuit publicInputs privateInputs with
  | none => return false               -- could not prove
  | some proof => verifySTARKProof proof publicInputs circuit

/-- `attributeValue` is a secret witness; it must never appear in the public
claim that ships with the proof. Build a positive case and check the private
value's byte-encoding is absent from every entry of `proof.publicInputs`. -/
def leakCheck (attr threshold : Nat) : IO Unit := do
  let merkleRoot ← buildMerkleTree #[]
  let circuit : PredicateCircuit :=
    { attributeValue := attr, merkleRoot, threshold,
      operator := ">", merkleProof := { rootHash := merkleRoot, path := #[], isLeft := #[] },
      output := true }
  let publicInputs : Array Aiur.G := #[Aiur.G.ofNat threshold]
  let privateInputs : Array Aiur.G := #[Aiur.G.ofNat attr]
  let some proof := (← generateSTARKProof circuit publicInputs privateInputs)
    | throw (IO.userError "leakCheck: prove failed")
  let secret := natToBytes8BE attr
  if proof.publicInputs.any (· == secret) then
    throw (IO.userError "LEAK: private attributeValue present in proof.publicInputs")
  IO.println "✓ no leak: attributeValue absent from public inputs"

/-- `verifySTARKProof` must bind to the caller's expected public inputs: a
proof generated for one threshold must not verify against a different
expected threshold, even though the proof itself is valid. -/
def bindingCheck : IO Unit := do
  let merkleRoot ← buildMerkleTree #[]
  let circuit : PredicateCircuit :=
    { attributeValue := 1500, merkleRoot, threshold := 1000,
      operator := ">", merkleProof := { rootHash := merkleRoot, path := #[], isLeft := #[] },
      output := true }
  let publicInputs : Array Aiur.G := #[Aiur.G.ofNat 1000]
  let privateInputs : Array Aiur.G := #[Aiur.G.ofNat 1500]
  let some proof := (← generateSTARKProof circuit publicInputs privateInputs)
    | throw (IO.userError "bindingCheck: prove failed")
  if (← verifySTARKProof proof #[Aiur.G.ofNat 2000] circuit) then
    throw (IO.userError "verify accepted a mismatched threshold — not bound to caller inputs")
  if !(← verifySTARKProof proof #[Aiur.G.ofNat 1000] circuit) then
    throw (IO.userError "verify rejected the correct threshold")
  IO.println "✓ verify binds to caller-supplied threshold"

/-- `generateSTARKProof` must reject inputs outside the u32 domain the
predicate's `u32_less_than` operates over, rather than reaching
`AiurSystem.prove` — whose Rust synthesis path ABORTS the process
(`ExecError::U32OutOfRange`) on such a value, not a catchable Lean error. -/
def outOfRangeGuardCheck : IO Unit := do
  let merkleRoot ← buildMerkleTree #[]
  let threshold := 2 ^ 32  -- first value outside u32
  let circuit : PredicateCircuit :=
    { attributeValue := threshold + 1, merkleRoot, threshold,
      operator := ">", merkleProof := { rootHash := merkleRoot, path := #[], isLeft := #[] },
      output := true }
  let publicInputs : Array Aiur.G := #[Aiur.G.ofNat threshold]
  let privateInputs : Array Aiur.G := #[Aiur.G.ofNat (threshold + 1)]
  match ← generateSTARKProof circuit publicInputs privateInputs with
  | some _ => throw (IO.userError "out-of-range threshold (2^32) should have been rejected, not proved")
  | none => IO.println "✓ out-of-range guard: threshold = 2^32 rejected before reaching the prover"

/-- `verifySTARKProof` must require `publicInputs.size == abi.publicInputCount`
(1, for the M1 circuit). `publicInputs := #[]` slices to a zero-length claim
segment, which would vacuously equal a zero-length expected-args array and
accept ANY proof for ANY threshold — the arity check must reject this before
the vacuous slice comparison is ever reached. -/
def arityBypassCheck : IO Unit := do
  let merkleRoot ← buildMerkleTree #[]
  let circuit : PredicateCircuit :=
    { attributeValue := 1500, merkleRoot, threshold := 1000,
      operator := ">", merkleProof := { rootHash := merkleRoot, path := #[], isLeft := #[] },
      output := true }
  let publicInputs : Array Aiur.G := #[Aiur.G.ofNat 1000]
  let privateInputs : Array Aiur.G := #[Aiur.G.ofNat 1500]
  let some proof := (← generateSTARKProof circuit publicInputs privateInputs)
    | throw (IO.userError "arityBypassCheck: prove failed")
  if (← verifySTARKProof proof #[] circuit) then
    throw (IO.userError "verify accepted publicInputs := #[] — arity bypass, any threshold verifies!")
  if !(← verifySTARKProof proof #[Aiur.G.ofNat 1000] circuit) then
    throw (IO.userError "verify rejected the correct threshold")
  IO.println "✓ verify rejects arity mismatch (publicInputs := #[])"

/-- `generateCertificateWithSTARK` must apply the u32 range guard at the
Nat level, BEFORE `G.ofNat` (which reduces mod the ~2^64 Goldilocks prime
and could silently wrap an out-of-range Nat into a small, in-range field
element — evading a guard that only ever sees the already-wrapped value). -/
def certificateNatRangeGuardCheck : IO Unit := do
  let merkleRoot ← buildMerkleTree #[]
  let ixon : Ixon := { id := 1, attributes := #[], merkleRoot, timestamp := 0 }
  match ← generateCertificateWithSTARK ixon { threshold := 2 ^ 32, operator := ">" } (2 ^ 32 + 1) #[] 0 with
  | some _ => throw (IO.userError "threshold = 2^32 should have been rejected at the Nat boundary, not certified")
  | none => IO.println "✓ certificate Nat-range guard: threshold >= 2^32 rejected before G.ofNat conversion"
  match ← generateCertificateWithSTARK ixon { threshold := 1000, operator := ">" } (2 ^ 32) #[] 0 with
  | some _ => throw (IO.userError "privateAttribute = 2^32 should have been rejected at the Nat boundary, not certified")
  | none => IO.println "✓ certificate Nat-range guard: privateAttribute >= 2^32 rejected before G.ofNat conversion"

/-- `generateCertificateWithSTARK` must never fabricate a certificate: for a
false predicate (or any other failure to prove) it returns `none`, not a
`some ZKCertificate` carrying `proofData := ByteArray.empty` /
`vkId := "mock_vk_generation_failed"`. The positive case is checked too, to
pin down that a real success still returns a real (non-mock) proof. -/
def noMockCertificateCheck : IO Unit := do
  let merkleRoot ← buildMerkleTree #[]
  let ixon : Ixon := { id := 1, attributes := #[], merkleRoot, timestamp := 0 }
  -- false predicate: 500 > 1000 is false
  match ← generateCertificateWithSTARK ixon { threshold := 1000, operator := ">" } 500 #[] 0 with
  | some cert => throw (IO.userError s!"expected none for a false predicate, got a certificate (vkId={cert.proof.vkId})")
  | none => IO.println "✓ no mock certificate: false predicate returns none, not a fake cert"
  -- positive case: the certificate that IS returned must be a real proof
  match ← generateCertificateWithSTARK ixon { threshold := 1000, operator := ">" } 1500 #[] 0 with
  | none => throw (IO.userError "expected a certificate for a true predicate, got none")
  | some cert =>
    if cert.proof.proofData.isEmpty || cert.proof.vkId == "mock_vk_generation_failed" then
      throw (IO.userError "certificate generation returned a mock proof instead of failing with none")
    IO.println "✓ no mock certificate: successful generation carries a real (non-mock) proof"

/-- The M1 Api verification path must accept a genuinely valid certificate.
Before this fix, `handleVerify` parsed the proof's whole claim expecting a
pre-M1 `[root, threshold]` shape, which does not match the real M1 claim
`[functionChannel, funIdx, threshold, output]` and made verification
spuriously fail (or, via `Tests/Validation`'s `arityBypassCheck` sibling bug,
spuriously succeed) regardless of proof validity. -/
def apiM1VerifyCheck : IO Unit := do
  let merkleRoot ← buildMerkleTree #[]
  let ixon : Ixon := { id := 1, attributes := #[], merkleRoot, timestamp := 0 }
  let predicate : IPPredicate := { threshold := 1000, operator := ">" }
  let some cert := (← generateCertificateWithSTARK ixon predicate 1500 #[] 0)
    | throw (IO.userError "apiM1VerifyCheck: certificate generation failed")
  let body := Json.pretty (certificateToJson cert)
  let response ← handleVerify body
  if response.statusCode != 200 then
    throw (IO.userError s!"apiM1VerifyCheck: expected HTTP 200, got {response.statusCode}: {response.body}")
  match Json.parse response.body >>= (·.getObjValAs? Bool "verified") with
  | .ok true => IO.println "✓ API verification: a valid M1 certificate passes handleVerify"
  | .ok false => throw (IO.userError s!"apiM1VerifyCheck: valid certificate failed to verify: {response.body}")
  | .error e => throw (IO.userError s!"apiM1VerifyCheck: could not parse response: {e}: {response.body}")

/-- The verification path must guard threshold >= 2^32 BEFORE converting with
G.ofNat. G.ofNat reduces mod Goldilocks (~2^64), so an out-of-range threshold
(e.g. 2^64) wraps to a small field value and could be accepted by verification
against a proof for that wrapped value if the guard is missing. This test
manually constructs a certificate JSON with an out-of-range threshold and
asserts that handleVerify rejects it, not wraps and accepts it. -/
def apiVerifyThresholdRangeGuardCheck : IO Unit := do
  let merkleRoot ← buildMerkleTree #[]
  let ixon : Ixon := { id := 1, attributes := #[], merkleRoot, timestamp := 0 }
  let predicate : IPPredicate := { threshold := 1000, operator := ">" }
  let some cert := (← generateCertificateWithSTARK ixon predicate 1500 #[] 0)
    | throw (IO.userError "apiVerifyThresholdRangeGuardCheck: certificate generation failed")
  -- Construct a malicious certificate with out-of-range threshold
  let maliciousCert : ZKCertificate := {
    cert with
    predicate := { threshold := 2 ^ 32, operator := ">" }  -- out of range
  }
  let body := Json.pretty (certificateToJson maliciousCert)
  let response ← handleVerify body
  if response.statusCode != 200 then
    throw (IO.userError s!"apiVerifyThresholdRangeGuardCheck: expected HTTP 200, got {response.statusCode}: {response.body}")
  match Json.parse response.body >>= (·.getObjValAs? Bool "verified") with
  | .ok false => IO.println "✓ API verify threshold guard: threshold >= 2^32 rejected (not wrapped and accepted)"
  | .ok true => throw (IO.userError s!"apiVerifyThresholdRangeGuardCheck: out-of-range threshold (2^32) was accepted — wrap regression!")
  | .error e => throw (IO.userError s!"apiVerifyThresholdRangeGuardCheck: could not parse response: {e}: {response.body}")

end Tests.Validation

open Tests.Validation in
def main : IO Unit := do
  -- positive: 1500 > 1000 must verify
  if !(← proveVerify 1500 1000) then throw (IO.userError "positive case failed to verify")
  IO.println "✓ positive: 1500 > 1000 verifies"
  -- negative: 500 > 1000 is false; must NOT verify (and ideally not prove)
  if (← proveVerify 500 1000) then throw (IO.userError "NEGATIVE case verified — constraint not binding!")
  IO.println "✓ negative: 500 > 1000 rejected"
  -- boundary: 1000 > 1000 is false; must NOT verify
  if (← proveVerify 1000 1000) then throw (IO.userError "boundary case verified — off-by-one")
  IO.println "✓ boundary: 1000 > 1000 rejected"
  -- leak: attributeValue must not appear in the public claim
  leakCheck 1500 1000
  -- verify must bind to the caller's expected public inputs
  bindingCheck
  -- guard: out-of-range (>= 2^32) inputs must be rejected, not crash the prover
  outOfRangeGuardCheck
  -- verify must reject an arity-mismatched publicInputs (M1 final-review fix)
  arityBypassCheck
  -- generateCertificateWithSTARK must guard Nat-level threshold/attribute, before G.ofNat
  certificateNatRangeGuardCheck
  -- generateCertificateWithSTARK must never fabricate a certificate on failure
  noMockCertificateCheck
  -- a valid M1 certificate must pass API verification
  apiM1VerifyCheck
  -- the API verify path must guard threshold >= 2^32 before G.ofNat conversion
  apiVerifyThresholdRangeGuardCheck
  IO.println "All predicate soundness tests passed"
