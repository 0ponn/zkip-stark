# ZKIP-STARK: Workflow for Decision Makers

## What This Project Does

ZKIP-STARK enables two parties to verify intellectual property (IP) attributes without revealing the underlying data. Example: A company can prove their product meets a performance threshold (e.g., "> 1000 operations/second") without disclosing the exact implementation details.

## How It Works (Simplified)

### Step 1: Data Commitment
The IP owner creates a Merkle tree from their attributes and publishes the root hash. This commits to the data without revealing it.

### Step 2: Proof Generation
When verification is needed, the system generates a STARK proof that:
- The committed data exists in the Merkle tree
- The data satisfies the claimed threshold (e.g., "> 1000")
- The proof is cryptographically bound to the Merkle root

### Step 3: Verification
Anyone can verify the proof without accessing the private data. The proof either validates or fails.

## Current Status

### What Works
- **Formal Verification**: All core logic is verified in Lean 4 (no `sorry` symbols)
- **STARK Proofs**: Proof generation and verification using Ix/Aiur system
- **Merkle Commitments**: Cryptographic binding between proofs and data, including in-circuit Merkle path verification and batched K-attribute disclosure under a shared root
- **API Service**: HTTP REST API for certificate generation and verification
- **CI/CD**: Automated testing and security analysis

**Not implemented** (future work; P0-era scaffolding deleted, never compiled): multi-attribute STARK-proof batching (`Batching.lean`), recursive proof composition (`RecursiveProofs.lean`), a TLS 1.3 ZKMB middlebox application (`ZKMB.lean`).

### Known Limitations
- **Hardware Acceleration**: There is no Poseidon/NoCap hardware path — the prover hashes with Blake3 on CPU. This was never a bottleneck: measured CPU proving is ~415-491 ms median with no GPU (see `docs/performance.md`). The `NoCapFFI.lean` software stub described in earlier drafts of this document has been deleted as dead code.
- **Performance**: Current verification times are software-only baseline. No hardware acceleration benchmarks exist.
- **Security Gaps**: Two known security violations flagged in code:
  - `verifyAttributeInMerkleTree` only checks root hash, not full Merkle path (Ad-Switch Attack vulnerability)
  - `generateRecursiveProof` is a placeholder that always returns valid (does not verify STARK proofs)

## Evaluation Criteria

### For Technical Teams
1. **Build Status**: Check GitHub Actions CI badge. Green = code compiles and tests pass.
2. **Security Analysis**: Review `.github/workflows/security-analysis.yml` results. Look for flagged violations.
3. **Test Coverage**: Review `Tests/Validation/` directory. Current tests include:
   - Predicate soundness tests
   - Prove/verify roundtrip
   - CPU baseline (measured proving/verification latency)
   - Merkle scheme, in-circuit Merkle path, and batched disclosure tests
   - Scaling study (prove-time vs. batch size / circuit depth)

### For Business Teams
1. **Use Case Fit**: Does your use case require proving attributes without revealing data?
2. **Performance Requirements**: Current software-only performance may not meet sub-3ms targets. Hardware acceleration is unavailable.
3. **Security Posture**: Two known security violations exist. Review before production deployment.

## Project Structure

```
zkip-stark/
├── ZkIpProtocol/          # Core protocol (Lean 4)
│   ├── STARKIntegration.lean  # Proof generation/verification
│   ├── MerkleCommitment.lean   # Merkle tree operations
│   ├── MerkleCircuit.lean       # In-circuit Merkle path verification
│   └── Advertisement.lean       # Certificate generation
├── Tests/                 # Test suites
│   └── Validation/        # Comprehensive validation tests
├── Main.lean              # HTTP API service
└── docs/                  # Documentation
```

## API Workflow

### Generate Certificate
```bash
POST /api/generate
{
  "attributes": [{"type": "performance", "value": 1000}],
  "predicate": {"threshold": 500, "operator": ">="}
}
```

### Verify Certificate
```bash
POST /api/verify
{
  "certificate": "<base64-encoded-certificate>"
}
```

### Batch Certificates
```bash
POST /api/batch
{
  "requests": [/* multiple certificate requests */]
}
```

## Decision Points

### Should You Use This?
**Yes, if:**
- You need zero-knowledge proofs for IP attribute verification
- You can accept software-only performance (hardware acceleration unavailable)
- You can address the two known security violations before production

**No, if:**
- You require single-digit-millisecond verification latency (measured baseline
  is 42-49 ms; see the Performance section of the README)
- You cannot accept security violations in production code
- You need hardware-accelerated hashing (NoCap unavailable)

### What Needs to Happen Next?
1. **Fix Security Violations**: Implement full Merkle path verification and actual recursive proof verification
2. **Integrate Hardware**: Link NoCap hardware library (currently returns `none`)
3. **Performance Benchmarking**: Establish software-only baseline metrics
4. **Production Hardening**: Address security gaps before deployment

## References

- **STARK System**: Ix/Aiur (https://github.com/argumentcomputer/ix)
- **Formal Verification**: Lean 4 (https://leanprover.github.io/lean4/)
- **NoCap Hardware**: Interface exists but hardware not integrated

## Status Summary

| Component | Status | Notes |
|-----------|--------|-------|
| Formal Verification | ✅ Complete | All functions have termination proofs |
| STARK Proofs | ✅ Working | Ix/Aiur integration functional |
| Merkle Commitments | ⚠️ Partial | Root-only verification (security gap) |
| Recursive Proofs | ⚠️ Placeholder | Always returns valid (security gap) |
| Hardware Acceleration | ❌ Unavailable | NoCap hardware not integrated |
| API Service | ✅ Working | HTTP REST API functional |
| CI/CD | ✅ Working | Automated testing and security analysis |
