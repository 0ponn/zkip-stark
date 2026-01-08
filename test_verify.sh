#!/bin/bash
# Test script for certificate verification endpoint

PORT=${1:-8082}
BASE_URL="http://localhost:$PORT"

echo "=== Certificate Verification Test ==="
echo "Testing service on port $PORT"
echo ""

# Check if service is running
check_service() {
    if command -v lsof >/dev/null 2>&1; then
        PID=$(lsof -Pi :$PORT -sTCP:LISTEN -t 2>/dev/null)
        if [ -n "$PID" ]; then
            return 0
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -q ":$PORT "; then
            return 0
        fi
    fi
    return 1
}

if ! check_service; then
    echo "✗ ERROR: No service running on port $PORT"
    echo ""
    echo "Please start the service first:"
    echo "  ./START_SERVICE.sh $PORT"
    echo ""
    exit 1
fi

echo "✓ Service detected on port $PORT"
echo ""

# Step 1: Generate a certificate first
echo "Step 1: Generating a certificate..."
GENERATE_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/certificate/generate" \
  -H "Content-Type: application/json" \
  -d '{
    "id": 1,
    "attributes": [
      {"type": "performance", "value": 100},
      {"type": "security", "value": 85}
    ],
    "predicate": {
      "threshold": 50,
      "operator": ">="
    },
    "privateAttribute": 100
  }')

# Extract certificate JSON (skip HTTP headers if present)
CERT_JSON=$(echo "$GENERATE_RESPONSE" | sed -n '/^{/,$p' | head -1)

if [ -z "$CERT_JSON" ] || echo "$CERT_JSON" | grep -q '"error"'; then
    echo "✗ Failed to generate certificate"
    echo "$GENERATE_RESPONSE"
    exit 1
fi

echo "✓ Certificate generated successfully"
echo ""

# Step 2: Extract certificate from response
CERT=$(echo "$CERT_JSON" | grep -o '"certificate":{[^}]*}' | sed 's/"certificate"://' || echo "$CERT_JSON" | jq -c '.certificate' 2>/dev/null)

if [ -z "$CERT" ]; then
    # Try to extract the full certificate object
    CERT=$(echo "$CERT_JSON" | jq -c '.certificate // .' 2>/dev/null)
fi

if [ -z "$CERT" ]; then
    echo "✗ Failed to extract certificate from response"
    echo "Response: $CERT_JSON"
    exit 1
fi

echo "Step 2: Verifying certificate..."
echo "Certificate to verify:"
echo "$CERT" | jq . 2>/dev/null || echo "$CERT"
echo ""

# Step 3: Verify the certificate
VERIFY_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/certificate/verify" \
  -H "Content-Type: application/json" \
  -d "$CERT")

# Extract JSON from response
VERIFY_JSON=$(echo "$VERIFY_RESPONSE" | sed -n '/^{/,$p' | head -1)

echo "Verification response:"
echo "$VERIFY_JSON" | jq . 2>/dev/null || echo "$VERIFY_JSON"
echo ""

# Check if verification succeeded
if echo "$VERIFY_JSON" | grep -q '"verified":\s*true'; then
    echo "✓ Certificate verification PASSED"
    exit 0
elif echo "$VERIFY_JSON" | grep -q '"verified":\s*false'; then
    echo "✗ Certificate verification FAILED (proof is invalid)"
    exit 1
else
    echo "? Verification response unclear"
    exit 1
fi

