/-
ZK-IP Protocol REST API Service
Provides HTTP endpoints for certificate generation and verification
-/

import ZkIpProtocol.Core.STARKIntegration
import ZkIpProtocol.CoreTypes
import ZkIpProtocol.MerkleCommitment
import ZkIpProtocol.Apps.Financing.FinancialVector
import ZkIpProtocol.Apps.Financing.LenderCircuits
import ZkIpProtocol.Apps.Financing.BatchedLenderCircuits
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

-- Security: Validate that private data never leaks into public inputs
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
        let b0 := merkleRootHash[0]!
        let b1 := merkleRootHash[1]!
        let b2 := merkleRootHash[2]!
        let b3 := merkleRootHash[3]!
        let b4 := merkleRootHash[4]!
        let b5 := merkleRootHash[5]!
        let b6 := merkleRootHash[6]!
        let b7 := merkleRootHash[7]!
        (b0.toNat <<< 56) + (b1.toNat <<< 48) + (b2.toNat <<< 40) + (b3.toNat <<< 32) +
        (b4.toNat <<< 24) + (b5.toNat <<< 16) + (b6.toNat <<< 8) + b7.toNat
      else 0

    match publicInputs[0]?, publicInputs[1]? with
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
      -- Convert ByteArray public inputs to G, handling both large (8+ bytes) and small (<8 bytes) values
      -- Note: natToByteArray uses big-endian (most significant byte first)
      let proofPublicInputsG : Array G := cert.proof.publicInputs.map (fun bytes =>
        if bytes.size >= 8 then
          -- Large value: use first 8 bytes (big-endian)
          let val := (bytes[0]!.toNat <<< 56) + (bytes[1]!.toNat <<< 48) +
                     (bytes[2]!.toNat <<< 40) + (bytes[3]!.toNat <<< 32) +
                     (bytes[4]!.toNat <<< 24) + (bytes[5]!.toNat <<< 16) +
                     (bytes[6]!.toNat <<< 8) + bytes[7]!.toNat
          G.ofNat val
        else
          -- Small value: convert from bytes (big-endian, most significant byte first)
          let val := bytes.foldl (fun acc b => acc * 256 + b.toNat) 0
          G.ofNat val
      )

      -- Post-generation validation: Verify the returned proof doesn't leak private data
      -- Critical security check: proofs without required public inputs are invalid
      if proofPublicInputsG.size < 2 then
        let stderr ← IO.getStderr
        stderr.putStrLn s!"POST-GENERATION SECURITY CHECK FAILED: Insufficient public inputs (got {proofPublicInputsG.size}, required 2)"
        stderr.putStrLn "Proofs must contain at least Merkle root and threshold in public inputs"
        return (← errorResponse 500 "Generated proof failed security validation: insufficient public inputs")

      -- Debug: Log public input values to diagnose validation issues
      let stderr ← IO.getStderr
      let publicInputValues := proofPublicInputsG.map (fun g => g.val.toNat)
      stderr.putStrLn s!"DEBUG: Post-generation validation - privateAttribute: {privateAttribute}"
      stderr.putStrLn s!"DEBUG: Public input values: {publicInputValues}"

      -- Check if privateAttribute (the value we're proving) appears in public inputs
      -- This is the critical security check - the value being proven should not be public
      -- Note: We allow threshold in public inputs (it's supposed to be public), but we check
      -- if privateAttribute matches the threshold as a sanity check (they shouldn't match)
      -- We reject if the actual privateAttribute value appears in Merkle root (index 0) or threshold (index 1)
      match proofPublicInputsG[0]?, proofPublicInputsG[1]? with
      | some rootG, some thresholdG =>
        let rootValue := rootG.val.toNat
        let thresholdValue := thresholdG.val.toNat

        -- Check if privateAttribute matches threshold (shouldn't happen, but worth checking)
        if thresholdValue == privateAttribute then
          stderr.putStrLn s!"POST-GENERATION SECURITY CHECK FAILED: privateAttribute ({privateAttribute}) matches threshold ({thresholdValue})"
          stderr.putStrLn s!"This is suspicious - the value being proven should not equal the threshold"
          return (← errorResponse 500 "Generated proof failed security validation: private data matches threshold")

        -- Check if privateAttribute matches Merkle root (definitely a leak)
        if rootValue == privateAttribute then
          stderr.putStrLn s!"POST-GENERATION SECURITY CHECK FAILED: privateAttribute ({privateAttribute}) matches Merkle root ({rootValue})"
          stderr.putStrLn s!"This indicates the private value has leaked into the Merkle root, which is a security violation"
          return (← errorResponse 500 "Generated proof failed security validation: private data leaked to Merkle root")
      | _, _ =>
        -- This shouldn't happen since we already checked size >= 2, but handle it anyway
        stderr.putStrLn "POST-GENERATION SECURITY CHECK FAILED: Could not access public inputs"
        return (← errorResponse 500 "Generated proof failed security validation: could not access public inputs")

      return jsonResponse 200 (Json.mkObj [
        ("success", Json.bool true),
        ("certificate", certificateToJson cert)
      ])
    | none =>
      let stderr ← IO.getStderr
      stderr.putStrLn "Certificate generation returned none - possible causes:"
      stderr.putStrLn "  1. No matching attribute found in Ixon"
      stderr.putStrLn "  2. Merkle verification failed"
      stderr.putStrLn "  3. Circuit verification failed"
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

/-- Handle POST /api/v1/financing/eligibility -/
def handleFinancingEligibility (body : String) : IO HttpResponse := do
  let json ← match Json.parse body with
    | .ok j => pure j
    | .error err => return (← errorResponse 400 s!"Invalid JSON: {err}")

  -- Parse financial vector
  let creditScore ← match (Json.getObjVal? json "creditScore" >>= Json.getNat?).toOption with
    | some v => pure v
    | none => return (← errorResponse 400 "Missing creditScore")
  
  let income ← match (Json.getObjVal? json "income" >>= Json.getNat?).toOption with
    | some v => pure v
    | none => return (← errorResponse 400 "Missing income")
  
  let debtToIncomeRatio ← match (Json.getObjVal? json "debtToIncomeRatio" >>= Json.getNat?).toOption with
    | some v => pure v
    | none => return (← errorResponse 400 "Missing debtToIncomeRatio")
  
  let lenderIdHex ← match (Json.getObjVal? json "lenderId" >>= Json.getStr?).toOption with
    | some s => pure s
    | none => return (← errorResponse 400 "Missing lenderId")
  
  let lenderId ← match hexToByteArray lenderIdHex with
    | some ba => pure ba
    | none => return (← errorResponse 400 "Invalid lenderId hex format")
  
  -- Parse lender thresholds
  let minIncome ← match (Json.getObjVal? json "minIncome" >>= Json.getNat?).toOption with
    | some v => pure v
    | none => return (← errorResponse 400 "Missing minIncome")
  
  let minCreditScore ← match (Json.getObjVal? json "minCreditScore" >>= Json.getNat?).toOption with
    | some v => pure v
    | none => return (← errorResponse 400 "Missing minCreditScore")
  
  let maxDebtToIncome ← match (Json.getObjVal? json "maxDebtToIncome" >>= Json.getNat?).toOption with
    | some v => pure v
    | none => return (← errorResponse 400 "Missing maxDebtToIncome")
  
  let thresholdLenderIdHex ← match (Json.getObjVal? json "thresholdLenderId" >>= Json.getStr?).toOption with
    | some s => pure s
    | none => return (← errorResponse 400 "Missing thresholdLenderId")
  
  let thresholdLenderId ← match hexToByteArray thresholdLenderIdHex with
    | some ba => pure ba
    | none => return (← errorResponse 400 "Invalid thresholdLenderId hex format")
  
  -- Parse Merkle proof from JSON
  let merkleRootHex ← match (Json.getObjVal? json "merkleRoot" >>= Json.getStr?).toOption with
    | some s => pure s
    | none => pure "0x"
  
  let merkleRoot ← match hexToByteArray merkleRootHex with
    | some ba => pure ba
    | none => pure ByteArray.empty
  
  -- Parse Merkle proof path and directions
  let merkleProofJson ← match (Json.getObjVal? json "merkleProof").toOption with
    | some proofJson => pure proofJson
    | none => pure (Json.mkObj [])
  
  -- Parse path (array of hex strings)
  let pathHexArray ← match (Json.getObjVal? merkleProofJson "path" >>= Json.getArr?).toOption with
    | some arr => pure arr
    | none => pure #[]
  
  let merklePath : Array ByteArray := pathHexArray.filterMap (fun hexJson =>
    match hexJson with
    | Json.str hexStr => hexToByteArray hexStr
    | _ => none
  )
  
  -- Parse isLeft (array of booleans)
  let isLeftArray ← match (Json.getObjVal? merkleProofJson "isLeft" >>= Json.getArr?).toOption with
    | some arr => pure arr
    | none => pure #[]
  
  let merkleIsLeft : Array Bool := isLeftArray.filterMap (fun boolJson =>
    match boolJson with
    | Json.bool b => some b
    | _ => none
  )

  -- Optional provider-issued salt (Nat)
  let merkleSalt := ((Json.getObjVal? merkleProofJson "salt" >>= Json.getNat?).toOption)
    |>.getD ((Json.getObjVal? json "merkleSalt" >>= Json.getNat?).toOption |>.getD 0)

  -- Enforce fixed Merkle depth by padding
  let fixedDepth := ZkIpProtocol.merkleFixedDepth
  if merklePath.size != merkleIsLeft.size then
    return (← errorResponse 400 "Merkle path and direction sizes must match")
  if merklePath.size > fixedDepth then
    return (← errorResponse 400 s!"Merkle path too long (max {fixedDepth})")
  let padCount := fixedDepth - merklePath.size
  let paddedPath := merklePath ++ (Array.replicate padCount ByteArray.empty)
  let paddedIsLeft := merkleIsLeft ++ (Array.replicate padCount false)
  
  -- Build Merkle proof structure
  let merkleProof : MerkleProof := {
    rootHash := merkleRoot
    path := paddedPath
    isLeft := paddedIsLeft
  }
  
  -- Build financial vector and thresholds
  let financialVector : ZkIpProtocol.Apps.Financing.FinancialVector := {
    creditScore
    income
    debtToIncomeRatio
    merkleSalt
    lenderId
    merkleRoot
    merkleProof
  }
  
  let thresholds : ZkIpProtocol.Apps.Financing.LenderThresholds := {
    minIncome
    minCreditScore
    maxDebtToIncome
    lenderId := thresholdLenderId
  }
  
  -- Convert Merkle path to field elements
  -- Siblings: convert ByteArray path elements to field elements (first 8 bytes as Nat)
  let merklePathSiblings : Array G := paddedPath.map (fun ba =>
    if ba.size >= 8 then
      let bytes := ba.toList.take 8
      let nat := bytes.foldl (fun acc b => acc * 256 + b.toNat) 0
      G.ofNat nat
    else
      G.ofNat 0
  )
  
  -- Directions: convert Bool array to field elements (0 = left, 1 = right)
  let merklePathDirections : Array G := paddedIsLeft.map (fun isLeft =>
    if isLeft then G.ofNat 0 else G.ofNat 1
  )
  
  -- Compute financial data leaf hash using Poseidon(income, creditScore, debtToIncomeRatio)
  let financialDataLeaf : G := ZkIpProtocol.Apps.Financing.FinancialVector.computeFinancialDataLeaf financialVector
  
  -- Build circuit
  let circuit : ZkIpProtocol.Apps.Financing.LenderCircuit := {
    financialVector
    thresholds
    incomeWitness := ZkIpProtocol.Apps.Financing.FinancialVector.incomeToField financialVector
    creditScoreWitness := ZkIpProtocol.Apps.Financing.FinancialVector.creditScoreToField financialVector
    debtToIncomeWitness := ZkIpProtocol.Apps.Financing.FinancialVector.debtToIncomeToField financialVector
    lenderIdWitness := ZkIpProtocol.Apps.Financing.FinancialVector.lenderIdToField financialVector
    merklePathSiblings
    merklePathDirections
    output := true
  }
  
  -- Verify eligibility (in-circuit checks)
  if !ZkIpProtocol.Apps.Financing.LenderCircuit.verifyEligibility circuit then
    return jsonResponse 200 (Json.mkObj [
      ("success", Json.bool true),
      ("eligible", Json.bool false),
      ("message", Json.str "Applicant does not meet eligibility criteria")
    ])
  
  -- Prepare public and private inputs
  let lenderIdField := ZkIpProtocol.Apps.Financing.LenderThresholds.lenderIdToField thresholds
  let minIncomeField := ZkIpProtocol.Apps.Financing.LenderThresholds.minIncomeToField thresholds
  let minCreditScoreField := ZkIpProtocol.Apps.Financing.LenderThresholds.minCreditScoreToField thresholds
  let maxDebtToIncomeField := ZkIpProtocol.Apps.Financing.LenderThresholds.maxDebtToIncomeToField thresholds

  -- Compute Merkle root hash as field element
  let merkleRootField := if merkleRoot.size >= 8 then
      let bytes := merkleRoot.toList.take 8
      let nat := bytes.foldl (fun acc b => acc * 256 + b.toNat) 0
      G.ofNat nat
    else G.ofNat 0

  -- 5 public inputs: lenderId, minIncome, minCreditScore, maxDebtToIncome, merkleRoot
  let publicInputs : Array G := #[
    lenderIdField,
    minIncomeField,
    minCreditScoreField,
    maxDebtToIncomeField,
    merkleRootField
  ]

  let incomeWitness := ZkIpProtocol.Apps.Financing.FinancialVector.incomeToField financialVector
  let creditScoreWitness := ZkIpProtocol.Apps.Financing.FinancialVector.creditScoreToField financialVector
  let debtToIncomeWitness := ZkIpProtocol.Apps.Financing.FinancialVector.debtToIncomeToField financialVector
  let lenderIdWitness := ZkIpProtocol.Apps.Financing.FinancialVector.lenderIdToField financialVector
  let isValid := G.ofNat 1

  -- Compute financial data leaf hash
  let financialDataLeaf := ZkIpProtocol.Apps.Financing.FinancialVector.computeFinancialDataLeaf financialVector

  -- 6 + 2*pathDepth private inputs: income, creditScore, debtToIncome, lenderId, isValid, financialDataLeaf, + path siblings/directions
  let privateInputs : Array G := #[
    incomeWitness,
    creditScoreWitness,
    debtToIncomeWitness,
    lenderIdWitness,
    isValid,
    financialDataLeaf
  ] ++ merklePathSiblings ++ merklePathDirections
  
  -- Generate STARK proof
  let some proof ← ZkIpProtocol.Apps.Financing.LenderCircuit.generateLenderEligibilityProof
    circuit
    publicInputs
    privateInputs
    | return (← errorResponse 500 "Failed to generate STARK proof")
  
  return jsonResponse 200 (Json.mkObj [
    ("success", Json.bool true),
    ("eligible", Json.bool true),
    ("proof", starkProofToJson proof),
    ("message", Json.str "Eligibility verified with zero-knowledge proof")
        ])

/-- Handle POST /api/v1/financing/batch-eligibility -/
def handleBatchedFinancingEligibility (body : String) : IO HttpResponse := do
  let json ← match Json.parse body with
    | .ok j => pure j
    | .error err => return (← errorResponse 400 s!"Invalid JSON: {err}")
  
  -- Parse financial data (same as single lender)
  let creditScore ← match (Json.getObjVal? json "creditScore" >>= Json.getNat?).toOption with
    | some v => pure v
    | none => return (← errorResponse 400 "Missing creditScore")
  
  let income ← match (Json.getObjVal? json "income" >>= Json.getNat?).toOption with
    | some v => pure v
    | none => return (← errorResponse 400 "Missing income")
  
  let debtToIncomeRatio ← match (Json.getObjVal? json "debtToIncomeRatio" >>= Json.getNat?).toOption with
    | some v => pure v
    | none => return (← errorResponse 400 "Missing debtToIncomeRatio")
  
  let merkleRootHex ← match (Json.getObjVal? json "merkleRoot" >>= Json.getStr?).toOption with
    | some s => pure s
    | none => pure "0x"
  
  let merkleRoot ← match hexToByteArray merkleRootHex with
    | some ba => pure ba
    | none => pure ByteArray.empty
  
  -- Parse Merkle proof from JSON (same as single endpoint)
  let merkleProofJson ← match (Json.getObjVal? json "merkleProof").toOption with
    | some proofJson => pure proofJson
    | none => pure (Json.mkObj [])
  
  let pathHexArray ← match (Json.getObjVal? merkleProofJson "path" >>= Json.getArr?).toOption with
    | some arr => pure arr
    | none => pure #[]
  
  let merklePath : Array ByteArray := pathHexArray.filterMap (fun hexJson =>
    match hexJson with
    | Json.str hexStr => hexToByteArray hexStr
    | _ => none
  )
  
  let isLeftArray ← match (Json.getObjVal? merkleProofJson "isLeft" >>= Json.getArr?).toOption with
    | some arr => pure arr
    | none => pure #[]
  
  let merkleIsLeft : Array Bool := isLeftArray.filterMap (fun boolJson =>
    match boolJson with
    | Json.bool b => some b
    | _ => none
  )

  -- Optional provider-issued salt (Nat)
  let merkleSalt := ((Json.getObjVal? merkleProofJson "salt" >>= Json.getNat?).toOption)
    |>.getD ((Json.getObjVal? json "merkleSalt" >>= Json.getNat?).toOption |>.getD 0)

  -- Enforce fixed Merkle depth by padding
  let fixedDepth := ZkIpProtocol.merkleFixedDepth
  if merklePath.size != merkleIsLeft.size then
    return (← errorResponse 400 "Merkle path and direction sizes must match")
  if merklePath.size > fixedDepth then
    return (← errorResponse 400 s!"Merkle path too long (max {fixedDepth})")
  let padCount := fixedDepth - merklePath.size
  let paddedPath := merklePath ++ (Array.replicate padCount ByteArray.empty)
  let paddedIsLeft := merkleIsLeft ++ (Array.replicate padCount false)
  
  let merkleProof : MerkleProof := {
    rootHash := merkleRoot
    path := paddedPath
    isLeft := paddedIsLeft
  }
  
  -- Parse lender thresholds array
  let lendersJson ← match (Json.getObjVal? json "lenders" >>= Json.getArr?).toOption with
    | some arr => pure arr
    | none => return (← errorResponse 400 "Missing 'lenders' array")
  
  if lendersJson.isEmpty then
    return (← errorResponse 400 "Empty lenders array")

  let maxLenders := ZkIpProtocol.maxBatchedLenders
  if lendersJson.size > maxLenders then
    return (← errorResponse 400 s!"Batch size exceeds software-only cap (max {maxLenders}).")
  
  -- Parse each lender's thresholds
  let mut lenderThresholds : Array ZkIpProtocol.Apps.Financing.LenderThresholds := #[]
  let mut lenderIds : Array ByteArray := #[]
  
  for lenderJson in lendersJson do
    let lenderIdHex ← match (Json.getObjVal? lenderJson "lenderId" >>= Json.getStr?).toOption with
      | some s => pure s
      | none => return (← errorResponse 400 "Missing lenderId in lender object")
    
    let lenderId ← match hexToByteArray lenderIdHex with
      | some ba => pure ba
      | none => return (← errorResponse 400 "Invalid lenderId hex format")
    lenderIds := lenderIds.push lenderId
    
    let minIncome ← match (Json.getObjVal? lenderJson "minIncome" >>= Json.getNat?).toOption with
      | some v => pure v
      | none => return (← errorResponse 400 "Missing minIncome in lender object")
    
    let minCreditScore ← match (Json.getObjVal? lenderJson "minCreditScore" >>= Json.getNat?).toOption with
      | some v => pure v
      | none => return (← errorResponse 400 "Missing minCreditScore in lender object")
    
    let maxDebtToIncome ← match (Json.getObjVal? lenderJson "maxDebtToIncome" >>= Json.getNat?).toOption with
      | some v => pure v
      | none => return (← errorResponse 400 "Missing maxDebtToIncome in lender object")
    
    let thresholds : ZkIpProtocol.Apps.Financing.LenderThresholds := {
      minIncome
      minCreditScore
      maxDebtToIncome
      lenderId
    }
    lenderThresholds := lenderThresholds.push thresholds
  
  -- Build financial vector (lenderId not used in batched mode, use first lender's ID)
  let financialVector : ZkIpProtocol.Apps.Financing.FinancialVector := {
    creditScore
    income
    debtToIncomeRatio
    merkleSalt
    lenderId := lenderIds[0]!
    merkleRoot
    merkleProof
  }
  
  -- Convert Merkle path to field elements (same as single endpoint)
  let merklePathSiblings : Array G := paddedPath.map (fun ba =>
    if ba.size >= 8 then
      let bytes := ba.toList.take 8
      let nat := bytes.foldl (fun acc b => acc * 256 + b.toNat) 0
      G.ofNat nat
    else
      G.ofNat 0
  )
  
  let merklePathDirections : Array G := paddedIsLeft.map (fun isLeft =>
    if isLeft then G.ofNat 0 else G.ofNat 1
  )
  
  -- Compute financial data leaf hash using Poseidon(income, creditScore, debtToIncomeRatio)
  let financialDataLeaf : G := ZkIpProtocol.Apps.Financing.FinancialVector.computeFinancialDataLeaf financialVector
  
  -- Build batched circuit
  let batchedCircuit : ZkIpProtocol.Apps.Financing.BatchedLenderCircuit := {
    financialVector
    lenderThresholds
    incomeWitness := ZkIpProtocol.Apps.Financing.FinancialVector.incomeToField financialVector
    creditScoreWitness := ZkIpProtocol.Apps.Financing.FinancialVector.creditScoreToField financialVector
    debtToIncomeWitness := ZkIpProtocol.Apps.Financing.FinancialVector.debtToIncomeToField financialVector
    merklePathSiblings
    merklePathDirections
    financialDataLeaf
    outputs := ZkIpProtocol.Apps.Financing.BatchedLenderCircuit.verifyAllLenders {
      financialVector
      lenderThresholds
      incomeWitness := ZkIpProtocol.Apps.Financing.FinancialVector.incomeToField financialVector
      creditScoreWitness := ZkIpProtocol.Apps.Financing.FinancialVector.creditScoreToField financialVector
      debtToIncomeWitness := ZkIpProtocol.Apps.Financing.FinancialVector.debtToIncomeToField financialVector
      merklePathSiblings
      merklePathDirections
      financialDataLeaf
      outputs := #[]
    }
  }
  
  -- Prepare public inputs: merkleRoot + (lenderId, minIncome, minCreditScore, maxDebtToIncome) per lender
  let merkleRootField := if merkleRoot.size >= 8 then
      let bytes := merkleRoot.toList.take 8
      let nat := bytes.foldl (fun acc b => acc * 256 + b.toNat) 0
      G.ofNat nat
    else
      G.ofNat 0
  let mut publicInputs : Array G := #[merkleRootField]
  
  for thresholds in lenderThresholds do
    let lenderIdField := ZkIpProtocol.Apps.Financing.LenderThresholds.lenderIdToField thresholds
    let minIncomeField := ZkIpProtocol.Apps.Financing.LenderThresholds.minIncomeToField thresholds
    let minCreditScoreField := ZkIpProtocol.Apps.Financing.LenderThresholds.minCreditScoreToField thresholds
    let maxDebtToIncomeField := ZkIpProtocol.Apps.Financing.LenderThresholds.maxDebtToIncomeToField thresholds
    publicInputs := publicInputs ++ #[lenderIdField, minIncomeField, minCreditScoreField, maxDebtToIncomeField]
  
  -- Private inputs: income, creditScore, debtToIncome, financialDataLeaf, + merkle path
  let incomeWitness := ZkIpProtocol.Apps.Financing.FinancialVector.incomeToField financialVector
  let creditScoreWitness := ZkIpProtocol.Apps.Financing.FinancialVector.creditScoreToField financialVector
  let debtToIncomeWitness := ZkIpProtocol.Apps.Financing.FinancialVector.debtToIncomeToField financialVector

  let privateInputs : Array G := #[incomeWitness, creditScoreWitness, debtToIncomeWitness, financialDataLeaf] ++ merklePathSiblings ++ merklePathDirections
  
  -- Generate batched STARK proof
  let proof ←
    match (← ZkIpProtocol.Apps.Financing.BatchedLenderCircuit.generateBatchedLenderProof
      batchedCircuit
      publicInputs
      privateInputs) with
    | some p => pure p
    | none => return (← errorResponse 500 "Failed to generate batched STARK proof")
  
  -- Build results array
  let mut results : Array Json := #[]
  for i in [0:lenderThresholds.size] do
    let isEligible := batchedCircuit.outputs[i]!
    let lenderId := lenderIds[i]!
    results := results.push (Json.mkObj [
      ("lenderId", Json.str (byteArrayToHex lenderId)),
      ("eligible", Json.bool isEligible)
    ])
  
  let message := s!"Batched eligibility verified for {lenderThresholds.size} lenders with zero-knowledge proof"
  return jsonResponse 200 (Json.mkObj [
    ("success", Json.bool true),
    ("proof", starkProofToJson proof),
    ("results", Json.arr results),
    ("message", Json.str message)
  ])

end ZkIpProtocol
