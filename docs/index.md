# ZKIP-STARK Documentation

Welcome to the ZKIP-STARK documentation.

> ## ⚠️ Early prototype — not usable, not secure, not a ZK system
>
> None of the cryptography in this repository is implemented. Every circuit is a
> stub that returns a constant, the hash function is the identity function, the
> secret witness is published in the public claim, and there are no formal
> proofs. Most modules do not compile. See
> [`REMEDIATION.md`](https://github.com/memmmmike/zkip-stark/blob/main/REMEDIATION.md)
> for the full accounting.
>
> These docs describe an intended design, not a delivered one.

## Overview

ZKIP-STARK is an early-stage design for a Zero-Knowledge protocol supporting
privacy-preserving IP metadata exchange, written in Lean 4 and targeting STARK
proofs via Ix/Aiur.

## Quick Links

- [Workflow for Decision Makers](workflow-for-decision-makers.md) - Non-technical overview
- [Getting Started](getting-started.md)
- [Architecture](architecture.md)
- [API Reference](api-reference.md)
- [Examples](examples.md)
- [Performance](performance.md)

## Intended Features

All design goals. None are currently delivered:

- **Formal verification** — not started; the repository contains no theorems
- **STARK proofs** — Ix/Aiur is wired up, but the circuits prove a trivial statement
- **Zero-knowledge** — broken; the witness is published in the claim
- **Merkle commitment** — not implemented; the hash is the identity function
- **Recursive proofs** — not implemented; the verifier circuit returns `1`
- **Batching** — not implemented; the circuit returns its first input
- **Hardware acceleration** — unavailable
- **ZKMB application** — does not compile

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

