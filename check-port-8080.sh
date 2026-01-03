#!/usr/bin/env bash
# Simple port check for 8080

PORT=8080

if command -v ss >/dev/null 2>&1; then
    if ss -tuln 2>/dev/null | grep -q ":$PORT "; then
        echo "✗ Port $PORT is IN USE"
        ss -tuln | grep ":$PORT "
        exit 1
    else
        echo "✓ Port $PORT is AVAILABLE"
        exit 0
    fi
elif command -v lsof >/dev/null 2>&1; then
    if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo "✗ Port $PORT is IN USE"
        lsof -Pi :$PORT -sTCP:LISTEN
        exit 1
    else
        echo "✓ Port $PORT is AVAILABLE"
        exit 0
    fi
else
    echo "Checking port $PORT..."
    if timeout 1 bash -c "echo > /dev/tcp/localhost/$PORT" 2>/dev/null; then
        echo "✗ Port $PORT appears to be IN USE"
        exit 1
    else
        echo "✓ Port $PORT appears to be AVAILABLE"
        exit 0
    fi
fi

