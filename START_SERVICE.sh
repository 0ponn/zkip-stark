#!/bin/bash
# Start ZKIP-STARK API Service
# Checks if port is available and starts the service

PORT=${1:-8080}

# Check if port is in use
check_port() {
    if command -v lsof >/dev/null 2>&1; then
        PID=$(lsof -Pi :$PORT -sTCP:LISTEN -t 2>/dev/null)
        if [ -n "$PID" ]; then
            # Check if it's our service (socat or Main)
            CMD=$(ps -p $PID -o cmd= 2>/dev/null)
            if echo "$CMD" | grep -qE "(socat.*$PORT|Main|lake exe Main)"; then
                echo "Port $PORT is already in use by our service (PID: $PID)"
                echo "Killing existing service..."
                kill $PID 2>/dev/null
                sleep 1
                # Force kill if still running
                if kill -0 $PID 2>/dev/null; then
                    kill -9 $PID 2>/dev/null
                fi
                echo "Old service stopped. Starting new instance..."
                return 0
            else
                echo "Error: Port $PORT is already in use by another process (PID: $PID)"
                echo "Command: $CMD"
                echo "Please either:"
                echo "  1. Stop the process using port $PORT"
                echo "  2. Use a different port: ./START_SERVICE.sh 8081"
                return 1
            fi
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -q ":$PORT "; then
            # Try to get PID with ss
            PID=$(ss -tlnp | grep ":$PORT " | grep -oP 'pid=\K[0-9]+' | head -1)
            if [ -n "$PID" ]; then
                CMD=$(ps -p $PID -o cmd= 2>/dev/null)
                if echo "$CMD" | grep -qE "(socat.*$PORT|Main|lake exe Main)"; then
                    echo "Port $PORT is already in use by our service (PID: $PID)"
                    echo "Killing existing service..."
                    kill $PID 2>/dev/null
                    sleep 1
                    if kill -0 $PID 2>/dev/null; then
                        kill -9 $PID 2>/dev/null
                    fi
                    echo "Old service stopped. Starting new instance..."
                    return 0
                else
                    echo "Error: Port $PORT is already in use by another process (PID: $PID)"
                    echo "Command: $CMD"
                    echo "Please either:"
                    echo "  1. Stop the process using port $PORT"
                    echo "  2. Use a different port: ./START_SERVICE.sh 8081"
                    return 1
                fi
            else
                echo "Error: Port $PORT is already in use (could not determine PID)"
                echo "Please either:"
                echo "  1. Stop the service using port $PORT"
                echo "  2. Use a different port: ./START_SERVICE.sh 8081"
                return 1
            fi
        fi
    fi
    return 0
}

if ! check_port; then
    exit 1
fi

# Check if executable exists
EXE=".lake/build/bin/Main"
if [ ! -f "$EXE" ]; then
    echo "Executable not found. Building..."
    lake build Main || exit 1
fi

# Check if socat is available
if ! command -v socat >/dev/null 2>&1; then
    echo "Error: socat is not installed"
    echo "Install it with:"
    echo "  Fedora/RHEL: sudo dnf install socat"
    echo "  Ubuntu/Debian: sudo apt-get install socat"
    echo "  macOS: brew install socat"
    exit 1
fi

echo "Starting ZKIP-STARK API Service on port $PORT..."
echo "Endpoints:"
echo "  GET  http://localhost:$PORT/health"
echo "  GET  http://localhost:$PORT/ready"
echo "  POST http://localhost:$PORT/api/v1/certificate/generate"
echo "  POST http://localhost:$PORT/api/v1/certificate/verify"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Start the service
socat TCP-LISTEN:$PORT,fork,reuseaddr EXEC:"$EXE"

