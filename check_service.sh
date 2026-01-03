#!/bin/bash
# Check if service is running on a port

PORT=${1:-8082}

echo "Checking if service is running on port $PORT..."

# Check if port is in use
if command -v lsof >/dev/null 2>&1; then
    PID=$(lsof -Pi :$PORT -sTCP:LISTEN -t 2>/dev/null)
    if [ -n "$PID" ]; then
        CMD=$(ps -p $PID -o cmd= 2>/dev/null)
        echo "✓ Service is running on port $PORT (PID: $PID)"
        echo "  Command: $CMD"
        return 0
    fi
elif command -v ss >/dev/null 2>&1; then
    if ss -tuln | grep -q ":$PORT "; then
        PID=$(ss -tlnp | grep ":$PORT " | grep -oP 'pid=\K[0-9]+' | head -1)
        if [ -n "$PID" ]; then
            CMD=$(ps -p $PID -o cmd= 2>/dev/null)
            echo "✓ Service is running on port $PORT (PID: $PID)"
            echo "  Command: $CMD"
            return 0
        fi
    fi
fi

echo "✗ No service running on port $PORT"
echo ""
echo "To start the service, run:"
echo "  ./START_SERVICE.sh $PORT"
echo ""
echo "Or manually:"
echo "  socat TCP-LISTEN:$PORT,fork,reuseaddr EXEC:'lake exe Main'"
return 1

