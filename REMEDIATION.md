# Remediation Plan

This document records the gap between what ZKIP-STARK claims and what it
implements, and tracks the work needed to close it.

It exists because the repository previously described itself as "production
ready" and "formally verified" while containing no working cryptography. That
combination is worse than an incomplete project — it invites someone to trust an
artifact that means nothing. Every item below must be closed before any security
claim is restored to the README.

**Current state: early prototype. Not usable, not secure, not a ZK system.**

---

## How to confirm the state of this repository in 30 seconds

```bash
grep -rn "Aiur.Term.ret" ZkIpProtocol/     # every circuit body
grep -rc "theorem\|lemma" --include=*.lean . | awk -F: '{s+=$2} END {print s}'   # → 0
```

Every circuit returns a constant or echoes an input. There are no theorems.

---

## Circuit inventory

All nine circuits in the repository are placeholders. None expresses a single
constraint over its inputs.

| Circuit | Location | Body | Should do |
|---|---|---|---|
| `predicateCheck` | `STARKIntegration.lean:70` | `ret attr` | Prove `attr ≥ threshold` and a Merkle path to a public root, revealing only a boolean |
| `batchedPredicateCheck` | `Batching.lean:123` | `ret attr0` | The same, for N attributes in one proof |
| `verifyFRI` | `FRIVerification.lean:128` | `ret 1` | Verify FRI folding, Merkle paths, and final-polynomial degree |
| `merkleReconstruct` | `MerkleReconstruction.lean:100` | `ret 1` | Recompute a root from leaf + path and compare |
| `merkleVerify` | `MerkleReconstruction.lean:207` | `ret 1` | As above |
| recursive verifier | `RecursiveProofs.lean:104` | `ret 1` | Verify an inner STARK proof inside the circuit |
| full recursive verifier | `FullRecursiveVerification.lean:112` | `ret 1` | As above, complete |
| `poseidonHash` | `HashConstraints.lean:94` | `ret 0` | Poseidon permutation as constraints |
| `merkleHash` | `HashConstraints.lean:154` | `ret 0` | `hash(left ‖ right)` as constraints |

`verifyFRI` and the recursive verifiers returning `1` is the most severe of
these: they accept unconditionally, so any recursion built on them is
unconditionally "valid".

---

## Blocking defects

### R1 — The hash function is the identity function
**Severity: critical. Breaks both hiding and binding.**

`CoreTypes.lean:17` defines `Hash.hash b := b`, and `NoCapFFI.lean:28` defines
`hashPair l r := l ++ r`. Therefore `buildMerkleTree` (`MerkleCommitment.lean:14`)
returns **the concatenation of every leaf**.

The "Merkle root commitment" is the plaintext dataset. It hides nothing, binds
nothing, and grows linearly with the input.

**Fix:** implement Poseidon (or Rescue-Prime) over Goldilocks, both as a native
function and as in-circuit constraints. Everything else depends on this.

---

### R2 — Circuits enforce no constraints
**Severity: critical. Proofs attest to a trivially true statement.**

See the inventory above. The threshold comparison, the Merkle path check, and
the FRI check are all absent.

**Fix:** implement the predicate circuit first — range-check the comparison,
verify the Merkle path against a public root, emit only a boolean. Depends on R1.

---

### R3 — The witness is published in the public claim
**Severity: critical. There is no zero-knowledge property.**

`AiurSystem.prove` takes a single flat `args` list with no witness/public split;
everything in it enters the public claim. `STARKIntegration.lean:115` passes
`publicInputs ++ privateInputs`, and line 133 copies the whole claim into the
certificate's `publicInputs` field. The secret is published twice — once as an
argument, once as the circuit output (`ret attr`).

The repository's own `CircuitABI.totalClaimSize`
(`2 + private + public + output`) concedes this.

`SECURITY_VALIDATION.md` documents a guard against exactly this leak, but
`validatePrivatePublicSeparation` (`Api.lean:171`) only inspects the
locally-constructed `publicInputs` array — not the claim that actually ships. It
checks the wrong object and always passes.

**Fix:** use a proving interface with a real witness/public distinction. This
may require changes to how Aiur is invoked, not just to this repository. Until
then, no configuration of this code is zero-knowledge.

---

### R4 — Proof generation fails open
**Severity: high.**

`STARKIntegration.lean` — on proof-generation failure, `generateCertificateWithSTARK`
returned `some certificate` carrying `proofData := ByteArray.empty` and
`vkId := "mock_vk_generation_failed"`. Callers matching on `some` accepted it.

**Status: fixed in this branch.** The function now returns `none` on failure.
Uncompiled — see "Verification status" below.

---

### R5 — The verifier ignores the public inputs it is given
**Severity: high. Makes the Ad-Switch test vacuous.**

`verifySTARKProof` took `_publicInputs` and discarded it, rebuilding the claim
from the proof itself — so a proof attested to whatever it said it attested to.
It also verified with `numQueries := 20` against proofs generated with
`numQueries := 100`.

`testAdSwitchResistance` (`Tests/Validation/SoundnessTests.lean:92`) therefore
could not fail: the verifier never consults the root it is handed.

