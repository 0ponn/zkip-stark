#!/bin/bash
# Test batch endpoint with proper JSON extraction

PORT=${1:-8082}

echo "Testing batch endpoint on port $PORT..."
echo ""

# Get raw response
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
  }' 2>&1)

# Check if response starts with HTTP (has headers)
if echo "$response" | head -1 | grep -q "^HTTP/1.1"; then
    echo "Response includes HTTP headers, extracting JSON..."
    # Find the first line that starts with { and extract from there
    json_body=$(echo "$response" | sed -n '/^{/,$p')
else
    json_body="$response"
fi

echo ""
echo "JSON Response:"
echo "$json_body"
echo ""

# Try to parse with jq if available
if command -v jq >/dev/null 2>&1; then
    echo "Parsed with jq:"
    echo "$json_body" | jq . 2>&1 || echo "jq parse failed - check JSON above"
else
    echo "jq not available - showing raw JSON above"
fi

echo ""
echo "Key fields:"
echo "$json_body" | grep -o '"success":[^,}]*' || echo "success field not found"
echo "$json_body" | grep -o '"total":[^,}]*' || echo "total field not found"
echo "$json_body" | grep -o '"succeeded":[^,}]*' || echo "succeeded field not found"

