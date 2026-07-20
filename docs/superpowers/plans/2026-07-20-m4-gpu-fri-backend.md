# M4 — GPU FRI-first Proving Backend Implementation Plan

> **⏸️ PARKED (2026-07-20) — decision, not abandonment.** The GPU verdict is GO
> (proof is FRI-bound, 91% accelerable — see `2026-07-20-proof-phase-profile.md`),
> and this plan + the ICICLE feasibility (`2026-07-20-icicle-fri-feasibility.md`)
> are execution-ready. Parked on ROI: the win is ~470ms→~150ms (3×), but the cost
> is ~2–4 weeks writing two byte-exact GPU adapters from scratch (no drop-in
> ICICLE→Plonky3 backend exists), and nothing currently needs sub-150ms proofs
> (no production throughput / latency SLA). Resume when there's a real consumer
> (throughput demand, much larger circuits, or a deliberate time investment).
>
> **Environment state (done, ready):** CUDA 13.3 toolkit + gcc15 host compiler
> installed; RTX 4070 Ti SUPER (sm_89) runs device code cleanly (no unsafe
> override); driver 610 untouched.
>
> **Toolchain finding for whoever resumes:** ICICLE does NOT build cleanly on
> Fedora 44's native toolchain (gcc16 / CUDA 13.3) — it targets an older matrix.
> One C++ conformance bug already hit (`returning_value_program.h`, missing
> `this->` on a base-template call; patched in the throwaway clone). The CUDA
> backend is a further pull+compile that may surface more. **Recommended on
> resume: pinned CUDA 12.x + gcc ≤13 alongside the current install** (they
> coexist, versioned) so ICICLE builds against its supported versions natively —
> avoids both the container's Lean-integration complexity and native
> bleeding-edge patch whack-a-mole.



> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Cut proof time from ~470 ms toward ~150–200 ms by moving the profiled hot path onto the RTX 4070 Ti SUPER — implement GPU adapters for the two Plonky3 traits (`Mmcs`, `TwoAdicSubgroupDft`) that `multi-stark`'s `TwoAdicFriPcs` routes all FRI hashing and LDE through, byte-exact so the unchanged CPU verifier still accepts every proof.

**Why this shape (measured, not assumed):** phase profile `2026-07-20-proof-phase-profile.md` — 79% is `stark/fri_open` (query-phase Blake3 Merkle openings + FRI folding), 91% GPU-accelerable. Spike `2026-07-20-icicle-fri-feasibility.md` — Plonky3 routes ALL FRI Merkle hashing through `p3_commit::Mmcs` and all LDE through `TwoAdicSubgroupDft`, so a GPU trait-swap reaches the 79% without patching `p3-fri`; ICICLE ships GPU Blake3 + hasher-agnostic Merkle + Goldilocks field/FRI.

**Architecture:** Fork chain `multi-stark → ix → zkip-stark`, all under `memmmmike/`. A new `p3-icicle` adapter crate implements the two traits via ICICLE (CUDA). `multi-stark` gains a `gpu` cargo feature that swaps its `Dft`/`Mmcs` type aliases to the GPU adapters; CPU remains default. **Conformance-first**: every GPU output must be byte-identical to its CPU Plonky3 counterpart; the GPU never changes the protocol or proof format.

**Tech Stack:** Rust, ICICLE (CUDA ≥12.4, GPU Blake3 + Merkle + Goldilocks NTT/FRI), Plonky3 (`p3-commit` `Mmcs`, `p3-dft` `TwoAdicSubgroupDft`, `p3-fri` `TwoAdicFriPcs`), `multi-stark`, RTX 4070 Ti SUPER (sm_89).

## Global Constraints

- **Byte-exact or it doesn't ship.** A GPU `Mmcs` root / `Dft` output MUST equal the CPU Plonky3 counterpart bit-for-bit, and a GPU-generated proof MUST verify under the **unchanged CPU verifier**. The GPU is a performance swap, never a protocol/format change. This preserves the whole M1/M2 soundness posture.
- CPU path stays default; GPU is behind a `gpu` cargo feature. `--no-default-features` / no-CUDA machines still build and pass on CPU.
- Prereq: CUDA toolkit ≥12.4 (`nvcc`), CMake ≥3.18. Driver 610 stays untouched.
- Fork chain under `memmmmike/`; `multi-stark` pinned rev matches ix's Cargo.lock as the fork base.
- Every task benchmarks against the measured baseline (~470 ms end-to-end, `stark/fri_open` 79%).
- Branch `gpu-proving-backend` (or a stacked `m4-gpu` branch off it).

