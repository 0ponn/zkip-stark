#!/usr/bin/env bash
# Test build and show errors

# Change to script directory (works regardless of where script is called from)
cd "$(dirname "$0")"

echo "Building ZkIpProtocol.Disclosure..."
lake build ZkIpProtocol.Disclosure 2>&1

echo ""
echo "Exit code: $?"

