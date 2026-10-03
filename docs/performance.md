# Performance

## Measured CPU Baseline

### Fused circuit, zero-knowledge prover with masked accumulators (M7, 2026-10-03, current)

| leaves | depth | prove median (ms) | verify median (ms) | proof bytes |
|-------:|------:|------------------:|-------------------:|------------:|
| 1      | 0     | 1705              | 55                 | 8,978,525   |
| 8      | 3     | 1631              | 45                 | 8,978,525   |
| 16     | 4     | 1600              | 45                 | 8,978,525   |
| 1024   | 10    | 1806              | 57                 | 8,978,525   |

Masking adds five columns and one or two lookups per circuit: about 0.28 MB of
proof; time differences against M6 are within run-to-run noise.

### Fused circuit, zero-knowledge prover (M6, 2026-10-03, superseded by M7)

Same circuit, machine and harness as the table below, with Aiur proving under
`GoldilocksBlake3ZkConfig` (Plonky3 `HidingFriPcs`, salted Merkle leaves,
random FRI-batch polynomial) from `0ponn/multi-stark`.

| leaves | depth | prove median (ms) | verify median (ms) | proof bytes |
|-------:|------:|------------------:|-------------------:|------------:|
| 1      | 0     | 1464              | 37                 | 8,697,309   |
| 8      | 3     | 1560              | 39                 | 8,697,309   |
| 16     | 4     | 1553              | 37                 | 8,697,309   |
| 1024   | 10    | 1673              | 40                 | 8,697,309   |

Every Aiur trace is padded to at least 128 rows (the zero-knowledge floor for
100 FRI queries); this costs nothing measurable at these sizes.

Against the plain prover: about 5x prove time, 2x verify time, 1.8x proof size.
Prove grows more than the trace doubling alone because zero-knowledge also
raises each constraint's degree by one (degree 3 to 4 needs quotient degree 4
instead of 2) and the hiding PCS doubles the chunk count again.

### Fused circuit, plain (non-ZK) prover, production parameters (2026-10-03, superseded by M6)

The shipping circuit (`merkle_predicate_batch1`: `attr > threshold` plus
Blake3 Merkle membership of the attribute's leaf under the public root),
proved at the production parameters (`logBlowup 2`, 100 FRI queries, 20-bit
PoW), measured with `Tests/Validation/CpuBaseline.lean`
(`lake build Tests.Validation.CpuBaseline && .lake/build/bin/Tests-Validation-CpuBaseline`).
Medians of 5 runs after one warm-up; the one-time system build is excluded.

- **Machine**: Intel(R) Core(TM) i7-13700K (AVX2, no AVX-512 exposed), 24 threads, 31 GiB RAM, no GPU.

| leaves | depth | prove median (ms) | verify median (ms) | proof bytes |
|-------:|------:|------------------:|-------------------:|------------:|
| 1      | 0     | 283               | 21                 | 4,767,735   |
| 8      | 3     | 314               | 23                 | 4,767,735   |
| 16     | 4     | 258               | 21                 | 4,767,735   |
| 1024   | 10    | 323               | 24                 | 4,767,735   |

Prove time and proof size are flat in depth: the trace is dominated by the
Blake3 gadget rows and padding, not by the number of fold levels. Depth-10
(1024 attributes) costs the same as a single attribute.

### History: M1 predicate-only circuit (2026-07-18)

The earlier baseline (`docs/superpowers/notes/2026-07-18-cpu-baseline.md`)
measured the predicate-only M1 circuit on an i5-11600K: 415-491 ms prove,
42-49 ms verify. That circuit did not bind the Merkle root and is no longer
shipped.

There is no hardware bottleneck here. Earlier drafts of this document
described a "NoCap hardware UNAVAILABLE" bottleneck that does not reflect
reality: the prover does not use NoCap or Poseidon hardware at all, and CPU
proving is sub-second.

## The Prover's Real Hash: Blake3

The proving stack is Ix/Aiur -> multi-stark -> Plonky3, over the Goldilocks
field. `multi-stark`'s MMCS (`multi-stark/src/types.rs`) is configured as
`MerkleTreeMmcs<Val, u8, SerializingHasher<Blake3>, Blake3CompressionFunction, 2, 32>`
— **Blake3**, not Poseidon. The application-layer Merkle commitment in
`CoreTypes.lean` also uses Blake3 (`Address.blake3`), matching the prover.
`NoCapFFI.lean` was a software-only stub (`HardwareCtx.create` always
returned `none`) that was never on this hot path — a red herring for
proving performance. It has been deleted as dead code.

## GPU Acceleration (Planned, Not Done)

GPU work is planned at the Plonky3 `TwoAdicFriPcs` trait seam — new types
implementing `TwoAdicSubgroupDft` and `Mmcs` with CUDA behind FFI, starting
with the NTT, swapped into `multi-stark`'s type aliases. This does not touch
Aiur or the constraint system, and it has nothing to do with NoCap or
Poseidon. See `docs/superpowers/specs/2026-07-18-gpu-proving-backend-design.md`
for the full design. The CPU baseline above is the number any GPU claim has
to beat.

## Proof Size

Recursive proof composition (constant proof size across state transitions)
was never implemented — its P0-era scaffolding (`RecursiveProofs.lean`,
`FullRecursiveVerification.lean`) never compiled and has been deleted.
Treat any specific KB figure for this as unverified future work.

## Optimization Techniques

### Batched Disclosure
K-attribute disclosure under a shared Merkle root in a single proof reduces
per-attribute overhead — see `Tests/Validation/BatchDisclosure.lean` and
`docs/superpowers/notes/2026-07-20-scaling-study.md` for measured
prove-time vs. (batch, depth) data.

### Not Implemented
Multi-attribute STARK-proof batching (`Batching.lean`), recursive proof
composition (`RecursiveProofs.lean`), and string-matching optimization
(`StringMatchOptimization.lean`) were never implemented — their P0-era
scaffolding never compiled and has been deleted. Future work, not shipped
features.

### Boolean Logic Arithmetization
Non-zero = True for efficient OR-gates:
- **Method**: Linear combinations instead of multiplicative gates
- **Benefit**: Reduced constraint count for policy evaluation

## Benchmarking

Run the CPU baseline harness (the only benchmark on the compiling path):

```bash
lake build Tests.Validation.CpuBaseline && .lake/build/bin/Tests-Validation-CpuBaseline
```

`Tests.Validation.ThroughputBenchmarks` does not currently compile.

