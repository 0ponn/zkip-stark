# API Enhancement Suggestions

## Current Endpoints
- `GET /health` - Health check
- `GET /ready` - Readiness check
- `POST /api/v1/certificate/generate` - Generate certificate
- `POST /api/v1/certificate/verify` - Verify certificate (placeholder)

## Suggested Additional Endpoints

### 1. Batch Certificate Generation
**Endpoint**: `POST /api/v1/certificates/batch`
**Purpose**: Generate multiple certificates in a single request
**Use Case**: When a seller wants to advertise multiple IP assets at once

```json
{
  "requests": [
    {
      "id": 1,
      "attributes": [
        {"type": "performance", "value": 100},
        {"type": "security", "value": 85}
      ],
      "predicate": {
        "threshold": 50,
        "operator": ">="
      },
      "privateAttribute": 100
    },
    {
      "id": 2,
      "attributes": [
        {"type": "efficiency", "value": 90}
      ],
      "predicate": {
        "threshold": 75,
        "operator": ">="
      },
      "privateAttribute": 90
    }
  ]
}
```

### 2. Certificate Listing/Query
**Endpoint**: `GET /api/v1/certificates?ipId=1&predicate=...`
**Purpose**: Query existing certificates by IP ID or predicate
**Use Case**: Buyers searching for IP that meets certain criteria

### 3. Merkle Root Verification
**Endpoint**: `POST /api/v1/merkle/verify`
**Purpose**: Verify a Merkle proof without generating a certificate
**Use Case**: Quick verification of attribute commitments

### 4. Circuit Complexity Analysis
**Endpoint**: `POST /api/v1/circuit/analyze`
**Purpose**: Analyze circuit complexity before proof generation
**Use Case**: Estimate proof generation time/cost

### 5. STARK Proof Status
**Endpoint**: `GET /api/v1/proof/status/{proofId}`
**Purpose**: Check status of async proof generation
**Use Case**: For long-running proof generation (when we fix the stack overflow)

### 6. Metrics/Statistics
**Endpoint**: `GET /api/v1/metrics`
**Purpose**: Service metrics (certificates generated, average proof time, etc.)
**Use Case**: Monitoring and debugging

### 7. Predicate Validation
**Endpoint**: `POST /api/v1/predicate/validate`
**Purpose**: Validate a predicate structure before certificate generation
**Use Case**: Client-side validation helper

### 8. Attribute Evaluation
**Endpoint**: `POST /api/v1/attribute/evaluate`
**Purpose**: Evaluate an attribute against a predicate (no proof generation)
**Use Case**: Quick compliance checking

## Implementation Priority

**High Priority:**
1. Batch certificate generation (useful for production)
2. Certificate listing/query (essential for marketplace)

**Medium Priority:**
3. Merkle root verification (useful for debugging)
4. Metrics endpoint (useful for monitoring)

**Low Priority:**
5. Circuit complexity analysis (nice to have)
6. Async proof status (when we fix stack overflow)
7. Predicate validation (can be done client-side)
8. Attribute evaluation (can be done client-side)

