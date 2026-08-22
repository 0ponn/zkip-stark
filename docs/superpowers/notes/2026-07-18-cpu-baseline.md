# CPU proving baseline

Honest, no-GPU wall-clock number for end-to-end STARK proving on this
machine, captured with `Tests/Validation/CpuBaseline.lean`
(`lake exe Tests.Validation.CpuBaseline`). This is the number any later
GPU-acceleration claim has to beat.

**Note (M1 update):** the sections below (`Results (run 1)`, `Results (run
2, ...)`, `Internal breakdown attempt`) predate the real constrained
predicate circuit (commit `9a6e536`) — they measured the earlier *vacuous*
circuit (one that constrained nothing). See "Real predicate circuit
baseline (M1)" at the bottom of this file for the current, real-circuit
numbers.

## Machine facts (vacuous-circuit baseline)

- CPU: Intel(R) Core(TM) i5-11600K @ 3.90GHz (11th Gen)
- Cores (`nproc`): 12
- RAM: 31 GiB total (from `free -h`)
- No GPU used for this run.

## Circuit under test

Same fixture as `Tests/STARKTests.lean`: 3-attribute `Ixon`
(`performance 1500`, `security 8`, `efficiency 95`), Merkle-committed,
`PredicateCircuit` with `attributeValue := 1500`, `threshold := 1000`,
`operator := ">"`.

## Results (run 1)

1 untimed warm-up run (absorbs JIT/lazy-init cost), then 5 timed
`generateSTARKProof` calls, then one timed `verifySTARKProof` call on the
last generated proof.

```
Warm-up proof generation (untimed)...
  run 1/5: 537 ms
  run 2/5: 398 ms
  run 3/5: 390 ms
  run 4/5: 415 ms
  run 5/5: 512 ms
CPU proving times (ms): [390, 398, 415, 512, 537]
median proving time: 415 ms
verify time: 42 ms
verification: PASSED
```

- **Median proving time: 415 ms**
- **Verify time: 42 ms**
- Proof verified successfully (`verifySTARKProof` returned `true`).
- Wall clock for the whole harness (`time lake exe ...`, includes process
  startup): `real 0m3.386s`.

## Results (run 2, with `RUST_LOG=info`)

Re-ran to check for internal tracing spans (see below). Numbers are
consistent with run 1, same order of magnitude:

```
Warm-up proof generation (untimed)...
  run 1/5: 491 ms
  run 2/5: 622 ms
  run 3/5: 457 ms
  run 4/5: 428 ms
  run 5/5: 611 ms
CPU proving times (ms): [428, 457, 491, 611, 622]
median proving time: 491 ms
verify time: 49 ms
verification: PASSED
```

Median proving time across the two runs: 415-491 ms. Treat ~400-620 ms
as the honest CPU proving range for this circuit on this machine, verify
consistently under 50 ms.

## Internal breakdown attempt: none surfaced

Ran `RUST_LOG=info lake exe Tests.Validation.CpuBaseline` — stdout/stderr
contained **no additional tracing output** beyond the harness's own
`IO.println` lines (see run 2 above, which is the complete captured
output).

This is not a fluke of the filter level. Checked why directly: the `ix`
package's Rust FFI crate (`ix-ffi`) does depend on `tracing`,
`tracing-subscriber`, and `tracing-texray` (confirmed via its Cargo
fingerprint/dep graph), but grepping the crate sources shows a tracing
subscriber is only ever installed in the `iroh` networking code
(`crates/ffi/src/iroh/client.rs`, `crates/ffi/src/iroh/server.rs`) — not
anywhere on the STARK proving/verification path (`AiurSystem.prove`,
`AiurSystem.verify`) that this harness exercises through the Lean FFI
boundary. `tracing` events may well be emitted internally by
`multi_stark`/`aiur` during proving, but with no subscriber registered
for this code path they go nowhere — `RUST_LOG` has nothing to filter
into.

**Conclusion: no internal proving/verification breakdown (trace-gen vs.
commit/NTT vs. FRI) is available from this binary today.** Getting one
requires wiring a `tracing_subscriber` registry into the proving/verify
FFI entry points themselves (mirroring the pattern already used for
`iroh`), which is out of scope for this task. Recording this plainly per
the task brief rather than fabricating a breakdown: P2 (or whichever
follow-up task instruments the prover) must add its own timing/tracing
if a phase-level breakdown is needed.

## Real predicate circuit baseline (M1)

Re-run of `Tests/Validation/CpuBaseline.lean` against the real, constrained
`predicate_check(threshold) -> G` circuit (commits `9a6e536`, `db9e7f0`,
`438195a`) — `attr > threshold` is enforced by an `assert_eq!` on
`u32_less_than`, `attr` is a private IO witness (channel 0), `threshold` is
the sole public input. Same machine as above.

### Machine facts

- CPU: Intel(R) Core(TM) i5-11600K @ 3.90GHz (11th Gen)
- Cores (`nproc`): 12
- RAM: 31 GiB total (from `free -h`)
- No GPU used for this run.

