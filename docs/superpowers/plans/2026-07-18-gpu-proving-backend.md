# GPU Proving Backend — Implementation Plan (P0 + P1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish an honest, measured CPU proving baseline for zkip-stark (fixing the void identity hash and the false docs), then run the ICICLE reuse spike that decides whether the GPU NTT backend is reuse-adapter work or from-scratch CUDA.

**Architecture:** GPU acceleration plugs into Plonky3's `TwoAdicFriPcs` trait seam inside `multi-stark` (Aiur's prover), via a fork chain `memmmmike/multi-stark -> memmmmike/ix -> zkip-stark`. This plan covers only the phases whose details are knowable today: **P0** (baseline + truth) and **P1** (reuse spike). P2 (wire GPU NTT), P3 (GPU Blake3 MMCS), P4 (FRI) are planned in a follow-up once P0's timing breakdown and P1's reuse verdict exist — writing them now would invent unverified ICICLE/Plonky3 API calls.

**Tech Stack:** Lean 4.24.0 (lake), Rust (cargo 1.96), Argument Ix/Aiur, multi-stark, Plonky3 (p3-dft/p3-fri/p3-merkle-tree over Goldilocks), Blake3 (via `Blake3.Rust.hash`), CUDA 12.x + ICICLE (P1 onward).

## Global Constraints

- Lean toolchain: **`leanprover/lean4:v4.29.0`** (`lean-toolchain`). Decision 2026-07-18: `ix@main` requires 4.29.0, so we follow it and migrate the app off 4.24.0. `lake` will auto-align the toolchain to ix's; keep it at 4.29.0.
- Ix dependency: `require ix from git ".../ix.git" @ "main"` (`lakefile.lean`). Track `main`; note the resolved rev in the manifest. (Superseded the earlier "pin to 4.24.0" idea after the toolchain-conflict escalation.)
- Target GPU: RTX 4070 Ti SUPER, compute capability 8.9 (Ada). CUDA 12.x required for P1+.
- All forks live under `memmmmike/` (personal world). Never introduce work-world identifiers.
- Correctness invariant (all GPU phases, forward reference): every GPU output must be **byte-identical** to its CPU Plonky3 counterpart; the GPU never changes the protocol.
- Work happens on branch `gpu-proving-backend` (already created).

---

### Task 1: First build + Lean 4.24→4.29 migration on ix@main

The repo has never been built, AND `ix@main` requires Lean 4.29.0 while the app was written for 4.24.0 (confirmed by the P0 escalation, `docs/superpowers/notes/2026-07-18-p0-buildlog.md`). This task follows ix to 4.29.0: bump the toolchain, track ix@main, and migrate the app's ~6k lines of Lean until it compiles and a proving test runs. This is an iterative integration/migration task (fix compile error, rebuild, repeat), not TDD. Deliverable: green `lake build` on 4.29.0 + a runnable `lake exe Tests.STARKTests`.

**Files:**
- Modify: `lean-toolchain` (→ `leanprover/lean4:v4.29.0`), `lakefile.lean`, `lake-manifest.json`
- Modify: whichever `ZkIpProtocol/*.lean`, `Main.lean`, `Tests/*.lean` fail to compile under 4.29
- Append: `docs/superpowers/notes/2026-07-18-p0-buildlog.md` (migration log — the blocker record already there is committed)

**Interfaces:**
- Produces: a working `lake build` on Lean 4.29.0; a runnable `lake exe Tests.STARKTests`; the resolved ix rev recorded in the build log.

- [ ] **Step 1: Set toolchain and fetch dependencies**

Set `lean-toolchain` to `leanprover/lean4:v4.29.0`. Run: `lake update`
Expected: `ix` and transitive deps (including `Blake3.Rust`) resolve into `.lake/packages/`; the toolchain aligns to 4.29.0. Record the resolved ix rev from `lake-manifest.json` into the build log.

- [ ] **Step 2: Build and capture the error surface**

