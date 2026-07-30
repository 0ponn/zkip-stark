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
grep -rn "merkle_predicate\|predicate_check" ZkIpProtocol/ Tests/
```

---

## Open

### O1 — The shipped certificate path has no Merkle-root binding
**Severity: high. This is the ad-switch attack, still open on the API path.**

The M2b fused circuit `merkle_predicate` (`ZkIpProtocol/MerkleCircuit.lean`) does
close ad-switch, and the construction looks sound: the same four bytes read on
channel 0 are both recomposed into the field element fed to
`u32_less_than(threshold, attr)` and hashed as the leaf preimage, with
`assert_eq!(ll, 4)` constraining the stream length so the leaf cannot be padded
to decouple the two. The root is bound across eight `u32` words, so the full
256-bit digest participates.

**But nothing outside `Tests/Validation/` calls it.** The shipped path —
`Api.lean` → `generateCertificateWithSTARK` → `PredicateCircuit.toAiurBytecode` —
compiles the M1 `predicate_check(threshold) -> G`, whose only public input is the
threshold. `Api.lean` sets `expectedPublicInputs := #[G.ofNat predicate.threshold]`
and its own comment confirms "there is no Merkle-root public input in M1".

So a certificate issued by the API proves `attr > threshold` for *some* attr,
with no binding to the advertised commitment. The `commitment` field on
`ZKCertificate` is carried alongside the proof, not bound by it.

**Fix:** route the certificate path through `merkle_predicate` (or the
variable-depth `batch_item`), and pass the eight root words as public inputs.
Until then the ad-switch claim should not appear in user-facing docs unqualified.

---

### O2 — Documentation claims a root binding that does not exist
**Severity: high, because this is the exact failure mode the branch set out to fix.**

Three statements about the same thing disagree, and the two user-facing ones
overstate:

| Source | Says |
|---|---|
| PR #4 description | "the **ad-switch attack is closed**" |
| `README.md` Security Properties | "the STARK proof binds the Merkle root as a public input, but ... only **~64 bits strong**" |
| `STARKIntegration.lean` / `Api.lean` comments | "the Merkle root is **NOT** part of the circuit's ABI yet" |

The code comments are the accurate ones. The README describes a ~64-bit root
binding inherited from the pre-M1 design that the M1 rewrite removed; there is
now no root in the claim at all. The README's caveat therefore understates the
gap while appearing to be a careful disclosure.

**Fix:** correct the README and PR description to describe the shipped path, and
state that ad-switch closure exists as a validated circuit not yet wired into the
API. Reword once O1 lands.

---

### O3 — Hiding is unproven; "not in the claim" is not "zero-knowledge"
**Severity: high as a claim. Correctly flagged in the PR body; recorded here so it is not lost.**

Keeping `attr` out of `args` and out of the claim is necessary for
zero-knowledge and is a real improvement over publishing it. It is not
sufficient. The witness still occupies trace cells, and a FRI-based STARK only
hides it if the protocol is explicitly ZK-blinded (masking polynomials, blinded
commitments). Many production STARKs are succinct arguments without that
blinding.

Until it is established whether Aiur blinds, the defensible claim is
**"the witness is not a public input"**, not "zero-knowledge". The repository
name and the phrase "without revealing sensitive data" both promise the latter.

**Fix:** determine whether `ix`'s STARK is ZK. If it is not, either add blinding
or restate the protocol's guarantee honestly across the docs.

---

### O4 — Two vacuous checks remain on the certificate path
**Severity: medium.**

- `PredicateCircuit.verifyMerkleCommitment` compares
  `circuit.merkleProof.rootHash == circuit.merkleRoot`, but
  `generateCertificateWithSTARK` constructs that proof with
  `rootHash := ixon.merkleRoot`. It compares a value to itself and cannot fail.
- `verifyAttributeInMerkleTree` is documented as checking membership but returns
  `proof.rootHash == root` — the same tautology, with the path ignored.

Neither is load-bearing today, but both read as membership checks and will be
mistaken for the real thing. Delete them or replace them with the M2a
`verifyProof` reference implementation.

---

### O5 — `[Hash ByteArray]` instance asymmetry
**Severity: low, latent.**

`generateCertificateWithSTARK` takes a `[Hash ByteArray]` instance binder while
`verifyCertificate` resolves the global instance. A caller supplying a different
instance would make prover and verifier disagree about the root. Only one
instance exists today, so this is latent — drop the binder, or thread it through
both sides.

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

C5's arity check deserves specific credit: comparing a zero-length caller array
against a zero-length claim slice succeeds vacuously, which is a genuinely easy
bug to ship. It was anticipated here rather than found later.

---

## Suggested order

O1 (wire the fused circuit into the API) → O2 (correct the docs to match) →
O3 (settle the hiding question) → O4 (delete the tautologies).

O5–O7 are cleanup and can go at any time.
