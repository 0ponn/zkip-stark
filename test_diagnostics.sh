#!/bin/bash
# Diagnostic script to identify which tests are failing

PORT=${1:-8082}
BASE_URL="http://localhost:$PORT"

echo "=== Test Diagnostics ==="
echo "Testing service on port $PORT"
echo ""

# Test each endpoint individually with verbose output
echo "1. Testing Health Check..."
curl -v "$BASE_URL/health" 2>&1 | grep -E "HTTP|status|healthy" | head -5
echo ""

echo "2. Testing Certificate Generation..."
GEN_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/certificate/generate" \
  -H "Content-Type: application/json" \
  -d '{
    "id": 999,
    "attributes": [{"type": "performance", "value": 100}],
    "predicate": {"threshold": 50, "operator": ">="},
    "privateAttribute": 100
  }')

echo "Response:"
echo "$GEN_RESPONSE" | jq . 2>/dev/null || echo "$GEN_RESPONSE"
echo ""

# Extract certificate if present
CERT=$(echo "$GEN_RESPONSE" | jq -c '.certificate // empty' 2>/dev/null)
if [ -n "$CERT" ] && [ "$CERT" != "null" ] && [ "$CERT" != "empty" ]; then
    echo "3. Testing Certificate Verification..."
    echo "Certificate extracted:"
    echo "$CERT" | jq . 2>/dev/null | head -10
    echo ""

    VERIFY_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/certificate/verify" \
      -H "Content-Type: application/json" \
      -d "$CERT")

    echo "Verification response:"
    echo "$VERIFY_RESPONSE" | jq . 2>/dev/null || echo "$VERIFY_RESPONSE"
else
    echo "3. Cannot test verification - certificate extraction failed"
    echo "Certificate value: '$CERT'"
fi
echo ""

echo "4. Testing Error Handling..."
ERROR_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/certificate/generate" \
  -H "Content-Type: application/json" \
  -d '{"invalid": "data"}')
echo "Error response:"
echo "$ERROR_RESPONSE" | jq . 2>/dev/null || echo "$ERROR_RESPONSE"
echo ""

echo "=== Diagnostics Complete ==="

