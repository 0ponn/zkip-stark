# Single-proof phase profile — the real GPU decision (0PO-553)

**Date:** 2026-07-20
**Branch:** `gpu-proving-backend`
**Question:** A single `merkle_predicate_batch1` (K=1) proof takes ~380–535 ms.
Where does that time actually go, and what fraction is in GPU-accelerable phases?
**Corrects:** an earlier study that measured only the NTT/LDE cost and *inferred*
the rest was un-accelerable. This one measures the whole prove, phase by phase.

## Method (what worked)

**Least-invasive route — the spans already existed; nothing was forked.**

- `multi-stark`'s prover (`stark/prove`, git rev `2c019220…`) and aiur's
  `synthesis.rs::prove()` (`aiur/prove`) already carry `#[tracing::instrument]` /
  `tracing::info_span!` spans. `aiur/prove` calls `tracing_texray::examine_current()`,
  making it the examined root over the whole nested `aiur/*` + `stark/*` subtree.
- ix already ships a Lean binding, `Ix.TracingTexray`, over an FFI shim
  (`.lake/packages/ix/crates/ffi/src/texray.rs`: `rs_texray_init`,
  `rs_texray_json_sink`). The P0 finding ("no subscriber on the FFI prove path")
  was about the *default* path — the subscriber just has to be installed from
  Lean before the prove call. Nothing in the prover needed changing.
- Harness `Tests/Validation/ProofPhaseProfile.lean` installs the subscriber +
  JSON sink, then proves `merkle_predicate_batch1` N=5 times (plus one untimed
  warm-up). Each closed examined span writes one `{"span","seconds"}` JSONL line,
  so the sink holds 5 samples/phase, which we average.

**Validation that the spans capture the whole proof:** Rust-measured `aiur/prove`
span (avg **470.9 ms**) matches the Lean wall-clock prove (median **475.7 ms**)
within run-to-run noise. The spans account for ~100% of wall time — no hidden
cost outside them.

FFI proof serialization (`proof.toBytes`, 4.70 MB proof) is timed separately
Lean-side: **~1.85 ms** (had to force `.size` inside the window — a bare `let`
only builds a thunk and mis-measures it as 0). It happens *outside* the
`aiur/prove` span, so it is additive: ~0.4% of end-to-end.

Trace dimensions for this proof (from `Aiur.computeStats`): **circuits=36,
totalWidth=4439, uniqueRows=1868, fftCost=1.06e6** — consistent with the
ScalingStudy K=1 point.

## Phase breakdown (avg of N=5, % of the 470.9 ms `aiur/prove` total)

| Phase | span | avg ms | % | GPU-accelerable? |
|---|---|---:|---:|---|
| Witness-gen / execute (semantic bytecode + blake3 gadget) | `aiur/execute` | 1.86 | 0.4% | No (semantic) |
| Trace build (query record → trace matrices) | `aiur/witness` | 11.06 | 2.3% | No (CPU, memory-bound) |
| Stage-1 commit (LDE/NTT + Merkle over trace cols) | `stark/stage1_commit` | 12.84 | 2.7% | **Yes** (NTT + hash) |
| Lookup construction (fingerprint + batch inverse) | `stark/lookup_construction` | 17.24 | 3.7% | Partial (ext-field) |
| Stage-2 commit (LDE/NTT + Merkle, perm traces) | `stark/stage2_commit` | 21.13 | 4.5% | **Yes** (NTT + hash) |
| Quotient (constraint eval + LDE + Merkle) | `stark/quotient` | 23.99 | 5.1% | **Yes** (NTT + hash) |
| **FRI open (interp + folding + query-phase Merkle hashing)** | `stark/fri_open` | **370.34** | **78.6%** | **Yes** (NTT-class + hash) |
| Challenger / observe / claim build (between spans) | (gaps) | 12.44 | 2.6% | No |
| FFI proof serialization (`proof.toBytes`, additive) | (Lean-side) | ~1.85 | ~0.4% | No |

Sub-spans of the lookup phase (informational, already inside the 17.24 ms):
`stark/lookup_messages` 5.0 ms, `stark/batch_inverse` 2.6 ms,
`stark/lookup_traces` 9.6 ms.

## GPU-accelerable fraction

- **Commit-hashing + NTT + FRI** (`stage1_commit + stage2_commit + quotient +
  fri_open`) = **428.3 ms = 91.0%** of proof time.
- Including the lookup phase (partially accelerable, extension-field ops) → **94.6%**.
- **Non-accelerable** (execute + witness + challenger gaps + FFI serialization) =
  **~27 ms = ~5.7%**.
- **FRI open alone is 78.6%** — the single dominant cost.

## Revised verdict: **GO**

The earlier "NTT is small, so NO-GO" conclusion was measuring the wrong thing.
The LDE/NTT commit phases (`stage1 + stage2 + quotient`) really *are* small here
(~12% combined). But the proof is not NTT-bound — it is **FRI-bound**: 79% of the
time is in `stark/fri_open`, dominated by query-phase Merkle-path hashing (Blake3
over the committed trees, `numQueries=100`, `logBlowup=1`) plus FRI folding and
barycentric interpolation. Every one of those is exactly what a GPU proving
backend accelerates — ICICLE provides Merkle/hashing and FRI/NTT primitives.

**What to target first, in priority order:**
1. **FRI / query phase (`stark/fri_open`, 79%)** — GPU Blake3 for the query-phase
   Merkle openings + GPU FRI folding. This one phase is the whole ballgame; a 3–5×
   here moves the proof from ~470 ms toward ~150–200 ms.
2. Commit-phase hashing + LDE (`stage1/stage2/quotient`, ~12% combined) — GPU
   Blake3 Merkle + GPU NTT. Secondary; only worth it after FRI.

Witness-gen (`aiur/execute` + `aiur/witness` = 2.7%) and FFI (~0.4%) are noise —
no reason to touch them for the GPU effort.

## Honest caveats / flags

- **`fri_open` is a single span** — its internal split (barycentric interp vs FRI
  folding vs query-phase Merkle openings) is not separately instrumented in the
  `multi-stark` dep, so I cannot give a measured interp-vs-fold-vs-hash breakdown
  without patching the git dependency. All three sub-components are GPU-accelerable
  (NTT-class arithmetic + Blake3 hashing), so the *accelerability* conclusion holds
  regardless of the internal split; only the "which primitive to optimize first
  inside FRI" ordering is an estimate.
- The FRI cost is inflated by real security parameters (`numQueries=100`,
  `logBlowup=1`). That is the actual config this proof ships with, not a stress
  knob — the 79% is legitimate for this stack.
- All numbers are **measured** (texray JSON sink + Lean wall-clock), not inferred.
  The only estimate is the intra-`fri_open` optimization ordering above.

## Reproduce

```
lake build Tests.Validation.ProofPhaseProfile
./.lake/build/bin/Tests-Validation-ProofPhaseProfile /tmp/spans.jsonl
# per-phase samples land in /tmp/spans.jsonl (5/span + 1 warm-up); the texray
# tree also prints to stderr.
```
