# M8: Fixed Trace Shape (close the trace-height leak)

**Status:** done 2026-10-03 (ix `3c66884`). Finding during the work: the two sibling directions cost different row counts, so the calibration is a maximum over all-left, all-right and alternating paths, not one synthetic path.

**Goal:** Every zkip-stark proof has identical per-circuit trace heights, so `Proof.log_degrees` reveals nothing about the witness.

## The leak

multi-stark proofs publish each circuit's log trace height. Aiur sizes a
circuit by how often it ran (padded to a power of two, at least 128 under ZK).
Anything that changes call counts (here, most likely the Merkle path length)
is visible to whoever holds the proof.

## Design

Pad to a fixed, worst-case shape.

1. **ix/Aiur.** `AiurSystem::trace_heights(fun_idx, input, io)` executes and
   returns each circuit's trace height without proving.
   `AiurSystem::prove_padded(.., floors)` pads circuit `i` to
   `max(next_pow2(rows), min_trace_height, floors[i])`. `prove` becomes
   `prove_padded` with no floors. Lean bindings: `AiurSystem.traceHeights`,
   `AiurSystem.provePadded`, and `Proof.logDegrees` for tests.
2. **zkip-stark.** A public depth cap `maxDepth = 16` (65,536 attributes).
   On first use, `FusedSystem` calibrates a height profile by tracing a
   synthetic maximum-depth witness and caches it. `generateSTARKProof` proves
   with that profile, and refuses (returns `none`) any tree deeper than the cap.
   `/generate` returns 400 above the cap.
3. **Check what varies.** Measure heights across depth, attribute value and
   threshold before relying on depth being the only driver; the profile must
   dominate every input the API accepts.

## Tests

- Red: certificates at depth 0 and depth 4 have different `logDegrees`.
- Green: certificates at depths 0, 3, 4, 10 and 16, with different attribute
  values and thresholds, all have identical `logDegrees`, and all verify.
- Depth 17 is refused.
- Timing at the fixed shape, recorded in `docs/performance.md`.
