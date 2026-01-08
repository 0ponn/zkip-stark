#!/bin/bash
# Test batch endpoint and extract JSON properly

PORT=${1:-8082}

echo "Testing batch endpoint on port $PORT..."
echo ""

# Test without jq first to see raw response
echo "Raw response (first 50 chars):"
curl -s -X POST http://localhost:$PORT/api/v1/certificates/batch \
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
  }' | head -c 200
echo ""
echo ""

# Try to extract JSON body (skip HTTP headers if present)
echo "Extracted JSON body:"
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

# Check if response starts with HTTP/1.1 (has headers)
if echo "$response" | grep -q "^HTTP/1.1"; then
    echo "Response includes HTTP headers, extracting JSON body..."
    # Extract everything after the first blank line
    echo "$response" | sed -n '/^$/,$p' | sed '1d'
else
    echo "$response"
fi

echo ""
echo ""

# Try with jq if JSON is valid
echo "Parsed with jq:"
if echo "$response" | grep -q "^HTTP/1.1"; then
    echo "$response" | sed -n '/^$/,$p' | sed '1d' | jq . 2>&1
else
    echo "$response" | jq . 2>&1
fi

