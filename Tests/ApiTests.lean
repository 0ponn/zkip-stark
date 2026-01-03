/-
Unit tests for ZkIpProtocol.Api module
Tests JSON parsing, hex conversion, and API handlers
-/

import ZkIpProtocol.Api
import ZkIpProtocol.CoreTypes
import Lean.Data.Json

namespace Tests

open ZkIpProtocol
open Lean

/-- Test hex conversion round-trip -/
def testHexConversion : IO Unit := do
  IO.println "=== Testing Hex Conversion ==="

  let testBytes := ByteArray.mk #[0x00, 0xFF, 0x12, 0x34, 0xAB, 0xCD]
  let hexStr := byteArrayToHex testBytes
  IO.println s!"Original: {testBytes}"
  IO.println s!"Hex: {hexStr}"

  match hexToByteArray hexStr with
  | some decoded =>
    if decoded == testBytes then
      IO.println "✓ Hex conversion round-trip PASSED"
    else
      IO.println s!"✗ Hex conversion FAILED: {decoded} != {testBytes}"
  | none =>
    IO.println "✗ Hex conversion FAILED: Could not decode"

/-- Test IPPredicate JSON parsing -/
def testIPPredicateParsing : IO Unit := do
  IO.println "=== Testing IPPredicate JSON Parsing ==="

  let jsonStr := """{"threshold": 50, "operator": ">="}"""
  match Json.parse jsonStr with
  | .ok json =>
    match parseIPPredicate json with
    | some pred =>
      if pred.threshold == 50 && pred.operator == ">=" then
        IO.println "✓ IPPredicate parsing PASSED"
      else
        IO.println s!"✗ IPPredicate parsing FAILED: {pred}"
    | none =>
      IO.println "✗ IPPredicate parsing FAILED: returned none"
  | .error err =>
    IO.println s!"✗ JSON parse error: {err}"

/-- Test ZKCertificate JSON round-trip -/
def testCertificateJSONRoundTrip : IO Unit := do
  IO.println "=== Testing ZKCertificate JSON Round-Trip ==="

  let cert : ZKCertificate := {
    ipId := 1
    commitment := ByteArray.mk #[0x64, 0x55, 0x5A]
    predicate := {
      threshold := 50
      operator := ">="
    }
    proof := {
      publicInputs := #[ByteArray.mk #[0x01], ByteArray.mk #[0x32]]
      proofData := ByteArray.mk #[0xFF, 0xEE, 0xDD]
      vkId := "test_vk_001"
    }
    timestamp := 1000
  }

  let json := certificateToJson cert
  IO.println s!"Certificate JSON: {Json.pretty json}"

  match parseZKCertificate json with
  | some decoded =>
    if decoded.ipId == cert.ipId &&
       decoded.commitment == cert.commitment &&
       decoded.predicate.threshold == cert.predicate.threshold &&
       decoded.predicate.operator == cert.predicate.operator &&
       decoded.proof.vkId == cert.proof.vkId &&
       decoded.timestamp == cert.timestamp then
      IO.println "✓ ZKCertificate JSON round-trip PASSED"
    else
      IO.println "✗ ZKCertificate JSON round-trip FAILED: fields don't match"
  | none =>
    IO.println "✗ ZKCertificate JSON round-trip FAILED: parse returned none"

/-- Test error handling for malformed JSON -/
def testErrorHandling : IO Unit := do
  IO.println "=== Testing Error Handling ==="

  -- Test invalid JSON
  let invalidJson := "{invalid json}"
  let response ← handleGenerate invalidJson
  if response.statusCode == 400 then
    IO.println "✓ Invalid JSON error handling PASSED"
  else
    IO.println s!"✗ Invalid JSON error handling FAILED: status {response.statusCode}"

  -- Test missing fields
  let missingFields := """{"id": 1}"""
  let response2 ← handleGenerate missingFields
  if response2.statusCode == 400 then
    IO.println "✓ Missing fields error handling PASSED"
  else
    IO.println s!"✗ Missing fields error handling FAILED: status {response2.statusCode}"

/-- Run all API tests -/
def main : IO Unit := do
  IO.println "Running API module tests..."
  IO.println ""

  testHexConversion
  IO.println ""

  testIPPredicateParsing
  IO.println ""

  testCertificateJSONRoundTrip
  IO.println ""

  testErrorHandling
  IO.println ""

  IO.println "=== API Tests Complete ==="

end Tests
