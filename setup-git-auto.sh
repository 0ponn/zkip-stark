#!/usr/bin/env bash
# Automatically setup git repository and push to GitHub (non-interactive)

set -e  # Exit on error

# Change to script directory
cd "$(dirname "$0")"

REPO_URL="https://github.com/memmmmike/zkip-stark.git"

echo "=== Setting up git repository for zkip-stark ==="
echo ""

# Check if already a git repo
if [ -d .git ]; then
    echo "✓ Git repository already initialized"
else
    echo "→ Initializing git repository..."
    git init
    echo "✓ Git repository initialized"
fi

# Check if remote exists
if git remote get-url origin >/dev/null 2>&1; then
    CURRENT_URL=$(git remote get-url origin)
    if [ "$CURRENT_URL" != "$REPO_URL" ]; then
        echo "→ Updating remote URL from: $CURRENT_URL"
        git remote set-url origin "$REPO_URL"
        echo "✓ Remote updated"
    else
        echo "✓ Remote 'origin' already set correctly"
    fi
else
    echo "→ Adding remote 'origin'..."
    git remote add origin "$REPO_URL"
    echo "✓ Remote added"
fi

echo ""
echo "→ Staging all files..."
git add .
echo "✓ Files staged"

echo ""
# Check if there are changes to commit
if ! git diff --staged --quiet || [ -z "$(git log --oneline -1 2>/dev/null)" ]; then
    echo "→ Creating initial commit..."
    git commit -m "Initial commit: ZKIP-STARK - Zero-Knowledge IP Protocol with STARK Proofs

- Formally verified in Lean 4
- STARK proof integration (Ix/Aiur)
- Hardware acceleration ready (NoCap FFI)
- Recursive proofs and batching support
- Zero-Knowledge Middlebox (ZKMB) application
- Complete test suite"
    echo "✓ Commit created"
else
    echo "✓ No changes to commit (repository up to date)"
fi

echo ""
echo "→ Setting branch to 'main'..."
git branch -M main 2>/dev/null || echo "✓ Already on main branch"

echo ""
echo "=== Repository setup complete! ==="
echo ""
echo "To push to GitHub, run:"
echo "  git push -u origin main"
echo ""
echo "Repository URL: $REPO_URL"

