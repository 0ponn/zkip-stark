# M7: Mask the Lookup Accumulators

**Status:** done 2026-10-03 (multi-stark `9609200`, ix `43e3d92`).

**Goal:** Under zero-knowledge, stop the public per-circuit lookup accumulators from confirming a guessed witness, without weakening the lookup argument's soundness.

**Where:** `0ponn/multi-stark` branch `zk-hiding-pcs` (working copy `/home/mlayug/Documents/0pon/multi-stark`); then re-pin `0ponn/ix` branch `zk` and zkip-stark. No Aiur or Lean change: masking happens inside multi-stark's `System::new` and prover.

## The leak

`Proof.intermediate_accumulators[i]` is the running LogUp sum after circuit `i`:
the claims' sum plus `Σ mult / (β + fp(γ, args))` over every lookup in circuits
`0..=i`. β and γ come from the public transcript, so anyone who guesses circuit
`i`'s lookup multiset can recompute the value and confirm the guess.

## Design

Mask with the lookup argument itself, so soundness is untouched.

Under ZK, with `n ≥ 2` circuits, `System::new` appends to circuit `i` five
stage-1 columns `[s, in_a, in_b, out_a, out_b]` and these lookups on the mask
channel (`MASK_TAG`, a fixed constant):

- `i < n-1`: push `(MASK_TAG, out_a, out_b)` with multiplicity `s`.
- `i > 0`: pull `(MASK_TAG, in_a, in_b)` with multiplicity `s`.

The prover fills row 0 with `s = 1`, `out = ρ_i` (two fresh uniform base-field
elements from the config's CSPRNG) and `in = ρ_{i-1}`; every other row is zero.
Then:

`next_acc_i = genuine_i + 1/(β + fp(MASK_TAG, ρ_i))` for `i < n-1`, and the last
accumulator is unchanged (0). Each published intermediate value carries an
independent offset that depends on a 128-bit secret held only in the blinded
stage-1 trace.

**Soundness.** Mask messages are ordinary lookup messages with a distinct tag.
Pushes and pulls on the mask channel cancel exactly when the prover is honest.
A cheating prover can set `s` and the `ρ` columns freely, but mask-channel
messages differ from every genuine message unless fingerprints collide
(probability ≤ N/|F_ext|, already in the soundness bound), so the mask channel
can only cancel itself. Any imbalance on it leaves the final accumulator
nonzero. No new constraint, no new trust.

**Cost.** Five base columns per circuit plus two or one extra lookups per
circuit. Negligible against the Blake3 trace.

**Callers unchanged.** Aiur builds `SystemWitness` without the mask columns; the
prover appends the columns and their lookup values before committing. Plain
(non-ZK) configs and single-circuit systems are untouched.

## Tasks

1. **Red.** In the fork, a test that proves the two-circuit lookup system under
   ZK, replays the transcript to recover β and γ, recomputes circuit 0's
   accumulator from the known witness, and asserts it does not equal the
   published `intermediate_accumulators[0]`. Fails today (they are equal).
2. **Green.** `StarkGenericConfig::sample_mask(&self, n) -> Vec<Val<Self>>`
   (plain configs: empty), backed by the ZK config's shared CSPRNG.
   `LookupAir.extra_width`; `System::new` adds the mask columns and lookups
   under ZK when there are ≥ 2 circuits; the prover appends columns and lookup
   values. All existing tests stay green.
3. **Soundness test.** A ZK proof where the prover tampers with one mask value
   (a pull that does not match the previous push) must fail verification.
4. Clippy, fmt, push the fork; re-pin ix (`cargo test -p aiur`), re-pin
   zkip-stark, run the 11 correctness executables and the timing sweep.
5. Docs: README, architecture, REMEDIATION O3 and the multi-stark module doc
   drop the accumulator residual; the trace-height residual stays.
6. Review: hermes-local, escalate to gpt-5.4 on any flag; fresh-context review
   of the fork diff.
