#!/bin/bash
# Script to move the last commit to a new feature branch

set -e

BRANCH_NAME="feat/security-validation-multi-tool-integration"

echo "Creating feature branch: $BRANCH_NAME"
git checkout -b "$BRANCH_NAME"

echo ""
echo "✓ Created branch: $BRANCH_NAME"
echo ""
echo "If you already committed to main/master, run these commands:"
echo ""
echo "  1. Reset main to before your commit:"
echo "     git checkout main"
echo "     git reset --hard HEAD~1"
echo ""
echo "  2. Switch back to feature branch:"
echo "     git checkout $BRANCH_NAME"
echo ""
echo "  3. Push the branch:"
echo "     git push -u origin $BRANCH_NAME"
echo ""
echo "  4. Create a PR on GitHub to trigger CodeRabbit review"

