# Architecture

ZKIP-STARK is a **research prototype** built on two pillars: **Soundness** and **Speed**. Only the core STARK proof path currently compiles and runs — see [Status](#status) at the bottom of this document.

## Core Principles

### Soundness
Lean 4 formal verification across the codebase. Recursive functions have verified termination proofs (no `sorry` symbols). The P0-era ZKMB (TLS 1.3 middlebox) scaffolding and other never-compiling modules described under [Status](#status) have been deleted from the repository.

### Speed
STARK proofs via **Ix/Aiur -> multi-stark -> Plonky3**, over the Goldilocks field, hashing with **Blake3**. CPU-only today; measured median proving is ~415-491 ms with verification at ~42-49 ms (see `docs/performance.md`). There was no hardware bottleneck to fix — the system had simply never been built or benchmarked before. GPU acceleration is planned as future work, at the Plonky3 `TwoAdicFriPcs` trait seam (NTT first) — see `docs/superpowers/specs/2026-07-18-gpu-proving-backend-design.md`.

## System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    User Application                      │
│    (HTTP REST API; ZKMB middlebox never implemented)      │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│              ZkIpProtocol API Layer                      │
│  (Advertisement, Disclosure, ABAC, Blake3 Merkle)        │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│           STARK Integration Layer                         │
│  (Proof Generation, Verification, In-Circuit Merkle)      │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│              Ix/Aiur STARK System                        │
│  (Circuit Compilation, Bytecode Generation)               │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│        multi-stark -> Plonky3 Proving Backend (CPU)      │
│  Goldilocks field, Blake3 MMCS (TwoAdicFriPcs)            │
│  Median proving ~415-491ms, verify ~42-49ms                │
└──────────────────────────────────────────────────────────┘
```

## Core Components

### STARKIntegration.lean
Core STARK proof generation and verification. Integrates with Ix/Aiur system.

### MerkleCommitment.lean
Merkle tree construction and verification. Provides cryptographic binding.

### MerkleCircuit.lean
In-circuit Merkle path verification (Blake3 leaf/node hashing as circuit constraints).

### Blake3Circuit.lean
Blake3 hashing as circuit constraints, used by `MerkleCircuit.lean`.

### Api.lean
HTTP REST API for certificate generation.

**Deleted, never implemented** (P0-era scaffolding that never compiled — see [Status](#status)): `ZKMB.lean` (Zero-Knowledge Middlebox for TLS 1.3 compliance verification), `Batching.lean` (STARK-proof batching), `RecursiveProofs.lean` / `FullRecursiveVerification.lean` / `FRIVerification.lean` / `HashConstraints.lean` / `MerkleReconstruction.lean` (recursive proof composition), `StringMatchOptimization.lean`, `AIOptimization.lean`, `IrohIntegration.lean`, and `NoCapFFI.lean` (vestigial hardware stub — the prover hashes with Blake3 internally via multi-stark, not through an FFI).

## Data Flow

1. **IP Metadata Creation**: User creates `Ixon` with attributes
2. **Merkle Commitment**: Attributes committed to Merkle tree
3. **Predicate Definition**: User defines `IPPredicate` to verify
4. **STARK Proof Generation**: Circuit compiled, proof generated
5. **Certificate Creation**: `ZKCertificate` created with proof
6. **Verification**: Certificate verified using STARK verifier

## Security Properties

- **Ad-Switch Attack Resistance (partial)**: the STARK proof binds the Merkle root as a public input, but the binding is weaker than "cryptographic" implies — see the caveat below.
- **Merkle Root Binding — caveat**: `ZkIpProtocol/Api.lean` reduces the Blake3 root to its first 8 bytes (big-endian) and packs that single `u64` into one Goldilocks field element as the public input. This is **~64-bit binding, not the full 256-bit Blake3 digest**. Recovering full-strength binding would mean spreading the digest across multiple field inputs — a protocol change, not yet done.
- **Termination Guarantees**: recursive functions have verified termination proofs.

## Status

The `ZkIpProtocol` library default target and all `lean_exe` targets in `lakefile.lean` compile and pass. The P0-era scaffolding for ZKMB (TLS 1.3 middlebox), string-matching optimization, AI-driven optimization, recursive proof composition, STARK-proof batching, and Iroh integration never compiled (fictional APIs / stale fields) and has been deleted from the repository — it is future work, not a shipped feature. See the root `README.md` for the full list of what was removed and what currently builds.

