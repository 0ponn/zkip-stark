/-
ZK-IP Protocol REST API Service
Provides HTTP endpoints for certificate generation and verification
-/

import ZkIpProtocol.STARKIntegration
import ZkIpProtocol.CoreTypes
import ZkIpProtocol.MerkleCommitment
import Lean.Data.Json
import Ix.Aiur.Goldilocks

open Lean
open Aiur

namespace ZkIpProtocol

-- G is already defined in STARKIntegration, we can use it directly

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
    let digits := hex.drop 2
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
  let attributes := attributesJson.filterMap (fun attrJson => do
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
  let merkleRootBytes := match (Json.getObjVal? json "merkleRoot").toOption with
    | some (Json.str s) => (hexToByteArray s).getD ByteArray.empty
    | some (Json.arr nums) => ByteArray.mk (nums.filterMap (fun n => (Json.getNat? n).toOption >>= (fun nat => some (UInt8.ofNat nat))))
    | _ => ByteArray.empty
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

/-- Security: Validate that private data never leaks into public inputs -/
namespace SecurityValidation

/-- Extract all private attribute values from an Ixon -/
def extractPrivateAttributeValues (ixon : Ixon) : Array Nat :=
  ixon.attributes.map (fun attr =>
    match attr with
    | .performance n => n
    | .security n => n
    | .efficiency n => n
    | .custom _ n => n
  )

/-- Check if a value appears in an array of Goldilocks field elements -/
def valueInPublicInputs (value : Nat) (publicInputs : Array G) : Bool :=
  publicInputs.any (fun g =>
    -- Convert G back to Nat and compare
    g.val.toNat == value
  )

/-- Validate that private attribute values never appear in public inputs -/
def validatePrivatePublicSeparation
  (ixon : Ixon)
  (privateAttribute : Nat)
  (publicInputs : Array G)
  : Bool :=
  let privateValues := extractPrivateAttributeValues ixon
  let allPrivateValues := privateValues.push privateAttribute

  -- Check that no private value appears in public inputs
  !(allPrivateValues.any (fun privVal => valueInPublicInputs privVal publicInputs))

/-- Validate that the Merkle root in public inputs matches the expected root -/
def validatePublicInputsStructure
  (expectedMerkleRoot : ByteArray)
  (expectedThreshold : Nat)
  (publicInputs : Array G)
  : Option String :=
  if publicInputs.size < 2 then
    some "Public inputs must contain at least Merkle root and threshold"
  else
    -- Extract Merkle root from first public input
    let merkleRootHash := Hash.hash expectedMerkleRoot
    let expectedRootNat := if merkleRootHash.size >= 8 then
        match merkleRootHash.get? 0, merkleRootHash.get? 1, merkleRootHash.get? 2,
              merkleRootHash.get? 3, merkleRootHash.get? 4, merkleRootHash.get? 5,
              merkleRootHash.get? 6, merkleRootHash.get? 7 with
        | some b0, some b1, some b2, some b3, some b4, some b5, some b6, some b7 =>
            (b0.toNat <<< 56) + (b1.toNat <<< 48) + (b2.toNat <<< 40) + (b3.toNat <<< 32) +
            (b4.toNat <<< 24) + (b5.toNat <<< 16) + (b6.toNat <<< 8) + b7.toNat
        | _, _, _, _, _, _, _, _ => 0
      else 0

    match publicInputs.get? 0, publicInputs.get? 1 with
    | some rootG, some thresholdG =>
        let actualRootNat := rootG.val.toNat
        let actualThresholdNat := thresholdG.val.toNat
        if actualRootNat != expectedRootNat then
          some s!"Merkle root mismatch in public inputs: expected {expectedRootNat}, got {actualRootNat}"
        else if actualThresholdNat != expectedThreshold then
          some s!"Threshold mismatch in public inputs: expected {expectedThreshold}, got {actualThresholdNat}"
        else
          none
    | _, _ => some "Public inputs must contain at least Merkle root and threshold"

/-- Comprehensive security validation before proof generation -/
def validateBeforeProofGeneration
  (ixon : Ixon)
  (predicate : IPPredicate)
  (privateAttribute : Nat)
  (publicInputs : Array G)
  : Option String :=
  -- Check 1: Private/public separation
  if !validatePrivatePublicSeparation ixon privateAttribute publicInputs then
    some "SECURITY VIOLATION: Private attribute values detected in public inputs"
  -- Check 2: Public inputs structure
  else
    validatePublicInputsStructure ixon.merkleRoot predicate.threshold publicInputs

end SecurityValidation

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

/-- Handle POST /api/v1/certificate/generate -/
def handleGenerate (body : String) : IO HttpResponse := do
  let json ← match Json.parse body with
    | .ok j => pure j
    | .error err => return (← errorResponse 400 s!"Invalid JSON: {err}")

  let ixon ← match parseIxon json with
    | some i => pure i
    | none => return (← errorResponse 400 "Invalid Ixon format")

  let predicate ← match (Json.getObjVal? json "predicate").toOption >>= parseIPPredicate with
    | some p => pure p
    | none => return (← errorResponse 400 "Invalid predicate format")

  let privateAttribute ← match (Json.getObjVal? json "privateAttribute" >>= Json.getNat?).toOption with
    | some v => pure v
    | none => return (← errorResponse 400 "Missing privateAttribute")

  -- Build IP data from attributes for Merkle tree
  let ipData := ixon.attributes.map (fun attr =>
    match attr with
    | .performance n => natToByteArray n
    | .security n => natToByteArray n
    | .efficiency n => natToByteArray n
    | .custom _ n => natToByteArray n
  )

  -- Compute Merkle root if not provided
  let ixonWithRoot ← if ixon.merkleRoot.isEmpty then do
    let root ← buildMerkleTree ipData
    pure { ixon with merkleRoot := root }
  else
    pure ixon

  let attributeIndex := 0  -- Default to first attribute

  -- SECURITY: Validate private/public input separation before proof generation
  -- Compute expected public inputs to validate structure
  let merkleRootHash := Hash.hash ixonWithRoot.merkleRoot
  let rootHashNat := if merkleRootHash.size >= 8 then
      (merkleRootHash[0]!.toNat <<< 56) + (merkleRootHash[1]!.toNat <<< 48) +
      (merkleRootHash[2]!.toNat <<< 40) + (merkleRootHash[3]!.toNat <<< 32) +
      (merkleRootHash[4]!.toNat <<< 24) + (merkleRootHash[5]!.toNat <<< 16) +
      (merkleRootHash[6]!.toNat <<< 8) + merkleRootHash[7]!.toNat
    else 0
  let expectedPublicInputs : Array G := #[
    G.ofNat rootHashNat,
    G.ofNat predicate.threshold
  ]

  -- Validate separation before calling the prover
  match SecurityValidation.validateBeforeProofGeneration
    ixonWithRoot predicate privateAttribute expectedPublicInputs with
  | some errorMsg =>
    let stderr ← IO.getStderr
    stderr.putStrLn s!"SECURITY VALIDATION FAILED: {errorMsg}"
    return (← errorResponse 400 s!"Security validation failed: {errorMsg}")
  | none =>
    -- Validation passed, proceed with proof generation
    let cert? ← try
      generateCertificateWithSTARK
        ixonWithRoot
        predicate
        privateAttribute
        ipData
        attributeIndex
    catch ex => do
      let stderr ← IO.getStderr
      stderr.putStrLn s!"Certificate generation exception: {ex}"
      pure none

    match cert? with
    | some cert =>
      -- Post-generation validation: Verify the returned proof doesn't leak private data
      let proofPublicInputsG : Array G := cert.proof.publicInputs.filterMap (fun bytes =>
        if bytes.size >= 8 then
          let val := (bytes[0]!.toNat <<< 56) + (bytes[1]!.toNat <<< 48) +
                     (bytes[2]!.toNat <<< 40) + (bytes[3]!.toNat <<< 32) +
                     (bytes[4]!.toNat <<< 24) + (bytes[5]!.toNat <<< 16) +
                     (bytes[6]!.toNat <<< 8) + bytes[7]!.toNat
          some (G.ofNat val)
        else none
      )

      match SecurityValidation.validateBeforeProofGeneration
        ixonWithRoot predicate privateAttribute proofPublicInputsG with
      | some errorMsg =>
        let stderr ← IO.getStderr
        stderr.putStrLn s!"POST-GENERATION SECURITY CHECK FAILED: {errorMsg}"
        return (← errorResponse 500 "Generated proof failed security validation")
      | none =>
        return jsonResponse 200 (Json.mkObj [
          ("success", Json.bool true),
          ("certificate", certificateToJson cert)
        ])
    | none =>
      return (← errorResponse 500 "Failed to generate certificate. Check server logs for details.")

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
  let merkleProof : MerkleProof := {
    rootHash := cert.commitment
    path := #[]
    isLeft := #[]
  }

  -- Extract public inputs from proof
  -- G is already defined in STARKIntegration (same namespace)
  let publicInputsG : Array G := cert.proof.publicInputs.filterMap (fun bytes =>
    if bytes.size >= 8 then
      let val := (bytes[0]!.toNat <<< 56) + (bytes[1]!.toNat <<< 48) +
                 (bytes[2]!.toNat <<< 40) + (bytes[3]!.toNat <<< 32) +
                 (bytes[4]!.toNat <<< 24) + (bytes[5]!.toNat <<< 16) +
                 (bytes[6]!.toNat <<< 8) + bytes[7]!.toNat
      some (Aiur.G.ofNat val)
    else none
  )

  -- SECURITY: Validate that public inputs don't contain private data
  -- We don't have the original privateAttribute, but we can validate structure
  match SecurityValidation.validatePublicInputsStructure
    cert.commitment cert.predicate.threshold publicInputsG with
  | some errorMsg =>
    let stderr ← IO.getStderr
    stderr.putStrLn s!"VERIFICATION SECURITY CHECK FAILED: {errorMsg}"
    return (← errorResponse 400 s!"Certificate verification failed security validation: {errorMsg}")
  | none =>
    -- Structure is valid, proceed with verification
    -- Reconstruct the circuit used for verification
    -- Note: We don't have the private attribute value, so we create a circuit
    -- that matches the public inputs structure
    let circuit : PredicateCircuit := {
      attributeValue := 0  -- Not used in verification
      merkleRoot := cert.commitment
      threshold := cert.predicate.threshold
      operator := cert.predicate.operator
      merkleProof
      output := true
    }

    -- Verify the STARK proof
    let verified? ← try
      let result ← verifySTARKProof cert.proof publicInputsG circuit
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
