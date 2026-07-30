# Architecture

> **Note:** this document describes the *intended* architecture. The
> cryptographic layers below are unimplemented stubs. See `REMEDIATION.md`.

ZKIP-STARK is designed around two pillars: **Soundness** and **Speed**. Neither
is load-bearing yet.

## Core Principles

### Soundness (not started)
The goal is machine-checked correctness in Lean 4. Today Lean provides type
checking only — the repository contains **zero** `theorem` or `lemma`
declarations. Two recursive functions carry `termination_by`. The absence of
`sorry` is not evidence of verification here, because no proofs are attempted.

### Speed (not measurable)
STARK proofs via Ix/Aiur, software-only; NoCap hardware unavailable. No
meaningful performance figure exists, because the circuits perform no work.

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
Core STARK proof generation and verification, integrating with Ix/Aiur.
**Status:** the `predicateCheck` circuit body is `ret attr` — it echoes its
input and enforces no predicate.

### MerkleCommitment.lean
Merkle tree construction. **Status:** provides no cryptographic binding.
`Hash.hash` on `ByteArray` is the identity function and `hashPair l r` is
`l ++ r`, so `buildMerkleTree` returns the concatenation of the plaintext
leaves.

### Batching.lean
Multiple attribute checks in a single proof. **Status:** circuit body is
`ret attr0`; not compiled by the default target.

### RecursiveProofs.lean
Verifier circuit for proof composition. **Status:** circuit body is `ret 1` —
it accepts unconditionally. Not compiled by the default target.

### ZKMB.lean
Zero-Knowledge Middlebox for TLS 1.3 compliance. **Status:** does not compile
(wrong `MerkleProof` fields, missing `STARKProof.vkId`, wrong `AiurSystem.build`
arity, references a `Batching` namespace that does not exist). Excluded from the
default build target.

### NoCapFFI.lean
Hardware acceleration interface. **Status:** unavailable. `HardwareCtx.create`
always returns `none`, and both branches of `poseidonHashFFI` call the same
software stub.

## Data Flow

1. **IP Metadata Creation**: User creates `Ixon` with attributes
2. **Merkle Commitment**: Attributes committed to Merkle tree
3. **Predicate Definition**: User defines `IPPredicate` to verify
4. **STARK Proof Generation**: Circuit compiled, proof generated
5. **Certificate Creation**: `ZKCertificate` created with proof
6. **Verification**: Certificate verified using STARK verifier

## Security Properties

**None of these hold.** Listed as design targets:

- **Ad-Switch Attack Resistance** — not achieved. Not "formally proven": no
  proof of this property exists anywhere in the repository.
- **Merkle Root Binding** — not achieved; the hash is the identity function.
- **Zero-knowledge** — not achieved; every argument passed to `AiurSystem.prove`
  lands in the public claim, including the "private" witness.
- **Termination Guarantees** — two recursive functions carry `termination_by`.
  This says nothing about cryptographic soundness.

