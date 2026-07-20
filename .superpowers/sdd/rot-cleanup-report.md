# 0PO-552 — P0-era rot cleanup report

Worktree: `/home/mlayug/Documents/0pon/zkip-stark/.claude/worktrees/agent-a09c696bb3f629f73`
Branch: `worktree-agent-a09c696bb3f629f73` (fast-forwarded from stale `801fa9f` to `gpu-proving-backend` tip `c9e1348` first — the worktree had been created before 36 commits of real M1-M3 work landed; see Setup Note below).

## Setup note

This worktree's branch was created off an old base (`801fa9f`), 36 commits
behind `gpu-proving-backend` (`c9e1348`), so none of the M1-M3 real test
files (`Tests/HashTests.lean`, `Tests/Validation/PredicateSoundness.lean`,
etc.) existed here initially. Fast-forwarded (`git merge --ff-only
gpu-proving-backend`) before starting — safe because the worktree branch
had zero unique commits ahead of the merge base.

## Inventory (compiles? / used by real system? / deleted?)

Verified each file by direct `lake build <target>` (not just import
inspection), with a copied `.lake` build cache to make iteration fast.

### Confirmed broken, never compiled — deleted

| File | Compiles? | Failure |
|---|---|---|
| `ZkIpProtocol/ZKMB.lean` | No | `bad import 'Ix.Aiur.Bytecode'`, `'Ix.Aiur.Term'`, `'Ix.Aiur.Simple'`, `'Ix.Aiur.Compile'` — none of these ix modules exist |
| `ZkIpProtocol/StringMatchOptimization.lean` | No | `unknown namespace 'Ix.Aiur.Goldilocks'`, unknown `G.ofNat`, `STARKIntegration.CircuitABI`/`PredicateCircuit` don't exist |
| `ZkIpProtocol/AIOptimization.lean` | No | `bad import 'Ix.Aiur.Bytecode'` |
| `ZkIpProtocol/IrohIntegration.lean` | No | `discloseViaIroh` already declared, type mismatches, zero references anywhere in the repo |
| `Tests/MinimalCircuitTest.lean` | No | not wired into `lakefile.lean` at all (orphan); `lake build` resolves it to a bogus path inside the `ix` package and fails |
| `Tests/ProtocolTests.lean` | No | stale `Ixon`/`IPPredicate` fields (`name`, `version`, `owner`, `attributeType`), unknown `serializeAttribute`, `commitIPData`, `generateCertificate` |
| `Tests/BatchingTests.lean` | No | unknown `serializeAttribute`, `ZkIpProtocol.commitIPData`, ambiguous terms |
| `Tests/ApiTests.lean` | No | stale predicate fields (`threshold`, `operator`), type mismatches |
| `Tests/ZKMBTests.lean` | No | imports broken `ZKMB.lean` |
| `Tests/Validation/MasterValidation.lean` | No | imports 5 broken Validation test files |
| `Tests/Validation/SoundnessTests.lean` | No | `bad import 'Ix.Aiur.Bytecode'` |
| `Tests/Validation/STARKRoundTripTests.lean` | No | `bad import 'Ix.Aiur.Bytecode'` |
| `Tests/Validation/ThroughputBenchmarks.lean` | No | `bad import 'Ix.Aiur.Bytecode'` |
| `Tests/Validation/ZKMBLatencyTests.lean` | No | imports broken `ZKMB.lean`, `bad import 'Ix.Aiur.Bytecode'` |
| `Tests/Validation/RecursiveStabilityTests.lean` | No | imports broken `ZKMB.lean`, `bad import 'Ix.Aiur.Bytecode'` |

### Compiles, but 100% dead once the rot above is removed — deleted

