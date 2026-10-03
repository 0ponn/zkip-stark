# ZKIP-STARK: Workflow for Decision Makers

## What This Project Does

ZKIP-STARK lets a company certify that a committed IP attribute meets a threshold (e.g., "> 1000 operations/second") with a certificate that carries the threshold and the commitment but not the attribute. The STARK proof inside the certificate is blinded (zero-knowledge in Plonky3's construction), so the proof bytes do not reveal the attribute through the opened trace values. Every proof has the same shape, so the proof bytes reveal nothing about the attribute or the size of the commitment. Certificates support up to 65,536 attributes.

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
1. **Use Case Fit**: The verifier learns that the committed attribute exceeds the threshold. The proof is blinded and fixed-shape (see `REMEDIATION.md` O3).
2. **Performance Requirements**: about 1.5 s to prove and 45 ms to verify per certificate on a desktop CPU with zero-knowledge blinding (`docs/performance.md`). GPU acceleration is parked.
3. **Security Posture**: research prototype; the open items are listed in `REMEDIATION.md`.

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
POST /api/v1/certificate/generate
{
  "id": 1,
  "attributes": [{"type": "performance", "value": 1000}, {"type": "security", "value": 8}],
  "predicate": {"threshold": 500, "operator": ">"},
  "attributeIndex": 0
}
```
The certificate proves `attributes[attributeIndex] > threshold` under the Merkle
root of all attributes, which is returned as `commitment`.
```

### Verify Certificate
```bash
POST /api/v1/certificate/verify
<the certificate JSON object returned by generate>
```

### Batch Certificates
```bash
POST /api/v1/certificates/batch
{
  "requests": [/* generate request bodies */]
}
```

## Decision Points

### Should You Use This?
**Yes, if:**
- You need a certificate that binds a threshold claim to a committed attribute without publishing the attribute
- Verifiers may hold the proof bytes (blinded; residual leak documented)
- You can accept about 1.5 s per proof on CPU

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
