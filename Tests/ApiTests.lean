/-
API handler tests: status codes and bodies of `/certificate/generate`,
`/certificates/batch` and `/certificate/verify`, called in-process (no
socket). Three proofs in total: one generate, one batch entry, one reuse.
-/

import ZkIpProtocol.Api

namespace Tests

open Lean ZkIpProtocol

def attrs : String :=
  "[{\"type\":\"performance\",\"value\":1500},{\"type\":\"security\",\"value\":8},{\"type\":\"efficiency\",\"value\":95}]"

def genBody (threshold : Nat) (extra : String := "") : String :=
  s!"\{\"id\":1,\"attributes\":{attrs},\"predicate\":\{\"operator\":\">\",\"threshold\":{threshold}}{extra}}"

def expectStatus (name : String) (resp : HttpResponse) (code : Nat) : IO Unit := do
  if resp.statusCode != code then
    throw (IO.userError s!"{name}: expected {code}, got {resp.statusCode}: {resp.body}")
  IO.println s!"✓ {name}: {code}"

def bodyJson (resp : HttpResponse) : IO Json :=
  match Json.parse resp.body with
  | .ok j => pure j
  | .error e => throw (IO.userError s!"response is not JSON: {e}")

def field (j : Json) (k : String) : IO Json :=
  match j.getObjVal? k with
  | .ok v => pure v
  | .error e => throw (IO.userError e)

/-- Requests the server must refuse with 400 before proving anything. -/
def testRejections : IO Unit := do
  IO.println "=== Rejected requests ==="
  expectStatus "invalid JSON" (← handleGenerate "{") 400
  expectStatus "missing fields" (← handleGenerate "{\"invalid\":\"data\"}") 400
  expectStatus "operator <" (← handleGenerate ((genBody 1000).replace "\">\"" "\"<\"")) 400
  expectStatus "threshold ≥ 2^32" (← handleGenerate (genBody (2 ^ 32))) 400
  expectStatus "attributeIndex out of range" (← handleGenerate (genBody 1000 ",\"attributeIndex\":3")) 400
  expectStatus "merkleRoot mismatch" (← handleGenerate (genBody 1000 ",\"merkleRoot\":\"0x00\"")) 400
  expectStatus "attribute equals threshold" (← handleGenerate (genBody 1500)) 400
  expectStatus "predicate false (1500 > 2000)" (← handleGenerate (genBody 2000)) 400
  expectStatus "privateAttribute removed" (← handleGenerate (genBody 1000 ",\"privateAttribute\":1500")) 400
  expectStatus "verify: malformed certificate" (← handleVerify "{\"invalid\":\"certificate\"}") 400
  expectStatus "batch: missing requests" (← handleBatchCertificates "{}") 400
  expectStatus "batch: empty requests" (← handleBatchCertificates "{\"requests\":[]}") 400

/-- Generate, verify, then verify a tampered copy. -/
def testRoundTrip : IO Unit := do
  IO.println "=== Generate and verify ==="
  let gen ← handleGenerate (genBody 1000)
  expectStatus "generate 1500 > 1000" gen 200
  let cert ← field (← bodyJson gen) "certificate"
  let ver ← handleVerify cert.compress
  expectStatus "verify honest certificate" ver 200
  if (← field (← bodyJson ver) "verified") != Json.bool true then
    throw (IO.userError s!"honest certificate not verified: {ver.body}")
  IO.println "✓ honest certificate verified"
  let tampered := cert.setObjVal! "predicate"
    (Json.mkObj [("operator", Json.str ">"), ("threshold", Json.num 1400)])
  let ver ← handleVerify tampered.compress
  expectStatus "verify tampered threshold" ver 200
  if (← field (← bodyJson ver) "verified") != Json.bool false then
    throw (IO.userError s!"tampered certificate verified: {ver.body}")
  IO.println "✓ tampered threshold rejected"

/-- One good and one bad entry: the batch reports each in place. -/
def testBatch : IO Unit := do
  IO.println "=== Batch ==="
  let resp ← handleBatchCertificates s!"\{\"requests\":[{genBody 1000},{genBody 2000}]}"
  expectStatus "batch with one failing entry" resp 200
  let j ← bodyJson resp
  if (← field j "succeeded") != Json.num 1 || (← field j "failed") != Json.num 1 then
    throw (IO.userError s!"expected 1 succeeded and 1 failed: {resp.body}")
  IO.println "✓ batch reports 1 succeeded, 1 failed"

end Tests

def main : IO Unit := do
  Tests.testRejections
  Tests.testRoundTrip
  Tests.testBatch
  IO.println "\n✓ All API tests passed"