| File | Compiles? | Used by? |
|---|---|---|
| `ZkIpProtocol/FRIVerification.lean` | Yes | Nobody, ever (zero references in the whole tree) |
| `ZkIpProtocol/MerkleReconstruction.lean` | Yes | Nobody, ever (zero references) |
| `ZkIpProtocol/FullRecursiveVerification.lean` | Yes | Only `RecursiveStabilityTests.lean` and `ZKMB.lean` (both deleted) |
| `ZkIpProtocol/RecursiveProofs.lean` | Yes | Only `RecursiveStabilityTests.lean` and `ZKMB.lean` (both deleted) |
| `ZkIpProtocol/HashConstraints.lean` | Yes | Only `MerkleReconstruction.lean`/`FRIVerification.lean`/`FullRecursiveVerification.lean` (all deleted) |
| `ZkIpProtocol/Batching.lean` | Yes | Only `ZKMB.lean`, `ZKMBLatencyTests.lean`, `ZKMBTests.lean`, `BatchingTests.lean` (all deleted) — distinct from the real, working batched-disclosure feature in `MerkleCircuit.lean`/`Tests/Validation/BatchDisclosure.lean`, which is untouched |
| `ZkIpProtocol/NoCapFFI.lean` | Yes | Nobody (`MerkleCommitment.lean` no longer imports it — already decoupled per the M2a plan doc); docs already called it "vestigial, slated for removal" |

Verified no surviving file imports any deleted module (scripted grep across
the full post-deletion `.lean` tree — zero hits).

### Kept — real, used, on the build path

`CoreTypes`, `MerkleCommitment`, `MerkleCircuit`, `Blake3Circuit`,
`STARKIntegration`, `Advertisement`, `Api`, `IPMetadata`, `ABAC`,
`Disclosure`, `Performance`, `DebugLogger`, `Optimization` (directly
imported by the `ZkIpProtocol.lean` root aggregator and used by
`advertiseAndDisclose`).

## Files deleted (22)

```
ZkIpProtocol/ZKMB.lean
ZkIpProtocol/StringMatchOptimization.lean
ZkIpProtocol/AIOptimization.lean
ZkIpProtocol/IrohIntegration.lean
ZkIpProtocol/FRIVerification.lean
ZkIpProtocol/FullRecursiveVerification.lean
ZkIpProtocol/RecursiveProofs.lean
ZkIpProtocol/MerkleReconstruction.lean
ZkIpProtocol/HashConstraints.lean
ZkIpProtocol/Batching.lean
ZkIpProtocol/NoCapFFI.lean
Tests/MinimalCircuitTest.lean
Tests/ProtocolTests.lean
Tests/BatchingTests.lean
Tests/ApiTests.lean
Tests/ZKMBTests.lean
Tests/Validation/MasterValidation.lean
Tests/Validation/SoundnessTests.lean
Tests/Validation/STARKRoundTripTests.lean
Tests/Validation/ThroughputBenchmarks.lean
Tests/Validation/ZKMBLatencyTests.lean
Tests/Validation/RecursiveStabilityTests.lean
```

## References removed

- `lakefile.lean`: removed the 10 `lean_exe` blocks for
  `Tests.ProtocolTests`, `Tests.BatchingTests`, `Tests.ZKMBTests`,
  `Tests.ApiTests`, `Tests.Validation.MasterValidation`,
  `Tests.Validation.SoundnessTests`, `Tests.Validation.STARKRoundTripTests`,
  `Tests.Validation.ThroughputBenchmarks`,
  `Tests.Validation.ZKMBLatencyTests`,
  `Tests.Validation.RecursiveStabilityTests`.
  (`Tests.MinimalCircuitTest` was never wired into the lakefile — nothing
  to remove there.)
- No surviving `.lean` file imports any deleted module (verified by grep
  after deletion).
- `ZkIpProtocol/CoreTypes.lean` keeps one harmless doc-comment mention of
  "ZKMB" (`/-- IP Attribute types for ZKMB and Advertisements -/`) — not a
  code dependency, left as-is (it's just a stale word in a comment, not
  worth a diff for).

## Docs updated

- `README.md` — Key Features, architecture mermaid diagram, Core
  Components list, Installation/Testing command lists (added the full set
  of real M1-M3 test exes), Project Structure tree, Optimization
  Techniques, Testing section, Status section, References — all rewritten
  to say ZKMB/string-match/AI-optimization/batching/recursive-proofs/Iroh/
  NoCapFFI were **never implemented** and their non-compiling scaffolding
  has been **deleted**, not "present but broken."