## Phasing (FRI-first — highest value + highest risk first)

The Mmcs adapter is BOTH the 79% of the time AND the hardest (byte-exact Blake3 Merkle, GPU-resident across 100 opens), so it goes first. The Dft is smaller (~12%) and easier.

---

### Task 1: Fork + `p3-icicle` crate skeleton + `gpu` feature seam (no kernels yet)

**Files:**
- Fork `argumentcomputer/multi-stark` → `memmmmike/multi-stark`; add `[features] gpu = [...]` and a `types_gpu.rs` selecting GPU `Dft`/`Mmcs` aliases behind `#[cfg(feature="gpu")]` (mirror `src/types.rs`).
- New crate `p3-icicle` (in the multi-stark fork workspace or standalone): declares `struct IcicleDft;` and `struct IcicleMmcs;` with the trait impls `todo!()`-stubbed but type-correct, depends on `icicle-*` crates + the same `p3-*` versions as multi-stark.

**Interfaces:**
- Produces: a `gpu`-featured `multi-stark` that compiles (with CUDA present) and, when the GPU types are still stubs, is not yet used at runtime; CPU default unchanged.

- [ ] **Step 1:** Fork multi-stark; confirm CPU build + its existing tests pass unchanged (`cargo test`).
- [ ] **Step 2:** Add the `p3-icicle` crate with `icicle-runtime`/`icicle-core`/`icicle-babybear`-style deps pinned to a version that has Goldilocks + Blake3 Merkle (from the spike: field v3.7+, FRI v3.8+); `struct IcicleDft`/`IcicleMmcs` implementing `TwoAdicSubgroupDft<Goldilocks>` / `Mmcs<Goldilocks>` with `todo!()` bodies but exact associated types matching `Radix2DitParallel` / `MerkleTreeMmcs<Val,u8,SerializingHasher<Blake3>,Blake3Compress,2,32>`.
- [ ] **Step 3:** Add `gpu` feature + `types_gpu.rs`; `cargo build --features gpu` succeeds (CUDA present); `cargo build` (default) unchanged.
- [ ] **Step 4: Commit** `feat(gpu): fork multi-stark, add p3-icicle skeleton + gpu feature seam`.

---

### Task 2: GPU Blake3 `Mmcs` adapter — byte-exact (the 79%)

The load-bearing task. Implement `IcicleMmcs` so a GPU-built Merkle tree over trace columns is BIT-IDENTICAL to Plonky3's `MerkleTreeMmcs<…Blake3…,2,32>` — same leaf packing, same digest layout, same compression, same root — so the CPU verifier accepts it.

**Files:** `p3-icicle/src/mmcs.rs`, `p3-icicle/tests/mmcs_conformance.rs`

**Interfaces:**
- Consumes: ICICLE GPU Blake3 + Merkle API.
- Produces: `impl Mmcs<Goldilocks> for IcicleMmcs` (`commit_matrix`/`open_batch`/`verify_batch` compatible), with roots/openings byte-identical to `MerkleTreeMmcs`.

- [ ] **Step 1: Conformance test FIRST.** For random Goldilocks matrices of representative shapes (widths ~4400, heights 2^11–2^16, matching our trace), compute the Merkle root + a batch opening with BOTH `p3_merkle_tree::MerkleTreeMmcs<…Blake3…,2,32>` (CPU reference) and `IcicleMmcs` (GPU). Assert **byte-identical roots AND openings**.
- [ ] **Step 2: Run → FAIL** (`IcicleMmcs` is `todo!()`).
- [ ] **Step 3: Implement** `IcicleMmcs` with ICICLE GPU Blake3 Merkle. Nail the byte-exactness: Plonky3 packs field rows → bytes, hashes leaves with `SerializingHasher<Blake3>`, compresses pairs with `Blake3` at arity 2, digest 32 bytes. Reproduce that packing/hashing/compression order EXACTLY on GPU (this is the crux — study `p3-merkle-tree` + `p3-symmetric` for the exact byte layout).
- [ ] **Step 4: Run → PASS** (byte-identical). Cover odd heights, single-row, tall/thin matrices.
- [ ] **Step 5:** Keep the tree GPU-resident: `commit_matrix` returns a handle holding device memory so the ~100 `open_batch` query calls don't re-transfer. Verify no per-open host round-trip.
- [ ] **Step 6: Commit** `feat(gpu): byte-exact ICICLE Blake3 Mmcs adapter + conformance`.

