# Session handoff, 2026-10-03/04

## State

All work is merged and pushed. Nothing is in flight.

| repo | branch | head | working copy |
|---|---|---|---|
| `0ponn/zkip-stark` | `main` | `7a5bd6e` | `/home/mlayug/Documents/0pon/zkip-stark` |
| `0ponn/ix` (fork) | `zk` | `3c66884` | `/home/mlayug/Documents/0pon/ix` |
| `0ponn/multi-stark` (fork) | `zk-hiding-pcs` | `f0687bd` | `/home/mlayug/Documents/0pon/multi-stark` |

zkip-stark pins ix by commit in `lakefile.lean` (the manifest is gitignored);
ix pins multi-stark by rev in its `Cargo.toml`.

## What shipped (PRs #8 and #9)

1. **Verify hardening.** Malformed `proofData` no longer aborts the server
   (checked decoder backported into the ix fork); the u32 guard moved into
   `verifySTARKProof`, closing a Goldilocks wrap.
2. **M5, commitment bound.** Production proves the fused predicate +
   Merkle-membership circuit; the claim carries the full 256-bit root.
   `/generate` takes `attributeIndex`, recomputes the root, and rejects bad
   input with 400s.
3. **M6, zero-knowledge.** Plonky3 `HidingFriPcs` through the multi-stark
   fork. Traces are padded to at least 128 rows (a review recovered a 4-row
   trace from one proof before this).
4. **M7, accumulators masked.** A secret push/pull pair per circuit link on a
   dedicated lookup channel; mask-tagged claims are rejected.
5. **M8, fixed trace shape.** Every proof is padded to a calibrated depth-16
   worst case, so published heights never vary; depth is capped at 16
   (65,536 attributes).

No known witness leak remains in the proof. Cost against the plain prover:
prove 0.3 s to 1.7 to 1.8 s, verify about 2x, proof 4.8 MB to 9.0 MB.

## Verified

- multi-stark fork: 41 tests with and without `parallel`, clippy clean.
- ix fork: `cargo test -p aiur`, `ix-ffi` builds, clippy clean.
- zkip-stark: 15 executables build; the 11 correctness executables pass,
  including `PredicateSoundness` (commitment swap, threshold wrap, operator
  relabel, garbage proof, depth 0/5/8/16, blinding liveness, fixed shape,
  depth cap). PR #9's fresh-clone CI build passed.
- Reviews per milestone: code-review agent or fresh-context reviewer, gpt-5.4
  on every disputed or cryptographic point, local Hermes on each diff.

## Open, in priority order

1. **Offer the forks upstream.** Zero-knowledge, accumulator masking and the
   minimum-height guard are general fixes for argumentcomputer/multi-stark and
   ix; Plonky3's batch-stark has the same short-trace flaw. Keeping two forks
   in step with upstream is the main ongoing cost.
2. **ix recursion path.** ix's Lean in-circuit verifier
   (`Ix/MultiStark/SystemDeserialize.lean`, `Verifier.lean`) does not read the
   fork's verifying-key fields or the ZK transcript tag. zkip-stark does not
   use it.
3. **Product gaps.** K>1 batch disclosure through the API (circuit entries
   exist); attribute type and name are not in the leaf (only the value is
   committed); no replacement for the deleted `Tests/ApiTests.lean`.
4. **Deferred minors.** A false predicate returns 500 instead of 400; batch
   returns 200 with per-entry errors; the CI withdrawn-claims filter is loose;
   Plonky3's `get_quotient_ldes` spin lock could deadlock if two proves on one
   config run as rayon jobs (Aiur does not); the forks' proofs are not
   wire-compatible with upstream; `isoc23Shim` in `lakefile.lean` rebuilds
   every time.
5. **GPU** stays parked (M4 decision).

## Risks

- The zero-knowledge argument has had model and cross-model review, not a
  cryptographer's. The non-trivial claims are written down in `REMEDIATION.md`
  O3 and the multi-stark verifier module docs.
- The fixed trace shape is calibrated empirically. The prover refuses any
  proof whose shape differs, so a miss costs completeness, never privacy.
- Proving is about 1.7 s per certificate on CPU.

## Gotchas learned this session (also in engram)

- Push dependency forks to the GitHub remote and confirm the pinned commit
  exists (`gh api repos/<o>/<r>/commits/<sha>`); a green local Lake build
  proves nothing about fetchability.
- Never chain `grep` on build output into `&& git commit`; use `set -e` and
  exit codes.
- After a kernel update, stale `-Ctarget-cpu=native` Rust artifacts can
  SIGILL; `cargo clean` in `.lake/packages/ix`. Ollama can start before the
  NVIDIA module; a user-service drop-in now waits for `/dev/nvidia0`.
- Importing `Ix.Aiur.Meta` (via `MerkleCircuit`) makes bare `G` a keyword;
  write `Aiur.G`.
