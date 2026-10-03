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

### O3 — The proof is not zero-knowledge (settled 2026-10-03)
**Severity: high as a claim. Settled: the STARK is a succinct argument, not a ZK proof.**

`multi-stark@2c01922` documents it in `src/verifier.rs`: traces are committed
without blinding and FRI query responses reveal low-degree-extension values of
the witness. The attribute is absent from the public claim (`leakCheck`), so a
party seeing only `(threshold, commitment, verified)` learns nothing beyond the
predicate; a party holding the proof bytes must be assumed able to recover the
witness. Full analysis and the path to blinding (Plonky3's `HidingFriPcs`
exists at the pinned rev; `multi-stark` would have to adopt it) in
`docs/superpowers/notes/2026-10-03-o3-hiding.md`.

**State of the docs:** README and `docs/architecture.md` now say exactly this.
Do not describe the protocol as zero-knowledge, and do not publish proof bytes
beyond the verifier, until `multi-stark` blinds and this is re-verified.

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

O3 is settled (not ZK; docs restated). The remaining work is upstream blinding
in `multi-stark`. O6 and O7 are cleanup and can go at any time.
