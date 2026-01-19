# Performance

## Benchmark Results (January 2026)

Actual benchmarks comparing Lean/Aiur (current implementation) vs Rust/Plonky2:

| Metric | Lean/Aiur | Rust/Plonky2 | Notes |
|--------|-----------|--------------|-------|
| **Proof Generation (avg)** | ~200 ms | ~7 ms | Plonky2 ~28x faster |
| **Proof Verification (avg)** | 2 ms | 1.8 ms | Comparable |
| **Proof Size** | 162 KB | 43 KB | Plonky2 ~3.8x smaller |
| **Field** | Goldilocks | Goldilocks | Same field |
| **Trusted Setup** | None | None | Both transparent |

### Why We Stay with Lean/Aiur

Despite Rust/Plonky2 being ~28x faster, we chose Lean/Aiur for financing applications:

1. **Formal Verification**: Lean 4 provides mathematical proofs of correctness that auditors and regulators can verify
2. **~200ms is acceptable**: Financing eligibility checks are not latency-sensitive like trading
3. **Transparent proofs**: STARKs require no trusted setup ceremony
4. **Single source of truth**: No risk of Rust implementation diverging from Lean specification

### When to Reconsider

Switch to Rust only if:
- You need <10ms proofs (real-time use case)
- You need 1000+ proofs per second
- Formal verification is not a regulatory requirement

## Current Performance

### Proof Generation
- **Current**: ~200ms average (software-only, measured January 2026)
- **With NoCap hardware**: Theoretical ~0.35ms (586x speedup per NoCap paper - not measured)
- **Status**: NoCap hardware UNAVAILABLE

### Proof Verification
- **Current**: ~2ms
- **Target**: Sub-3ms for ZKMB applications

### Proof Size
- **Current**: ~162 KB
- **Property**: O(log n) of computation

## Running Benchmarks

### Lean/Aiur Benchmark

```bash
lake build Benchmark
lake exe Benchmark
```

### Rust/Plonky2 Benchmark (for comparison)

```bash
cd rust-benchmark
rustup override set nightly
RUSTFLAGS="-Ctarget-cpu=native" cargo run --release
```

## Optimization Techniques

### Batching
Multiple attribute checks in a single STARK proof reduce per-attribute overhead.

### Recursive Proofs
Proof composition via verifier circuits.

### Hardware Acceleration
- **Status**: UNAVAILABLE - NoCap hardware not integrated
- **Impact**: All Poseidon hashing uses software fallback
- **Potential**: 586x speedup when available

### String Matching
ASCII character packing into field elements:
- 2 constraints per character (vs. naive approach)
- Pack multiple ASCII chars into single field element

### Boolean Logic Arithmetization
Non-zero = True for efficient OR-gates:
- Linear combinations instead of multiplicative gates
- Reduced constraint count for policy evaluation

## Profiling

Profile STARK proof generation:

```lean
import ZkIpProtocol.Performance

let metrics ← profileSTARKProof circuit publicInputs privateInputs
printMetrics metrics
```

Output includes:
- Constraint count (from bytecode)
- Proof generation time (ms)
- Proof verification time (ms)
- Proof size (bytes)
- Claim size (field elements)
