# Stack Overflow Fix

## Problem
The server was crashing with "Stack overflow detected. Aborting." when trying to generate STARK proofs using `AiurSystem.prove`.

## Root Cause
The `AiurSystem.prove` function in the Ix/Aiur system is causing infinite recursion or very deep recursion that exceeds the stack limit.

## Temporary Fix
I've disabled the actual STARK proof generation and replaced it with a mock proof. This allows the API to work while we debug the Aiur integration.

## Current Behavior
- Certificate generation now returns a mock STARK proof
- The mock proof includes the correct public inputs (Merkle root hash and threshold)
- The `vkId` is set to `"mock_vk_disabled"` to indicate it's not a real proof
- The API endpoint works and returns a valid certificate structure

## Next Steps
1. Debug the `AiurSystem.prove` call to identify why it's causing stack overflow
2. Check if the FRI parameters or circuit structure is causing issues
3. Consider using a simpler circuit or different FRI parameters
4. Once fixed, re-enable actual STARK proof generation

## Testing
The API should now work without crashing:
```bash
curl -X POST http://localhost:8081/api/v1/certificate/generate \
  -H "Content-Type: application/json" \
  -d '{
    "id": 1,
    "attributes": [{"type": "performance", "value": 100}],
    "predicate": {"threshold": 50, "operator": ">="},
    "privateAttribute": 100
  }'
```

You should get a response with a certificate containing a mock proof.

