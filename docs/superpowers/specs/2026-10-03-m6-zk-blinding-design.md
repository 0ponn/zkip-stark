# M6: Zero-Knowledge via a Blinded multi-stark

**Date:** 2026-10-03
**Status:** Design, pending review
**Closes:** REMEDIATION.md O3 (the proof is not hiding), subject to the residual leak named below.

## Why

M5 binds the commitment, but the STARK is a plain argument of knowledge:
`multi-stark@2c01922` commits traces without blinding, so FRI openings are
linear functions of the witness, and our witness is 4 attribute bytes plus
the Merkle path (`docs/superpowers/notes/2026-10-03-o3-hiding.md`). The
repository promises hiding. Plonky3 at the pinned revision (`e9d7561`)
already ships the blinding machinery: `HidingFriPcs` (`fri/src/hiding_pcs.rs`,
`Pcs::ZK = true`), `MerkleTreeHidingMmcs` (salted leaves), and prover/verifier
handling in `uni-stark` and `batch-stark` that doubles each trace with random
rows, randomizes the quotient chunks, and adds one random FRI-batch polynomial.
`multi-stark` uses `TwoAdicFriPcs` (`ZK = false`) and its own prover, verifier
and lookup argument, and never calls the ZK-aware PCS methods. The work is
therefore a fork of `multi-stark` (`0ponn/multi-stark`, branch `zk-hiding-pcs`,
working copy `/home/mlayug/Documents/0pon/multi-stark`), consumed through the
existing `0ponn/ix` fork.

## What is built

A `GoldilocksBlake3ZkConfig` for multi-stark whose proofs are
zero-knowledge in the Plonky3 sense (statistical ZK for the FRI-batch
polynomial, as Plonky3's own docs state), with the prover and verifier made
generic over `SC::Pcs::ZK` so the existing non-ZK config and its byte-exact
reference values keep working. Aiur (our ix fork) switches its `AiurConfig`
alias to the ZK config; zkip-stark re-pins ix, re-runs its suite, re-measures,
and restates the guarantee.

## Decisions

1. **ZK is a config type, not a runtime flag.** `StarkGenericConfig` gains
   `fn is_zk(&self) -> usize { Self::Pcs::ZK as usize }` (as `uni-stark`
   does). `GoldilocksBlake3Config` stays exactly as it is; a new
   `GoldilocksBlake3ZkConfig` uses `MerkleTreeHidingMmcs` + `HidingFriPcs`.
   Prover and verifier branch on `SC::Pcs::ZK` and the constants `TRACE_IDX`,
   `QUOTIENT_IDX`, `PREPROCESSED_TRACE_IDX`. Every existing multi-stark test
   runs under both configs; the non-ZK reference values in `types.rs` do not
   change.

2. **Follow batch-stark, not uni-stark, for rounds.** multi-stark is
   multi-trace with a committed lookup stage, which is batch-stark's shape.
   Round order under ZK becomes `[random, stage1, quotient, preprocessed?,
   stage2]`; non-ZK keeps `[stage1, stage2, quotient, preprocessed?]`
   (the order is selected by `is_zk`, since the hiding PCS strips random
   columns from every round except `PREPROCESSED_TRACE_IDX`). Preprocessed
   traces are committed with `commit_preprocessing` on the extended domain
   and read with `get_evaluations_on_domain_no_random`; the open uses
   `open_with_preprocessing`.

3. **Domains and degrees.** Stage-1, stage-2 and preprocessed commitments use
   `natural_domain_for_degree(height << is_zk)`. `log_degrees` in the proof
   carry the base degrees; the transcript observes both base and extended.
   `Circuit::quotient_degree` adds `is_zk` to the constraint degree before
   the power-of-two rounding (as `uni-stark/src/symbolic.rs:18`), and the
   chunk count doubles under ZK. Quotient commitment goes through
   `get_quotient_ldes` per circuit then one `commit_ldes` (replacing the
   single `pcs.commit`). `zeta_next`, selectors and the vanishing
   polynomial stay on the base domain.

4. **Randomization polynomial.** After the quotient commitment the prover
   calls `get_opt_randomization_poly_commitment(ext_trace_domains)`, observes
   it, then samples ζ. `Commitments` gains `random: Option<Com>` and the
   proof gains `random_opened_values: Option<Vec<Challenge>>`. The verifier
   rejects a proof whose random fields disagree with `SC::Pcs::ZK`.

5. **RNG.** The config takes a caller-supplied `R: Rng + Clone + Send + Sync`;
   `GoldilocksBlake3ZkConfig::new(commitment, fri, rng)`. Aiur constructs it
   with `rand::rngs::StdRng::from_os_rng()`. `MerkleTreeHidingMmcs` keeps its
   RNG in a `RefCell`, which is `!Sync`; if `System` must be `Sync` for
   Aiur's rayon use, wrap the MMCS RNG access in a `Mutex` in the fork (same
   pattern `HidingFriPcs` already uses). `num_random_codewords = 4`, the
   value every Plonky3 ZK test uses.

