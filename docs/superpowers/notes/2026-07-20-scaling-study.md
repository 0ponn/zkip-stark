> **⚠️ SUPERSEDED (2026-07-20) by `2026-07-20-proof-phase-profile.md`.**
> This study's NO-GO conclusion was WRONG. It measured `fftCost` (the LDE/NTT
> commit work) and found it small and flat — which is true — then mislabeled the
> remaining ~90% as un-accelerable "fixed overhead." A direct phase profile showed
> that remainder is **not** overhead: **79% of proof time is `stark/fri_open`**
> (query-phase Blake3 Merkle openings + FRI folding at numQueries=100), which is
> **fully GPU-accelerable**. The proof is FRI-bound, not NTT-bound. Prove time was
> flat across K because FRI cost scales ~numQueries·log(height), not with the trace
> size the `fftCost` metric tracks — so `fftCost` never captured the real bottleneck.
> **Corrected verdict: GO. GPU-accelerable fraction = 91%.** See the profile doc.
> The batching/depth circuit work below remains valid; only the GPU conclusion is retracted.

# M3 Task 3 — scaling study: prove time vs (batch K, depth D), GPU go/no-go

Harness: `Tests/Validation/ScalingStudy.lean` (`lake exe
Tests.Validation.ScalingStudy`). Sweeps the batch-count knob
`merkleBatchEntry k` (M3 Task 2) over K ∈ {1, 2, 4, 8} on the depth-3, 8-leaf
tree from `Tests/Validation/BatchDisclosure.lean` (K=8 discloses every
committed leaf). K=8 needed a new `merkle_predicate_batch8` entry in
`ZkIpProtocol/MerkleCircuit.lean` — mechanical extension of `batch4` (8
`batch_item` calls instead of 4), wired into `merkleBatchEntry`.

## Machine facts

- CPU: Intel(R) Core(TM) i5-11600K @ 3.90GHz (11th Gen), 6 cores / 12 threads
- Cores (`nproc`): 12
- RAM: 31 GiB total (`free -h`)
- No GPU used for this run.
- OS: Fedora, Linux 7.1.3-201.fc44.x86_64

## Method

Per K: build `merkle_predicate_batchK`, execute once (untimed) to pull
`Aiur.computeStats` trace totals, one untimed warm-up prove+verify (absorbs
JIT/lazy-init cost — same convention as `Tests/Validation/CpuBaseline.lean`),
then 5 timed prove/verify runs. Median = middle of the sorted 5 samples.

## Results (real numbers, one run — 2026-07-20)

| K | circuits | totalWidth | uniqueRows | rows(+hits) | fftCost | prove ms (5 samples) | prove median | verify median |
|---|---|---|---|---|---|---|---|---|
| 1 | 36 | 4439 | 1868 | 2714  | 1,063,897 | 553, 502, 314, 410, 385 | **410 ms** | 29 ms |
| 2 | 36 | 4439 | 2233 | 3307  | 1,252,666 | 504, 472, 407, 358, 391 | **407 ms** | 30 ms |
| 4 | 36 | 4439 | 3523 | 5299  | 2,038,458 | 260, 364, 301, 331, 337 | **331 ms** | 30 ms |
| 8 | 36 | 4439 | 6631 | 10089 | 4,149,844 | 381, 332, 433, 324, 394 | **381 ms** | 30 ms |

(`fftCost` = Σ over circuits of `width × height × log2(height)`, from
`Ix.Aiur.Statistics`; `totalWidth`/circuit count are per-circuit-definition
totals and constant because K only changes how many times each of the same 36
circuits is invoked, not how many circuit *kinds* exist — the batch8 entry
mechanically adds one more `pub fn` wrapper but reuses the exact same
`batch_item`/blake3/merkle_fold circuits.)

Merkle **depth** is not re-swept here: M3.1 (`Tests/Validation/MerkleCircuitPath.lean`,
`.superpowers/sdd/m3-task-1-report.md`) already measured depth 3/5/8 (+
odd-count, single item) and found prove time flat (~340–550 ms) — depth does
not grow the trace the way K does. Re-running that sweep would not add new
information; K is the real trace-growing lever (M3.2 finding, confirmed and
extended to K=8 above).

## Analysis

**(a) FFT/NTT is a small fraction of prove time at these sizes.**
`fftCost` grows **3.9×** from K=1 → K=8 (1.06M → 4.15M), while median prove
time is **flat to slightly down** (410 → 381 ms) — well within the run-to-run
noise floor (a single K's own 5 samples span up to ~240 ms, e.g. K=1:
314–553 ms). If FFT/NTT cost were a material fraction of total prove time, a
3.9× increase in the FFT-driving trace size would produce an increase in
prove time clearly exceeding that noise; it does not.

