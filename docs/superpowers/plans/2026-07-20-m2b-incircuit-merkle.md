# M2b — In-Circuit Blake3 Merkle Membership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Bind the proven `attributeValue` to the committed Merkle root inside the circuit — recompute the root from a private leaf + path using the Aiur Blake3 gadget and `assertEq` it to the public root — closing the Ad-Switch attack. This is the expensive, large circuit that motivates GPU acceleration.

**Architecture:** Compose the ix `IxVM.blake3` + `IxVM.byteStream` DSL toplevels with our predicate toplevel (merge their `dataTypes`/`typeAliases`/`functions`), call `blake3` from the circuit, and verify the recomputed root matches the public root. The in-circuit hashing MUST reproduce the M2a reference exactly: leaf = `Blake3(0x00 ++ bytes)`, node = `Blake3(0x01 ++ left ++ right)`, duplicate-last on odd.

**Tech Stack:** Lean 4.29, ix `IxVM.blake3`/`IxVM.byteStream` (Aiur DSL gadgets, digest type `[[U8;4];8]`, input via `#read_byte_stream` over IO channels), Aiur `Source.Toplevel`, Goldilocks.

## Global Constraints

- The in-circuit Merkle recomputation MUST match `ZkIpProtocol/MerkleCommitment.verifyProof` (the M2a reference) bit-for-bit: same leaf/node domain prefixes (0x00/0x01), same duplicate-last-on-odd, same fold direction. Any divergence is a bug.
- Blake3 gadget output is `[[U8;4];8]` (32 bytes). The public root must be bound across enough field elements to cover the full 256 bits (resolving the earlier ~64-bit binding weakness) — decide exact limb layout in the spike.
- Every constraint gets a NEGATIVE test: wrong leaf, wrong sibling, wrong root, wrong path must all fail to prove/verify.
- Do not weaken M1: the predicate constraint and no-leak/verify-binding properties must still hold.
- Branch `gpu-proving-backend`.

## Reconnaissance (established, see ledger)