6. **Blowup.** Production already runs `logBlowup 2`, which is what every
   Plonky3 ZK configuration uses. multi-stark's own tests run at `logBlowup 1`;
   if a test's constraint degree no longer fits at 1 under ZK, that test's
   ZK variant uses 2. `max_log_degree` subtracts `is_zk` so the extended
   domain still fits the two-adic subgroup.

7. **Residual leak, documented, not fixed here.** multi-stark's lookup
   argument publishes the per-circuit intermediate accumulator values
   (`Proof.intermediate_accumulators`) and the verifier checks them. Those
   are deterministic fingerprint sums of each circuit's lookup messages under
   the proof's β, γ. Blinding the trace does not hide them. Recovering a
   witness from them means guessing a circuit's entire message multiset,
   which includes the Merkle siblings, but the channel exists. batch-stark's
   global LogUp exposes the same per-instance sums. M6 ships with this
   stated in the docs; masking the boundaries (random, in-proof-constrained
   offsets that sum to zero) is a follow-up.

8. **Downstream wiring.** `0ponn/ix` gets a second backport commit:
   `Cargo.toml` points `multi-stark` at `0ponn/multi-stark@<rev>` and
   `aiur/src/synthesis.rs` sets `pub type AiurConfig = GoldilocksBlake3ZkConfig`.
   `AiurSystem::build` constructs the RNG. The ix `vk_codec` is unchanged
   unless a new parameter is added; `num_random_codewords` is a constant, not
   a parameter. zkip-stark re-pins ix by sha in `lakefile.lean` and touches
   no Lean code (the ZK flag is below the FFI).

## Definition of done

- multi-stark: all 23 existing tests pass under both configs (test modules
  parameterized over the config). New tests: (a) a ZK proof verifies; (b) a
  ZK proof is rejected if its random commitment or random opened values are
  stripped; (c) two ZK proofs of the same witness differ in their stage-1
  opened values (randomization is live); (d) a non-ZK proof fed to the ZK
  verifier and vice versa is rejected by shape, not by panic.
- ix fork: `cargo test -p aiur` green on the re-pinned multi-stark;
  `Tests/Aiur` Lean tests in ix green if cheap to run.
- zkip-stark: all 15 executables build; the 10 correctness binaries pass
  unchanged (no Lean source change); `docs/performance.md` gets a ZK row set
  (expect roughly 2x prove time and proof size); README, architecture,
  workflow doc and REMEDIATION O3 say: zero-knowledge per Plonky3's hiding
  construction, with the lookup-accumulator residual stated.
- Both forks pushed; zkip-stark pins ix by sha.

## Out of scope

- Masking the lookup accumulator boundaries (follow-up).
- Upstreaming to argumentcomputer (offer after it lands; not a gate).
- Any change to the circuit, the claim layout, or the HTTP API.
- GPU.
