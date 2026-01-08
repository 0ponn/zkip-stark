#!/bin/bash
# Complete test runner - starts service and runs tests

PORT=${1:-8082}

echo "=== ZK-IP Protocol Test Runner ==="
echo "Port: $PORT"
echo ""

# Check if service is already running
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

if check_service; then
    echo "✓ Service already running on port $PORT"
    echo ""
else
    echo "Starting service on port $PORT..."
    echo "  (This will run in the background)"
    echo ""

    # Start service in background
    ./START_SERVICE.sh $PORT > /tmp/zkip_service_$PORT.log 2>&1 &
    SERVICE_PID=$!

    # Wait for service to start
    echo "Waiting for service to start..."
    for i in {1..10}; do
        sleep 1
        if check_service; then
            echo "✓ Service started (PID: $SERVICE_PID)"
            break
        fi
        if [ $i -eq 10 ]; then
            echo "✗ Service failed to start"
            echo "Check logs: /tmp/zkip_service_$PORT.log"
            kill $SERVICE_PID 2>/dev/null
            exit 1
        fi
    done
    echo ""
fi

# Run tests
echo "Running test suite..."
echo ""
./test_all.sh $PORT
TEST_RESULT=$?

# Cleanup: kill service if we started it
if [ -n "$SERVICE_PID" ]; then
    echo ""
    echo "Stopping service (PID: $SERVICE_PID)..."
    kill $SERVICE_PID 2>/dev/null
    sleep 1
    kill -9 $SERVICE_PID 2>/dev/null
fi

exit $TEST_RESULT

