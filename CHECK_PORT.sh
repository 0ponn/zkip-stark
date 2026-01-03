#!/usr/bin/env bash
# Check if a port is available

PORT=${1:-8080}

echo "Checking port $PORT..."

# Try multiple methods to check port
if command -v lsof >/dev/null 2>&1; then
    if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo "✗ Port $PORT is IN USE"
        echo ""
        echo "Processes using port $PORT:"
        lsof -Pi :$PORT -sTCP:LISTEN
        exit 1
    else
        echo "✓ Port $PORT is AVAILABLE"
        exit 0
    fi
elif command -v ss >/dev/null 2>&1; then
    if ss -tuln | grep -q ":$PORT "; then
        echo "✗ Port $PORT is IN USE"
        echo ""
        echo "Connections on port $PORT:"
        ss -tuln | grep ":$PORT "
        exit 1
    else
        echo "✓ Port $PORT is AVAILABLE"
        exit 0
    fi
elif command -v netstat >/dev/null 2>&1; then
    if netstat -tuln 2>/dev/null | grep -q ":$PORT "; then
        echo "✗ Port $PORT is IN USE"
        echo ""
        echo "Connections on port $PORT:"
        netstat -tuln | grep ":$PORT "
        exit 1
    else
        echo "✓ Port $PORT is AVAILABLE"
        exit 0
    fi
else
    echo "Warning: No port checking tools available (lsof, ss, or netstat)"
    echo "Trying to connect to port $PORT..."
    if timeout 2 bash -c "echo > /dev/tcp/localhost/$PORT" 2>/dev/null; then
        echo "✗ Port $PORT appears to be IN USE (connection succeeded)"
        exit 1
    else
        echo "✓ Port $PORT appears to be AVAILABLE (connection failed as expected)"
        exit 0
    fi
fi

