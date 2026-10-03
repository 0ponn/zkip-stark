/-
ZK-IP Protocol REST API Service
Provides HTTP endpoints for certificate generation and verification
-/

import ZkIpProtocol.STARKIntegration
import ZkIpProtocol.Advertisement
import ZkIpProtocol.CoreTypes
import ZkIpProtocol.MerkleCommitment
import Lean.Data.Json
import Ix.Aiur.Goldilocks

open Lean
open Aiur

namespace ZkIpProtocol


/-- Simple HTTP response structure -/
structure HttpResponse where
  statusCode : Nat
  headers : List (String × String)
  body : String
  deriving Repr

/-- Create JSON response -/
def jsonResponse (statusCode : Nat) (data : Json) : HttpResponse :=
  {
    statusCode
    headers := [("Content-Type", "application/json")]
    body := Json.pretty data
  }

/-- Create error response -/
def errorResponse (statusCode : Nat) (message : String) : IO HttpResponse :=
  return jsonResponse statusCode (Json.mkObj [("error", Json.str message)])

/-- Convert ByteArray to hex string for JSON -/
def byteArrayToHex (ba : ByteArray) : String :=
  "0x" ++ (ba.toList.map (fun b =>
    let hex := b.toNat
    let high := hex / 16
    let low := hex % 16
    let toHexChar (n : Nat) : Char :=
      if n < 10 then Char.ofNat (Char.toNat '0' + n)
      else Char.ofNat (Char.toNat 'a' + n - 10)
    String.mk [toHexChar high, toHexChar low]
  )).foldl (· ++ ·) ""

/-- Convert hex string to ByteArray -/
def hexToByteArray (hexStr : String) : Option ByteArray :=
  let hex := hexStr.trim
  if hex.startsWith "0x" || hex.startsWith "0X" then
    let digits := (hex.drop 2).toString
    if digits.length % 2 != 0 then none
    else
      let hexToNat (c : Char) : Option Nat :=
        if '0' ≤ c && c ≤ '9' then some (c.toNat - '0'.toNat)
        else if 'a' ≤ c && c ≤ 'f' then some (c.toNat - 'a'.toNat + 10)
        else if 'A' ≤ c && c ≤ 'F' then some (c.toNat - 'A'.toNat + 10)
        else none
      let rec parseBytes (remaining : List Char) (acc : List UInt8) : Option (List UInt8) :=
        match remaining with
        | [] => some acc.reverse
        | [_] => none  -- Odd number of chars
        | high :: low :: rest => do
          let h ← hexToNat high
          let l ← hexToNat low
          parseBytes rest ((UInt8.ofNat (h * 16 + l)) :: acc)
      match parseBytes digits.toList [] with
      | some bytes => some (ByteArray.mk bytes.toArray)
      | none => none
  else none

/-- Parse IPPredicate from JSON -/
def parseIPPredicate (json : Json) : Option IPPredicate := do
  let threshold ← (Json.getObjVal? json "threshold" >>= Json.getNat?).toOption
  let operator ← (Json.getObjVal? json "operator" >>= Json.getStr?).toOption
  some { threshold, operator }

/-- Parse STARKProof from JSON -/
def parseSTARKProof (json : Json) : Option STARKProof := do
  let proofJsonVal ← (Json.getObjVal? json "proof").toOption
  let proofJson ← match proofJsonVal with
    | Json.obj obj => some (Json.obj obj)
    | _ => none
  let vkId ← (Json.getObjVal? proofJson "vkId" >>= Json.getStr?).toOption
  let publicInputsJson ← (Json.getObjVal? proofJson "publicInputs" >>= Json.getArr?).toOption
  let publicInputs := publicInputsJson.filterMap (fun inputJson =>
    match (Json.getStr? inputJson).toOption with
    | some hexStr => hexToByteArray hexStr
    | none => none
  )
  let proofDataHex ← (Json.getObjVal? proofJson "proofData" >>= Json.getStr?).toOption
  let proofData ← hexToByteArray proofDataHex
  some {
    vkId
    publicInputs
    proofData
  }

