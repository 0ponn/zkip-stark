# ZKIP-STARK API Usage Guide

## Overview

The ZKIP-STARK API Service provides REST endpoints for generating and verifying Zero-Knowledge certificates for IP metadata.

## Endpoints

### Health Checks

#### GET /health
Check service health status.

**Response:**
```json
{
  "status": "healthy",
  "service": "zkip-stark",
  "version": "0.1.0"
}
```

#### GET /ready
Check if service is ready to handle requests.

**Response:**
```json
{
  "status": "ready"
}
```

### Certificate Generation

#### POST /api/v1/certificate/generate
Generate a Zero-Knowledge certificate proving IP attributes meet a predicate.

**Request Body:**
```json
{
  "id": 1,
  "attributes": [
    {
      "type": "performance",
      "value": 1500
    },
    {
      "type": "security",
      "value": 8
    }
  ],
  "merkleRoot": [0, 0, 0, 0],
  "timestamp": 1234567890,
  "predicate": {
    "threshold": 1000,
    "operator": ">="
  },
  "privateAttribute": 1500
}
```

**Response (Success):**
```json
{
  "success": true,
  "certificate": {
    "ipId": 1,
    "timestamp": 1234567890,
    "commitment": [0, 0, 0, 0],
    "predicate": {
      "threshold": 1000,
      "operator": ">="
    },
    "proof": {
      "vkId": "aiur_vk",
      "publicInputs": [[...]],
      "proofData": [...]
    }
  }
}
```

**Response (Error):**
```json
{
  "error": "Failed to generate certificate"
}
```

### Certificate Verification

#### POST /api/v1/certificate/verify
Verify a Zero-Knowledge certificate.

**Request Body:**
```json
{
  "certificate": {
    "ipId": 1,
    "commitment": [...],
    "predicate": {...},
    "proof": {...},
    "timestamp": 1234567890
  }
}
```

**Response:**
```json
{
  "success": true,
  "verified": true
}
```

## Example Usage

### Using curl

**Generate Certificate:**
```bash
curl -X POST http://localhost:8080/api/v1/certificate/generate \
  -H "Content-Type: application/json" \
  -d '{
    "id": 1,
    "attributes": [
      {"type": "performance", "value": 1500}
    ],
    "merkleRoot": [],
    "timestamp": 1234567890,
    "predicate": {
      "threshold": 1000,
      "operator": ">="
    },
    "privateAttribute": 1500
  }'
```

**Check Health:**
```bash
curl http://localhost:8080/health
```

### Using Python

```python
import requests

# Generate certificate
response = requests.post(
    "http://localhost:8080/api/v1/certificate/generate",
    json={
        "id": 1,
        "attributes": [
            {"type": "performance", "value": 1500}
        ],
        "merkleRoot": [],
        "timestamp": 1234567890,
        "predicate": {
            "threshold": 1000,
            "operator": ">="
        },
        "privateAttribute": 1500
    }
)
print(response.json())
```

## Running the Service

### Local Development

```bash
# Build
lake build Main

# Run (using socat for TCP)
socat TCP-LISTEN:8080,fork,reuseaddr EXEC:'lake exe Main'

# Or with netcat
nc -l 8080 | lake exe Main
```

### Docker

```bash
# Build image
docker build -t zkip-stark:latest .

# Run container
docker run -p 8080:8080 zkip-stark:latest
```

### Kubernetes (via Argo CD)

The service is automatically deployed via Argo CD when you push to the repository.

## Testing

### Test Health Endpoint
```bash
curl http://localhost:8080/health
```

### Test Certificate Generation
```bash
curl -X POST http://localhost:8080/api/v1/certificate/generate \
  -H "Content-Type: application/json" \
  -d @test-request.json
```

Where `test-request.json` contains:
```json
{
  "id": 1,
  "attributes": [{"type": "performance", "value": 1500}],
  "merkleRoot": [],
  "timestamp": 1234567890,
  "predicate": {"threshold": 1000, "operator": ">="},
  "privateAttribute": 1500
}
```

## Error Handling

The API returns appropriate HTTP status codes:
- `200 OK`: Success
- `400 Bad Request`: Invalid request format
- `404 Not Found`: Endpoint not found
- `500 Internal Server Error`: Server error

All errors include a JSON response with an `error` field describing the issue.

## Next Steps

1. **Add Authentication**: Implement API keys or OAuth
2. **Add Rate Limiting**: Prevent abuse
3. **Add Logging**: Track requests and errors
4. **Add Metrics**: Monitor performance
5. **Add Database**: Store certificates and metadata
6. **Add Batch Endpoint**: Use the batching functionality
7. **Add ZKMB Endpoint**: Expose Zero-Knowledge Middlebox features