- `IxVM.blake3` (`.lake/packages/ix/Ix/IxVM/Blake3.lean`) is a DSL `⟦ ⟧` toplevel: `fn blake3(input: ByteStream) -> [[U8;4];8]`, reads input via `#read_byte_stream(0, idx, len)` (a macro) + `io_get_info`, depends on `IxVM.byteStream` and custom enums (Layer, MaybeDigest).
- Our predicate circuit is authored with explicit `Source.Term` (the `⟦⟧` DSL's `G` token collides with `abbrev G := Aiur.G` in the legacy file). But we can `import Ix.IxVM.Blake3` to get the already-elaborated `IxVM.blake3 : Source.Toplevel` VALUE (no DSL macro needed) and merge its `.functions`/`.dataTypes`/`.typeAliases` with ours.
- No toplevel-merge helper exists; `Source.Toplevel = { dataTypes, typeAliases, functions }` arrays → concatenate (dedup as needed).

---

### Task 1 (SPIKE): call Blake3 in-circuit, digest matches the reference

De-risk the whole milestone. Deliverable: a proof whose circuit calls the ix `blake3` gadget on known input bytes supplied via IO, and whose output digest EQUALS `Blake3.Rust.hash` of the same bytes (the reference Blake3 the M2a scheme commits with). If this cannot be made to work, report BLOCKED with the exact obstacle — do not proceed to the path circuit.

**Files:**
- Create: `ZkIpProtocol/Blake3Circuit.lean` (helpers to merge `IxVM.blake3`+`IxVM.byteStream` toplevels with an entry function that hashes IO-supplied bytes)
- Create: `Tests/Validation/Blake3CircuitSpike.lean`
- Modify: `lakefile.lean`

**Interfaces:**
- Produces: a function that builds a `Source.Toplevel` containing the blake3 gadget + an entry `hash_bytes` (or reuses `blake3_test`) that reads bytes from IO channel 0 and returns the digest; a Lean-side harness that proves it and extracts the digest.

- [ ] **Step 1: Learn the merge + call mechanics.** Read `.lake/packages/ix/Ix/IxVM/Blake3.lean`, `ByteStream.lean`, and `Tests/Aiur/Hashes.lean` (which already proves `blake3_test` over an IOBuffer). Determine: how `blake3_test`'s toplevel is assembled (does `IxVM.blake3` already include byteStream, or must both be merged?), how the input IOBuffer is shaped for channel 0, and how the `[[U8;4];8]` digest appears in the output/claim. Write findings into the report as you go.

- [ ] **Step 2: Reproduce the ix blake3 test path.** The simplest viable spike is to reuse ix's own `blake3_test` toplevel + IOBuffer shape (from `Tests/Aiur/Hashes.lean`) via `AiurSystem.build/prove`, and confirm the produced digest equals `(Blake3.Rust.hash inputBytes).val`. This proves we can invoke the gadget and that its output matches the reference Blake3. (If `Tests/Aiur/Hashes.lean` is not importable from this repo, replicate its toplevel-construction pattern.)

- [ ] **Step 3: Assert digest == reference.** Test: for several input byte lengths (0, 1, 32, 65 — 65 = a node preimage `0x01 ++ 32 ++ 32`), the in-circuit blake3 digest (recomposed from `[[U8;4];8]` to a 32-byte ByteArray) equals `(Blake3.Rust.hash inputBytes).val`. This is the load-bearing fact: the gadget computes the SAME Blake3 as the M2a scheme.

- [ ] **Step 4: Decide root-limb layout.** From how the digest surfaces as field elements, decide how to bind the full 32-byte root as public input(s) (e.g. 8× u32 words or 4× u64 limbs). Record the decision — it drives Task 2.

- [ ] **Step 5: Commit** `spike: call ix blake3 gadget in-circuit; digest matches reference Blake3` (include the report). If BLOCKED, commit the findings and STOP for re-planning.

**Exit criterion:** a passing test that the in-circuit blake3 digest equals `Blake3.Rust.hash` for node-sized (65-byte) input, plus a recorded limb layout. Only then plan/execute Task 2.

---

### Task 2 (post-spike, to be detailed after Task 1): in-circuit path recomputation

Sketch only — detailed steps depend on the spike's merge/call/limb findings:
- Circuit reads (private, via IO) the leaf bytes, the sibling hashes, and the direction bits for a fixed-depth path.
- For each level, compute `nodeHash` in-circuit via the blake3 gadget on `0x01 ++ (ordered acc,sibling)`, matching M2a's fold.
- `assertEq` the final recomputed root (as limbs) to the PUBLIC root limbs.
- Keep the M1 predicate `assertEq(u32LessThan(threshold, attr), 1)` in the same circuit.
- Negative tests mirror M2a: wrong leaf / sibling / direction / root ⇒ unprovable or unverifiable; a value not under the committed root cannot produce a passing proof (ad-switch closed).
- Re-baseline: record the (much larger) proving time — this is the GPU-justifying number.

A dedicated planning pass writes Task 2's bite-sized steps once Task 1 reports the exact mechanics.

## Self-Review

- **Spec coverage:** M2b = in-circuit membership (spec §M2, the hard half). Task 1 de-risks the gadget call + reference match + limb layout; Task 2 (path recomputation + root binding + ad-switch negatives) is deliberately sketched pending spike facts — detailing it now would invent the merge/call API.
- **Placeholders:** Task 2 is intentionally a sketch (honest: its steps depend on Task 1's discovery); Task 1 is concrete with a definite exit criterion.
- **Consistency:** the in-circuit hash must equal `Blake3.Rust.hash` (Task 1 gate) and reproduce `MerkleCommitment.verifyProof` (Task 2), the M2a reference — same prefixes, same fold, same odd-rule.
