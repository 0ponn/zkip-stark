# M3 — Batching / Scaling Study Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Scale the fused predicate+membership circuit along its two real axes — Merkle **depth D** and attribute **batch count K** — and measure where proving becomes constraint/hashing-dominated (the regime where GPU acceleration actually helps). Deliver a data-driven answer to the GPU go/no-go, plus the real batched-disclosure feature the README always claimed.

**Why:** The M2 fused circuit proves in ~426 ms — barely more than M1's ~506 ms — so proving is currently FRI/commitment-dominated, not constraint-dominated. GPU (NTT/FRI) acceleration only pays off once the circuit is large. This milestone finds, with measurements, whether batching+depth reach that regime.

**Architecture:** Parameterize the M2b `MerkleCircuit.lean` circuits: (1) replace the hard-unrolled depth-3 `merkle_path` with a recursive in-circuit fold over depth D; (2) a batched entry proving K independent (predicate + membership-under-shared-root) statements in one circuit; (3) a scaling-study harness sweeping (K, D) and recording prove/verify times.

**Tech Stack:** Lean 4.29, ix Aiur (`⟦⟧` DSL, recursion, `merkle_predicate`/`node_from`/`digest_to_stream` from M2b), Goldilocks.

## Global Constraints

- Correctness is preserved at every depth/batch: the parameterized circuit MUST still match the M2a off-circuit reference (`buildMerkleTree`/`generateProof`/`verifyProof`) and keep every M2 negative (ad-switch, wrong sibling/dir/root, non-Boolean dir, leaf-length≠4) rejecting. Scaling must not weaken soundness.
- Measurements are HONEST: median-of-N (N≥5) wall time, machine facts recorded, no fabricated numbers, note warm-up. If a (K,D) point is too slow to run, record that it was skipped and why — never extrapolate silently.
- Branch `gpu-proving-backend`.
- Reference the M2 baseline (~426 ms prove) as the K=1,D=3 anchor point.

---

### Task 1: Parameterize Merkle depth (recursive fold)

Replace the hard-unrolled depth-3 fold in `merkle_predicate`/`merkle_path` with a recursive in-circuit fold that handles arbitrary depth D, so depth becomes a knob.

**Files:**
- Modify: `ZkIpProtocol/MerkleCircuit.lean` (recursive `merkle_fold`/depth-D path; keep `node_from` with its dir∈{0,1} constraint)
- Modify/Create: `Tests/Validation/MerkleCircuitPath.lean` (test at multiple depths)

**Interfaces:**
- Produces: a depth-parameterized membership fold (Aiur recursion over the sibling/direction lists, terminating when the path is exhausted), reusing `node_from`.

- [ ] **Step 1: Write failing tests** — cross-check the circuit root against `buildMerkleTree`/`generateProof` for depths 3, 5, and 8 (build trees of 8, 32, 256 leaves), several indices each. Include the odd-count case Codex flagged as untested (e.g. a 5-leaf tree → duplicate-last path).
- [ ] **Step 2: Run, confirm FAIL** (current circuit is fixed depth 3).
- [ ] **Step 3: Implement recursive fold** — an Aiur function that folds `acc` up a variable-length path (recursion like blake3's own layer recursion), each step `node_from` with the Boolean-direction constraint, matching `verifyProof`'s fold exactly. Depth chosen by the witness path length (still assert final root == public root).
- [ ] **Step 4: Run, confirm PASS** at depths 3/5/8 incl. odd-count; all M2 negatives still reject. `lake build` green.
- [ ] **Step 5: Commit** `feat: parameterize in-circuit Merkle depth via recursive fold`.

---

### Task 2: Batch K attributes under a shared root

One circuit proving K independent statements: for each of K attributes, `attr_i > threshold_i` AND membership of `leaf_i = 4LE(attr_i)` under the SAME public `root`. This is the real batched-disclosure feature and the batch-count knob.

**Files:**
- Modify: `ZkIpProtocol/MerkleCircuit.lean` (batched entry) or a new `ZkIpProtocol/BatchCircuit.lean`; replace the `Batching.lean` stub or wire to it
- Create: `Tests/Validation/BatchDisclosure.lean`

**Interfaces:**
- Consumes: the depth-D fold (Task 1), `merkle_predicate` logic.
- Produces: `merkle_predicate_batch` proving K (predicate ∧ membership) under one shared root; public = `root` + K thresholds; private = K (attr, path).

- [ ] **Step 1: Failing test** — a real tree; disclose K∈{2,4} committed attributes each satisfying its threshold → prove/verify true; and the batched ad-switch negative (one of the K attrs advertised as a non-committed value) → fails.
- [ ] **Step 2: Run, confirm FAIL.**
- [ ] **Step 3: Implement** the batched circuit (K unrolled or recursive over the K statements), each reusing the depth-D membership + predicate, all binding the same public root.
- [ ] **Step 4: Run, confirm PASS** (positives verify, batched ad-switch + per-item negatives reject). `lake build` green.
- [ ] **Step 5: Commit** `feat: batched K-attribute disclosure under a shared root`.

---

### Task 3: Scaling-study harness + GPU-crossover findings

Sweep (K, D), measure, and write the data-driven GPU recommendation.

**Files:**
- Create: `Tests/Validation/ScalingStudy.lean` (parameterized harness)
- Create: `docs/superpowers/notes/2026-07-20-scaling-study.md` (the results + recommendation)

- [ ] **Step 1: Harness** — for each (K, D) in a grid (e.g. K∈{1,2,4,8}, D∈{3,8,16}, skipping points that exceed a wall-time cap), build the circuit, prove N≥5 times, record median prove + verify + (if available) constraint/trace-row count from the ABI/bytecode.
- [ ] **Step 2: Run** the grid; capture the table into the notes file with machine facts. Record any skipped (too-slow) points explicitly.
- [ ] **Step 3: Analyze** — identify where prove time starts scaling with circuit size (constraint-dominated) vs staying flat (FRI-dominated). State the crossover, and whether a realistic (K, D) reaches a regime where GPU NTT/FRI acceleration would give meaningful speedup. If it does NOT reach that regime at feasible sizes, say so plainly — that is a valid, important finding that redirects the GPU plan.
- [ ] **Step 4: Commit** `docs: scaling study — prove-time vs (batch, depth); GPU-crossover finding`.

---

## Self-Review

- **Coverage:** depth knob (Task 1), batch knob (Task 2), measurement + GPU decision (Task 3). Correctness/soundness preserved as a Global Constraint and re-tested at each scale.
- **Placeholders:** none — grid, metrics, and the "state the crossover honestly (including if unreached)" instruction are concrete.
- **Consistency:** the recursive fold (Task 1) and batched circuit (Task 2) both reuse `node_from` (dir∈{0,1}) and match `verifyProof`; the harness (Task 3) measures the very circuits Tasks 1–2 build. This milestone answers the GPU go/no-go the M2 baseline raised.
