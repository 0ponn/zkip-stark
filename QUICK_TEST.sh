#!/bin/bash
# Quick test verification script

echo "=== Fixing Permissions ==="
chmod +x test_all.sh test_verify.sh
echo "✓ Scripts are now executable"
echo ""

echo "=== Testing Build ==="
# Get script directory and navigate to repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
if lake build Tests.ApiTests 2>&1 | grep -q "error"; then
    echo "✗ Build failed - check errors above"
    exit 1
else
    echo "✓ Tests.ApiTests build successful"
fi
echo ""

echo "=== Ready to Run ==="
echo "Run tests with:"
echo "  ./test_all.sh 8082"
echo "  ./test_verify.sh 8082"
echo "  lake exe Tests.ApiTests"