- `docs/architecture.md` — Soundness section, system diagram, Core
  Components, Status section updated the same way.
- `docs/index.md` — Overview and Key Features updated.
- `docs/workflow-for-decision-makers.md` — "What Works" list, Known
  Limitations (NoCap hardware bottleneck claim was already contradicted by
  the measured CPU baseline; now says so plainly), Test Coverage list,
  Project Structure tree.
- `docs/api-reference.md` — removed `ZkIpProtocol.Batching`/
  `RecursiveProofs`/`ZKMB` from the real module list, added
  `MerkleCircuit`/`Api`, added a "never implemented" note.
- `docs/performance.md` — Optimization Techniques, Proof Size, and the
  NoCapFFI paragraph all updated to say deleted/never implemented instead
  of "present, non-compiling, unverified."
- `docs/examples.md` — replaced the fictional Batch Verification / ZKMB
  Application / Recursive State Updates code examples (which called
  functions that never existed) with a "Not Implemented" section and a
  pointer to the real `Tests/Validation/BatchDisclosure.lean` batching
  feature.
- Left `docs/superpowers/**` untouched — those are dated planning/spec
  notes (historical record of decisions), not living documentation.

## Verification

- `lake build` (default target, `ZkIpProtocol` library): **GREEN** (38
  jobs, only pre-existing deprecation warnings in `DebugLogger.lean` /
  `STARKIntegration.lean`, no errors).
- `lake build <all 13 lean_exe targets + Main>`: **GREEN** (126 jobs).
- Every real test exe run and passed:

| Test | Result |
|---|---|
| `Tests.HashTests` | PASS |
| `Tests.STARKTests` | PASS (proof gen 505ms, verify 1ms) |
| `Tests.Validation.PredicateSoundness` | PASS (13 checks) |
| `Tests.Validation.ProveVerifyRoundtrip` | PASS (proof size 884788 bytes, prove+verify roundtrip OK) |
| `Tests.Validation.CpuBaseline` | PASS (median prove 468ms, verify 31ms) |
| `Tests.Validation.MerkleScheme` | PASS |
| `Tests.Validation.MerkleCircuitSingle` | PASS |
| `Tests.Validation.MerkleCircuitPath` | PASS (depths 3/5/8 + odd counts) |
| `Tests.Validation.MerklePredicate` | PASS (incl. ad-switch rejection) |
| `Tests.Validation.BatchDisclosure` | PASS (K=1,2,4) |
| `Tests.Validation.ScalingStudy` | PASS (K=1,2,4,8) |
| `Tests.Validation.Blake3CircuitSpike` | PASS |
| `Tests.Validation.MerkleNodeHashSpike` | PASS |
| `Main` (HTTP API exe) | builds clean, not a test — not run |

## Net LOC

`git diff --stat` (cached): **30 files changed, 120 insertions(+), 4255
deletions(-)** → net **-4135 LOC**.

## Commit

One commit: `chore: remove P0-era non-compiling scaffolding (ZKMB, optimization stubs, dead tests)`

## Concerns / follow-ups for the caller

- `docs/workflow-for-decision-makers.md` still contains some pre-existing
  staleness unrelated to this cleanup (e.g. "Ad-Switch Attack
  vulnerability" / "generateRecursiveProof placeholder" language predates
  the M1-M3 rebuild) — left untouched as out of scope for a rot-deletion
  task; flagging for a separate docs-accuracy pass if desired.
- The report file could not be written to the requested absolute path
  `/home/mlayug/Documents/0pon/zkip-stark/.superpowers/sdd/` because that
  path resolves outside this worktree's sandbox (the tool blocked it:
  "Edit the worktree copy of this file instead of the shared-checkout
  path"). Written instead to the worktree-local equivalent:
  `.claude/worktrees/agent-a09c696bb3f629f73/.superpowers/sdd/rot-cleanup-report.md`.
- The `.lake` build cache was copied (not symlinked) from the sibling
  worktree at `/home/mlayug/Documents/0pon/zkip-stark/.lake` to speed up
  iteration; it is untracked and worktree-local, no risk to the commit.
