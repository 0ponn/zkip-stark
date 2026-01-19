# Architecture

CHAP (Commercial High Assurance Platform) is built on two pillars: **Soundness** and **Transparency**.

## Why STARKs Over SNARKs

For financial applications, we chose STARKs (via Ix/Aiur) over SNARKs for critical reasons:

| Property | STARKs (Aiur) | SNARKs (Groth16, etc.) |
|----------|---------------|------------------------|
| **Trusted Setup** | None required | Required (toxic waste) |
| **Quantum Resistance** | Post-quantum secure | Vulnerable to quantum |
| **Proof Size** | Larger (~162 KB) | Smaller (~200 bytes) |
| **Verification** | Fast (~2ms) | Very fast (~1ms) |
| **Auditability** | Hash functions only | Trust ceremony participants |

### The Trusted Setup Problem

Many SNARK systems (Groth16, original PLONK) require a "trusted setup ceremony":
- Participants generate cryptographic parameters
- They must destroy their secret "toxic waste"
- If any participant keeps their secret, they can forge proofs

**For regulated finance, this is unacceptable.** You cannot tell auditors "trust that these people deleted their keys."

STARKs are **transparent**: security relies only on hash functions and public randomness.

### Note on Plonky2

Plonky2 (Polygon Zero) is labeled a "SNARK" but uses FRI for polynomial commitments, making it **transparent like STARKs**. We benchmarked against it and found it 20x faster, but chose Lean/Aiur for formal verification. See [performance.md](performance.md) for details.

## Why Lean 4 Over Rust

| Aspect | Lean 4 | Rust |
|--------|--------|------|
| **Formal Verification** | Built-in theorem prover | Requires external tools |
| **Correctness Proofs** | Mathematical guarantees | Testing only |
| **Proof Generation** | ~207ms | ~10ms |
| **Regulatory Story** | "Mathematically proven correct" | "Well-tested" |

For financing applications where trust and compliance matter more than milliseconds, **formal verification is our competitive moat**.

## Core Principles

### Soundness
Lean 4 formal verification ensures mathematical correctness. All recursive functions have verified termination proofs (no `sorry` symbols).

### Transparency
STARK proofs require no trusted setup. Verifiers trust only cryptographic hash functions.

## System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    User Application                      │
│         (Financing Eligibility, ZKMB, etc.)             │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│              ZkIpProtocol API Layer                      │
│  (Advertisement, Disclosure, ABAC, Optimization)        │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│           STARK Integration Layer                        │
│  (Proof Generation, Verification, Batching)             │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│              Ix/Aiur STARK System                        │
│  (Circuit Compilation, Goldilocks Field)                │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│           Software STARK Backend                         │
│  (Poseidon Hash, FRI Protocol)                          │
│  STATUS: NoCap hardware UNAVAILABLE                      │
└──────────────────────────────────────────────────────────┘
```

## Core Components

### STARKIntegration.lean
Core STARK proof generation and verification. Integrates with Ix/Aiur system using Goldilocks field (p = 2^64 - 2^32 + 1).

### MerkleCommitment.lean
Merkle tree construction and verification. Provides cryptographic binding between advertised claims and committed data.

### Batching.lean
Multiple attribute checks in a single STARK proof for efficiency.

### RecursiveProofs.lean
Verifier circuit for proof composition.

### HashConstraints.lean
Poseidon hash implemented as circuit constraints, optimized for potential NoCap hardware acceleration.

### NoCapFFI.lean
Hardware acceleration interface. STATUS: UNAVAILABLE - `HardwareCtx.create` returns `none`. All operations use software fallback.

## Data Flow

1. **Eligibility Request**: User submits financing eligibility check
2. **Merkle Commitment**: Financial attributes committed to Merkle tree
3. **Predicate Definition**: Define eligibility criteria (e.g., credit score >= 700)
4. **STARK Proof Generation**: Circuit compiled, proof generated (~207ms)
5. **Certificate Creation**: `ZKCertificate` created with proof
6. **Verification**: Certificate verified using STARK verifier (~2ms)

## Security Properties

- **No Trusted Setup**: Transparent proofs rely only on hash functions
- **Ad-Switch Attack Resistance**: ⚠️ PLACEHOLDER - `verifyFinancialDataMerkleSource` always returns `true`
- **Merkle Root Binding**: Root included in proof, but path verification NOT IMPLEMENTED
- **Termination Guarantees**: All recursive functions have verified termination proofs
- **Post-Quantum Security**: STARKs remain secure against quantum computers

**SECURITY WARNING**: See `LenderCircuits.lean:207-213` for documented security violation.
