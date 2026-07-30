# Performance

> ## ⚠️ No trustworthy performance data exists for this repository
>
> Previously published figures — sub-3ms verification, 300–500 proofs/second,
> and a constant ~162 KB proof size across 1,000 recursive transitions — have
> been **withdrawn**. They were produced by benchmarks that time stub functions.
>
> For example, `testSingleProofLatency` in
> `Tests/Validation/ZKMBLatencyTests.lean` measures `ZKMB.verifyPacket`, whose
> entire body is `true`. The recursive proof-size figure was measured against a
> verifier circuit whose body is `ret 1`.
>
> The benchmark suite also does not currently compile.
>
> Figures will be republished only once (a) the circuits express real
> constraints, (b) the benchmark targets compile, and (c) they run in CI on a
> declared machine configuration.

## Performance Targets

These remain the design goals. All are unvalidated:

- **Verification latency**: under 3 milliseconds for ZKMB applications
- **Proof size**: constant under recursive composition

## Hardware Acceleration

- **Status**: unavailable. NoCap hardware is not integrated.
- **Current**: software-only STARK proving via Ix/Aiur
- **Interface**: `NoCapFFI.lean` defines FFI signatures, but `HardwareCtx.create`
  always returns `none` and both branches of `poseidonHashFFI` call the same
  software stub. No hardware path has ever executed.

## Optimization Techniques

### Batching
Multiple attribute checks in a single STARK proof reduce per-attribute overhead.

### Recursive Proofs
Infinite state transitions with constant proof size via verifier circuits.

### Hardware Acceleration
- **Status**: UNAVAILABLE - NoCap hardware not integrated
- **Impact**: All Poseidon hashing uses software fallback (`Hash.hash`)
- **FFI Interface**: NoCapFFI.lean exists but `HardwareCtx.create` returns `none`

### Optimization Techniques

#### String Matching
ASCII character packing into field elements:
- **Reduction**: 2 constraints per character (vs. naive approach)
- **Method**: Pack multiple ASCII chars into single field element

#### Boolean Logic Arithmetization
Non-zero = True for efficient OR-gates:
- **Method**: Linear combinations instead of multiplicative gates
- **Benefit**: Reduced constraint count for policy evaluation

## Benchmarking

The benchmark target does not currently compile (`Tests/Validation/ThroughputBenchmarks.lean`
constructs `MerkleProof` with a nonexistent `leafIndex` field). Once fixed, it
will still be measuring stub circuits until the remediation work lands.

```bash
lake build Tests.Validation.ThroughputBenchmarks   # currently fails
lake exe Tests.Validation.ThroughputBenchmarks
```

## Profiling

Profile STARK proof generation:

```lean
import ZkIpProtocol.Performance

let metrics ← profileSTARKProof circuit publicInputs privateInputs
IO.println s!"Constraints: {metrics.constraintCount}"
IO.println s!"Proof time: {metrics.proofTime}ms"
IO.println s!"Verify time: {metrics.verifyTime}ms"
```

