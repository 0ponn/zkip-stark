# 2026-10-03: branch review + verify-path hardening

Review of `gpu-proving-backend` (30 commits ahead of `main`) by the code-review
agent, confirmed by gpt-5.4 via Hermes. Three correctness findings; two fixed
here, one parked.

## Fixed

1. **Remote abort on garbage `proofData`.** `verifySTARKProof` called
   `Aiur.Proof.ofBytes` first thing. Its Rust side is
   `.expect("Deserialization error")` and ix builds with `panic = "abort"`, so
   a `/verify` POST with malformed hex killed the server; Lean `try/catch`
   cannot intercept it. Fix: ix is now pinned to `0ponn/ix@794037e`, which is
   upstream `a75cb04` plus a 28-line backport of upstream #598's
   `Aiur.Proof.ofBytesChecked : ByteArray -> Except String Proof`. Decoding
   now happens after the arity, claim-size and claim-arg rejects, and a
   decode error is an ordinary `verified: false`.
2. **Goldilocks wrap in `verifyCertificate`.** `Advertisement.verifyCertificate`
   converted the certificate threshold with `G.ofNat` and no range guard;
   `handleVerify` had the guard, the library entry point did not.
   `G.ofNat` goes through `Nat.toUInt64`, so `T + 2^64` verified as `T`.
   Fix: `verifySTARKProof` now takes `Array Nat` and rejects anything
   `>= 2^32` itself; the per-handler guard in `Api.lean` is deleted.

Tests: `apiVerifyGarbageProofCheck` and `verifyCertificateThresholdWrapCheck`
in `Tests/Validation/PredicateSoundness.lean`. Both watched red (SIGABRT,
exit 134; and "wrapped to 1000 and verified") before the fix.

## Parked (not in this unit)

- ~~Merkle commitment is not bound by the proof.~~ Closed by M5 the same day
  (`docs/superpowers/notes/2026-10-03-m5-handoff.md`).
- ~~`AiurSystem.build` reruns per request.~~ Closed by M5 (`fusedSystem` cache).
- `Tests/ApiTests.lean` was deleted on this branch with no replacement
  (partly covered now by the API checks in `PredicateSoundness`).
- `isoc23Shim` in `lakefile.lean` recompiles every build and never on
  source change.
- ~~Test harness helpers duplicated across six validation tests.~~ Closed by M5.

## Toolchain gotchas hit on the way

- Cached Rust artifacts (July) were built with ix's `-Ctarget-cpu=native`
  while this CPU exposed AVX-512; it no longer does, so rustc, build scripts
  and the old test binaries all died with SIGILL (`vpbroadcastq %rbp,%ymm0`).
  `cargo clean` in `.lake/packages/ix` fixes it.
- `lake build` with no target builds only `ZkIpProtocol`; name the test
  executables or you run stale binaries.
- `lake-manifest.json` is gitignored, so the old `@ "main"` require was
  unpinned on a fresh clone. The lakefile now pins ix by commit sha.
