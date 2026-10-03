# M6 ZK Blinding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Aiur proofs zero-knowledge by retrofitting Plonky3's hiding PCS and randomized protocol into a `multi-stark` fork, then consume it through the ix fork.

**Architecture:** multi-stark's prover and verifier become generic over `SC::Pcs::ZK`, following `batch-stark`'s shape (extended domains, randomization commitment, per-chunk quotient LDEs, round order `[random, stage1, quotient, preprocessed?, stage2]`). A new `GoldilocksBlake3ZkConfig` wires `MerkleTreeHidingMmcs` + `HidingFriPcs`. The non-ZK config is untouched. Aiur's `AiurConfig` alias switches to the ZK config.

**Tech Stack:** Rust 1.92, Plonky3 `e9d7561` (`p3-fri::HidingFriPcs`, `p3-merkle-tree::MerkleTreeHidingMmcs`), `rand 0.10`, multi-stark fork at `/home/mlayug/Documents/0pon/multi-stark` (branch `zk-hiding-pcs`, remote `origin` = `0ponn/multi-stark`, `upstream` = argumentcomputer). ix fork scratch clone at `/home/mlayug/.cache/claude-tmp/.../scratchpad/ix-fork` (recreate from `.lake/packages/ix` if gone).

**Spec:** `docs/superpowers/specs/2026-10-03-m6-zk-blinding-design.md`

## Global Constraints

