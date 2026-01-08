#!/bin/bash
# Kill process using a specific port

PORT=${1:-8080}

echo "Finding process using port $PORT..."

if command -v lsof >/dev/null 2>&1; then
    PID=$(lsof -ti :$PORT)
    if [ -n "$PID" ]; then
        echo "Found process $PID using port $PORT"
        echo "Killing process..."
        kill $PID
        sleep 1
        if kill -0 $PID 2>/dev/null; then
            echo "Process still running, force killing..."
            kill -9 $PID
        fi
        echo "Process killed"
    else
        echo "No process found using port $PORT"
    fi
elif command -v ss >/dev/null 2>&1; then
    PID=$(ss -tlnp | grep ":$PORT " | grep -oP 'pid=\K[0-9]+' | head -1)
    if [ -n "$PID" ]; then
        echo "Found process $PID using port $PORT"
        echo "Killing process..."
        kill $PID
        sleep 1
        if kill -0 $PID 2>/dev/null; then
            echo "Process still running, force killing..."
            kill -9 $PID
        fi
        echo "Process killed"
    else
        echo "No process found using port $PORT"
    fi
else
    echo "Error: Neither lsof nor ss is available"
    exit 1
fi

