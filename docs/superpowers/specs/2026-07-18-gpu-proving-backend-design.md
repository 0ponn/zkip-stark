# GPU Proving Backend for zkip-stark

**Date:** 2026-07-18
**Status:** Design approved, pending spec review
**Target hardware:** NVIDIA GeForce RTX 4070 Ti SUPER (16 GB, compute capability 8.9, Ada Lovelace)

## Goal

Cut end-to-end STARK proving latency by moving the FRI-PCS hot spots (NTT, Merkle
hashing, later FRI folding) onto the GPU, via a backend that plugs into Plonky3's
trait seam. No rewrite of Aiur or the prover protocol. GPU touches performance
only, never the constraint system or soundness.

## Background: what this repo actually is

Ground truth established by reading the source, not the README:

- `zkip-stark` is a **Lean 4 application** on top of Argument Computer's Ix/Aiur.
- The proving stack is:
  ```
  zkip-stark (Lean app)
    -> ix / Aiur        (Lean+Rust: builds circuits, generates traces)
         -> multi-stark  (argumentcomputer Rust STARK prover, git rev-pinned)
              -> Plonky3: p3-dft (NTT), p3-fri (FRI), p3-merkle-tree, p3-poseidon2
  ```
- The **actual prover config** (`multi-stark/src/types.rs`):
  ```rust
  pub type Val = Goldilocks;
  pub type Dft = Radix2DitParallel<Val>;   // CPU NTT
  pub type Mmcs = MerkleTreeMmcs<Val, u8, SerializingHasher<Blake3>,
                                 Blake3CompressionFunction, 2, 32>;  // Blake3
  pub type Pcs = TwoAdicFriPcs<Val, Dft, Mmcs, ExtMmcs>;
  ```

### Two consequences that reframe the original problem

1. **The prover hashes with Blake3, not Poseidon.** The entire `NoCapFFI` /
   "Poseidon hardware acceleration UNAVAILABLE — CRITICAL PERFORMANCE BOTTLENECK"
   narrative plastered across the README/docs is **orthogonal to what the prover
   spends time on**. A GPU Poseidon would not have sped up proving. `NoCapFFI.lean`
   is a stub (`HardwareCtx.create` always returns `none`) and a red herring for
   proving performance.

2. **The app's own hash is a no-op.** `CoreTypes.lean`: `hash b := b` (identity).
   The application-layer Merkle commitment is therefore cryptographically void.
   This is a correctness defect independent of GPU work and must be fixed as part
   of establishing an honest baseline.

3. **The project has never been built locally** — no `.lake`, Ix not fetched,
   `nvcc` not installed (driver 610 present).

## Injection seam

`TwoAdicFriPcs` is generic over `Dft: TwoAdicSubgroupDft` and `Mmcs: Mmcs`. A GPU
backend is **new types implementing those Plonky3 traits with CUDA behind FFI**,
swapped into `multi-stark`'s type aliases. This is the same seam ICICLE-Stwo and
comparable projects use. "Fork the prover" therefore means "add a backend crate,"
not "rewrite the prover."

### Fork chain

Each layer gains exactly one redirect; nothing upstream is rewritten:

```
zkip-stark    -> lake dep points at memmmmike/ix fork
  ix          -> Cargo points multi-stark at memmmmike/multi-stark fork (or [patch])
    multi-stark -> new `gpu` cargo feature swaps Dft/Mmcs aliases to GPU impls
      p3-gpu (new crate) -> CUDA kernels via FFI
```

All forks under `memmmmike/`.

## Where the GPU helps (priority order)

1. **NTT / DFT** — `Radix2DitParallel<Goldilocks>` -> CUDA `TwoAdicSubgroupDft`.
   Biggest single win; LDE + coset DFTs dominate STARK proving.
2. **Merkle MMCS Blake3 tree-build** — `MerkleTreeMmcs` -> GPU Blake3 leaf hash +
   compression. FRI commits many matrices; second hot spot.
3. **FRI folding** — later, gated on 1–2 numbers. Interleaved with Fiat-Shamir,
   thinner win, more care required.

## Sizing decision: reuse-first (ICICLE)

