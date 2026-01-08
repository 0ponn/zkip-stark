#!/usr/bin/env bash
# Test script for certificate generation endpoint

PORT=${1:-8081}

echo "Testing certificate generation on port $PORT..."
echo ""

curl -X POST http://localhost:$PORT/api/v1/certificate/generate \
  -H "Content-Type: application/json" \
  -d '{
    "id": 1,
    "attributes": [
      {"type": "performance", "value": 100}
    ],
    "predicate": {
      "threshold": 50,
      "operator": ">="
    },
    "privateAttribute": 100
  }' | jq .

echo ""
echo "Done!"

