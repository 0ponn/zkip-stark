# M14: Smaller proofs

Status: done locally (2026-10-05). Operator approved both levers ("yes to
both") after the bench/proof-size measurement.

## Measurement (bench/proof-size, 4-core GitHub runner)

- Proof size is about 97 KB per FRI query plus about 240 KB fixed: every
  query opens one row of every committed column (5,053 columns, mostly Blake3).
- 27% of the function columns (1,370 of 4,932) belonged to circuits a
  single-disclosure proof never calls: legacy spike entries, Blake3 test
  helpers, and the other batch entries.

## Changes

1. Pruning: `pruneTo` marks every function the entry cannot reach through
   `call` ops (any branch) as unconstrained, so it gets no circuit. Each entry
   size now has its own pruned bytecode and system. A wrongly pruned function
   would break completeness only: its callers' call lookups would have no
   table to balance.
2. Parameters: blowup 8 (logBlowup 3), 38 queries, 16-bit query PoW (20-bit
   commit PoW unchanged). Conjectured 130 bits (was 200). The proven
   (Johnson-bound) figure drops from about 100 to about 73 bits; this is
   flagged in the review packet. The ZK floor follows the query count: 128 rows.

## Results (one disclosure, 4 threads, lowest priority)

| | bytes | prove | verify |
|---|---:|---:|---:|
| before | 9,935,009 | ~3.5 s | ~40 ms |
| pruned | 7,436,787 | 3.5 s | 39 ms |
| pruned + new parameters | 2,963,765 | 5.8 s | 12 ms |

All 9 CI executables pass (PredicateSoundness 186 s at lowest priority);
`test_all.sh` 10/10; cross-process check passes.