/-- Parse Ixon from JSON (for certificate generation) -/
def parseIxon (json : Json) : Option Ixon := do
  let id ← (Json.getObjVal? json "id" >>= Json.getNat?).toOption
  let attributesJson ← (Json.getObjVal? json "attributes" >>= Json.getArr?).toOption
  -- Every attribute entry must parse: a dropped entry would silently shift
  -- `attributeIndex` and change the committed tree.
  let attributes ← attributesJson.mapM (fun attrJson => do
    let attrType ← (Json.getObjVal? attrJson "type" >>= Json.getStr?).toOption
    let value ← (Json.getObjVal? attrJson "value" >>= Json.getNat?).toOption
    match attrType with
    | "performance" => some (IPAttribute.performance value)
    | "security" => some (IPAttribute.security value)
    | "efficiency" => some (IPAttribute.efficiency value)
    | "custom" => do
      let name ← (Json.getObjVal? attrJson "name" >>= Json.getStr?).toOption
      some (IPAttribute.custom name value)
    | _ => none
  )
  -- A supplied `merkleRoot` must decode; malformed hex is an error, not "absent".
  let merkleRootBytes ← match (Json.getObjVal? json "merkleRoot").toOption with
    | none => some ByteArray.empty
    | some (Json.str s) => hexToByteArray s
    | some (Json.arr nums) => nums.mapM (fun n => (Json.getNat? n).toOption.map UInt8.ofNat) |>.map ByteArray.mk
    | some _ => none
  let timestamp := ((Json.getObjVal? json "timestamp" >>= Json.getNat?).toOption).getD 0
  some {
    id
    attributes := attributes
    merkleRoot := merkleRootBytes
    timestamp
  }

/-- Parse ZKCertificate from JSON -/
def parseZKCertificate (json : Json) : Option ZKCertificate := do
  let ipId ← (Json.getObjVal? json "ipId" >>= Json.getNat?).toOption
  let commitmentHex ← (Json.getObjVal? json "commitment" >>= Json.getStr?).toOption
  let commitment ← hexToByteArray commitmentHex
  let predicateJsonVal ← (Json.getObjVal? json "predicate").toOption
  let predicateJson ← match predicateJsonVal with
    | Json.obj obj => some (Json.obj obj)
    | _ => none
  let predicate ← parseIPPredicate predicateJson
  let proof ← parseSTARKProof json
  let timestamp := ((Json.getObjVal? json "timestamp" >>= Json.getNat?).toOption).getD 0
  some {
    ipId
    commitment
    predicate
    proof
    timestamp
  }


/-- Convert IPPredicate to JSON -/
def ipPredicateToJson (pred : IPPredicate) : Json :=
  Json.mkObj [
    ("threshold", Json.num pred.threshold),
    ("operator", Json.str pred.operator)
  ]

/-- Convert STARKProof to JSON -/
def starkProofToJson (proof : STARKProof) : Json :=
  Json.mkObj [
    ("vkId", Json.str proof.vkId),
    ("publicInputs", Json.arr (proof.publicInputs.map (fun ba => Json.str (byteArrayToHex ba)))),
    ("proofData", Json.str (byteArrayToHex proof.proofData))
  ]

/-- Convert ZKCertificate to JSON -/
def certificateToJson (cert : ZKCertificate) : Json :=
  Json.mkObj [
    ("ipId", Json.num cert.ipId),
    ("timestamp", Json.num cert.timestamp),
    ("commitment", Json.str (byteArrayToHex cert.commitment)),
    ("predicate", ipPredicateToJson cert.predicate),
    ("proof", starkProofToJson cert.proof)
  ]

/-- Parse one generate request and produce a certificate, or (status, message).
    Shared by `/certificate/generate` and `/certificates/batch`.

    Request: `{ id, attributes: [{type, value[, name]}], predicate: {threshold, operator: ">"},
    attributeIndex?: Nat (default 0), merkleRoot?: hex, timestamp?: Nat }`.
    The witness is `attributes[attributeIndex]`; the root is recomputed from the
    attributes and a supplied `merkleRoot` must match it. -/
def generateFromJson (json : Json) : IO (Except (Nat × String) ZKCertificate) := do
  let some ixon := parseIxon json | return .error (400, "Invalid Ixon format")
  let some predicate := (Json.getObjVal? json "predicate").toOption >>= parseIPPredicate
    | return .error (400, "Invalid predicate format")
  if (Json.getObjVal? json "privateAttribute").toOption.isSome then
    return .error (400, "privateAttribute was removed; send attributeIndex (the attribute to prove)")
  if predicate.operator != ">" then
    return .error (400, "operator must be \">\" (the circuit proves attribute > threshold)")
  if predicate.threshold ≥ 2 ^ 32 then return .error (400, "threshold must be < 2^32")
  if ixon.attributes.any (·.value ≥ 2 ^ 32) then return .error (400, "attribute values must be < 2^32")
  let attributeIndex := ((Json.getObjVal? json "attributeIndex" >>= Json.getNat?).toOption).getD 0
  let some witness := ixon.attributes[attributeIndex]?.map (·.value)
    | return .error (400, s!"attributeIndex {attributeIndex} out of range for {ixon.attributes.size} attributes")
  let root ← buildMerkleTree (ixon.attributes.map (attrLeafBytes ·.value))
  if !ixon.merkleRoot.isEmpty && ixon.merkleRoot != root then
    return .error (400, "merkleRoot does not match attributes")
  if witness == predicate.threshold then
    return .error (400, s!"attribute {attributeIndex} equals the threshold; the predicate is strict")
  let cert? ← try
      generateCertificateWithSTARK { ixon with merkleRoot := root } predicate attributeIndex
    catch ex => do
      (← IO.getStderr).putStrLn s!"Certificate generation exception: {ex}"
      pure none
  let some cert := cert?
    | return .error (500, "Failed to generate certificate: predicate not satisfied or proof failed")
  -- Post-generation check: the certificate's own proof verifies.
  if !(← verifySTARKProof cert.proof cert.predicate.threshold cert.commitment) then
    return .error (500, "Generated proof failed self-verification")
  return .ok cert

