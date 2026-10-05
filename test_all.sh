#!/bin/bash
# Comprehensive test script for ZK-IP Protocol API

PORT=${1:-8080}
BASE_URL="http://localhost:$PORT"
# The proving endpoints need the server's API key; verify and health do not.
AUTH=(-H "Authorization: Bearer ${ZKIP_API_KEY:?set ZKIP_API_KEY to the server key}")

echo "=== ZK-IP Protocol API Test Suite ==="
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
    echo "Or in another terminal:"
    echo "  socat TCP-LISTEN:$PORT,fork,reuseaddr EXEC:'lake exe Main'"
    echo ""
    exit 1
fi

echo "✓ Service detected on port $PORT"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Print at most 500 characters: a certificate carries ~18 MB of proof hex,
# and dumping it into the CI log stalled the job.
show() {
    local text="$1"
    if [ ${#text} -gt 500 ]; then echo "${text:0:500}... (${#text} chars)"; else echo "$text"; fi
}

test_endpoint() {
    local name=$1
    local method=$2
    local endpoint=$3
    local data=$4
    local expected_code=${5:-200}  # Default to 200, but allow override

    echo -n "Testing $name... "

    if [ -z "$data" ]; then
        response=$(curl -s --max-time 30 -w "\n%{http_code}" "${AUTH[@]}" -X $method "$BASE_URL$endpoint" 2>/dev/null)
    else
        response=$(curl -s --max-time 30 -w "\n%{http_code}" "${AUTH[@]}" -X $method "$BASE_URL$endpoint" \
            -H "Content-Type: application/json" \
            -d "$data" 2>/dev/null)
    fi

    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | head -n -1)

    local body_check=$6  # Optional jq filter the response body must satisfy
    if [ "$http_code" = "$expected_code" ] && \
       { [ -z "$body_check" ] || [ "$(echo "$body" | jq -r "$body_check" 2>/dev/null)" = "true" ]; }; then
        echo -e "${GREEN}✓ PASSED${NC}"
        show "$body"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAILED (HTTP $http_code, expected $expected_code${body_check:+, body check $body_check})${NC}"
        show "$body"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Test 1: Health Check
echo "1. Health Check"
test_endpoint "GET /health" "GET" "/health"
echo ""

# Test 2: Readiness Check
echo "2. Readiness Check"
test_endpoint "GET /ready" "GET" "/ready"
echo ""

# Test 3: Single Certificate Generation
echo "3. Single Certificate Generation"
SINGLE_CERT='{
  "id": 1,
  "attributes": [
    {"type": "performance", "value": 100},
    {"type": "security", "value": 85},
    {"type": "efficiency", "value": 90}
  ],
  "predicate": {
    "threshold": 50,
    "operator": ">"
  }
}'
test_endpoint "POST /api/v1/certificate/generate" "POST" "/api/v1/certificate/generate" "$SINGLE_CERT"
echo ""

# Test 4: Batch Certificate Generation (2 certificates)
echo "4. Batch Certificate Generation (2 certificates)"
BATCH_CERT='{
  "requests": [
    {
      "id": 1,
      "attributes": [
        {"type": "performance", "value": 100},
        {"type": "security", "value": 85}
      ],
      "predicate": {
        "threshold": 50,
        "operator": ">"
      }
    },
    {
      "id": 2,
      "attributes": [
        {"type": "performance", "value": 200},
        {"type": "efficiency", "value": 95}
      ],
      "predicate": {
        "threshold": 100,
        "operator": ">"
      }
    }
  ]
}'
test_endpoint "POST /api/v1/certificates/batch" "POST" "/api/v1/certificates/batch" "$BATCH_CERT" 200 '.failed == 0 and .succeeded == 2'
echo ""

