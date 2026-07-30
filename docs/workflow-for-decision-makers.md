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

**Read this section before anything else in this document.**

The three steps described above are the *design*. None of them are implemented.
This project is an early prototype — a skeleton of type definitions and module
structure with the cryptography left as stubs.

### What does not work

- **Step 1 (Data Commitment) does not commit.** The hash function is the
  identity function, so the "Merkle root" is simply the input data concatenated
  together. Publishing it publishes the data. It hides nothing and binds
  nothing.
- **Step 2 (Proof Generation) proves nothing.** Every circuit in the repository
  returns a constant or echoes an input. The threshold comparison is never
  checked. The Merkle path is never checked. The proof attests to a statement
  that is true regardless of the data.
- **Step 3 (Verification) is not zero-knowledge.** The secret value is copied
  into the proof's public portion, so anyone verifying a certificate can read
  the number it was supposed to conceal.

### What this means in practice

A certificate produced by this system today is not evidence of anything. It
looks like an attestation, which makes it more dangerous than having no system
at all — a reader could reasonably mistake it for a real one.

### Other gaps

- **Does not build.** Seven modules and six of the eleven test targets have type
  errors. CI passed only because it did not build them.
- **No formal verification.** The repository contains zero theorems. "Verified
  in Lean 4" previously meant only that the code type-checks.
- **No performance data.** Published benchmark figures were withdrawn; they
  measured functions that return constants.
- **Hardware acceleration**: unavailable and never implemented.

See `REMEDIATION.md` for the tracked list of what would need to be built.

## Evaluation Criteria

### For Technical Teams
1. **Build Status**: do **not** read the CI badge as "code compiles and tests
   pass". The default build target covers six modules; the other seven are never
   compiled, and the test job ran with `continue-on-error: true`. A green badge
   has meant "the subset that compiles, compiles."
2. **Start with the circuit bodies.** Grep for `Aiur.Term.ret` in
   `ZkIpProtocol/`. Every match is a circuit that returns a constant or echoes
   an input. That single grep is the fastest way to confirm the state of the
   project.
3. **Test Coverage**: `Tests/Validation/` does not compile. Even once it does,
   the tests are vacuous — they assert properties of stub functions.

### For Business Teams
1. **Use Case Fit**: the underlying idea — proving an attribute meets a
   threshold without revealing it — is real and valuable. This implementation
   does not deliver it.
2. **Timeline**: treat this as a pre-implementation design sketch. Reaching a
   defensible first version means writing the cryptography from scratch; the
   existing type definitions and module layout are the reusable part.
3. **Security Posture**: not suitable for evaluation, pilot, or deployment. It
   has not been audited, and there is nothing to audit yet.

## Project Structure

```
zkip-stark/
├── ZkIpProtocol/          # Core protocol (Lean 4)
│   ├── STARKIntegration.lean  # Proof generation/verification
│   ├── MerkleCommitment.lean   # Merkle tree operations
│   ├── Advertisement.lean       # Certificate generation
│   └── NoCapFFI.lean           # Hardware interface (UNAVAILABLE)
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
- You want to read or extend an early design sketch of a selective-disclosure
  protocol in Lean 4, and you intend to implement the cryptography yourself

**No, if:**
- You need working zero-knowledge proofs. None exist here.
- You need a commitment scheme. The hash is the identity function.
- You need any performance guarantee. No valid measurement exists.
- You need something you can pilot, audit, or deploy.

There is currently no configuration of this repository suitable for production
use. Reaching one requires implementing the cryptography from scratch; see
`REMEDIATION.md`.

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
| Formal Verification | ❌ Not started | Zero theorems in the repository; Lean provides type checking only |
| Predicate circuit | ❌ Not implemented | Body is `ret attr` — echoes the input, checks no threshold |
| Zero-knowledge | ❌ Broken | Witness is published in the public claim |
| Merkle Commitments | ❌ Not implemented | Hash is the identity function; root is the plaintext |
| Batching | ❌ Not implemented | Circuit returns its first input; module excluded from build |
| Recursive Proofs | ❌ Not implemented | Verifier circuit returns `1` — accepts unconditionally |
| Hardware Acceleration | ❌ Unavailable | Both FFI branches call the same software stub |
| ZKMB application | ❌ Does not compile | Excluded from the default build target |
| API Service | ⚠️ Runs | Serves endpoints, but the certificates it issues are meaningless |
| Test suite | ❌ Does not compile | 6 of 11 targets have type errors |
| CI/CD | ⚠️ Misleading | Green badge; built only the subset that compiles |
