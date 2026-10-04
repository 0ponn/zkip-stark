# Draft: upstream design issue for argumentcomputer/multi-stark

Status: POSTED 2026-10-04 as https://github.com/argumentcomputer/multi-stark/issues/89
Target: https://github.com/argumentcomputer/multi-stark/issues/new

---

**Title:** Interest in an opt-in zero-knowledge mode? (we have a working fork against 2c01922)

**Body:**

We use multi-stark to prove predicates over private certificate attributes,
where the witness has to stay hidden from the verifier. The verifier docs say
the protocol is not zero-knowledge, so we built an opt-in ZK mode on a fork.
It works against an older base. Before porting it to current `main` we'd like
to know if you would take it, and in what shape.

Fork branch: https://github.com/0ponn/multi-stark/tree/zk-hiding-pcs
(8 commits on 2c01922, 12 files, +1449/-187)

### What the fork does

1. **Hiding PCS config.** `GoldilocksBlake3ZkConfig` uses Plonky3's
   `HidingFriPcs` with a salted MMCS. Both draw from one shared prover-side CSPRNG handle,
   so the salts and the blinding can never come from cloned, identical
   streams. The prover and verifier are generic over `Pcs::ZK`. The plain
   config's behavior is unchanged, and every end-to-end test also runs under
   the ZK config.
2. **Minimum trace height under ZK.** The hiding PCS adds only `h` random rows
   to an `h`-row trace. With `num_queries` FRI openings plus the out-of-domain
   points, a short trace is over-determined. During review we recovered a
   4-row trace from a single ZK proof. The branch tests the fix
   (`zk_short_trace_refused`, `zk_short_trace_proof_rejected_by_shape`) but
   not the attack itself, and we can write that up if useful. The fork adds `StarkGenericConfig::min_trace_height`,
   which is `next_pow2(num_queries + 2)` under ZK. The prover refuses shorter
   traces and the verifier rejects them by shape.
3. **Masked lookup accumulators.** The intermediate accumulators are public.
   Anyone who can guess a circuit's lookups can replay the transcript for
   beta/gamma and confirm the guess. We reproduced this bit for bit
   (`zk_accumulators_do_not_confirm_witness`). Under ZK, each pair of adjacent
   circuits shares a secret value, sampled by the prover from the CSPRNG, on a
   dedicated
   `MASK_TAG` lookup channel: one circuit pushes it and the next pulls it.
   That needs 5 extra stage-1 columns per circuit. The pair cancels in the
   lookup sum, so soundness is unchanged, but each published accumulator is
   offset by a secret. Claims tagged `MASK_TAG` are rejected, which closes a
   forgery where the unconstrained mask could balance a fake claim
   (`zk_mask_tag_claim_rejected`). It requires a degree-2 challenge field,
   because the two secret base elements per link are only uniform over a
   quadratic extension.
4. **`Sync` hiding MMCS.** Plonky3's `MerkleTreeHidingMmcs` keeps its RNG in
   a `RefCell`. That makes the config `!Sync`, which breaks sharing a system
   across rayon threads. `SyncHidingMmcs` uses the same scheme behind a
   `Mutex`.

Known gap: trace heights still leak through proof shape. We handle that in
the application by fixing one trace shape for every proof.

### Why this is a question first, not a PR

Current `main` has moved a long way from our base: sparse systems, logUp
without committed inverses, the quotient committed from coefficients,
sharding, and CUDA. A trial merge conflicts in 11 files. More importantly,
`prover.rs` now asserts `!Pcs::ZK`, because `commit_ldes` and the
accelerated quotient path skip the hiding PCS's randomization. A ZK mode
would need either:

- (a) a ZK-only fallback that commits the quotient through `Pcs::commit`
  (slower, and CPU only under ZK), or
- (b) blinding added to the coefficient and accelerated commit path.

### Questions

1. Is an opt-in ZK mode something you'd accept, or is it out of scope?
2. If yes, which do you prefer for the quotient: (a) or (b)?
3. Would you take the parts separately? The minimum trace height and the
   `Sync` hiding MMCS are small and independent. The accumulator masking is
   the most invasive part and interacts with the new logUp design.

Happy to do the port. We'd rather match your direction than ship a 1.4k-line
surprise.

Separately: Plonky3's batch prover appears to have the same short-trace
issue under `HidingFriPcs`. We plan to report that there.
