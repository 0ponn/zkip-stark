#!/usr/bin/env bash
# Setup git repository and push to GitHub

set -e  # Exit on error

# Change to script directory
cd "$(dirname "$0")"

REPO_URL="https://github.com/memmmmike/zkip-stark.git"

echo "Setting up git repository for zkip-stark..."
echo ""

# Check if already a git repo
if [ -d .git ]; then
    echo "Git repository already initialized."
else
    echo "Initializing git repository..."
    git init
fi

# Check if remote exists
if git remote get-url origin >/dev/null 2>&1; then
    CURRENT_URL=$(git remote get-url origin)
    if [ "$CURRENT_URL" != "$REPO_URL" ]; then
        echo "Remote 'origin' exists with different URL: $CURRENT_URL"
        echo "Updating to: $REPO_URL"
        git remote set-url origin "$REPO_URL"
    else
        echo "Remote 'origin' already set correctly."
    fi
else
    echo "Adding remote 'origin'..."
    git remote add origin "$REPO_URL"
fi

echo ""
echo "Staging all files..."
git add .

echo ""
echo "Checking for changes to commit..."
if git diff --staged --quiet; then
    echo "No changes to commit. Repository is up to date."
    if [ -z "$(git log --oneline -1 2>/dev/null)" ]; then
        echo "But no commits exist. Creating initial commit..."
        git commit -m "Initial commit: ZKIP-STARK - Zero-Knowledge IP Protocol with STARK Proofs

- Formally verified in Lean 4
- STARK proof integration (Ix/Aiur)
- Hardware acceleration ready (NoCap FFI)
- Recursive proofs and batching support
- Zero-Knowledge Middlebox (ZKMB) application
- Complete test suite"
    fi
else
    echo "Creating commit..."
    git commit -m "Initial commit: ZKIP-STARK - Zero-Knowledge IP Protocol with STARK Proofs

- Formally verified in Lean 4
- STARK proof integration (Ix/Aiur)
- Hardware acceleration ready (NoCap FFI)
- Recursive proofs and batching support
- Zero-Knowledge Middlebox (ZKMB) application
- Complete test suite"
fi

echo ""
echo "Setting branch to 'main'..."
git branch -M main

echo ""
echo "Repository setup complete!"
echo ""
echo "To push to GitHub, run:"
echo "  git push -u origin main"
echo ""
echo "Or if you want to push now, this script can do it (requires authentication)."
read -p "Push to GitHub now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Pushing to GitHub..."
    git push -u origin main
    echo ""
    echo "Success! Repository pushed to: $REPO_URL"
else
    echo "Skipping push. Run 'git push -u origin main' when ready."
fi