- The non-ZK `GoldilocksBlake3Config` path must produce byte-identical proofs and pass `types.rs`'s reference-value tests unchanged.
- Reference implementation for every ZK branch is Plonky3 `batch-stark/src/prover.rs` (120-600) and `batch-stark/src/verifier/mod.rs`; when in doubt, copy its order of operations.
- `num_random_codewords = 4`. RNG is caller-supplied, `StdRng::from_os_rng()` in Aiur; never `SmallRng` outside tests.
- Transcript must observe: shape, preprocessed commitment, stage-1 commitment, base and extended log degrees, claims, β, γ, stage-2 commitment, accumulators, α, quotient commitment, random commitment (ZK only), then ζ. The verifier replays the same order.
- `zeta_next`, selectors and vanishing polynomial are evaluated on the base domain; commitments, FRI verification of chunks and the random round use the extended domains.
- Test loop: `cd /home/mlayug/Documents/0pon/multi-stark && cargo test --release 2>&1 | grep -E "test result|FAILED|panicked"` (23 tests, about 20 s including compile).
- Commit per task in the fork with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`; push the fork before re-pinning ix.
- No em-dashes.

## Review Focus

1. A ZK proof with `commitments.random` removed must fail verification with a shape error, not verify (random polynomial is what makes the FRI batch hiding). Task 2 test (b).
2. Under ZK the quotient chunk count doubles; a verifier using the un-doubled count would accept nothing. Task 1's parameterized `multi_stark_test` covers it; Task 2 test (d) covers the cross-config case.
3. Preprocessed round: the hiding PCS strips random columns from every round except `PREPROCESSED_TRACE_IDX`; if stage2 is opened before preprocessed, widths mismatch. Covered by `preprocessed_proof`-style test under ZK (Task 1, test parameterization includes `test_circuits::u32_add` which has preprocessed columns; confirm, else add one).
4. Lookup accumulator chaining across circuits still holds with random rows interleaved (constraints only enforced on the base subgroup). `lookup_test` under ZK, Task 1.
5. `max_log_degree` must subtract `is_zk`; a circuit at the old max would overflow the two-adic domain under ZK. Task 1: `test_oversized_log_degree_rejected` under ZK.

---

### Task 1: multi-stark generic over ZK, with a ZK Goldilocks config

**Files (fork):**
- Modify: `src/config.rs` (`StarkGenericConfig::is_zk`)
- Modify: `src/types.rs` (`GoldilocksBlake3ZkConfig`, hiding MMCS/PCS aliases, `new_hiding_pcs`, `max_log_degree` subtracts `is_zk`, `max_quotient_degree` accounts for the doubled chunk count)
- Modify: `src/system.rs` (`System::new` commits preprocessed on `height << is_zk` via `commit_preprocessing`; `quotient_degree` adds `is_zk`; `observe_shape` binds `is_zk`)
- Modify: `src/prover.rs` (`prove_multiple_claims` per spec decisions 2 to 4; `Commitments.random`, `Proof.random_opened_values`)
- Modify: `src/verifier.rs` (random presence check, extended vs base domains, doubled chunk domains for `pcs.verify`, un-doubled for recomposition, round order, transcript replay, `verify_shape` random-shape and extended-degree bound; replace the "Not zero-knowledge" doc section)
- Modify: `Cargo.toml` (`rand` becomes a normal dependency)
- Modify: every test module that builds a config so it runs under both configs (`macro_rules!` or a `fn run_with<SC>()` pair).

**Interfaces:**
- Produces: `pub struct GoldilocksBlake3ZkConfig`, `impl StarkGenericConfig`, constructor `new(commitment: CommitmentParameters, fri: FriParameters, rng: R)`; `StarkGenericConfig::is_zk(&self) -> usize`.
- Consumes: Plonky3 `HidingFriPcs::new(dft, mmcs, fri_params, num_random_codewords, rng)`, `MerkleTreeHidingMmcs::new(hash, compress, cap_height, rng)`.

- [ ] **Step 1: Read** `src/config.rs`, `src/types.rs`, `src/system.rs`, `src/prover.rs:190-480`, `src/verifier.rs:190-480,477-609`, and Plonky3 `batch-stark/src/prover.rs:120-600`, `batch-stark/src/verifier/mod.rs:60-430`, `fri/src/hiding_pcs.rs`. Write a one-screen mapping (multi-stark line to batch-stark line) into the SDD ledger before editing.
- [ ] **Step 2: Red.** Add `GoldilocksBlake3ZkConfig` and parameterize `verifier::tests::multi_stark_test` to run under it. Run the suite: expected failure is the domain-size assertion panic inside `TwoAdicFriPcs::commit` (`assert_eq!(domain.size(), evals.height())`).
- [ ] **Step 3: Green, in this order, running the suite after each:** config `is_zk`; `system.rs` preprocessed/extended domains and degree; prover extended domains and transcript; quotient via `get_quotient_ldes`/`commit_ldes`; randomization commitment; round reorder and `open_with_preprocessing`; verifier mirror. Expected: `multi_stark_test` passes under both configs.
- [ ] **Step 4:** Parameterize the remaining tests (`verifier::tests::*`, `system::tests::*`, `lookup::tests::*`, `test_circuits::*`). Expected: 23 non-ZK + the ZK twins all pass; the `types.rs` reference values unchanged.
- [ ] **Step 5: Commit** in the fork: `feat: zero-knowledge config (HidingFriPcs) with prover/verifier generic over Pcs::ZK`.

### Task 2: ZK-specific tests

**Files (fork):** `src/verifier.rs` tests (or a new `src/zk_tests.rs`).

- [ ] (a) `zk_proof_verifies`: prove+verify a lookup circuit under the ZK config.
- [ ] (b) `zk_proof_without_random_commitment_rejected`: set `commitments.random = None` (and separately `random_opened_values = None`) on a valid ZK proof; expect `Err`, not panic.
- [ ] (c) `zk_proofs_of_same_witness_differ`: prove twice with different RNG seeds; the stage-1 opened values at ζ differ (ζ itself differs because commitments differ, so compare the stage-1 commitment bytes and the opened values; both must differ).
- [ ] (d) `cross_config_proofs_rejected`: deserialize a non-ZK proof's bytes with the ZK verifier and vice versa; expect `Err` (shape), not panic. If bincode layout makes the ZK proof fail to deserialize at all, that is the accepted outcome; assert it is an `Err`.
- [ ] Run the suite; commit: `test: ZK verification, randomization liveness, cross-config rejection`. Push `zk-hiding-pcs` to `origin` (0ponn). Record the rev.

### Task 3: ix fork consumes the ZK config

**Files (ix scratch clone, branch `ofbytes-checked` or a new branch `zk` from it):**
- Modify: `Cargo.toml` (`multi-stark = { git = "https://github.com/0ponn/multi-stark.git", rev = "<Task 2 rev>" }`), `Cargo.lock` via `cargo update -p multi-stark`.
- Modify: `crates/aiur/src/synthesis.rs` (`pub type AiurConfig = GoldilocksBlake3ZkConfig;`, `build` constructs `StdRng::from_os_rng()`), `crates/aiur/Cargo.toml` (`rand`).
- Check: `vk_codec.rs` compiles unchanged; `crates/ffi` compiles.

- [ ] Red: change the alias, `cargo build -p aiur`; expected compile errors at the constructor call.
- [ ] Green: wire the RNG; `cargo test -p aiur --release` green. If `System` must be `Sync` and the hiding MMCS's `RefCell` blocks it, fix in the multi-stark fork (Mutex), re-push, re-pin.
- [ ] Commit `feat: Aiur proves with the zero-knowledge multi-stark config`, push to `0ponn/ix`, record the rev.

### Task 4: zkip-stark re-pin, suite, timing, docs

**Files:** `lakefile.lean` (ix sha), `docs/performance.md`, `README.md`, `docs/architecture.md`, `docs/workflow-for-decision-makers.md`, `REMEDIATION.md` (O3), `docs/superpowers/notes/2026-10-03-o3-hiding.md` (addendum), new `docs/superpowers/notes/2026-10-03-m6-handoff.md`.

- [ ] Re-pin, `lake update ix` (expect a re-clone and full rebuild, about 2 min), build all 15 executables, run the 10 correctness binaries. Expected: all exit 0 with no Lean change.
- [ ] Run `Tests-Validation-CpuBaseline`; add the ZK rows to `docs/performance.md` next to the non-ZK rows.
- [ ] Restate: "zero-knowledge per Plonky3's hiding construction (statistical ZK for the FRI-batch polynomial); residual: per-circuit lookup accumulator values are public." Commit, push.

### After the tasks

Code-review skill on the multi-stark fork diff (point it at the fork directory) and on zkip-stark; hermes-local on the fork diff with questions about transcript ordering and domain sizes; escalate to gpt-5.4 if it flags anything.
