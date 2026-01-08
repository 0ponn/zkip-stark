#!/usr/bin/env bash
# Test the HTTP server with raw output to see what's actually being sent

PORT=${1:-8081}
EXECUTABLE="./.lake/build/bin/Main"

echo "Testing raw HTTP response on port $PORT..."
echo ""

# Start server in background
socat TCP-LISTEN:$PORT,fork,reuseaddr EXEC:"$EXECUTABLE $PORT" &
SERVER_PID=$!
sleep 1

# Test with netcat to see raw bytes
echo "=== Raw HTTP Response (hexdump) ==="
echo -e "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n" | nc localhost $PORT | hexdump -C | head -20

echo ""
echo "=== Raw HTTP Response (od -c) ==="
echo -e "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n" | nc localhost $PORT | od -c | head -20

echo ""
echo "=== Testing with curl (should show the actual error) ==="
curl -v http://localhost:$PORT/health 2>&1 | head -30

# Cleanup
kill $SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null

