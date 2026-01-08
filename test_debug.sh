#!/bin/bash
# Test the stack overflow debugging by making a certificate generation request
# Watch stderr for [DEBUG] messages

PORT=${1:-8081}

echo "=== Testing Stack Overflow Debugging ==="
echo ""
echo "Making certificate generation request to port $PORT..."
echo "Watch the service stderr for [DEBUG] messages showing:"
echo "  1. Minimal circuit test result"
echo "  2. Full circuit proof generation attempt"
echo ""
echo "Request:"
echo ""

curl -X POST http://localhost:$PORT/api/v1/certificate/generate \
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

echo ""
echo ""
echo "=== Check service stderr for [DEBUG] output ==="
echo "The debug messages will show:"
echo "  - Whether minimal circuit test passed/failed"
echo "  - Whether full circuit proof generation succeeded"
echo "  - Any stack overflow errors with context"

