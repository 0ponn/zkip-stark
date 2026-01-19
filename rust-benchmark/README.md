# Rust/Plonky2 Benchmark

This directory contains a Rust implementation of the CHAP eligibility proof circuit using Plonky2, created for benchmarking against the Lean/Aiur implementation.

## Purpose

This is a **comparison benchmark only**, not the production implementation. We use it to validate our technology choice (Lean/Aiur vs Rust/Plonky2).

## Results (January 2026)

| Metric | Lean/Aiur | Rust/Plonky2 | Ratio |
|--------|-----------|--------------|-------|
| Proof Generation | ~200 ms | ~7 ms | ~28x |
| Proof Verification | 2 ms | 1.8 ms | ~equal |
| Proof Size | 162 KB | 43 KB | ~3.8x |

**Conclusion**: Despite Rust being ~28x faster, we chose Lean/Aiur for:
1. Formal verification (mathematical proofs of correctness)
2. Regulatory compliance story
3. ~200ms is acceptable for financing eligibility checks

## Requirements

- Rust nightly toolchain (Plonky2 requires nightly features)
- jemalloc (for optimal performance)

## Running

```bash
# Set nightly toolchain
rustup override set nightly

# Build and run with native CPU optimizations
RUSTFLAGS="-Ctarget-cpu=native" cargo run --release
```

## Output

```
=== CHAP Eligibility Proof Benchmark ===
Rust/Plonky2 Implementation
Field: Goldilocks (p = 2^64 - 2^32 + 1)

Test case:
  Merkle root: 0x1234567890abcdef
  Threshold: 500
  Attribute (private): 1000
  Operator: GreaterThanOrEq
  Predicate satisfied: true

=== Results ===
Circuit build:        2.38 ms
Proof generation:     4.45 ms
Proof verification:   1.35 ms
Proof size:          43024 bytes (~42.0 KB)
Public inputs:           3
```

## Notes

- Plonky2 is deprecated in favor of Plonky3
- Both Plonky2 and Aiur use the Goldilocks field
- Both systems are transparent (no trusted setup)
- The circuit complexity is simplified for benchmarking