The spec commits to a **reuse-first** bias. Phase 1 evaluates Ingonyama's ICICLE
Goldilocks NTT / MMCS as the GPU backend provider. Hand-written CUDA (sppark-style)
is the **fallback**, taken only if ICICLE genuinely does not fit the Plonky3 trait
shape. This is the difference between a weeks-scale and a months-scale project, and
P1 is the gate that confirms which one we are in. The spec does not assert ICICLE
drops in cleanly — P1 proves or disproves that against Plonky3 conformance tests.

## Phases

### P0 — Honest baseline (unavoidable, no GPU)
- Install CUDA toolkit (`nvcc`); driver already present. (System change — confirm
  before executing.)
- Fetch Ix, build `zkip-stark` + `ix` + `multi-stark` on CPU for the first time.
- Fix the identity hash in `CoreTypes.lean` so the app-layer Merkle commitment is a
  real cryptographic hash.
- Prove one certificate end-to-end on CPU; capture a real timing breakdown
  (flamegraph / `tracing` spans) showing where proving time goes (trace-gen vs
  NTT vs FRI vs Merkle).
- **Rewrite README/docs to reflect reality**: never-built status, placeholder hash
  now fixed, Blake3 (not Poseidon) prover, NoCap as a red herring for proving perf.
  Remove the "CRITICAL PERFORMANCE BOTTLENECK" theater.
- **Exit criterion:** a real, cited CPU proving-time baseline and truthful docs.

### P1 — Reuse spike
- Create `p3-gpu` crate skeleton.
- Evaluate ICICLE Goldilocks as DFT (and later MMCS) provider; decide reuse vs custom.
- **Deliverable:** a GPU NTT passing Plonky3's `TwoAdicSubgroupDft` conformance
  tests byte-for-byte against the `Radix2DitParallel` reference.
- **Exit criterion:** documented reuse/custom decision + passing GPU NTT.

### P2 — NTT backend
- Wire the GPU DFT into `multi-stark` behind a `gpu` cargo feature (CPU remains
  default).
- Prove the same certificate on GPU; assert the proof is byte-identical to the CPU
  proof and verifies under the unchanged CPU verifier.
- **Exit criterion:** GPU proof == CPU proof, with a measured NTT speedup number.

### P3 — Merkle / Blake3 GPU MMCS
- GPU Blake3 leaf + compression implementing `p3_commit::Mmcs`.
- Same conformance-then-benchmark discipline (MMCS root equality, full proof
  verifies).
- **Exit criterion:** GPU Merkle root == CPU root; end-to-end speedup number.

### P4 — FRI folding (optional)
- Gated on P2/P3 numbers justifying the added complexity.

## Correctness discipline

Every GPU component MUST produce output **byte-identical** to its CPU Plonky3
counterpart:
- DFT: conformance tests vs `Radix2DitParallel`.
- MMCS: identical Merkle roots vs `MerkleTreeMmcs`.
- End to end: full proof verifies under the **unchanged CPU verifier**.

GPU is an implementation swap, never a protocol change. This preserves the repo's
Lean-verified-soundness posture: the GPU touches performance, the constraint system
is untouched.

## Prerequisites and risks

- **CUDA toolkit not installed.** `nvcc` missing; driver 610.43.03 present. P0
  installs it — a real system change, confirmed before execution.
- **multi-stark is rev-pinned inside ix** (`rev = 2c019220...`). The fork chain (or
  a Cargo `[patch]`) is the override mechanism. Standard but fiddly.
- **Effort is real.** Even the reuse path is multi-week; from-scratch is longer.
  P0+P1 are the de-risking gate — no commitment to P2+ until the spike reports
  reuse vs custom.
- **compute capability 8.9 (Ada).** Modern; well supported by CUDA 12.x and ICICLE.

## Out of scope

- GPU Poseidon via `NoCapFFI` — does not touch the prover hot path (Blake3). The
  NoCap FFI stub may be removed or documented as vestigial during the P0 doc
  rewrite.
- Any change to the Aiur constraint system, DSL, or the protocol.
- SP1/Zisk zkVM backends (a different Ix proving path than the Aiur one this app
  uses).
