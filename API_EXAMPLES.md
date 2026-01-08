# API Usage Examples

## Health Check

```bash
curl http://localhost:8081/health
```

Expected response:
```json
{
  "status": "healthy",
  "service": "zkip-stark",
  "version": "0.1.0"
}
```

## Ready Check

```bash
curl http://localhost:8081/ready
```

Expected response:
```json
{
  "status": "ready"
}
```

## Generate Certificate

```bash
curl -X POST http://localhost:8081/api/v1/certificate/generate \
  -H "Content-Type: application/json" \
  -d '{
    "id": 1,
    "attributes": [
      {"type": "performance", "value": 100},
      {"type": "security", "value": 85},
      {"type": "efficiency", "value": 90}
    ],
    "predicate": {
      "threshold": 50,
      "operator": ">="
    },
    "privateAttribute": 100
  }'
```

### Request Fields

- `id` (number): Unique identifier for the IP object
- `attributes` (array): Array of attribute objects
  - `type` (string): One of "performance", "security", "efficiency", or "custom"
  - `value` (number): Numeric value for the attribute
  - `name` (string, optional): Required if type is "custom"
- `predicate` (object): Compliance predicate
  - `threshold` (number): Threshold value
  - `operator` (string): Comparison operator (">=" or ">")
- `privateAttribute` (number): Private attribute value for proof generation
- `merkleRoot` (string/array, optional): Pre-computed Merkle root (hex string or array of bytes)
- `timestamp` (number, optional): Timestamp (defaults to 0)

### Response

Success (200):
```json
{
  "success": true,
  "certificate": {
    "ipId": 1,
    "timestamp": 0,
    "commitment": [/* byte array */],
    "predicate": {
      "threshold": 50,
      "operator": ">="
    },
    "proof": {
      "vkId": "...",
      "publicInputs": [/* array of byte arrays */],
      "proofData": [/* byte array */]
    }
  }
}
```

Error (400/500):
```json
{
  "error": "Error message here"
}
```

## Verify Certificate

```bash
curl -X POST http://localhost:8081/api/v1/certificate/verify \
  -H "Content-Type: application/json" \
  -d '{
    "certificate": { /* certificate object */ }
  }'
```

**Note**: The verify endpoint is currently a placeholder and returns a success response. Full implementation is pending.

## Using the Test Script

```bash
# Test certificate generation
./test_certificate_generate.sh 8081
```

## Pretty Print with jq

If you have `jq` installed, pipe responses through it:

```bash
curl -X POST http://localhost:8081/api/v1/certificate/generate \
  -H "Content-Type: application/json" \
  -d '{...}' | jq .
```