### Circuit under test

Same fixture as before: 3-attribute `Ixon` (`performance 1500`,
`security 8`, `efficiency 95`), Merkle-committed (root unused by the M1
predicate), `PredicateCircuit` with `attributeValue := 1500`,
`threshold := 1000`, `operator := ">"`. Public input: `#[threshold]`.
Private input (IO witness): `#[attr]`.

### Results

1 untimed warm-up run, then 5 timed `generateSTARKProof` calls, then one
timed `verifySTARKProof` call on the last generated proof:

```
Warm-up proof generation (untimed)...
  run 1/5: 606 ms
  run 2/5: 506 ms
  run 3/5: 523 ms
  run 4/5: 467 ms
  run 5/5: 496 ms
CPU proving times (ms): [467, 496, 506, 523, 606]
median proving time: 506 ms
verify time: 44 ms
verification: PASSED
```

- **Median proving time: 506 ms**
- **Verify time: 44 ms**
- Proof verified successfully (`verifySTARKProof` returned `true`).
- Wall clock for the whole harness (`time lake exe ...`, includes process
  startup): `real 0m3.764s`.

### Comparison to the vacuous-circuit baseline

Real-circuit median (506 ms) is in the same ~400-620 ms range as the old
vacuous-circuit numbers (415-491 ms median across two runs). Expected: the
circuit itself is tiny either way (7 bytecode ops for the real predicate,
per `analyzeCircuitComplexity` — `ABI: funIdx=0, privateInputs=1,
publicInputs=1, outputs=1`, 14 auxiliaries, 7 lookups), so proving cost here
is dominated by the fixed STARK commitment/FRI overhead
(`starkCommitmentParams`, `starkFriParams` in `STARKIntegration.lean`), not
circuit size. This is the honest number for the real constrained predicate
and the one any later GPU-acceleration claim has to beat.

## Predicate+Merkle circuit baseline (M2)

Re-run against the FUSED `merkle_predicate` circuit (M2b Task 4, commit at
end of this note) — the milestone payoff that closes the ad-switch attack.
One circuit proves BOTH `attr > threshold` (the M1 predicate) AND that
`leafHash(encode(attr))` is a member of a depth-3 Merkle tree under a public
root, with the private `attr` bound to the committed leaf in-circuit (the
same 4 LE bytes feed the predicate's field element and the leaf hash). This
is the largest circuit in the protocol so far — it invokes the Blake3 gadget
4x (1 leaf hash + 3 node hashes up the depth-3 path) on top of the u32
predicate — and is the GPU-justifying baseline any later acceleration claim
has to beat.

Measured by `Tests/Validation/MerklePredicate.lean` (`RE-BASELINE` line),
which times a single warm `AiurSystem.prove` + `AiurSystem.verify` on the
honest index-3 witness after the positive/negative suite has already run
(so JIT/lazy-init is absorbed).

### Machine facts

- CPU: Intel(R) Core(TM) i5-11600K @ 3.90GHz (11th Gen)
- Cores (`nproc`): 12
- RAM: 31 GiB total
- No GPU used for this run.
- Circuit params: `commitmentParameters = { logBlowup := 1, capHeight := 0 }`,
  `friParameters = { logFinalPolyLen := 0, maxLogArity := 1, numQueries := 100,
  commitProofOfWorkBits := 20, queryProofOfWorkBits := 0 }` (the M2b test
  params, matching `MerkleCircuitPath.lean`).

### Circuit under test

`merkle_predicate(threshold, r0..r7) -> G` — public: `threshold` + 8x u32
root words; private IO: 4-byte LE `attr` (channel 0, = the leaf), 3 sibling
digests (channels 1-3), 3 direction bytes (channels 4-6). Fixture: 8 committed
attrs `[500, 1500, ..., 7500]` (`attrLeafBytes` leaves), threshold 1000,
honest proof for index 3 (attr 3500).

### Results

Four runs (`prove` ms / `verify` ms), warm single sample each:

```
prove 459 ms, verify 27 ms, verified=true
prove 329 ms, verify 28 ms, verified=true
prove 336 ms, verify 28 ms, verified=true
prove 354 ms, verify 28 ms, verified=true
```

- **Prove time: ~330-460 ms** (representative ~350 ms warm).
- **Verify time: ~28 ms.**
- Proof verified successfully.

### Comparison

Prove time (~350 ms warm) is in the same order of magnitude as the M1
real-predicate baseline (median 506 ms) despite adding 4 Blake3 hash gadgets
and the full depth-3 membership fold. Consistent with the M1 finding: at
these STARK params the cost is dominated by fixed FRI/commitment overhead
rather than circuit size, and the Blake3 gadget rows do not blow up the trace
at `logBlowup := 1`. This is the honest CPU number for the fused, ad-switch-
closing circuit and the baseline any GPU-acceleration claim must beat.
