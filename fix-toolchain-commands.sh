#!/usr/bin/env bash
# Alternative: Run these commands directly instead of as a script

echo "=== ZK-IP Protocol: Toolchain Fix ==="
echo ""

# Step 1: Check current toolchain
echo "Step 1: Checking current Lean toolchain..."
REQUIRED_TOOLCHAIN=$(cat lean-toolchain)
echo "Required toolchain: $REQUIRED_TOOLCHAIN"

CURRENT_TOOLCHAIN=$(elan show 2>/dev/null || echo "none")
echo "Current toolchain: $CURRENT_TOOLCHAIN"
echo ""

# Step 2: Install required toolchain if needed
if [ "$CURRENT_TOOLCHAIN" != "$REQUIRED_TOOLCHAIN" ]; then
    echo "Step 2: Installing required toolchain..."
    elan toolchain install "$REQUIRED_TOOLCHAIN" || {
        echo "ERROR: Failed to install toolchain $REQUIRED_TOOLCHAIN"
        echo "Trying alternative: elan toolchain install stable"
        elan toolchain install stable
        elan override set stable
    }
    elan override set "$REQUIRED_TOOLCHAIN"
    echo "✓ Toolchain installed and set"
else
    echo "Step 2: Toolchain already correct"
fi
echo ""

# Step 3: Verify toolchain
echo "Step 3: Verifying toolchain..."
elan show
lean --version
echo ""

# Step 4: Clean and update
echo "Step 4: Cleaning and updating dependencies..."
lake clean 2>/dev/null || true
rm -f lake-manifest.json
lake update
echo ""

# Step 5: Try building core library first
echo "Step 5: Building core library..."
if lake build ZkIpProtocol; then
    echo "✓ Core library built successfully"
else
    echo "✗ Core library build failed"
    echo "Showing first 50 lines of error:"
    lake build ZkIpProtocol 2>&1 | head -50
    exit 1
fi
echo ""

echo "=== Summary ==="
echo "If core library built successfully, the toolchain is fixed."
echo ""
echo "Next steps:"
echo "  1. Run: lake build (to build everything)"
echo "  2. Run: lake exe Tests.Validation.MasterValidation (to run validation)"

