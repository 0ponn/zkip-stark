# Performance

## Performance Targets

### Verification Latency
- **Target**: Sub-3ms for ZKMB applications
- **Current**: Optimized for hardware acceleration

### Hardware Acceleration
- **Target**: 586x speedup with NoCap FFI
- **Method**: Zero-copy FFI, batch hashing, pipelined operations

### Proof Size
- **Constant**: ~162 KB even after 1,000 recursive state transitions
- **Optimization**: Recursive proof composition maintains constant size

## Optimization Techniques

### Batching
Multiple attribute checks in a single STARK proof reduce per-attribute overhead.

### Recursive Proofs
Infinite state transitions with constant proof size via verifier circuits.

### Hardware Acceleration
- **NoCap Hash Unit**: Dedicated hardware for Poseidon hashing
- **Zero-Copy FFI**: Direct pointer passing to hardware buffers
- **Batch Operations**: Pipelined hashing for vector processor lanes

### Symbolic AI Optimizations

#### H1-H5: Circuit Structure
- LUT maximization for FPGA targets
- Pipeline depth optimization for ASIC targets
- Resource-aware constraint reduction

#### H6 (STRING-MATCH)
ASCII character packing into field elements:
- **Reduction**: 2 constraints per character (vs. naive approach)
- **Method**: Pack multiple ASCII chars into single field element

#### Off-Path Proving
Split decryption proofs:
- **Keystream Commit**: Precomputable during idle
- **Payload Verify**: On-path verification only

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