Run: `lake build` (allow 30+ min for the first Rust+Lean build; use generous Bash timeouts).
Expected initially: FAIL with Lean 4.24→4.29 migration errors across the app. Capture the list.

- [ ] **Step 3: Migrate the app to compile under 4.29 (iterate)**

Fix compile errors minimally and idiomatically for 4.29, rebuilding after each cluster. Known migration hotspots in this repo:
  - `ZkIpProtocol/CoreTypes.lean` has manual instances "required for Lean 4.24.0" (`Repr`/`Inhabited` for `ByteArray`). 4.29 may now provide these — remove the manual ones if they conflict, keep them if still needed. Let the compiler decide.
  - Import-path drift in `Ix.Aiur.*` (Protocol/Bytecode/Term/Simple/Compile/Goldilocks) if ix@main moved them — update the import to the new path.
  - Lean module-system: ix uses `module`/`public section`; if an import demands it, adjust the importing app file, not ix.
  - Stdlib API renames (Array/ByteArray/String) between 4.24 and 4.29 — follow the compiler's suggestions.
Do NOT change ix or `multi-stark`. Keep edits confined to this repo's own `.lean` files. Log each non-obvious fix.

- [ ] **Step 4: Run the STARK test executable**

Run: `lake exe Tests.STARKTests`
Expected: runs to completion and prints its `✓`/`✗` lines. It need not fully pass (the identity hash is fixed in Task 2); it must *execute the prove path* (`generateSTARKProof`) without crashing.

- [ ] **Step 5: Commit**

```bash
git add lean-toolchain lakefile.lean lake-manifest.json docs/superpowers/notes/2026-07-18-p0-buildlog.md ZkIpProtocol Main.lean Tests
git commit -m "build: migrate to Lean 4.29 on ix@main; first green build"
```
(Include only files that actually changed. If the migration is large, it may be split into a toolchain-bump commit and a migration commit — reviewer sees the full range.)

**If BLOCKED:** if the 4.29 migration reveals the app depends on an Aiur/multi-stark API that ix@main removed or reshaped in a way that needs design decisions (not mechanical fixes), STOP and report BLOCKED with the specific API and the options — do not guess at protocol-level changes.

---

### Task 2: Replace the identity hash with Blake3

The `Hash ByteArray` instance is `hash b := b` (identity), making the app-layer Merkle commitment cryptographically void. Replace it with Blake3 (the same hash family the prover uses), exposed by Ix as `Blake3.Rust.hash : ByteArray -> { val : ByteArray }` (32-byte digest).

**Files:**
- Modify: `ZkIpProtocol/CoreTypes.lean` (the `Hash ByteArray` instance, lines ~14-16)
- Create: `Tests/HashTests.lean`
- Modify: `lakefile.lean` (add a `lean_exe Tests.HashTests` entry, mirroring the existing test-exe blocks)

**Interfaces:**
- Consumes: `Blake3.Rust.hash` from the `Blake3.Rust` package (transitive via Ix).
- Produces: `Hash ByteArray` instance whose `hash` is Blake3-32; every existing `.hash` call site (e.g. `merkleRoot.hash.toNat` in `Tests/STARKTests.lean`, `MerkleCommitment.lean`) keeps compiling because the return type is still `ByteArray`.

- [ ] **Step 1: Write the failing test**

Create `Tests/HashTests.lean`:

