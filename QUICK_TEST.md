# Quick Test Guide

## Test if Everything is Working

### 1. Health Check (should work)
```bash
curl http://localhost:8082/health | jq .
```

### 2. Single Certificate (check for real STARK proof)
```bash
curl -X POST http://localhost:8082/api/v1/certificate/generate \
  -H "Content-Type: application/json" \
  -d '{
    "id": 1,
    "attributes": [{"type": "performance", "value": 100}],
    "predicate": {"threshold": 50, "operator": ">="},
    "privateAttribute": 100
  }' | sed -n '/^{/,$p' | jq '.certificate.proof.vkId'
```

**Expected:** `"aiur_vk"` (real proof) or `"mock_vk_*"` (mock proof)

### 3. Batch Certificates (extract JSON properly)
```bash
curl -s -X POST http://localhost:8082/api/v1/certificates/batch \
  -H "Content-Type: application/json" \
  -d '{
    "requests": [
      {
        "id": 1,
        "attributes": [{"type": "performance", "value": 100}],
        "predicate": {"threshold": 50, "operator": ">="},
        "privateAttribute": 100
      }
    ]
  }' | sed -n '/^{/,$p' | jq .
```

**Expected:** JSON with `"success": true`, `"total": 1`, `"succeeded": 1`

## Success Indicators

✅ **Health endpoint returns 200**
✅ **Single certificate has `vkId: "aiur_vk"`** (real STARK proof)
✅ **Batch endpoint returns valid JSON with statistics**
✅ **No stack overflow errors in server logs**

## If jq Fails

The `sed -n '/^{/,$p'` command extracts just the JSON body, skipping HTTP headers. This fixes the jq parse error.

## Debug Mode

To see what's happening:
```bash
DEBUG_ZK=true ./START_SERVICE.sh 8082
```

Then watch stderr for `[DEBUG]` messages.
