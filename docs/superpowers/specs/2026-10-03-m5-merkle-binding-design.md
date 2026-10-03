# M5: Bind the Merkle Commitment Into the Production Proof

**Date:** 2026-10-03
**Status:** Design, pending review
**Closes:** REMEDIATION.md O1 and O4; review finding 3 of 2026-10-03 (`docs/superpowers/notes/2026-10-03-verify-hardening.md`).

## Why

The fused predicate + Merkle-membership circuit (`merkle_predicate_batch1` in
`ZkIpProtocol/MerkleCircuit.lean`) exists and is tested, but production still
proves the M1 predicate-only circuit. Consequences, all confirmed in source:

- `handleGenerate` builds a tree, puts its root in the certificate as
  `commitment`, and then proves a claim that does not mention the root.
  `verifyAttributeInMerkleTree` compares `cert.commitment` to itself.
  Swapping the commitment bytes in a certificate leaves `handleVerify`
  returning `verified: true`.
- A client-supplied `merkleRoot` is used as-is and never checked against the
  attributes (`Api.lean:268-272`).
- `privateAttribute` is a free request field; nothing ties it to any
  attribute in the tree, and `attributeIndex` is hard-coded to 0.
- The API tree is built over `natToByteArray` leaves (minimal-length
  big-endian) while the circuit's leaf preimage is `attrLeafBytes` (4-byte
  little-endian u32), so the two roots disagree even for the same data.

A certificate must mean: "the committed attribute at some index under
`commitment` exceeds `threshold`." Today it means "some number exceeds
`threshold`."

## Statement proved after M5

Public claim: `[0, funIdx, threshold, r0, …, r7, 1]` (12 Goldilocks elements).

- `threshold`: the certificate's predicate threshold, `< 2^32`.
- `r0..r7`: the 32-byte Blake3 root as eight little-endian u32 words,
  word `i` = bytes `[4i, 4i+3]`. Full 256-bit binding.
- Output `1`: the predicate held.

Private witness (IO channels, key `[0]`): the 4-byte LE attribute value
(channel 0) and the flat Merkle path, `dir ‖ sibling` per level, leaf level
first (channel 1). Depth is whatever the tree has; `merkle_fold` consumes
`33 · D` bytes and rejects any other length.

Circuit entry: `merkle_predicate_batch1`. Not `merkle_predicate`, which is
unrolled at depth 3 and only fits 5 to 8 leaves.

## Decisions

Each one is a call made for this milestone. Correct it in review if wrong.

1. **Leaf encoding is `attrLeafBytes`, everywhere.** The API and the batch
   handler in `Main.lean` build the tree from `attributes.map (attrLeafBytes ·.value)`.
   Every attribute value is guarded `< 2^32` at request parse time (400 on
   violation), because `attrLeafBytes` silently truncates above that.
   `natToByteArray` is no longer used as a leaf encoding anywhere; the
   `CpuBaseline`, `ProveVerifyRoundtrip` and `STARKTests` fixtures move with it.
   The leaf commits the value only, not the attribute type or custom name.
   That is the same as today and is out of scope here; noted as a limitation.

2. **The witness is `attributes[attributeIndex]`, not a free field.** The
   `/generate` request replaces `privateAttribute : Nat` with
   `attributeIndex : Nat` (default 0). The server takes the value from the
   attribute array, generates the path with `generateProof leaves index`,
   and proves. This is an API-breaking change; `privateAttribute` is
   rejected with 400 naming the new field, so stale clients fail loudly.

3. **A client-supplied `merkleRoot` must equal the recomputed root.** The
   server always rebuilds the tree. If the request carries a `merkleRoot`
   and it differs, respond 400 "merkleRoot does not match attributes". No
   path trusts a client root.

4. **Verification derives the whole expected claim from the certificate.**
   `verifySTARKProof` expected public inputs become
   `#[threshold] ++ rootWords cert.commitment` as `Array Nat` (all `< 2^32`,
   so the existing guard applies unchanged). It additionally checks
   `claim[1] == funIdx` of `merkle_predicate_batch1` and `claim[11] == 1`.
   Both are cheap and close the gap where only the args slice was compared.
   The certificate JSON shape does not change; `proof.publicInputs` simply
   carries 12 entries.

