# M12: Label-keyed Merkle tree (one slot per label)

Status: done locally (2026-10-04). Operator approved after the CI benchmark
(bench/depth32: 16 to 32 levels costs about 10% prove time for 1 attribute and
about 50% for 8; proof size and verify time unchanged).

## Why

kedihacker (ZK Hack #discussions) pointed out that a root can commit the same
label twice with different values. A certificate then only proves "some value
with this label passes". This was section 8 of the review packet.

## Design

- Depth fixed at 32. Slot of a label = `a0`, the first little-endian u32
  word of `attrIdOf label` (already public in the claim).
- Off-circuit: a sparse Merkle tree over 2^32 slots. An empty subtree at level
  `l` is `E_l`, with `E_0 = Blake3(0x04)` and `E_{l+1} = nodeHash(E_l, E_l)`.
  Leaves are unchanged (`leafHash(attrId ++ value)`). Two labels in one slot
  (about 0.01% at 1,000 labels) and duplicate labels are refused at commit
  time.
- In-circuit (`batch_item`): fold the path while accumulating
  `idx = Σ dir_j · 2^j` and `pow = 2^levels`; assert `pow == 2^32` (exactly 32
  levels) and `idx == a0` (the slot is the label's). Directions stay in the
  witness but are pinned by these checks.
- Symmetric node step: siblings are parsed into digests (`read_digest`), and
  both orders build the preimage with the same calls, so the trace shape does
  not depend on the directions (which now come from public labels).
- Legacy spike entries (`merkle_single`, `merkle_path`, `merkle_predicate`)
  keep their old functions and tests.

## Units

1. Circuit: `read_digest`, `keyed_node`, `keyed_fold`; `batch_item` uses
   them.
2. Library: keyed tree build and proof, empty-subtree digests, label checks;
   certificate generation; calibration at depth 32.
3. API: 400 for duplicate labels and slot clashes.
4. Tests: fixtures get distinct labels; add negatives for wrong slot, short
   path, duplicate label, and slot clash.
5. Docs (README, packet section 8, API reference), then a full local run at
   capped threads, then the PR.

## Results

- The circuit rejects a second value for a label placed in another label's
  slot (ProveVerifyRoundtrip, BatchDisclosure), a 16-level path, and a label
  committed twice (library 400 and API 400).
- Calibration needed headroom: a real witness had 2,076 raw rows in table 9
  against 1,948 to 2,012 for synthetic ones, across the 2,048 boundary. Floors
  are now `next_pow2(raw + raw/8)` over raw execution counts, verified to align
  with `traceHeights`.
- BatchDisclosure's path encoder converted direction bytes to Booleans, so
  its "non-Boolean direction" negative never injected a 2. It encodes raw
  bytes now, and the case is rejected for the right reason.
- All 9 CI executables pass, plus ScalingStudy (K = 1/2/4/8) and
  ProofPhaseProfile; `test_all.sh` passes 8/8 across processes. Proof is
  9,935,009 bytes (was 9,232,206).
- Self-review found that the first depth check, `2^levels == 2^32`, wraps:
  2 has order 192 in Goldilocks, so a 224-level path at position `a0 + p`
  passed (red test in BatchDisclosure, accepted). It is replaced by a plain
  level counter `== 32` (now rejected: 224 != 32). gpt-5.4 had reviewed the
  first version and found nothing.
- BatchDisclosure now prints why each negative is rejected. That caught a
  first draft of the 224-level test failing for the wrong reason (its value
  was below the threshold).
