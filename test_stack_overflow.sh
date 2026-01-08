#!/bin/bash
# Test script to debug stack overflow with increased stack limits

echo "=== Stack Overflow Debug Test ==="
echo "Current stack limit:"
ulimit -s

echo ""
echo "Setting stack limit to unlimited..."
ulimit -s unlimited

echo "New stack limit:"
ulimit -s

echo ""
echo "Starting API service with increased stack limit..."
echo "Make a test request to trigger proof generation:"
echo ""
echo "curl -X POST http://localhost:8081/api/v1/certificate/generate \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{"
echo "    \"id\": 1,"
echo "    \"attributes\": ["
echo "      {\"type\": \"performance\", \"value\": 100}"
echo "    ],"
echo "    \"predicate\": {"
echo "      \"threshold\": 50,"
echo "      \"operator\": \">=\""
echo "    },"
echo "    \"privateAttribute\": 100"
echo "  }'"
echo ""
echo "Watch stderr for [DEBUG] messages showing:"
echo "  1. Minimal circuit test result"
echo "  2. Full circuit proof generation attempt"
echo "  3. Any stack overflow errors"

