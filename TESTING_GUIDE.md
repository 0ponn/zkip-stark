# ZK-IP Protocol Testing Guide

## Quick Start

### 1. Start the Service

```bash
cd /home/mlayug/Documents/GitHub/zkp-projects/zk-ip-protocol

# Option A: Default port 8080
./START_SERVICE.sh 8080

# Option B: Different port (if 8080 is in use)
./START_SERVICE.sh 8081
```

### 2. Run Comprehensive Tests

```bash
# Test on default port 8080
./test_all.sh 8080

# Or test on port 8081
./test_all.sh 8081
```

## Manual Testing

### Health Check
```bash
curl http://localhost:8080/health | jq .
```

Expected response:
```json
{
  "status": "healthy",
  "service": "zkip-stark",
  "version": "0.1.0"
}
```

### Single Certificate Generation
```bash
curl -X POST http://localhost:8080/api/v1/certificate/generate \
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
  }' | jq .
```

Expected: Certificate with real STARK proof (not mock)

### Batch Certificate Generation
```bash
curl -X POST http://localhost:8080/api/v1/certificates/batch \
  -H "Content-Type: application/json" \
  -d '{
    "requests": [
      {
        "id": 1,
        "attributes": [{"type": "performance", "value": 100}],
        "predicate": {"threshold": 50, "operator": ">="},
        "privateAttribute": 100
      },
      {
        "id": 2,
        "attributes": [{"type": "security", "value": 85}],
        "predicate": {"threshold": 40, "operator": ">="},
        "privateAttribute": 85
      }
    ]
  }' | jq .
```

Expected: Array of certificates with statistics

## Debug Mode Testing

Enable debug logging to see detailed STARK proof generation:

```bash
DEBUG_ZK=true ./START_SERVICE.sh 8080
```

Then make a request and watch stderr for `[DEBUG]` messages showing:
- Circuit compilation
- FRI parameters
- Proof generation status

## Performance Testing

### Test Batch Performance
```bash
# Time a batch of 10 certificates
time curl -X POST http://localhost:8080/api/v1/certificates/batch \
  -H "Content-Type: application/json" \
  -d '{
    "requests": [
      {"id": 1, "attributes": [{"type": "performance", "value": 100}], "predicate": {"threshold": 50, "operator": ">="}, "privateAttribute": 100},
      {"id": 2, "attributes": [{"type": "security", "value": 85}], "predicate": {"threshold": 40, "operator": ">="}, "privateAttribute": 85},
      {"id": 3, "attributes": [{"type": "efficiency", "value": 90}], "predicate": {"threshold": 45, "operator": ">="}, "privateAttribute": 90},
      {"id": 4, "attributes": [{"type": "performance", "value": 150}], "predicate": {"threshold": 75, "operator": ">="}, "privateAttribute": 150},
      {"id": 5, "attributes": [{"type": "security", "value": 95}], "predicate": {"threshold": 50, "operator": ">="}, "privateAttribute": 95},
      {"id": 6, "attributes": [{"type": "efficiency", "value": 80}], "predicate": {"threshold": 40, "operator": ">="}, "privateAttribute": 80},
      {"id": 7, "attributes": [{"type": "performance", "value": 120}], "predicate": {"threshold": 60, "operator": ">="}, "privateAttribute": 120},
      {"id": 8, "attributes": [{"type": "security", "value": 75}], "predicate": {"threshold": 35, "operator": ">="}, "privateAttribute": 75},
      {"id": 9, "attributes": [{"type": "efficiency", "value": 95}], "predicate": {"threshold": 50, "operator": ">="}, "privateAttribute": 95},
      {"id": 10, "attributes": [{"type": "performance", "value": 110}], "predicate": {"threshold": 55, "operator": ">="}, "privateAttribute": 110}
    ]
  }' | jq '.total, .succeeded, .failed'
```

## Verification Checklist

- [ ] Health endpoint returns 200
- [ ] Ready endpoint returns 200
- [ ] Single certificate generation succeeds
- [ ] Certificate contains real STARK proof (check `proof.vkId` is not "mock_vk_*")
- [ ] Batch endpoint processes multiple requests
- [ ] Batch endpoint returns correct statistics
- [ ] No stack overflow errors in server logs
- [ ] Debug mode works (when DEBUG_ZK=true)

## Troubleshooting

### Service won't start
- Check if port is in use: `lsof -i :8080`
- Kill existing process: `./KILL_PORT.sh 8080`
- Use different port: `./START_SERVICE.sh 8081`

### Certificates return mock proofs
- Check server logs for errors
- Verify STARK proof generation is working
- Enable debug mode: `DEBUG_ZK=true ./START_SERVICE.sh 8080`

### Build errors
- Rebuild: `lake build Main`
- Check for compilation errors
- Verify all dependencies are installed

## Success Criteria

✅ **System is ready when:**
1. All test endpoints return 200
2. Certificates contain real STARK proofs (not mocks)
3. Batch endpoint processes multiple certificates successfully
4. No stack overflow or crash errors
5. Debug logging works (optional)

