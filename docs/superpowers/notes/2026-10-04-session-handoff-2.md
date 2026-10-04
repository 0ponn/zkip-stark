# Session handoff, 2026-10-04 (second session)

Follows `2026-10-04-session-handoff.md`.

## State

| repo | branch | head |
|---|---|---|
| zkip-stark | main | fd1f197 |
| 0ponn/ix | zk | 441fce5 |
| 0ponn/multi-stark | zk-hiding-pcs | 2788bff |

Everything is merged and pushed. CI is green on main, including API
Integration Tests (53 s), which had never run real proofs before.

## Shipped

- **M9, PR #11.** The ZK minimum trace height follows Plonky3 PR #2100's
  hiding budget, `next_pow2(2 · (D · 2 + num_queries))`, which is 256 rows at
  100 queries. The old rule gave 128, and 28 of 38 circuits sat below the
  budget. Proof cost did not change: 1711 ms prove at 8 threads, 34 ms
  verify, 8.98 MB. Plan: `docs/superpowers/plans/2026-10-04-m9-hiding-budget.md`.
- **Cross-process verification, PR #12 (critical).** Since M6, a
  certificate verified only in the process that proved it: the preprocessed
  commitment in the verifying key was salted from the live RNG. The fix
  (multi-stark 2788bff) commits the preprocessed traces through a second
  hiding PCS that salts from a fixed public seed
  (`StarkGenericConfig::preprocessing_pcs`, `SharedRng::fixed`).
- **The API test job could not fail, PRs #12 and #13.** `test_all.sh` used
  stale requests and counted an unverified honest certificate as a pass. The
  workflow took its exit status from tee, read the ANSI-colored failure count
  as 0, and ran under `continue-on-error`. Once real proofs ran, the 18 MB
  bodies it printed (54 MB of log per run) stalled the job. All fixed: it now
  runs under pipefail, prints at most 500 characters per body, and has a
  20-minute job limit.
- A false predicate returns 400 instead of 500. The API checks live in
  `PredicateSoundness`, which includes a mixed batch.
- The `isoc23Shim` is built with `buildO`, so links are cached.
- The withdrawn-claims CI filter passes a hit only when a negation precedes
  the claim.
- Upstream issue argumentcomputer/multi-stark#89 asks whether they want an
  opt-in ZK mode. No reply yet.

## Open, needs the operator

1. ~~Post the correction on #89~~ Posted 2026-10-04 (
   `docs/superpowers/notes/2026-10-04-multi-stark-89-correction.md`). It
   says Plonky3 already fixed the short-trace flaw and adds the
   verifying-key fix.
2. Bind the attribute type and name into the leaf. This breaks existing
   certificates, and you need to decide whether the verifier learns which
   attribute is being proved.
3. The K > 1 batch API. Each K needs its own calibrated trace shape, and the
   request format is your call.

## Open, no decision needed

- The ix Lean in-circuit verifier still cannot verify fork proofs. zkip-stark
  does not use it.
- Plonky3's `get_quotient_ldes` spin lock (Aiur does not trigger it).
- The forks' proofs are not wire-compatible with upstream.

## Risks

- The ZK argument has had model review only. The trace floor now matches
  Plonky3's audited bound, but Plonky3 does not document where its factor
  of two comes from.
- Certificates proved before #11 and #12 do not verify. Nothing persisted
  them.

## Gotchas (also in engram)

- `gh pr checks --watch` exits 0 on CANCELLED. Check every conclusion before
  merging. #12 merged with its API job cancelled.
- Test verification across processes with independently built systems.
  Same-process tests hid the verifying-key bug from M6 onward.
- `lake-manifest.json` is gitignored, so `lakefile.lean` holds the ix pin.

## Later the same session

| repo | branch | head |
|---|---|---|
| zkip-stark | main | c6af211 |
| 0ponn/ix | zk | 441fce5 (unchanged) |
| 0ponn/multi-stark | zk-hiding-pcs | 2788bff (unchanged) |

- **#89 correction posted** (operator approved). No maintainer reply yet. The
  most active committers are arthurpaulino, samuelburnham and gabriel-barrett.
  Plan: wait about a week, then @-mention them; failing that, send the small
  PR (floor plus reproducible verifying key).
- **M10, PR #16.** The leaf is `attrIdOf label ++ value`, and the attribute id
  is public. Certificates name their attribute; relabelling fails.
- **M11, PR #17.** Up to 8 disclosures per certificate, in one proof.
  `"disclosures"` is the certificate format. There is a per-entry-size trace
  shape, calibrated lazily on a synthetic sparse tree. gpt-5.4 review: none.
- **Review packet, PR #18.** `docs/security-review-packet.md`, linked from
  the README. It is ready to send to a cryptographer.
- Completeness estimate: about 75% (was 66%). Most of the rest needs outside
  people: the forks need upstream, and the ZK argument needs a person's
  review.

### Next

1. The operator picks reviewers for the packet (ZK Hack Discord for a free
   first look; the eprint 2024/1037 authors; an audit firm for a formal
   report).
2. Around 2026-10-11, if #89 is still quiet, @-mention the maintainers (the
   draft needs operator approval).
3. Optional, no outside dependency: a long-running server with auth, about a
   day.

### Risks

- The duplicate-label ambiguity is documented, not enforced.
- PredicateSoundness takes about 90 s at 8 threads; CI has room (45 min).
