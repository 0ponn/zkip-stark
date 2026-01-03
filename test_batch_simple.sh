#!/bin/bash
# Simple batch test without jq

PORT=${1:-8082}

echo "Testing batch endpoint (raw output):"
echo ""

curl -X POST http://localhost:$PORT/api/v1/certificates/batch \
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
  }'

echo ""
echo ""
echo "If you see JSON above, the endpoint is working!"
echo "If you see HTTP headers, that's normal - use: curl -s ... | tail -n +1"

