# Remediation Tracker

A running ledger of the gap between what this repository claims and what it
implements, kept because that gap was once very large and closed quietly.

Before this branch, the project described itself as "production ready" and
"formally verified" while every circuit was a stub returning a constant, the
hash function was the identity function, the witness was published in the public
claim, and seven of thirteen modules did not compile. None of that was visible
from the README or a green CI badge.

The purpose of this file is to make the next such gap loud. Add an entry when
you find one; close it only when the code, not the plan, says so.

---

## Verify the state of the tree in 30 seconds

```bash
# Circuit bodies. A body that is a bare constant enforces nothing.
grep -rn "assert_eq!\|Term.ret" ZkIpProtocol/

# Formal proofs. Zero means "type-checked", not "verified".
grep -rc "theorem\|lemma" --include=*.lean . | awk -F: '{s+=$2} END {print s+0}'

# What actually reaches the shipped API, as opposed to a test executable.
grep -rn "fusedEntry\|merkle_predicate_batch1" ZkIpProtocol/   # the API path proves the fused circuit
```

---

## Open

### O3 — Zero-knowledge (blinding shipped by M6, 2026-10-03; one residual)
**Severity now: medium, for the residual below.**

The STARK was a plain argument of knowledge (`multi-stark` committed traces
unblinded). M6 forks `multi-stark` to `0ponn/multi-stark` (branch
`zk-hiding-pcs`) and proves with Plonky3's `HidingFriPcs`, salted Merkle
leaves (a `Sync` port of `MerkleTreeHidingMmcs`), randomized quotient chunks
and a random FRI-batch polynomial; Aiur in `0ponn/ix` (branch `zk`) proves
with it. Verified by: the fork's 35 tests including ZK twins of every
end-to-end test, a missing-randomization rejection, a cross-config rejection
and a randomization-liveness test; and zkip-stark's `blindingLiveCheck`.

**Review (2026-10-03):** a fresh-context review recovered a 4-row trace
exactly from one ZK proof: the hiding PCS adds only h random rows, and 100
FRI openings plus two out-of-domain points determine any trace shorter than
about 102 rows. Fixed: multi-stark refuses traces below
`next_pow2(num_queries + 2)` and the verifier rejects them; Aiur pads every
function and memory trace to that floor. gpt-5.4 confirmed the bound is
sufficient for the trace and quotient chunks and that zero padding does not
weaken hiding. Also fixed from the same review: the ZK config constructor now
wraps any CSPRNG in one shared stream (cloned seeded generators would have
published blinding values in the opened salts), and a pre-existing verifier
panic on truncated preprocessed openings.

**Accumulators masked (M7, same day):** the public intermediate lookup
accumulators let anyone who guessed a circuit's lookups confirm the guess
(`zk_accumulators_do_not_confirm_witness` reproduced this bit for bit). Under
ZK each circuit now pushes a secret 128-bit message on a dedicated `MASK_TAG`
lookup channel and the next circuit pulls it, offsetting every published
accumulator by a secret. Soundness is unchanged because mask messages cannot
cancel genuine ones (their tag differs from every genuine channel, which Aiur
pins to constants 0 to 12 through boolean selectors); an unbalanced mask is
rejected (`zk_unbalanced_mask_rejected`). The local Hermes lane claimed an
attack; gpt-5.4 adjudicated for soundness and confirmed perfect hiding.
A fresh-context review then found that a *claim* starting with `MASK_TAG`
could be balanced by the unconstrained mask channel; the verifier now rejects
such claims (`zk_mask_tag_claim_rejected`). zkip-stark was never exposed (it
pins the claim to `[0, funIdx, ...]`), but the fork is general-purpose.

**Residual:** each circuit's trace height is public, revealing call counts
above 128 (rounded to a power of two). Recovering the attribute from them means guessing a circuit's
whole message multiset, but the channel exists. Masking them is follow-up
work. Also: FRI-batch randomization is statistical ZK, as in Plonky3, and
ix's in-circuit recursive verifier was not ported to the ZK transcript.

---

### O6 — Catch-all mislabelled as a stack overflow
**Severity: low.**

`generateSTARKProof`'s `catch ex => debugLog s!"Stack overflow in generateSTARKProof: {ex}"`
catches every exception and reports all of them as stack overflow, then returns
`none`. Since a `none` is now (correctly) a hard failure rather than a mock
certificate, the misleading label costs debugging time. Log the exception
without asserting its cause.

---

### O7 — Docs and CI drift
**Severity: low, but it is the mechanism behind O2.**

`.github/workflows/multi-tool-integration.md` still called the workflow
"Production-ready", and `docs/workflow-for-decision-makers.md` still offered a
sub-3ms latency criterion tied to the deleted NoCap path. Both corrected in this
commit, and a `claims-audit` CI job now fails if either reappears.

---

## Closed by this branch

Recorded so the history is not re-litigated. All were open on `main` at 801fa9f.

| | Defect | How it was closed |
|---|---|---|
| C1 | `Hash.hash` was the identity function, so the "Merkle root" was the concatenated plaintext | Replaced with Blake3 (`Address.blake3`) |
| C2 | Every circuit body returned a constant or echoed an input | Real `assert_eq!`-constrained predicate and Blake3 Merkle circuits |
| C3 | The witness was passed in `args` and published in the claim, twice | Read via private IO channel; `args` carries public inputs only |
| C4 | Proof failure returned a mock certificate with empty `proofData` | Returns `none` |
| C5 | Verifier ignored caller public inputs and rebuilt the claim from the proof | Binds claim args to caller inputs, **and** rejects arity mismatch so an empty array cannot vacuously match |
| C6 | Prover used `numQueries := 100`, verifier `20` | Single shared `starkFriParams` |
| C7 | `natToByteArray` was minimal-length but every reader required ≥8 bytes, so verification could never succeed | Fixed-width `natToBytes8BE` |
| C8 | Seven modules and six test targets did not compile, excluded from the default target | Deleted rather than patched; all remaining targets build |
| C9 | Benchmarks timed stub functions | Real measurements on declared hardware, `Tests/Validation/CpuBaseline.lean` |
| C10 | No range checks at the `Nat` → field boundary | Guards before `G.ofNat` and before the prover, with the `u32` domain enforced |
| O1 | The shipped certificate path proved the M1 predicate-only circuit; `commitment` was carried alongside the proof, not bound by it | M5 (2026-10-03): `generateCertificateWithSTARK` proves `merkle_predicate_batch1` with the eight root words as public inputs; the verifier derives the full 12-element claim from the certificate's threshold and commitment. `commitmentSwapCheck`, `apiRoundTripCheck`, `depthCoverageCheck` in `Tests/Validation/PredicateSoundness.lean` |
| O2 | README and architecture docs described a ~64-bit root binding that did not exist | Rewritten to describe the shipped 256-bit binding and the unproven hiding property |
| O4 | `verifyMerkleCommitment` and `verifyAttributeInMerkleTree` compared a value to itself | Deleted with `PredicateCircuit`; membership is enforced in-circuit |
| O5 | `[Hash ByteArray]` binder on `generateCertificateWithSTARK` could desync prover and verifier | Binder removed; both sides use the global instance |

C5's arity check deserves specific credit: comparing a zero-length caller array
against a zero-length claim slice succeeds vacuously, which is a genuinely easy
bug to ship. It was anticipated here rather than found later.

---

## Suggested order

O3: blinding and accumulator masking shipped; trace heights are the remaining residual. O6 and O7 are cleanup and can go at any time.