5. **Operator is `>` only.** The circuit constrains `u32_less_than(threshold, attr)`.
   `>=` is rejected at parse time (400). `IPPredicate.evaluate` loses its
   role in the generate path; the circuit decides. Rewriting `>= t` to
   `> t-1` is a one-line follow-up if a client needs it.

6. **The Aiur system is built once per process.** `fusedToplevel` (merge of
   `IxVM.core`, `IxVM.byteStream`, `IxVM.blake3`, `merkleCircuit`),
   `compile`, `getFuncIdx`, and `AiurSystem.build` with the production
   parameters (`starkCommitmentParams`, `starkFriParams`) run lazily on
   first use and are cached in an `IO.Ref`. `generateSTARKProof` and
   `verifySTARKProof` take the cached system. This replaces the per-request
   compile (twice per `/generate` today) and is the natural home for the
   merge the tests each re-derive.

7. **`SecurityValidation` is re-scoped.** `validatePublicInputsStructure`
   requires exactly 9 inputs: threshold then the 8 root words recomputed
   from the root. `validatePrivatePublicSeparation` compares the private
   value against `threshold` only; root words are hash output and a
   chance 32-bit collision with an attribute value must not reject a
   legitimate request. Its leak guarantee is already enforced by the
   `leakCheck` test on the serialized claim.

8. **Delete what the proof now subsumes.** `verifyMerkleCommitment`,
   `verifyAttributeInMerkleTree`, the `merkleProof`/`merkleRoot`/`attributeValue`
   fields of `PredicateCircuit` that `toAiurBytecode` ignores, the "PENDING
   M2" test and comments, the `[Hash ByteArray]` dead binder, and the
   duplicated tree logic in `Main.lean`'s batch handler (it calls the same
   `generateCertificateWithSTARK`). `merkleToplevel`/`rootWords`/`pathBytes`
   move from the six test copies into `MerkleCircuit.lean` (or a small
   non-module helper if the `⟦⟧` DSL `G` clash makes that awkward) and the
   tests import them. Target: net-negative LOC for the milestone.

## Depth and performance

Depth is `ceil(log2 n)` for `n` attributes; `generateProof` duplicates the
last node on odd levels and the circuit folds whatever siblings it is given,
so odd counts need an in-circuit parity test (5 leaves) in addition to the
existing 8-leaf case. Depth 0 (one attribute) means the root is
`leafHash leaf` and the path is empty; it must prove and verify.

Measured so far (logBlowup 1, not the production 2): fused depth-3 prove
about 350 ms, verify about 30 ms, `batch1` about 475 ms with a 4.7 MB proof.
No depth-16 measurement exists. The plan includes one timing task at the
production parameters for depth 0, 3, 4 and 10 so `docs/performance.md`
states what shipping actually costs.

## Definition of done

- `/generate` with 8 attributes, index 2, predicate `> 1000` returns a
  certificate; `/verify` returns `verified: true`.
- Swap one byte of `commitment` in that certificate: `verified: false`.
- Change `threshold` in that certificate: `verified: false` (already true, stays).
- `/generate` with an index whose value fails the predicate: no certificate
  (500 "proof generation failed", not a fabricated one).
- `/generate` with a `merkleRoot` that does not match: 400.
- `/generate` with `privateAttribute`, with `>=`, or with an attribute
  `>= 2^32`: 400.
- Depth 0, depth 3 (8 leaves), odd count (5 leaves), and depth 4 (16 leaves)
  all prove and verify through the API path.
- `leakCheck` still passes: the attribute value is absent from `publicInputs`.
- The library entry `verifyCertificate` rejects the swapped-commitment
  certificate too (same `verifySTARKProof`).
- `grep natToByteArray` finds no leaf-encoding use.
- All test executables build; the eight correctness ones pass.

## Out of scope

- Binding attribute type or custom name into the leaf.
- K > 1 batch disclosure through the HTTP API (the batch entries exist; the
  API shape for them is a separate milestone).
- GPU (parked, see the M4 decision).
- Proving Aiur's STARK is zero-knowledge (still an open question, as in M1).
- `Optimization.lean`'s empty-proof path and `ZkIpProtocol.lean:24-27`
  which calls it; flagged for deletion in a separate cleanup.
