#!/bin/bash
# Simple test script without jq dependency

PORT=${1:-8080}
BASE_URL="http://localhost:$PORT"

echo "=== ZK-IP Protocol Simple Test ==="
echo "Testing service on port $PORT"
echo ""

# Test 1: Health Check
echo "1. Health Check:"
echo "   curl $BASE_URL/health"
response=$(curl -s "$BASE_URL/health" 2>&1)
echo "   Response: $response"
echo ""

# Test 2: Single Certificate (raw output)
echo "2. Single Certificate Generation:"
echo "   curl -X POST $BASE_URL/api/v1/certificate/generate"
response=$(curl -s -X POST "$BASE_URL/api/v1/certificate/generate" \
  -H "Content-Type: application/json" \
  -d '{
    "id": 1,
    "attributes": [{"type": "performance", "value": 100}],
    "predicate": {"threshold": 50, "operator": ">="},
    "privateAttribute": 100
  }' 2>&1)
echo "   Response:"
echo "$response" | head -20
echo ""

# Check if response contains "success"
if echo "$response" | grep -q "success"; then
    echo "   ✓ Certificate generation appears successful"
else
    echo "   ✗ Certificate generation may have failed"
fi

echo ""
echo "=== Test Complete ==="
echo "If you see 'success: true' in the response, the service is working!"

