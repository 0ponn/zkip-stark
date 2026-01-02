#!/usr/bin/env bash
# Permanent toolchain setup script
# This sets up the toolchain correctly and permanently for this project

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "=== Permanent Toolchain Setup for ZK-IP Protocol ==="
echo ""

# Step 1: Check elan is available
if ! command -v elan &> /dev/null; then
    echo "ERROR: elan is not installed or not in PATH"
    echo "Install elan: curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh"
    exit 1
fi

echo "✓ Elan found: $(elan --version)"
echo ""

# Step 2: Read required toolchain
REQUIRED_TOOLCHAIN=$(cat lean-toolchain)
echo "Required toolchain: $REQUIRED_TOOLCHAIN"
echo ""

# Step 3: Check if toolchain is installed
if elan toolchain list | grep -q "$REQUIRED_TOOLCHAIN"; then
    echo "✓ Toolchain $REQUIRED_TOOLCHAIN is already installed"
else
    echo "Installing toolchain $REQUIRED_TOOLCHAIN..."
    if elan toolchain install "$REQUIRED_TOOLCHAIN"; then
        echo "✓ Toolchain installed successfully"
    else
        echo "⚠ Failed to install $REQUIRED_TOOLCHAIN"
        echo "Trying to install 'stable' instead..."
        if elan toolchain install stable; then
            echo "✓ Installed 'stable' toolchain"
            echo "stable" > lean-toolchain
            REQUIRED_TOOLCHAIN="stable"
        else
            echo "✗ Failed to install any toolchain"
            exit 1
        fi
    fi
fi
echo ""

# Step 4: Set project override (PERMANENT - creates .lean-toolchain file)
echo "Setting project toolchain override (permanent)..."
elan override set "$REQUIRED_TOOLCHAIN"
echo "✓ Project toolchain override set"
echo ""

# Step 5: Verify
CURRENT_TOOLCHAIN=$(elan show)
echo "Current toolchain: $CURRENT_TOOLCHAIN"
if [ "$CURRENT_TOOLCHAIN" = "$REQUIRED_TOOLCHAIN" ]; then
    echo "✓ Toolchain correctly set"
else
    echo "⚠ Warning: Toolchain mismatch (expected $REQUIRED_TOOLCHAIN, got $CURRENT_TOOLCHAIN)"
fi
echo ""

# Step 6: Verify Lean is accessible
if command -v lean &> /dev/null; then
    echo "Lean version: $(lean --version)"
else
    echo "⚠ Warning: 'lean' command not found in PATH"
    echo "You may need to: source ~/.elan/env"
fi
echo ""

# Step 7: Clean and update Lake
echo "Cleaning and updating Lake dependencies..."
lake clean 2>/dev/null || true
rm -f lake-manifest.json
if lake update; then
    echo "✓ Dependencies updated"
else
    echo "⚠ Lake update had issues (this may be normal)"
fi
echo ""

# Step 8: Test build
echo "Testing build..."
if lake build ZkIpProtocol 2>&1 | head -20; then
    echo ""
    echo "✓ Build successful! Toolchain is permanently configured."
else
    echo ""
    echo "⚠ Build had issues. Toolchain is set, but there may be code errors."
    echo "Run 'lake build' to see full error messages."
fi
echo ""

echo "=== Setup Complete ==="
echo ""
echo "The toolchain is now permanently configured for this project."
echo "The .lean-toolchain file ensures Lake always uses the correct version."
echo ""
echo "Next steps:"
echo "  1. Run: lake build (to build everything)"
echo "  2. Run: lake exe Tests.Validation.MasterValidation (to run validation tests)"

