# Architecture

ZKIP-STARK is built on two pillars: **Soundness** and **Speed**.

## Core Principles

### Soundness
Lean 4 formal verification ensures mathematical correctness. All recursive functions have verified termination proofs (no `sorry` symbols).

### Speed
STARK proofs (Ix/Aiur) for scalable transparent arguments. STATUS: Software-only proving. NoCap hardware UNAVAILABLE - CRITICAL PERFORMANCE BOTTLENECK.

## System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    User Application                      │
│              (ZKMB, IP Exchange, etc.)                   │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│              ZkIpProtocol API Layer                      │
│  (Advertisement, Disclosure, ABAC, Optimization)       │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│           STARK Integration Layer                         │
│  (Proof Generation, Verification, Batching)             │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│              Ix/Aiur STARK System                        │
│  (Circuit Compilation, Proof Generation)                 │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│           Software STARK Backend (Aiur)                  │
│  (Poseidon Hash via software fallback)                   │
│  STATUS: NoCap hardware UNAVAILABLE                        │
└──────────────────────────────────────────────────────────┘
```

## Core Components

### STARKIntegration.lean
Core STARK proof generation and verification. Integrates with Ix/Aiur system.

### MerkleCommitment.lean
Merkle tree construction and verification. Provides cryptographic binding.

### Batching.lean
Multiple attribute checks in a single STARK proof for efficiency.

### RecursiveProofs.lean
Verifier circuit for proof composition, enabling infinite state transitions.

### ZKMB.lean
Zero-Knowledge Middlebox application for TLS 1.3 compliance verification.

### NoCapFFI.lean
Hardware acceleration interface. STATUS: UNAVAILABLE - `HardwareCtx.create` returns `none`. All operations use software fallback.

## Data Flow

1. **IP Metadata Creation**: User creates `Ixon` with attributes
2. **Merkle Commitment**: Attributes committed to Merkle tree
3. **Predicate Definition**: User defines `IPPredicate` to verify
4. **STARK Proof Generation**: Circuit compiled, proof generated
5. **Certificate Creation**: `ZKCertificate` created with proof
6. **Verification**: Certificate verified using STARK verifier

## Security Properties

- **Ad-Switch Attack Resistance**: Formally proven binding between ZK proof and Merkle root
- **Merkle Root Binding**: Mathematical security anchor ensures committed data matches advertised claims
- **Termination Guarantees**: All recursive functions have verified termination proofs

