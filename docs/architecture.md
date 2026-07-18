# Architecture

ZKIP-STARK is a **research prototype** built on two pillars: **Soundness** and **Speed**. Only the core STARK proof path currently compiles and runs — see [Status](#status) at the bottom of this document.

## Core Principles

### Soundness
Lean 4 formal verification for the parts of the codebase that compile. Recursive functions on that path have verified termination proofs (no `sorry` symbols); this has not been audited for the non-compiling modules (`ZKMB.lean` and most of `Tests/`).

### Speed
STARK proofs via **Ix/Aiur -> multi-stark -> Plonky3**, over the Goldilocks field, hashing with **Blake3**. CPU-only today; measured median proving is ~415-491 ms with verification at ~42-49 ms (see `docs/performance.md`). There was no hardware bottleneck to fix — the system had simply never been built or benchmarked before. GPU acceleration is planned as future work, at the Plonky3 `TwoAdicFriPcs` trait seam (NTT first) — see `docs/superpowers/specs/2026-07-18-gpu-proving-backend-design.md`.

## System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    User Application                      │
│         (HTTP REST API; ZKMB does not compile)           │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│              ZkIpProtocol API Layer                      │
│  (Advertisement, Disclosure, ABAC, Blake3 Merkle)        │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│           STARK Integration Layer                         │
│  (Proof Generation, Verification, Batching)             │
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

### Batching.lean
Multiple attribute checks in a single STARK proof for efficiency.

### RecursiveProofs.lean
Verifier circuit for proof composition, enabling infinite state transitions.

### ZKMB.lean
Zero-Knowledge Middlebox application for TLS 1.3 compliance verification. **Does not currently compile** — not part of the working system (see [Status](#status)).

### NoCapFFI.lean
Software-only stub (`HardwareCtx.create` always returns `none`). Not on the prover's hot path — the prover hashes with Blake3 internally via multi-stark, not through this FFI. Vestigial, slated for removal.

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
- **Termination Guarantees**: recursive functions in the compiling modules have verified termination proofs; this has not been audited across the non-compiling modules.

## Status

Only the core STARK proof path compiles and runs today: the `ZkIpProtocol` library default target, `Tests.STARKTests`, `Tests.Validation.CpuBaseline`, and `Tests.Validation.ProveVerifyRoundtrip`. `ZKMB.lean`, `StringMatchOptimization.lean`, `AIOptimization.lean`, and most of `Tests/` are non-compiling, pre-existing rot (fictional APIs / stale fields) and are not part of the working system. See the root `README.md` for the full list.

