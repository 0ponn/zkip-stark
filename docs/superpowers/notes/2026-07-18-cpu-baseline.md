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
