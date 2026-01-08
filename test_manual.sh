#!/bin/bash
# Manual test - shows raw output for debugging

PORT=${1:-8082}

echo "=== Manual Batch Test ==="
echo "Port: $PORT"
echo ""
echo "Making request..."
echo ""

# Save response to file to inspect
curl -v -X POST http://localhost:$PORT/api/v1/certificates/batch \
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
  }' > /tmp/batch_response.txt 2>&1

echo "Response saved to /tmp/batch_response.txt"
echo ""
echo "First 500 characters:"
head -c 500 /tmp/batch_response.txt
echo ""
echo ""
echo "Last 500 characters:"
tail -c 500 /tmp/batch_response.txt
echo ""
echo ""
echo "Full response in: /tmp/batch_response.txt"
echo "View with: cat /tmp/batch_response.txt"