---

### Task 3: GPU `TwoAdicSubgroupDft` adapter — byte-exact (~12%)

**Files:** `p3-icicle/src/dft.rs`, `p3-icicle/tests/dft_conformance.rs`

- [ ] **Step 1: Conformance test** — GPU DFT/coset-LDE output byte-identical to `Radix2DitParallel<Goldilocks>` for sizes 2^10–2^18, several batch widths.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** `IcicleDft` via ICICLE Goldilocks NTT (match twiddle/bit-reversal convention + coset shift to Plonky3's exactly).
- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit** `feat(gpu): byte-exact ICICLE Goldilocks Dft adapter + conformance`.

---

### Task 4: Wire into `multi-stark`, prove GPU, verify under CPU verifier, benchmark

**Files:** `multi-stark` fork `types_gpu.rs`; a `multi-stark` bench.

- [ ] **Step 1:** Point `types_gpu.rs`'s `Pcs = TwoAdicFriPcs<Val, IcicleDft, IcicleMmcs, ...>`; build `--features gpu`.
- [ ] **Step 2: Cross-verifier test** — prove a representative circuit (our `merkle_predicate` trace, exported as fixtures) with `--features gpu`; assert the proof **verifies under the unchanged CPU verifier** (byte-identical proof to the CPU-generated one is the strong form; verifier-accepts is the required form).
- [ ] **Step 3: Benchmark** GPU vs CPU: end-to-end prove time + the `stark/fri_open` span. Record the speedup and the new proof time. Target: FRI phase 3–5× → end-to-end ~150–200 ms.
- [ ] **Step 4: Commit** `feat(gpu): wire ICICLE Dft+Mmcs into multi-stark FriPcs; GPU proof verifies on CPU + benchmark`.

---

### Task 5: Fork-chain up to Lean; end-to-end GPU proof from zkip-stark

**Files:** `ix` fork Cargo (`multi-stark` → `memmmmike/multi-stark`, gpu feature); `zkip-stark` lakefile → `memmmmike/ix`.

- [ ] **Step 1:** Fork ix; point its `multi-stark` dep at the fork with `gpu` on (feature-gated so CPU CI still works).
- [ ] **Step 2:** Point this repo's lake `ix` dep at the ix fork; rebuild.
- [ ] **Step 3: End-to-end** — `Tests/Validation/ProofPhaseProfile` (or a GPU baseline harness) proves `merkle_predicate` through the GPU backend from Lean; assert it still verifies; record the end-to-end wall-clock vs the 475 ms CPU baseline.
- [ ] **Step 4: Commit** `feat(gpu): fork-chain GPU backend to Lean; end-to-end GPU proof + final number`.

---

## Self-Review

- **Coverage:** the profiled 79% (FRI Merkle openings) → Task 2 (GPU Blake3 Mmcs, byte-exact, GPU-resident). LDE ~12% → Task 3 (GPU Dft). Integration + verify-under-CPU + benchmark → Task 4. Fork-chain to Lean + final number → Task 5. Feature-gating keeps CPU default (Global Constraints).
- **Risk ordering:** hardest/highest-value first (Mmcs byte-exactness + GPU residency). If Task 2 can't hit byte-exact, that's a BLOCKED escalation (options: match Plonky3's exact Blake3 layout, or — larger — switch multi-stark's MMCS hash to one ICICLE reproduces trivially, which changes the commitment scheme but not our circuits/soundness). Surface, don't paper over.
- **Placeholders:** exact ICICLE API calls are filled during implementation against the pinned ICICLE version; the conformance tests (byte-identical vs CPU) are the concrete oracle for every task, so "it compiles" is never mistaken for "it's correct."
- **Gate:** blocked on CUDA toolkit ≥12.4 (`nvcc`) — user-installed prerequisite before Task 1 executes.