# Test 5: Batch Certificate Generation (5 certificates - performance test)
# Skip in CI to avoid timeouts - this test can be slow
if [ -z "$CI" ]; then
  echo "5. Batch Certificate Generation (5 certificates - performance test)"
  BATCH_LARGE='{
    "requests": [
      {"id": 1, "attributes": [{"type": "performance", "value": 100}], "predicate": {"threshold": 50, "operator": ">"}},
      {"id": 2, "attributes": [{"type": "security", "value": 85}], "predicate": {"threshold": 40, "operator": ">"}},
      {"id": 3, "attributes": [{"type": "efficiency", "value": 90}], "predicate": {"threshold": 45, "operator": ">"}},
      {"id": 4, "attributes": [{"type": "performance", "value": 150}], "predicate": {"threshold": 75, "operator": ">"}},
      {"id": 5, "attributes": [{"type": "security", "value": 95}], "predicate": {"threshold": 50, "operator": ">"}}
    ]
  }'
  echo -n "Testing batch with 5 certificates... "
  start_time=$(date +%s%N)
  response=$(curl -s --max-time 60 -w "\n%{http_code}" "${AUTH[@]}" -X POST "$BASE_URL/api/v1/certificates/batch" \
      -H "Content-Type: application/json" \
      -d "$BATCH_LARGE" 2>/dev/null)
  end_time=$(date +%s%N)
  duration=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" = "200" ] && [ "$(echo "$body" | jq -r '.failed == 0' 2>/dev/null)" = "true" ]; then
      echo -e "${GREEN}✓ PASSED${NC} (${duration}ms)"
      echo "$body" | jq '.total, .succeeded, .failed' 2>/dev/null
      TESTS_PASSED=$((TESTS_PASSED + 1))
  else
      echo -e "${RED}✗ FAILED (HTTP $http_code)${NC}"
      show "$body"
      TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  echo ""
else
  echo "5. Batch Certificate Generation (5 certificates) - SKIPPED in CI (performance test)"
  echo ""
fi

# Test 6: Invalid Request (should return 400)
echo "6. Error Handling - Invalid Request"
test_endpoint "POST /api/v1/certificate/generate (invalid)" "POST" "/api/v1/certificate/generate" '{"invalid": "data"}' 400
echo ""

# Test 7: Certificate Verification (round-trip test)
echo "7. Certificate Verification (Round-Trip)"
echo -n "Generating certificate for verification... "
GEN_RESPONSE=$(curl -s --max-time 30 "${AUTH[@]}" -X POST "$BASE_URL/api/v1/certificate/generate" \
    -H "Content-Type: application/json" \
    -d '{
      "id": 999,
      "attributes": [{"type": "performance", "value": 100}],
      "predicate": {"threshold": 50, "operator": ">"}
    }' 2>/dev/null)

# Extract JSON body (skip HTTP headers if present, get full JSON)
# Try to get complete JSON - remove any trailing HTTP status codes
CERT_JSON=$(echo "$GEN_RESPONSE" | sed -n '/^{/,$p' | grep -v '^[0-9]\{3\}$' | tr -d '\n' | sed 's/[^}]*$//' | sed 's/^[^{]*{/{/')

# If jq can parse it, use jq to extract just the JSON part
if command -v jq >/dev/null 2>&1; then
    # Try to validate and extract JSON
    CERT_JSON_VALID=$(echo "$GEN_RESPONSE" | jq -c . 2>/dev/null)
    if [ -n "$CERT_JSON_VALID" ]; then
        CERT_JSON="$CERT_JSON_VALID"
    fi
fi

# Debug: show what we got
if [ -z "$CERT_JSON" ]; then
    echo -e "${RED}✗ FAILED${NC} (empty response)"
    echo "Raw response (first 500 chars): ${GEN_RESPONSE:0:500}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
