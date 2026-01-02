#!/usr/bin/env bash
# Diagnostic script to identify build failures

set -e

cd "$(dirname "$0")"

echo "=== Build Diagnostic ==="
echo ""

echo "1. Checking toolchain..."
elan show || echo "  ⚠ elan show failed"
lean --version || echo "  ⚠ lean --version failed"
echo ""

echo "2. Checking project files..."
ls -la lean-toolchain .lean-toolchain 2>/dev/null || echo "  ⚠ Some toolchain files missing"
echo ""

echo "3. Checking Lake..."
lake --version || echo "  ⚠ lake --version failed"
echo ""

echo "4. Attempting to build core library..."
echo "   (This will show actual errors)"
echo ""
lake build ZkIpProtocol 2>&1 | tee /tmp/lake-build-errors.log || true
echo ""

echo "5. Checking for common issues..."
if grep -q "toolchain" /tmp/lake-build-errors.log 2>/dev/null; then
    echo "  ⚠ Toolchain-related errors found"
fi
if grep -q "unknown" /tmp/lake-build-errors.log 2>/dev/null; then
    echo "  ⚠ Unknown identifier errors found"
fi
if grep -q "type mismatch" /tmp/lake-build-errors.log 2>/dev/null; then
    echo "  ⚠ Type mismatch errors found"
fi
echo ""

echo "6. Full error log saved to: /tmp/lake-build-errors.log"
echo "   Review it for detailed error messages"
echo ""

echo "=== Diagnostic Complete ==="

