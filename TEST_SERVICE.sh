#!/usr/bin/env bash
# Test script for the ZKIP-STARK service

PORT=${1:-8081}

echo "Testing ZKIP-STARK service on port $PORT..."
echo ""

# Test health endpoint
echo "1. Testing /health endpoint:"
curl -v http://localhost:$PORT/health 2>&1 | head -20
echo ""
echo ""

# Test ready endpoint
echo "2. Testing /ready endpoint:"
curl -v http://localhost:$PORT/ready 2>&1 | head -20
echo ""
echo ""

echo "If you see HTTP responses above, the service is working!"
echo "If curl hangs, the service may not be running or may have issues."

