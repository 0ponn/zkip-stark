#!/bin/bash
# Final verification of batch endpoint

PORT=${1:-8082}

echo "=== Batch Endpoint Verification ==="
echo ""

# Test single request
echo "1. Testing single certificate in batch..."
response=$(curl -s -X POST http://localhost:$PORT/api/v1/certificates/batch \
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
  }')

# Extract JSON (skip any HTTP headers)
json=$(echo "$response" | sed -n '/^{/,$p')

# Check key fields
echo "Response structure:"
echo "$json" | grep -o '"success":[^,}]*' && echo "  ✓ success field present"
echo "$json" | grep -o '"total":[^,}]*' && echo "  ✓ total field present"
echo "$json" | grep -o '"succeeded":[^,}]*' && echo "  ✓ succeeded field present"
echo "$json" | grep -o '"failed":[^,}]*' && echo "  ✓ failed field present"
echo "$json" | grep -q '"certificates"' && echo "  ✓ certificates array present"

echo ""
echo "2. Summary:"
if echo "$json" | grep -q '"success":\s*true'; then
    echo "  ✓ Batch endpoint is WORKING"
    total=$(echo "$json" | grep -o '"total":[0-9]*' | grep -o '[0-9]*')
    succeeded=$(echo "$json" | grep -o '"succeeded":[0-9]*' | grep -o '[0-9]*')
    echo "  ✓ Processed $total request(s), $succeeded succeeded"
else
    echo "  ✗ Batch endpoint returned error"
fi

echo ""
echo "3. Full JSON (first 1000 chars):"
echo "$json" | head -c 1000
echo "..."