```lean
import ZkIpProtocol.CoreTypes

namespace Tests
open ZkIpProtocol

def testHashIsNotIdentity : IO Unit := do
  let input : ByteArray := ByteArray.mk #[1, 2, 3, 4]
  let out := Hash.hash input
  -- Blake3 digest is 32 bytes and must differ from the input.
  if out == input then
    throw (IO.userError "hash is identity — commitment is void")
  if out.size != 32 then
    throw (IO.userError s!"expected 32-byte digest, got {out.size}")
  IO.println "✓ hash is Blake3-32, not identity"

def testHashDeterministicAndDistinct : IO Unit := do
  let a : ByteArray := ByteArray.mk #[0]
  let b : ByteArray := ByteArray.mk #[1]
  if Hash.hash a != Hash.hash a then
    throw (IO.userError "hash not deterministic")
  if Hash.hash a == Hash.hash b then
    throw (IO.userError "distinct inputs collided")
  IO.println "✓ hash deterministic and collision-distinct on {0} vs {1}"

def main : IO Unit := do
  testHashIsNotIdentity
  testHashDeterministicAndDistinct
  IO.println "All hash tests passed"

end Tests
```

Add to `lakefile.lean` (after the other `lean_exe Tests.*` blocks):

```lean
lean_exe Tests.HashTests where
  root := `Tests.HashTests
  srcDir := "."
  supportInterpreter := true
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lake exe Tests.HashTests`
Expected: FAIL with `hash is identity — commitment is void` (the current instance returns `b`).

- [ ] **Step 3: Write minimal implementation**

In `ZkIpProtocol/CoreTypes.lean`, add the import at the top (this file is currently import-free by design; `Blake3.Rust` is an external package, so it cannot create a cycle with app modules):

```lean
import Blake3.Rust
```

Replace the instance:

```lean
/-- Hash instance for ByteArray: Blake3-256 (32-byte digest).
    Same hash family the multi-stark prover uses for its Merkle MMCS. -/
instance : Hash ByteArray where
  hash b := (Blake3.Rust.hash b).val
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lake exe Tests.HashTests`
Expected: PASS — `All hash tests passed`.

- [ ] **Step 5: Verify no import cycle and the lib still builds**

Run: `lake build`
Expected: PASS. If a cycle is reported (some module CoreTypes now transitively imports also imports CoreTypes — should not happen with an external package), move the instance into a new leaf module `ZkIpProtocol/Hashing.lean` that imports `Blake3.Rust`, and have call sites import it. Only do this if a cycle actually appears.

- [ ] **Step 6: Re-run the STARK test (hash change is drop-in)**

Run: `lake exe Tests.STARKTests`
Expected: runs; `merkleRoot.hash.toNat` now hashes a real 32-byte digest before the mod-Goldilocks reduction. Behavior differs numerically but types are unchanged.

- [ ] **Step 7: Commit**

```bash
git add ZkIpProtocol/CoreTypes.lean Tests/HashTests.lean lakefile.lean
git commit -m "fix: replace void identity hash with Blake3 for Merkle commitment"
```

---

### Task 2b: Fix prove/verify claim serialization mismatch

Inserted 2026-07-18 after Task 1/2 review. Confirmed bug: `generateSTARKProof` serializes each claim field with `natToByteArray` (minimal-length big-endian), but `verifySTARKProof` reads each back requiring `bytes.size >= 8` (fixed 8-byte big-endian) or bails `return false`. Small fields (threshold, output) are <8 bytes, so verification can never succeed. Goldilocks values are <2^64, so fixed 8-byte big-endian is lossless on both sides.

**Files:**
- Modify: `ZkIpProtocol/STARKIntegration.lean` (`generateSTARKProof` publicInputs serialization; optionally a shared `natToBytes8BE` helper in `CoreTypes.lean`)
- Create: `Tests/Validation/ProveVerifyRoundtrip.lean` (the missing end-to-end test)
- Modify: `lakefile.lean` (add the exe)

**Interfaces:**
- Consumes: `generateSTARKProof`, `verifySTARKProof` (existing signatures), the STARKTests fixture pattern.
- Produces: a fixed 8-byte big-endian claim serialization used by prove; verify's existing 8-byte reader is unchanged.

- [ ] **Step 1: Write the failing roundtrip test** — build a circuit, `generateSTARKProof`, then `verifySTARKProof` on the result; assert it returns `true`. (Reuse the fixture shape from `Tests/STARKTests.lean`.)
- [ ] **Step 2: Run it, confirm it FAILS** (verify returns false today).
- [ ] **Step 3: Fix serialization** — add `natToBytes8BE (n : Nat) : ByteArray` returning exactly 8 bytes big-endian of `n % 2^64`; use it in `generateSTARKProof`'s `publicInputs := claim.map ...` in place of `natToByteArray`. Leave `verifySTARKProof`'s 8-byte reader as-is.
- [ ] **Step 4: Run the roundtrip test, confirm it PASSES** (verify returns true).
- [ ] **Step 5: `lake build` green; `lake exe Tests.STARKTests` now prints ✓ for verification too.**
- [ ] **Step 6: Commit** `fix: align STARK claim serialization to 8-byte big-endian so proofs verify`.

---

### Task 3: Capture the honest CPU proving baseline

Produce the real timing number that every later GPU claim is measured against. No GPU. Measure end-to-end proving and, where the prover exposes it, the internal breakdown.

**Files:**
- Create: `Tests/Validation/CpuBaseline.lean` (timing harness)
- Modify: `lakefile.lean` (add `lean_exe Tests.Validation.CpuBaseline`)
- Create: `docs/superpowers/notes/2026-07-18-cpu-baseline.md` (recorded numbers)

**Interfaces:**
- Consumes: `generateSTARKProof (circuit : PredicateCircuit) (publicInputs privateInputs : Array G) : IO (Option StarkProof)` and the test fixtures pattern from `Tests/STARKTests.lean`.
- Produces: a committed baseline document with wall-clock proving time (median of N runs) on this machine.

- [ ] **Step 1: Write the timing harness**

Create `Tests/Validation/CpuBaseline.lean`, reusing the fixture shape from `Tests/STARKTests.lean`:

```lean
import ZkIpProtocol.IPMetadata
import ZkIpProtocol.MerkleCommitment
import ZkIpProtocol.STARKIntegration
import Ix.Aiur.Goldilocks