Quantitatively: let `prove_ms = fixed + c·fftCost`. For the observed K=1→K=8
delta (Δprove ≈ 0, bounded by the ~60–90 ms noise floor) to be consistent
with a fftCost delta of `2.9× fftCost(K=1)` ≈ 3.08M, `c` must satisfy
`c · 3.08M ≤ ~90 ms` ⇒ `c ≤ 2.9e-5 ms per fftCost-unit`. At K=1's fftCost of
1.06M that puts an **upper bound of ~31 ms of FFT time inside the ~410 ms
prove median — at most ~7–8%**, with fixed overhead (witness generation
across the 36-circuit multi-STARK setup, blake3 gadget commitment, FRI
commitment, FFI serialization to/from the Rust prover) accounting for the
remaining >90%. This is an upper bound, derived from the noisiest plausible
reading of the data — the true FFT fraction is likely smaller.

**(b) Row growth is sub-linear in K, not linear** — a second, independent
piece of evidence against the "batch harder to reach the GPU regime" idea.
Naively K items should cost ~K× the per-item rows; instead unique rows grow
1868 → 6631, only **3.55×** for an 8× increase in K, and fftCost grows only
3.9× for the same 8× increase (fftCost ~ K^0.65 empirically over this range,
vs K^1 for pure linear). This is consistent with several of the 36 circuits
being lookup/table circuits (bounded row counts) whose usage by additional
items shows up as cache hits (`rows(+hits)` growing faster than `uniqueRows`)
rather than new unique rows — so batching saturates rather than compounding.
(M3.2's own K=1/2/4 numbers on a different index/threshold selection showed a
closer-to-linear 3.09× for a 4× K step; the exact exponent is sensitive to
which items/circuits get reused, but the direction — sub-linear, not
super-linear — is the same in both runs.)

**Extrapolating the crossover.** Using the most GPU-favorable (upper-bound)
FFT coefficient `c ≈ 2.9e-5 ms/unit` from (a): fixed overhead ≈ 380 ms
(410 ms − ~30 ms FFT at K=1). FFT time would equal fixed overhead — the point
past which GPU NTT/FRI acceleration starts to matter for the *end-to-end*
number — at `fftCost ≈ 380 / 2.9e-5 ≈ 13–14M`. Extrapolating the *observed*
sub-linear fftCost-vs-K trend (fftCost ~ K^0.65 over 1→8) from K=8's 4.15M to
14M requires **K on the order of 50–60** items in a single batched proof at
this same depth-3 tree — and that's the optimistic bound; since the true `c`
is likely well below the 2.9e-5 upper bound used here, the real crossover K
is plausibly higher still. This is an estimate with explicit assumptions
(constant-`c` linear FFT model, extrapolated power-law row growth), not a
measured point — nothing past K=8 was run.

**(c) Is K≈50-60 reachable/realistic for this application?** No, not for the
IP-disclosure use case this repo targets: a single proof discloses a bounded
set of an IP holder's attributes (performance/security/efficiency-style
claims) under one commitment, not tens of unrelated attributes batched into
one STARK. Realistic K is closer to the 1–8 range already measured, where
prove time is flat around 330–410 ms regardless of K. Depth doesn't move this
number either (M3.1: flat 340–550 ms across depth 3/5/8). Combining large K
with large D was not measured and is not assumed to close the gap — depth
adds a `merkle_fold` recursion step per level, which M3.1 already showed is
cheap relative to the fixed overhead; there's no evidence combining it with
K=8 would meaningfully change the fftCost growth curve, and no measurement
here is claimed to show that.

## GPU GO / NO-GO

**NO-GO** for GPU (ICICLE) NTT/FRI acceleration at any realistic (K, D) for
this application. Proving is **fixed-overhead-dominated**, not
FFT/NTT-dominated, across the full measured range K∈{1,2,4,8} at D=3: FFT
cost quadrupled (3.9×) while prove time stayed flat within noise
(410→381 ms median). The estimated crossover — where FFT time would start to
matter for the end-to-end number — sits around K≈50-60 single-batch items,
an order of magnitude past any realistic disclosure batch size for this
IP-disclosure protocol. GPU NTT/FRI would accelerate a part of the pipeline
(~≤8% of wall time, upper bound) that isn't the bottleneck.

**What would change this verdict:**

1. **Much larger circuits via proof aggregation/recursion** — a recursive
   verifier circuit that folds many separate disclosure proofs into one
   (verifying N STARK proofs inside a single new STARK) is a genuinely
   large, hash/FFT-heavy circuit, unlike batching K independent statements
   side by side in one small proof. That's the regime where GPU NTT/FRI
   acceleration would plausibly pay off — but it's a different feature
   (aggregation, not batching) from what's built/measured here.
2. **Targeting the fixed overhead itself, not NTT.** The actual bottleneck
   at these sizes (>90% of prove time, per the bound above) is witness
   generation across the 36-circuit multi-STARK setup, commitment building,
   and FFI serialization to the Rust prover — not the FFT/NTT step ICICLE
   accelerates. If GPU work is pursued at all, profiling and accelerating
   *that* path (not swapping in a GPU NTT backend) is the number that would
   actually move.

## Reproduce

```
lake build Tests.Validation.ScalingStudy
lake exe Tests.Validation.ScalingStudy
```
