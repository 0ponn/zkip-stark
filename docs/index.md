# ZKIP-STARK Documentation

Welcome to the ZKIP-STARK documentation.

## Overview

ZKIP-STARK is a **research prototype** for privacy-preserving IP metadata exchange. Built with Lean 4, powered by STARK proofs via Ix/Aiur -> multi-stark -> Plonky3 (Goldilocks field), hashing with Blake3. Only the core STARK proof path currently compiles and runs — see the [Architecture](architecture.md#status) doc for exactly what does and does not. Measured CPU proving is ~415-491 ms median, with no hardware bottleneck (see [Performance](performance.md)).

## Quick Links

- [Workflow for Decision Makers](workflow-for-decision-makers.md) - Non-technical overview
- [Getting Started](getting-started.md)
- [Architecture](architecture.md)
- [API Reference](api-reference.md)
- [Examples](examples.md)
- [Performance](performance.md)

## Key Features

- **Lean 4 Types**: Core protocol types and the STARK proof path are written and checked in Lean 4; the ZKMB application layer and most of `Tests/` do not currently compile
- **STARK Proofs**: Ix/Aiur -> multi-stark -> Plonky3 over the Goldilocks field
- **Blake3 Merkle Commitments**: matching the prover's own MMCS — there is no Poseidon hardware path in the working system; `NoCapFFI.lean` is a vestigial software-only stub
- **Recursive Proofs**: verifier circuits for proof composition in the DSL
- **Batching**: Multiple attribute checks in a single STARK proof for efficiency

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