/-- Handle POST /api/v1/certificate/generate -/
def handleGenerate (body : String) : IO HttpResponse := do
  let json ← match Json.parse body with
    | .ok j => pure j
    | .error err => return (← errorResponse 400 s!"Invalid JSON: {err}")
  match ← generateFromJson json with
  | .error (status, msg) => errorResponse status msg
  | .ok cert => return jsonResponse 200 (Json.mkObj [
      ("success", Json.bool true),
      ("certificate", certificateToJson cert)
    ])

/-- Upper bound on entries per batch request: each entry is a full STARK prove
on a single-threaded server. -/
def maxBatchRequests : Nat := 16

/-- Handle POST /api/v1/certificates/batch: `{ "requests": [ <generate request>, ... ] }`,
each entry shaped exactly like a `/certificate/generate` body. Per-entry
failures are reported in place; the response is 200 when the batch itself was
well-formed. -/
def handleBatchCertificates (body : String) : IO HttpResponse := do
  let json ← match Json.parse body with
    | .ok j => pure j
    | .error err => return (← errorResponse 400 s!"Invalid JSON: {err}")
  let requestsJson ← match (Json.getObjVal? json "requests" >>= Json.getArr?).toOption with
    | some arr => pure arr
    | none => return (← errorResponse 400 "Missing 'requests' array")
  if requestsJson.isEmpty then
    return (← errorResponse 400 "Empty requests array")
  if requestsJson.size > maxBatchRequests then
    return (← errorResponse 400 s!"Too many requests: {requestsJson.size} > {maxBatchRequests}")

  let mut results : Array Json := #[]
  let mut successCount := 0
  let mut failureCount := 0
  for reqJson in requestsJson do
    match ← generateFromJson reqJson with
    | .ok cert =>
      results := results.push (certificateToJson cert)
      successCount := successCount + 1
    | .error (_, msg) =>
      results := results.push (Json.mkObj [("error", Json.str msg)])
      failureCount := failureCount + 1

  return jsonResponse 200 (Json.mkObj [
    ("success", Json.bool true),
    ("total", Json.num requestsJson.size),
    ("succeeded", Json.num successCount),
    ("failed", Json.num failureCount),
    ("certificates", Json.arr results)
  ])

/-- Handle POST /api/v1/certificate/verify -/
def handleVerify (body : String) : IO HttpResponse := do
  let json ← match Json.parse body with
    | .ok j => pure j
    | .error err => return (← errorResponse 400 s!"Invalid JSON: {err}")

  let cert ← match parseZKCertificate json with
    | some c => pure c
    | none => return (← errorResponse 400 "Invalid certificate format")

  -- Reconstruct the circuit from the certificate
  -- We need to extract the attribute value from the proof's public inputs
  -- For verification, we reconstruct the circuit that was used to generate the proof
  -- Verify the STARK proof
  let verified? ← try
    let result ← verifyCertificate cert
    pure (some result)
  catch ex => do
    let stderr ← IO.getStderr
    stderr.putStrLn s!"Proof verification exception: {ex}"
    pure none

  match verified? with
  | none => return (← errorResponse 500 "Verification failed due to internal error")
  | some verified =>
    if verified then
      return jsonResponse 200 (Json.mkObj [
        ("success", Json.bool true),
        ("verified", Json.bool true),
        ("message", Json.str "Certificate verification successful")
      ])
    else
      return jsonResponse 200 (Json.mkObj [
        ("success", Json.bool true),
        ("verified", Json.bool false),
        ("message", Json.str "Certificate verification failed: proof is invalid")
      ])

end ZkIpProtocol
