# M10: Bind the attribute's identity into the leaf

Status: done locally (2026-10-04). Operator decision: the attribute is public
and its value is private.

## Why

The leaf committed only the 4-byte value, so a certificate proved "some
committed attribute > T". A holder could present a passing security score as
performance.

## Design

- `label`: `performance`, `security`, `efficiency`, or `custom/<name>`. The
  built-in labels contain no `/`, so labels are unambiguous.
- `attrId = Blake3(0x02 ++ utf8(label))`, 32 bytes. The tag 0x02 separates it
  from the leaf (0x00) and node (0x01) hashes.
- Leaf bytes are `attrId ++ value_le32` (36 bytes). The leaf hash stays
  `Blake3(0x00 ++ leaf)`, still a single Blake3 block.
- Claim: `[0, funIdx, threshold, a0..a7, r0..r7, 1]`, 20 elements (was 12).
  `a_k` are the little-endian u32 words of `attrId`.
- Circuit `batch_item(i, threshold, a0..a7, r0..r7)` asserts a 36-byte leaf,
  checks that its first 8 words equal `a0..a7`, recomposes the last 4 bytes
  into `attr`, and proves `attr > threshold` plus membership. Batch entries
  take `(t_i, a_i0..a_i7)` per item, then the root.
- The certificate carries `attribute` (the label). The verifier recomputes
  `attrId` from it, so relabelling a certificate fails the claim check.
- The trace shape is independent of the label (fixed 36-byte leaf). Recalibrate
  anyway and compare.

## Units

1. Core: `IPAttribute.label`, `attrIdOf`, `attrLeaf`, label validation.
2. Circuit plus FusedCircuit layout plus STARKIntegration plus certificate,
   API and Advertisement.
3. Tests: update every caller, and add relabel and cross-attribute negatives.
4. Docs, then a full local run including the cross-process `test_all.sh`.

Legacy `merkle_predicate` (fixed depth 3, M2b spike) keeps the 4-byte leaf.
Only its own validation test uses it.

## Results

- Claim: 20 elements. Proof: 9,232,206 bytes (was 8,978,525). Prove 1880 ms
  (STARKTests, 8 threads), verify 36 ms. The fixed trace shape check passes
  with labels varied.
- New negatives: a proof does not verify under any other attribute; a value
  committed under one attribute cannot be proved under another; a relabelled
  certificate fails through the library and the API; in-circuit attribute swap
  (BatchDisclosure).
- All 9 CI executables pass, `test_all.sh` passes 7/7 across processes, and
  ScalingStudy proves K = 1/2/4/8.
- Surface: about +120 lines, mostly the batch entries (each item now takes 8
  attribute-id words) and the new tests.