elif echo "$CERT_JSON" | grep -q '"error"'; then
    echo -e "${RED}✗ FAILED${NC} (generation returned error)"
    show "$CERT_JSON"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    # Extract certificate object - the response should be {"success": true, "certificate": {...}}
    CERT=$(echo "$CERT_JSON" | jq -c '.certificate // empty' 2>/dev/null)

    # If that fails, try to get the whole response if it's already a certificate
    if [ -z "$CERT" ] || [ "$CERT" = "null" ] || [ "$CERT" = "empty" ]; then
        # Check if the response itself is a certificate (has ipId, commitment, proof)
        if echo "$CERT_JSON" | jq -e '.ipId' >/dev/null 2>&1; then
            CERT=$(echo "$CERT_JSON" | jq -c . 2>/dev/null)
        else
            echo -e "${RED}✗ FAILED${NC} (could not extract certificate)"
            echo "Response structure:"
            echo "$CERT_JSON" | jq 'keys' 2>/dev/null || echo "Not valid JSON or jq not available"
            echo "Full response (first 1000 chars):"
            echo "${CERT_JSON:0:1000}"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            CERT=""  # Set empty to skip verification
        fi
    fi

    if [ -n "$CERT" ] && [ "$CERT" != "null" ] && [ "$CERT" != "empty" ]; then
        echo -e "${GREEN}✓ Generated${NC}"
        echo -n "Verifying certificate... "

        # Write certificate to temp file to avoid "Argument list too long" error
        TEMP_CERT_FILE=$(mktemp)
        echo "$CERT" > "$TEMP_CERT_FILE"

        VERIFY_RESPONSE=$(curl -s --max-time 30 -w "\n%{http_code}" -X POST "$BASE_URL/api/v1/certificate/verify" \
            -H "Content-Type: application/json" \
            --data @"$TEMP_CERT_FILE" 2>&1)

        # Clean up temp file
        rm -f "$TEMP_CERT_FILE"

        HTTP_CODE=$(echo "$VERIFY_RESPONSE" | tail -1)
        BODY=$(echo "$VERIFY_RESPONSE" | head -n -1)

        # Debug: show response if HTTP code is empty
        if [ -z "$HTTP_CODE" ] || [ "$HTTP_CODE" = "" ]; then
            echo -e "${RED}✗ FAILED${NC} (empty HTTP code - endpoint may have crashed)"
            show "Response: $VERIFY_RESPONSE"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        elif [ "$HTTP_CODE" = "200" ]; then
            if echo "$BODY" | grep -q '"verified":\s*true'; then
                echo -e "${GREEN}✓ PASSED${NC}"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo -e "${RED}✗ FAILED${NC} (honest certificate did not verify)"
                show "$BODY"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi
        else
            echo -e "${RED}✗ FAILED (HTTP $HTTP_CODE)${NC}"
            show "$BODY"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    fi
fi
echo ""

# Test 8: Invalid Certificate Verification (should return 400)
echo "8. Error Handling - Invalid Certificate Format"
# Should return 400 for invalid certificate format
test_endpoint "POST /api/v1/certificate/verify (invalid)" "POST" "/api/v1/certificate/verify" '{"invalid": "certificate"}' 400
echo ""

# Test 9: Two disclosures in one certificate, verified by a separate process
echo "9. Multi-Disclosure Certificate (Round-Trip)"
echo -n "Generating and verifying a two-disclosure certificate... "
MULTI_FILE=$(mktemp)
curl -s --max-time 60 "${AUTH[@]}" -X POST "$BASE_URL/api/v1/certificate/generate" \
    -H "Content-Type: application/json" \
    -d '{
      "id": 42,
      "attributes": [{"type": "performance", "value": 1500}, {"type": "custom", "name": "uptime", "value": 99}],
      "disclosures": [
        {"attributeIndex": 0, "predicate": {"threshold": 1000, "operator": ">"}},
        {"attributeIndex": 1, "predicate": {"threshold": 95, "operator": ">"}}
      ]
    }' 2>/dev/null | jq -c '.certificate // empty' > "$MULTI_FILE"
if [ ! -s "$MULTI_FILE" ] || [ "$(jq '.disclosures | length' "$MULTI_FILE" 2>/dev/null)" != "2" ]; then
    echo -e "${RED}✗ FAILED${NC} (no two-disclosure certificate)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    MULTI_VERIFIED=$(curl -s --max-time 60 -X POST "$BASE_URL/api/v1/certificate/verify" \
        -H "Content-Type: application/json" --data @"$MULTI_FILE" 2>/dev/null | jq -r '.verified')
    if [ "$MULTI_VERIFIED" = "true" ]; then
        echo -e "${GREEN}✓ PASSED${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAILED${NC} (verified=$MULTI_VERIFIED)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
fi
rm -f "$MULTI_FILE"
echo ""

# Test 10: The proving endpoints refuse a missing or wrong key
echo "10. Authentication"
for case in "none" "wrong"; do
    echo -n "Testing generate with $case key... "
    if [ "$case" = "none" ]; then KEYARG=(); else KEYARG=(-H "Authorization: Bearer wrong-key-0123456789"); fi
    code=$(curl -s --max-time 30 -o /dev/null -w "%{http_code}" "${KEYARG[@]}" -X POST "$BASE_URL/api/v1/certificate/generate" \
        -H "Content-Type: application/json" -d "$SINGLE_CERT" 2>/dev/null)
    if [ "$code" = "401" ]; then
        echo -e "${GREEN}✓ PASSED${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAILED (HTTP $code, expected 401)${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done
echo ""

# Summary
echo "=== Test Summary ==="
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed! System is ready.${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed. Check the output above.${NC}"
    exit 1
fi

