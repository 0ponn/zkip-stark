# M11: Several attributes in one certificate

Status: done locally (2026-10-04). Operator approved the feature; the API shape
below is my call.

## API

- Request: `"disclosures": [{"attributeIndex": i, "predicate": {...}}, ...]`,
  1 to 8 entries, each index at most once. The single form
  (`predicate` + `attributeIndex`) is still accepted as one disclosure; sending
  both forms is a 400.
- Certificate: `{ipId, timestamp, commitment, disclosures: [{attribute,
  predicate}], proof}`. One STARK proof covers every disclosure.

## Circuit sizes

Entries exist for K = 1, 2, 4, 8 (`merkle_predicate_batchK`). A request with K
disclosures uses the smallest entry of at least K and pads by repeating the
last disclosure. The verifier pads identically. The padding is visible in the
claim, which is fine: the disclosure list is public anyway.

## Trace shape per entry

Each entry gets its own fixed shape, calibrated lazily and cached per process.
Calibration witnesses come from a synthetic sparse depth-16 tree: the K leaves
sit in distinct top-level subtrees (so upper paths share as little as a real
witness can), every other node is a distinct filler digest, and the lower
index bits follow the all-left, all-right and alternating patterns used for
K = 1. The prover refuses any proof whose shape differs from its entry's
shape, so a calibration miss costs completeness, never privacy.

## Units

1. FusedCircuit: per-K entry, calibration, cached systems.
2. STARKIntegration and certificate type (`disclosures`), Advertisement verify.
3. API parse/serialize. Tests: K = 2, 3 (padded) and 8 round trips; relabel
   or tamper one disclosure; duplicate index; more than 8.
4. Docs, then the full local run including `test_all.sh`.

## Results

- K = 2, 3 (padded to 4) and 8 certify and verify. Tampering with one
  disclosure's threshold or attribute, dropping one, or reordering them fails.
  Two 2-disclosure certificates over a 12-attribute tree and a 65,536-attribute
  tree publish the same shape. Empty lists, duplicate indices, 9 disclosures
  and one false predicate are refused (library and API).
- `test_all.sh` gains a two-disclosure generate-then-verify across processes:
  8/8 pass, so lazy per-process calibration is deterministic.
- The single disclosure costs the same: 2.0 s prove at 8 threads, 39 ms
  verify, 9.23 MB.
- Repeating the last disclosure verifies, because padding works that way:
  every listed disclosure is still proved.
- Residual (documented): a label committed more than once in one tree is
  ambiguous, so the certificate proves at least one attribute with that label
  exceeds the threshold. The verifier cannot see the tree, so only the
  committer can prevent this.
