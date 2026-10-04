# Draft: correction comment for argumentcomputer/multi-stark#89

Status: DRAFT, not posted. Post only after operator review.

---

Two corrections, plus one more thing a ZK port would need:

1. **Plonky3 has already fixed the short-trace issue.** I said its batch
   prover appears to have it. That was out of date: Plonky3 PR #2100
   (b4ef483, 2026-09-09) enforces `trace_height >= 2 · (D · points +
   num_queries)` inside `HidingFriPcs`. Your current pin (3152b14) predates
   it, as did ours.
2. **Our fork's floor was weaker than that.** `next_pow2(num_queries + 2)`
   counted each extension-field opening as one value and had no factor of
   two. We now use Plonky3's bound (0ponn/multi-stark 3bc3ab9).
3. **The verifying key must not depend on the prover's RNG.** Under the
   hiding PCS, `System::new` committed preprocessed traces through the salted
   MMCS, so each process built a different preprocessed commitment and
   rejected proofs from any other process (`InvalidPowWitness`). We now
   commit preprocessed traces through a second PCS that salts from a fixed
   seed. That data is public, so the salts don't need to be secret
   (0ponn/multi-stark 2788bff, test
   `zk_proof_verifies_under_independently_built_system`).