namespace Tests.Validation
open ZkIpProtocol Aiur

def buildCircuit : IO (PredicateCircuit × Array G × Array G) := do
  let attrBytes : Array ByteArray :=
    (#[IPAttribute.performance 1500, IPAttribute.security 8, IPAttribute.efficiency 95]).map
      serializeAttribute
  let merkleRoot := commitIPData attrBytes
  let some merkleProof := generateProof attrBytes 0
    | throw (IO.userError "failed to build Merkle proof")
  let circuit : PredicateCircuit :=
    { attributeValue := 1500, merkleRoot, threshold := 1000,
      operator := ">", merkleProof, output := true }
  let publicInputs : Array G := #[G.ofNat merkleRoot.hash.toNat, G.ofNat 1000]
  let privateInputs : Array G := #[G.ofNat 1500]
  return (circuit, publicInputs, privateInputs)

def timeOnce : IO Nat := do
  let (c, pub, priv) ← buildCircuit
  let t0 ← IO.monoMsNow
  let some _proof ← generateSTARKProof c pub priv
    | throw (IO.userError "proof generation returned none")
  let t1 ← IO.monoMsNow
  return t1 - t0

def main : IO Unit := do
  -- one warm-up (JIT / lazy init), then timed runs
  let _ ← timeOnce
  let runs := 5
  let mut times : Array Nat := #[]
  for _ in [0:runs] do
    times := times.push (← timeOnce)
  let sorted := times.qsort (· < ·)
  IO.println s!"CPU proving times (ms): {sorted.toList}"
  IO.println s!"median: {sorted[runs/2]!} ms"

end Tests.Validation
```

Add to `lakefile.lean`:

```lean
lean_exe Tests.Validation.CpuBaseline where
  root := `Tests.Validation.CpuBaseline
  srcDir := "."
  supportInterpreter := true
```

- [ ] **Step 2: Build the harness**

Run: `lake build Tests.Validation.CpuBaseline`
Expected: PASS. If `serializeAttribute` / `commitIPData` / `generateProof` names differ from `Tests/STARKTests.lean`, match that file's exact names (it is the source of truth for the fixture API).

- [ ] **Step 3: Run and record the baseline**

Run: `lake exe Tests.Validation.CpuBaseline`
Expected: prints per-run times and a median. Record the median plus machine facts (CPU, RAM, `nproc`) into `docs/superpowers/notes/2026-07-18-cpu-baseline.md`.

- [ ] **Step 4: Capture the internal breakdown (best effort)**

Aiur/multi-stark use the `tracing` crate. Run with tracing on to see where time goes (trace-gen vs commit/NTT vs FRI):

Run: `RUST_LOG=info lake exe Tests.Validation.CpuBaseline 2>&1 | tee -a docs/superpowers/notes/2026-07-18-cpu-baseline.md`
Expected: `tracing` spans in stderr. If nothing useful surfaces (spans not wired through the FFI boundary), record that fact — it tells us P2 must add its own timing, and do NOT fabricate a breakdown.

- [ ] **Step 5: Commit**

```bash
git add Tests/Validation/CpuBaseline.lean lakefile.lean docs/superpowers/notes/2026-07-18-cpu-baseline.md
git commit -m "test: add CPU proving baseline harness and record numbers"
```

---

### Task 4: Rewrite the docs to reflect reality

Strip the false "NoCap UNAVAILABLE / CRITICAL PERFORMANCE BOTTLENECK" narrative and describe the actual system: Blake3 prover, fixed hash, real CPU baseline, GPU as future work at the Plonky3 seam.

**Files:**
- Modify: `README.md`, `docs/architecture.md`, `docs/performance.md`, `docs/index.md`
- Modify: `ZkIpProtocol/NoCapFFI.lean` (mark vestigial or delete — see Step 3)

**Interfaces:**
- Consumes: the recorded numbers from `docs/superpowers/notes/2026-07-18-cpu-baseline.md`.
- Produces: docs whose claims match the code.

- [ ] **Step 1: Rewrite the performance/hardware claims**

In `README.md`, `docs/performance.md`, `docs/architecture.md`, `docs/index.md`, replace every "NoCap hardware UNAVAILABLE — CRITICAL PERFORMANCE BOTTLENECK" and "Hardware Acceleration" claim with the truth:
  - The prover is Ix/Aiur → multi-stark → Plonky3 over Goldilocks, hashing with **Blake3** (not Poseidon).
  - There is no hardware bottleneck; there was an unmeasured, never-built system. Cite the real CPU baseline number.
  - GPU acceleration is planned at the Plonky3 `TwoAdicFriPcs` trait seam (NTT first), not via NoCap/Poseidon.
Remove the "production-ready" claim unless the baseline + tests justify it; prefer "research prototype".

- [ ] **Step 2: Fix the false hash claim**

In `README.md` "Key Features" and anywhere describing hashing, remove the Poseidon-hardware framing. State: Merkle commitments use Blake3 (`CoreTypes.lean`), matching the prover's MMCS.

- [ ] **Step 3: Resolve NoCapFFI**

`NoCapFFI.lean` is a stub that does not touch the prover's hot path (the prover hashes Blake3 internally, not through this FFI). Choose:
  - **Delete** it and remove imports/usages (preferred if nothing references it meaningfully — grep first: `grep -rn "NoCapFFI\|NoCap\|poseidonHash" ZkIpProtocol Tests`).
  - If something depends on it, add a top-of-file doc comment: `-- VESTIGIAL: software-only stub, not on the prover hot path (prover uses Blake3 in multi-stark). Slated for removal.`

Run the grep, act on the result, and `lake build` to confirm nothing breaks.

- [ ] **Step 4: Verify build and links**

Run: `lake build`
Expected: PASS (if NoCapFFI was deleted, all references are gone).

- [ ] **Step 5: Commit**

```bash
git add README.md docs/ ZkIpProtocol/NoCapFFI.lean
git commit -m "docs: rewrite to reflect real Blake3 prover and CPU baseline; retire NoCap theater"
```

---

### Task 5 (P1 spike): ICICLE reuse decision — GPU NTT conformance

Spike, not TDD-in-anger: the deliverable is a **documented reuse-vs-custom decision** backed by a GPU NTT that passes Plonky3's DFT conformance against the CPU reference. Fold CUDA/ICICLE setup into this task.

**Files:**
- Create: `docs/superpowers/notes/2026-07-18-p1-icicle-spike.md` (findings + decision)
- Create (scratch, outside this repo): a throwaway Rust crate that pulls ICICLE + `p3-dft` to test conformance. Do NOT wire it into `multi-stark` yet — that is P2.

**Interfaces:**
- Produces: a decision record (`reuse` | `custom`) and, if reuse, the exact ICICLE crate/version and the adapter shape needed to satisfy `p3_dft::TwoAdicSubgroupDft<Goldilocks>`.

- [ ] **Step 1: Install CUDA toolkit**

Confirm with the operator before running (system change). Install CUDA 12.x so `nvcc --version` works (driver 610 already present). Record the exact install method in the spike doc.
Run (after confirmation): `nvcc --version`
Expected: CUDA 12.x, and `nvidia-smi` still healthy.

- [ ] **Step 2: Verify ICICLE has a Goldilocks NTT and a Plonky3 path**

Research ICICLE's current Goldilocks + Plonky3 support (crate name, version, features). Record in the spike doc with links. If ICICLE does NOT support Goldilocks NTT at a usable version, stop and record `custom` with the reason — the sppark-style from-scratch path becomes P2's basis.

- [ ] **Step 3: Conformance harness in a scratch crate**

In a throwaway crate (in scratch, not this repo), generate random `Goldilocks` matrices, run both `p3_dft::Radix2DitParallel` (CPU reference) and the ICICLE GPU DFT over the same input, and assert **byte-identical** coefficient output for several sizes (e.g. 2^10..2^18 rows).

- [ ] **Step 4: Record the decision**

Write `docs/superpowers/notes/2026-07-18-p1-icicle-spike.md`: reuse-vs-custom verdict, the passing/failing conformance evidence, ICICLE version + adapter sketch (if reuse), and a revised effort estimate for P2. This document is the input to the P2/P3/P4 follow-up plan.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/notes/2026-07-18-p1-icicle-spike.md
git commit -m "spike: ICICLE Goldilocks NTT reuse decision + Plonky3 conformance evidence"
```

---

## Follow-up (planned after this plan completes)

P2 (wire GPU NTT into `multi-stark` behind a `gpu` feature via the fork chain), P3 (GPU Blake3 MMCS), and P4 (FRI folding) get their own plan, written against:
- the real hot-spot breakdown from Task 3, and
- the reuse-vs-custom verdict + ICICLE adapter shape from Task 5.

Deferring them is deliberate: their code steps depend on data that only P0/P1 can produce.

## Self-Review

- **Spec coverage:** P0 (baseline + fix hash + rewrite docs) → Tasks 1-4. P1 (ICICLE reuse spike, GPU NTT conformance) → Task 5. Fork chain / correctness invariant → Global Constraints (mechanics land in the P2 follow-up, correctly deferred). P2-P4 → explicitly deferred with rationale. No spec requirement for *this* plan's scope is unaddressed.
- **Placeholders:** none — the one genuinely unknown (ICICLE's exact API) is a spike deliverable, not a code step, which is the honest treatment.
- **Type consistency:** `Hash.hash : ByteArray -> ByteArray` (Task 2) matches all `.hash` call sites (Task 3 uses `merkleRoot.hash.toNat`). `generateSTARKProof` signature reused verbatim from `Tests/STARKTests.lean`. Fixture names (`serializeAttribute`, `commitIPData`, `generateProof`) flagged in Task 3 Step 2 to be matched against the source-of-truth test file.
