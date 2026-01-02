# ZKIP-STARK Documentation

Welcome to the ZKIP-STARK documentation.

## Overview

ZKIP-STARK is a production-ready, formally verified Zero-Knowledge protocol for privacy-preserving IP metadata exchange. Built with Lean 4 for soundness, powered by STARK proofs (Ix/Aiur) for speed, and optimized for NoCap hardware acceleration.

## Quick Links

- [Getting Started](getting-started.md)
- [Architecture](architecture.md)
- [API Reference](api-reference.md)
- [Examples](examples.md)
- [Performance](performance.md)

## Key Features

- **Formally Verified**: Complete Lean 4 type system guarantees with verified termination proofs
- **STARK Proofs**: Ix/Aiur integration for scalable transparent arguments of knowledge
- **Hardware Accelerated**: NoCap FFI integration targeting 586x speedup over CPU
- **Recursive Proofs**: Infinite state transitions via verifier circuits in the DSL
- **Batching**: Multiple attribute checks in a single STARK proof for efficiency
- **Real-World Applications**: Zero-Knowledge Middlebox (ZKMB) for TLS 1.3 compliance verification

## Installation

```bash
git clone https://github.com/memmmmike/zkip-stark.git
cd zkip-stark
lake build
```

## Documentation Structure

- **Getting Started**: Installation and quick start guide
- **Architecture**: System design and component overview
- **API Reference**: Detailed API documentation
- **Examples**: Code examples and use cases
- **Performance**: Performance benchmarks and optimization guides

## Contributing

Contributions are welcome! Please ensure:
- All code compiles without errors (`lake build`)
- No `sorry` symbols in proofs
- Tests pass (`lake build Tests`)
- Code follows Lean 4 style guidelines

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](../LICENSE) for details.

