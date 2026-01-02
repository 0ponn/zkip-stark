# Git Setup Instructions

Follow these steps to set up and push to GitHub:

## Step 1: Navigate to project directory
```bash
cd /home/mlayug/Documents/GitHub/zkp-projects/zk-ip-protocol
```

## Step 2: Initialize git (if not already done)
```bash
git init
```

## Step 3: Add remote repository
```bash
git remote add origin https://github.com/memmmmike/zkip-stark.git
```

If you get "remote origin already exists", update it with:
```bash
git remote set-url origin https://github.com/memmmmike/zkip-stark.git
```

## Step 4: Stage all files
```bash
git add .
```

## Step 5: Create initial commit
```bash
git commit -m "Initial commit: ZKIP-STARK - Zero-Knowledge IP Protocol with STARK Proofs

- Formally verified in Lean 4
- STARK proof integration (Ix/Aiur)
- Hardware acceleration ready (NoCap FFI)
- Recursive proofs and batching support
- Zero-Knowledge Middlebox (ZKMB) application
- Complete test suite"
```

## Step 6: Set branch to main
```bash
git branch -M main
```

## Step 7: Push to GitHub
```bash
git push -u origin main
```

**Note:** If you hit authentication errors:
- You may need to use a personal access token instead of password
- Or set up SSH keys: `git remote set-url origin git@github.com:memmmmike/zkip-stark.git`
- GitHub CLI: `gh auth login` then `git push -u origin main`

## Verify
After pushing, check your repository at:
https://github.com/memmmmike/zkip-stark

