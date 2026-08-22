# Real Predicate Circuit — Design Spec

**Date:** 2026-07-19
**Status:** Design, pending review
**Supersedes the GPU work as the immediate priority** (GPU resumes once the circuit proves a real statement — see `2026-07-18-gpu-proving-backend-design.md`).

## Why

The final Codex review of the P0 branch found the STARK circuit is unsound and non-private (both confirmed in source):

- **Critical 1 — proves nothing.** `PredicateCircuit.toAiurBytecode` (`STARKIntegration.lean:72`) ignores its `_circuit` argument. The Aiur body is `ret (var "attr")` — it returns the attribute and constrains nothing: not the threshold, not the `>` predicate, not Merkle membership, not the output. The verifying proof is vacuous.
- **Critical 2 — leaks the secret.** `args := publicInputs ++ privateInputs`; the whole claim (`[channel, funIdx] ++ args ++ output`) including the private `attributeValue` is serialized into `STARKProof.publicInputs` and emitted as JSON (`Api.lean`). Not zero-knowledge.
- **Important — verify not bound to caller.** `verifySTARKProof` rebuilds the claim solely from `proof.publicInputs`, ignoring the verifier-supplied expected inputs; a verifier cannot check the proof against an expected root/threshold.

Accelerating a proof-of-nothing with a GPU is pointless. This spec builds a circuit that actually proves the intended statement, without leaking the secret.

## Aiur model (established from ix source)

- **Public claim = function `args` ++ `output`.** These are revealed to the verifier. Anything placed in `args` is public.
- **Private witness = IO channels.** Data supplied through the `IOBuffer` (`ioRead`/`ioGetInfo`) is part of the execution/witness and is NOT in the claim. This is how ix's `Tests/Aiur/Hashes.lean` feeds input bytes.
- **Constraint primitives:** `assertEq` and `eqZero` (the stub uses neither). Comparison: `u32LessThan` / `u8LessThan` with `u8BitDecomposition`. Hashing: Blake3 as an in-circuit gadget (`Ix.IxVM.Blake3`), the same Blake3 the app's commitment uses.

### Zero-knowledge caveat (do not overclaim)

Keeping `attributeValue` out of the claim fixes the blatant **disclosure** (Critical 2). Full **zero-knowledge** (the verifier provably learns nothing about `attributeValue` beyond the predicate) additionally requires Aiur's STARK to be zero-knowledge (randomized/blinded). That property is unverified here. This spec commits to *no disclosure in the public claim*; it does NOT claim cryptographic hiding until Aiur's ZK property is confirmed. Docs must reflect this distinction.

## Milestones (user decision 2026-07-19: predicate first, then Merkle)

### Milestone 1 — constrained, non-leaking predicate

Statement proved: "I know a private `attributeValue` such that `attributeValue > threshold`", where `threshold` is public and `attributeValue` is never revealed in the claim.

- **Public args:** `[threshold]`. **Output:** `[satisfied]` (= 1).
- **Private witness (IO channel):** `attributeValue`.
- **Body:**
  1. Read `attributeValue` from the private IO channel.
  2. Constrain `attributeValue > threshold` using `u32LessThan` (decompose as needed) and `assertEq` the comparison result to `1`. A false predicate must make the proof unprovable/unverifiable, not silently pass.
  3. Return `output = 1`.
- **Verify:** `verifySTARKProof` must build the expected claim from the **caller-supplied** `threshold` (+ expected output), not solely from the proof, and reject on mismatch.
- **`generateSTARKProof` change:** `attributeValue` moves from `args` into the IO buffer; only `threshold` (+ output) remain public. The emitted `STARKProof.publicInputs` must contain no private value.

**Definition of done (M1):**
- Positive: `attributeValue > threshold` ⇒ proof generates and verifies.
- Negative: `attributeValue <= threshold` ⇒ proof cannot be produced OR fails to verify (test both a value equal to and below threshold).
- Leak test: the serialized `STARKProof.publicInputs` (and JSON) does NOT contain `attributeValue`.
- Verify-binding test: verifying with a different `threshold` than was proven fails.

### Milestone 2 — Merkle membership binding (closes ad-switch)

Adds: the proven `attributeValue` is the one committed in the public Merkle root, so an advertiser cannot swap the value.

- **Public args:** `[merkleRoot, threshold]` (root as field element(s) — see note). **Output:** `[satisfied]`.
- **Private witness (IO channel):** `attributeValue`, Merkle path (sibling hashes + left/right directions).
- **Body:** M1 predicate, PLUS recompute the Merkle root from the `attributeValue` leaf and the path using the in-circuit Blake3 gadget, and `assertEq` the recomputed root to the public `merkleRoot`. Same Blake3 as `CoreTypes.Hash` so on-chain/off-chain roots match.
- **Root representation:** a Blake3 root is 256 bits; a single Goldilocks field element is ~64 bits. Bind the full root across multiple field elements (e.g. 4 × u64 limbs) so binding is full-width, resolving the ~64-bit weakness the earlier review flagged. Decide exact limb layout during M2 planning against the gadget's output shape.

**Definition of done (M2):**
- Positive: correct `attributeValue` + valid path to `merkleRoot`, and predicate holds ⇒ verifies.
- Negative: wrong path / wrong leaf / value not under the committed root ⇒ fails.
- Ad-switch test: proving a different `attributeValue` than the committed one fails.

## Files (expected)

- `ZkIpProtocol/STARKIntegration.lean` — rewrite `PredicateCircuit.toAiurBytecode` to emit a real constrained circuit; change `generateSTARKProof`/`verifySTARKProof` public/private split; verify binds to caller inputs.
- `ZkIpProtocol/Api.lean` — ensure emitted proof JSON carries only public claim, never private witness.
- `Tests/Validation/PredicateSoundness.lean` (new) — positive + negative + leak + verify-binding tests (M1); Merkle/ad-switch tests (M2).
- Possibly a small Aiur circuit-builder helper module if `toAiurBytecode` grows.

## Correctness discipline

- Negative tests are mandatory and first-class: a circuit that only passes positive cases is exactly the bug we are fixing. Every constraint gets a test that violates it and must fail.
- No `_circuit`-ignored parameters: the circuit is a function of the actual predicate/root.
- Keep the Lean-verified-soundness posture: the Aiur circuit encodes the statement; the STARK proves the circuit; tests prove the circuit rejects false statements.

## Out of scope

- GPU acceleration (resumes after M2; a real, larger circuit is where GPU finally matters).
- Operators beyond `>` initially (generalize after `>` is correct).
- ZKMB and the other non-compiling modules.
- Proving Aiur's STARK is zero-knowledge (flagged as an open cryptographic question, not solved here).
