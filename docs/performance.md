# Performance

## Performance Targets

### Verification Latency
- **Target**: Sub-3ms for ZKMB applications
- **Current**: Optimized for hardware acceleration

### Hardware Acceleration
- **Status**: UNAVAILABLE - NoCap hardware not integrated. CRITICAL PERFORMANCE BOTTLENECK.
- **Current**: Software-only STARK proving using Ix/Aiur
- **Interface**: NoCapFFI.lean provides FFI bindings, but `HardwareCtx.create` always returns `none`

### Proof Size
- **Constant**: ~162 KB even after 1,000 recursive state transitions
- **Optimization**: Recursive proof composition maintains constant size

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

Run performance benchmarks:

```bash
lake build Tests.Validation.ThroughputBenchmarks
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

