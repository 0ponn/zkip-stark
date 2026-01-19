# CHAP Documentation

Welcome to the **CHAP** (Commercial High Assurance Platform) documentation.

## Overview

CHAP is a formally verified, zero-knowledge platform for high-assurance commercial transactions. Built with Lean 4 for soundness, powered by STARK proofs (Ix/Aiur) for transparency.

**Key differentiators:**
- **No Trusted Setup**: STARKs are transparent - no ceremony, no "toxic waste"
- **Formally Verified**: Lean 4 provides mathematical proofs of correctness
- **Post-Quantum Secure**: Hash-based proofs remain secure against quantum computers

## Quick Links

### Getting Started
- [Getting Started Guide](getting-started.md) - Installation and setup
- [Financing Demo](financing-demo.md) - Demo of ZK financing eligibility
- [Testing Guide](testing-guide.md) - How to test the system

### Architecture & Design
- [Architecture](architecture.md) - System design, STARKs vs SNARKs rationale
- [Performance](performance.md) - Benchmarks (Lean vs Rust comparison)
- [Workflow for Decision Makers](workflow-for-decision-makers.md) - Non-technical overview

### Reference
- [API Reference](api-reference.md) - HTTP API documentation
- [Examples](examples.md) - Code examples and use cases

### Security & Validation
- [Security Validation](SECURITY_VALIDATION.md) - Security audit results
- [Safety Verification](SAFETY_VERIFICATION.md) - ByteArray access safety audit

## Why STARKs Over SNARKs?

For regulated financial applications, we chose **STARKs** over SNARKs:

| Property | STARKs (Our Choice) | SNARKs (Groth16, etc.) |
|----------|---------------------|------------------------|
| Trusted Setup | **None required** | Required ceremony |
| Quantum Security | **Post-quantum safe** | Vulnerable |
| Auditability | **Trust only hash functions** | Trust ceremony participants |

See [Architecture](architecture.md) for detailed rationale.

## Performance (January 2026)

| Metric | Lean/Aiur | Notes |
|--------|-----------|-------|
| Proof Generation | ~207 ms | Acceptable for financing |
| Proof Verification | ~2 ms | Sub-3ms target achieved |
| Proof Size | ~162 KB | Constant with recursion |

We benchmarked Rust/Plonky2 at 20x faster but chose Lean for formal verification.
See [Performance](performance.md) for full comparison.

## Installation

```bash
git clone https://github.com/memmmmike/zkip-stark.git
cd zkip-stark
lake build
```

## Running Benchmarks

```bash
# Lean/Aiur benchmark
lake build Benchmark
lake exe Benchmark

# Rust/Plonky2 benchmark (for comparison)
cd rust-benchmark
rustup override set nightly
RUSTFLAGS="-Ctarget-cpu=native" cargo run --release
```

## Project Structure

```
zkip-stark/
├── ZkIpProtocol/           # Core protocol modules
│   ├── Core/               # STARK integration, hash constraints
│   ├── CoreTypes.lean      # Shared data structures
│   ├── Api.lean            # HTTP API handlers
│   └── ...
├── Tests/                  # Test suites
│   └── Validation/         # Validation tests
├── docs/                   # Documentation
├── rust-benchmark/         # Rust/Plonky2 comparison benchmark
├── Benchmark.lean          # Lean/Aiur benchmark
├── Main.lean               # API server entry point
└── lakefile.lean           # Build configuration
```

## Contributing

Contributions are welcome! Please ensure:
- All code compiles without errors (`lake build`)
- No `sorry` symbols in proofs
- Tests pass
- Code follows Lean 4 style guidelines

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](../LICENSE) for details.
