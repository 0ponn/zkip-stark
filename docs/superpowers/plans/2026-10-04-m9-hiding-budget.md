# M9: Raise the ZK minimum trace height to Plonky3's hiding budget

Status: units 1 to 3 done (2026-10-04); unit 4 waits for the operator

## Why

Plonky3 PR #2100 (b4ef483, 2026-09-09) enforces, in `HidingFriPcs`:
`trace_height >= 2 * (D * opening_points + num_queries)`.
Our fork's rule is `next_pow2(num_queries + 2)` (multi-stark `src/types.rs:216`).
With production parameters (numQueries 100, Goldilocks D = 2, points zeta and
zeta*g) ours gives 128 and Plonky3's gives 208, which rounds up to 256. The
calibrated M8 shape has 28 of 38 circuits at 128 rows. Plonky3 does not
document where the factor 2 comes from. We adopt its audited bound rather
than re-derive it.

## Units

1. multi-stark `zk-hiding-pcs`: replace the rule with
   `next_pow2(2 * (D * 2 + num_queries))`, using D from the challenge field,
   and add a test pinning 256 for q = 100. Run the ZK suite.
2. ix `zk`: bump the multi-stark rev in `Cargo.toml`. Build.
3. zkip-stark: bump the ix rev, rebuild, re-run tests (RAYON_NUM_THREADS
   capped, nice'd), re-measure the proof cost, open a PR.
4. Comment on multi-stark #89 to correct the Plonky3 claim. This is public,
   so it waits for the operator.

## Calibrated shape before M9 (q = 100)

floors = 128 x28, 256 x2, 1024 x3, 2048 x3, 8192, 65536

## Calibrated shape after M9

floors = 256 x30, 1024 x3, 2048 x3, 8192, 65536. Production proof: 1711 ms
prove (RAYON_NUM_THREADS=8), 34 ms verify, 8,978,525 bytes (was about 9.0 MB).

## Results

- multi-stark 3bc3ab9: 42/42 tests, clippy clean.
- ix 086754b: aiur tests pass, workspace check clean.
- zkip-stark: all 9 CI test executables pass.
- Review: local lane (gpt-oss:20b) agreed with the formula, the two opening
  points and the test padding.
- Breaking: certificates proved before M9 carry the old shape and are now
  rejected by shape.
