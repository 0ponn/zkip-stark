# Private/Public Input Separation Security Validation

## Overview

This document describes the security validation implemented in `ZkIpProtocol/Api.lean` to prevent private data from leaking into public STARK proof inputs.

## Security Risk

In a Zero-Knowledge Proof system, **private data must never appear in public inputs**. If private IP attribute values (e.g., performance metrics, security scores) accidentally appear in the public inputs of a STARK proof, they become visible to anyone who verifies the proof, breaking the "zero-knowledge" property.

## Implementation

### SecurityValidation Namespace

Located in `ZkIpProtocol/Api.lean`, the `SecurityValidation` namespace provides:

1. **`extractPrivateAttributeValues`**: Extracts all private attribute values from an `Ixon`
2. **`valueInPublicInputs`**: Checks if a private value appears in public inputs
3. **`validatePrivatePublicSeparation`**: Validates that no private values leak into public inputs
4. **`validatePublicInputsStructure`**: Validates that public inputs match expected structure (Merkle root, threshold)
5. **`validateBeforeProofGeneration`**: Comprehensive validation combining all checks

### Validation Points

#### 1. Pre-Generation Validation (`handleGenerate`)

**Location**: Before calling `generateCertificateWithSTARK`

**Checks**:
- Private attribute values (from `ixon.attributes`) are not in `publicInputs`
- `privateAttribute` is not in `publicInputs`
- Public inputs structure matches expected format (Merkle root hash, threshold)

**Response**: Returns HTTP 400 with security error message if validation fails

#### 2. Post-Generation Validation (`handleGenerate`)

**Location**: After proof generation, before returning certificate

**Checks**:
- The generated proof's public inputs don't contain private data
- Same validation as pre-generation

**Response**: Returns HTTP 500 if generated proof fails security validation

#### 3. Verification Validation (`handleVerify`)

**Location**: Before calling `verifySTARKProof`

**Checks**:
- Public inputs structure matches certificate commitment and threshold
- Validates that public inputs don't contain unexpected private data

**Response**: Returns HTTP 400 if certificate fails security validation

## Example Attack Prevention

### Attack Scenario

A malicious client attempts to send a request where `privateAttribute` (e.g., `100`) appears in the public inputs:

```json
{
  "id": 1,
  "attributes": [{"type": "performance", "value": 100}],
  "predicate": {"threshold": 50, "operator": ">="},
  "privateAttribute": 100
}
```

### Prevention

The `validateBeforeProofGeneration` function detects that:
1. `privateAttribute = 100` is in the private values list
2. `100` appears in `publicInputs` (if attacker tries to inject it)
3. Validation fails with: `"SECURITY VIOLATION: Private attribute values detected in public inputs"`

## Code Flow

```
handleGenerate (request)
  ↓
Parse Ixon, Predicate, privateAttribute
  ↓
Compute expected publicInputs (Merkle root hash, threshold)
  ↓
SecurityValidation.validateBeforeProofGeneration
  ├─ validatePrivatePublicSeparation ✓
  └─ validatePublicInputsStructure ✓
  ↓
generateCertificateWithSTARK
  ↓
Post-generation validation
  ├─ Extract publicInputs from generated proof
  └─ SecurityValidation.validateBeforeProofGeneration ✓
  ↓
Return certificate (if all validations pass)
```

## Testing

To test the security validation:

1. **Valid Request** (should pass):
```bash
curl -X POST http://localhost:8080/api/v1/certificate/generate \
  -H "Content-Type: application/json" \
  -d '{
    "id": 1,
    "attributes": [{"type": "performance", "value": 100}],
    "predicate": {"threshold": 50, "operator": ">="},
    "privateAttribute": 100
  }'
```

2. **Invalid Request** (should fail - if we could inject private data):
   - The validation prevents this at the API layer before it reaches the prover
   - Any attempt to modify `STARKIntegration.lean` to leak private data would be caught by post-generation validation

## Security Guarantees

✅ **Private data never appears in public inputs**
✅ **Public inputs structure is validated**
✅ **Both pre and post-generation checks prevent leaks**
✅ **Verification endpoint validates incoming certificates**

## Future Enhancements

1. **Logging**: Add security event logging for failed validations
2. **Metrics**: Track validation failure rates
3. **Rate Limiting**: Add rate limiting for repeated validation failures
4. **Audit Trail**: Log all validation checks for compliance

---

**Status**: ✅ Implemented and active in `handleGenerate` and `handleVerify`