**Status: partially fixed in this branch.** The verifier now checks the
caller-supplied public inputs against the claim prefix and uses matching FRI
parameters, and both sides derive those inputs through one shared function
(`predicatePublicInputs`). It remains vacuous until R2 lands, because the
circuit does not bind the root to anything.

Related wart, not addressed: `generateCertificateWithSTARK` takes a
`[Hash ByteArray]` instance binder while `verifyCertificate` resolves the global
instance. A caller supplying a different instance would make prover and verifier
disagree about the root. There is only one instance today, so this is latent —
but the binder should be dropped, or threaded through both sides, when R1 lands.

---

### R6 — Most of the repository does not compile
**Severity: high. Masked by the build configuration.**

`lake build` builds only `@[default_target] lean_lib ZkIpProtocol`, whose root
imports six modules. These seven are never compiled:

`ZKMB.lean`, `Batching.lean`, `FRIVerification.lean`, `HashConstraints.lean`,
`MerkleReconstruction.lean`, `RecursiveProofs.lean`, `FullRecursiveVerification.lean`

Known errors in `ZKMB.lean` alone:
- `MerkleProof` built with a `leafIndex` field (real fields: `rootHash`, `path`, `isLeft`) — line 254
- `STARKProof` built without its required `vkId` — line 309
- `AiurSystem.build` called with wrong arity and treated as `Except` — lines 341, 389
- `Batching.BatchedPredicateCircuit` — namespace does not exist — line 331
- `p.attributes.attributeValues` on an `Array IPAttribute` — line 323

Six of eleven test targets use the same nonexistent `leafIndex` field
(`STARKTests`, `STARKRoundTripTests`, `SoundnessTests`, `ThroughputBenchmarks`),
and `ZKMBLatencyTests.lean:123` has unreachable code after a `match`.

**Status: `leafIndex` mismatches fixed in this branch.** The structural errors in
`ZKMB.lean` are not — that module needs rewriting once R1–R3 land.

---

### R7 — CI reported success on unbuilt code
**Severity: high — this is what allowed R1–R6 to persist.**

The workflow ran `lake build` (six modules), `lake build Main`, and one test
target guarded by `continue-on-error: true`. Nothing that failed could turn the
badge red.

The "no `sorry`" gate is vacuous: there are no proofs, so there is nothing to
leave incomplete. It reads as evidence of verification and is not.

**Status: fixed in this branch.** CI no longer swallows failures, and builds
every target. It is expected to be **red** until R6 is fully closed — that is the
correct signal.

---

### R8 — No formal verification
**Severity: high as a claim; the code is merely unproven.**

Zero `theorem` or `lemma` declarations. "Formally verified" meant Lean's type
checker plus `termination_by` on two recursive functions.

**Fix:** after R1–R3, state and prove soundness and zero-knowledge properties.
This is the largest item here and the only one that would justify the original
claim.

---

### R9 — Benchmarks measure stubs
**Severity: medium as code; high as published claims.**

The withdrawn figures (sub-3ms, 300–500 proofs/sec, constant ~162 KB over 1,000
recursive transitions) came from timing placeholder functions.
`testSingleProofLatency` (`Tests/Validation/ZKMBLatencyTests.lean:26`) measures
`ZKMB.verifyPacket`, whose body is `true`.

**Status: claims withdrawn from docs in this branch.** Republish only after
R1–R3, with the suite compiling and running in CI on a declared machine.

---

### R11 — Claim serialisation did not round-trip
**Severity: high. Verification could never succeed.**

`CoreTypes.natToByteArray` produces a *minimal-length* big-endian encoding, but
every reader (`verifySTARKProof`, `Api.handleVerify`) requires at least 8 bytes
and reads exactly the first 8. A claim element below 2^56 serialises to fewer
than 8 bytes and is then rejected outright by the reader.

Since claim elements are ordinary small values — a truncated root, a threshold,
an attribute — essentially every proof failed to deserialise. Combined with R4,
which returned a mock certificate on failure, this went unnoticed.

**Status: fixed in this branch.** Claim elements are now encoded at fixed
8-byte width via `natToByteArray8`. `natToByteArray` is retained for Merkle
leaves, where variable width is fine.

---

### R10 — Hardware acceleration never existed
**Severity: low — now documented accurately.**

Both branches of `poseidonHashFFI` (`NoCapFFI.lean:36`) call the same software
stub, and `HardwareCtx.create` always returns `none`. No hardware path has ever
executed.

---

## Suggested order of work

R1 (real hash) → R2 (real circuits) → R3 (witness separation) → R6 (make it all
compile) → R9 (honest benchmarks) → R8 (formal proofs).

R4, R5, R7, R10 are addressed or documented in this branch and are not blockers.

Realistically this is a rewrite of the cryptographic core. The type definitions,
module structure, and API surface are the reusable parts.

---

## Verification status of this branch

The Lean changes in this branch **have not been compiled.** The environment in
which they were written could not reach `release.lean-lang.org` to install a
toolchain, so `lake build` was never run.

They are deliberately small, local, and conservative for that reason. Treat them
as needing review and a green build before merge. The documentation changes carry
no such risk.
