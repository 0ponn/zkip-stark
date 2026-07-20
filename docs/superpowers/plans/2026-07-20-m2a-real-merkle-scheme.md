# M2a — Real Blake3 Merkle Scheme (off-circuit) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Replace the stub Merkle commitment (unhashed leaves, no path generation, always-empty `MerkleProof`) with a real, domain-separated Blake3 binary Merkle scheme with genuine path generation and reference verification — the off-circuit foundation the in-circuit M2b membership check will mirror.

**Architecture:** Pure-Lean `ByteArray` Blake3 tree in `MerkleCommitment.lean`. Leaf and node hashing are domain-separated (distinct prefixes) to prevent second-preimage/leaf-node confusion. `Hash.hash` is Blake3 (from P0). No circuit work here (that is M2b).

**Tech Stack:** Lean 4.29, `Hash.hash : ByteArray → ByteArray` (Blake3, 32 bytes), `CoreTypes.MerkleProof { rootHash, path : Array ByteArray, isLeft : Array Bool }`.

## Global Constraints

- `Hash.hash` = Blake3-256 (do not reintroduce NoCap/Poseidon). Drop the `NoCapFFI` dependency from `MerkleCommitment.lean`.
- Domain separation is mandatory: leaf hash and node hash MUST use distinct byte prefixes so `leafHash(x) ≠ nodeHash(a,b)` structurally.
- Every verification property gets a NEGATIVE test that violates it and must fail (tampered leaf, sibling, direction, root).
- Keep `lake build` green and the M1 tests (`PredicateSoundness`, `ProveVerifyRoundtrip`, `STARKTests`) still passing.
- `MerkleReconstruction.lean` holds separate FIELD-based in-circuit scaffolding for M2b — do NOT modify it here; M2a is `ByteArray`-based in `MerkleCommitment.lean`.
- Branch `gpu-proving-backend`.

## Hashing convention (fix this exactly)

- `leafHash (b : ByteArray) : ByteArray := Hash.hash (ByteArray.mk #[0x00] ++ b)`
- `nodeHash (l r : ByteArray) : ByteArray := Hash.hash ((ByteArray.mk #[0x01] ++ l) ++ r)`
- Odd node count at a level: duplicate the last node (`nodeHash last last`).
- Tree over the ordered leaf byte-arrays; root of a single leaf `[b]` is `leafHash b`; root of empty is `Hash.hash ByteArray.empty` (documented edge).

---

### Task 1: Domain-separated Blake3 tree + deterministic root

**Files:**
- Modify: `ZkIpProtocol/MerkleCommitment.lean` (rewrite `buildMerkleTree`; add `leafHash`/`nodeHash`; remove `import ZkIpProtocol.NoCapFFI` and the `HardwareCtx`/`poseidonHashFFI` usage)
- Create: `Tests/Validation/MerkleScheme.lean`
- Modify: `lakefile.lean` (add `lean_exe Tests.Validation.MerkleScheme`)

**Interfaces:**
- Produces: `leafHash (b : ByteArray) : ByteArray`, `nodeHash (l r : ByteArray) : ByteArray`, `buildMerkleTree (data : Array ByteArray) : IO ByteArray` (now hashing leaves via `leafHash` and internal nodes via `nodeHash`).

- [ ] **Step 1: Write failing tests** in `Tests/Validation/MerkleScheme.lean`:

```lean
import ZkIpProtocol.MerkleCommitment
namespace Tests.Validation
open ZkIpProtocol

def b (xs : List UInt8) : ByteArray := ByteArray.mk xs.toArray

def main : IO Unit := do
  -- domain separation: leafHash(x) != nodeHash(x, empty-ish) structurally
  if leafHash (b [1,2]) == nodeHash (b [1,2]) (b []) then
    throw (IO.userError "leaf and node hashes collide — no domain separation")
  -- determinism
  let r1 ← buildMerkleTree #[b [1], b [2], b [3]]
  let r2 ← buildMerkleTree #[b [1], b [2], b [3]]
  if r1 != r2 then throw (IO.userError "root not deterministic")
  if r1.size != 32 then throw (IO.userError s!"root not 32 bytes: {r1.size}")
  -- sensitivity: changing a leaf changes the root
  let r3 ← buildMerkleTree #[b [1], b [2], b [9]]
  if r1 == r3 then throw (IO.userError "root insensitive to leaf change")
  -- known two-leaf tree: root == nodeHash(leafHash a, leafHash b)
  let two ← buildMerkleTree #[b [1], b [2]]
  if two != nodeHash (leafHash (b [1])) (leafHash (b [2])) then
    throw (IO.userError "two-leaf root != nodeHash(leafHash a, leafHash b)")
  IO.println "All Merkle scheme tests passed"

end Tests.Validation
```
Add the exe to `lakefile.lean`.

- [ ] **Step 2: Run, confirm FAIL** — `lake exe Tests.Validation.MerkleScheme` fails (current `buildMerkleTree` leaves are unhashed and it uses NoCap, so the known-answer and domain-separation checks fail; `leafHash`/`nodeHash` don't exist yet → fix the test compile by adding the defs in Step 3).

- [ ] **Step 3: Implement** in `MerkleCommitment.lean`: remove `import ZkIpProtocol.NoCapFFI`; add `leafHash`/`nodeHash` per the convention; rewrite `buildMerkleTree` to hash each leaf with `leafHash` at the base and combine with `nodeHash` (duplicate last on odd counts). Keep it `IO` only if needed (Blake3 via `Hash.hash` is pure — prefer making `buildMerkleTree` pure `def ... : ByteArray`, updating callers; if that ripples too far, keep the `IO` signature).

- [ ] **Step 4: Run, confirm PASS**; then `lake build` green and `lake exe Tests.STARKTests` / `Tests.Validation.PredicateSoundness` still pass (M1 unaffected — it does not depend on the tree contents).

- [ ] **Step 5: Commit** `feat: real domain-separated Blake3 Merkle tree (drop NoCap stub)`.

---

### Task 2: Real path generation + reference verification

**Files:**
- Modify: `ZkIpProtocol/MerkleCommitment.lean` (add `generateProof`, `verifyProof`)
- Modify: `Tests/Validation/MerkleScheme.lean` (path tests)

**Interfaces:**
- Consumes: `leafHash`, `nodeHash`, `buildMerkleTree` (Task 1); `MerkleProof { rootHash, path : Array ByteArray, isLeft : Array Bool }` from `CoreTypes`.
- Produces:
  - `generateProof (data : Array ByteArray) (index : Nat) : Option MerkleProof` — `path` = sibling hashes leaf→root, `isLeft` = whether the sibling is on the left at each level, `rootHash` = the tree root. `none` if index out of range.
  - `verifyProof (leaf : ByteArray) (proof : MerkleProof) : Bool` — recompute: start `acc := leafHash leaf`; for each `(sib, sibIsLeft)` fold `acc := if sibIsLeft then nodeHash sib acc else nodeHash acc sib`; return `acc == proof.rootHash`. This is the reference the in-circuit M2b check must match bit-for-bit.

- [ ] **Step 1: Write failing tests** appended to `MerkleScheme.lean`:

```lean
def leaves : Array ByteArray := #[b [1], b [2], b [3], b [4]]

def pathMain : IO Unit := do
  let root ← buildMerkleTree leaves
  for i in [0:leaves.size] do
    let some proof := generateProof leaves i | throw (IO.userError s!"no proof for index {i}")
    if proof.rootHash != root then throw (IO.userError s!"proof root mismatch at {i}")
    if !verifyProof (leaves[i]!) proof then throw (IO.userError s!"valid proof rejected at {i}")
    -- negative: wrong leaf must fail
    if verifyProof (b [99]) proof then throw (IO.userError s!"tampered leaf accepted at {i}")
    -- negative: flip a direction bit (if any) must fail
    if proof.isLeft.size > 0 then
      let bad := { proof with isLeft := proof.isLeft.set! 0 (!proof.isLeft[0]!) }
      if verifyProof (leaves[i]!) bad then throw (IO.userError s!"flipped-direction proof accepted at {i}")
    -- negative: tamper a sibling must fail
    if proof.path.size > 0 then
      let bad := { proof with path := proof.path.set! 0 (b [123]) }
      if verifyProof (leaves[i]!) bad then throw (IO.userError s!"tampered-sibling proof accepted at {i}")
  IO.println "All Merkle path tests passed"
```
Call `pathMain` from `main`.

- [ ] **Step 2: Run, confirm FAIL** (`generateProof`/`verifyProof` undefined).

- [ ] **Step 3: Implement** `generateProof` and `verifyProof` in `MerkleCommitment.lean` per the Interfaces. `generateProof` walks the level arrays (same leaf-hash + duplicate-last-on-odd convention as `buildMerkleTree`), collecting the sibling and its side at each level. Ensure `verifyProof` uses the SAME leaf/node hashing and the SAME odd-duplication rule so the round-trip closes for every index.

- [ ] **Step 4: Run, confirm PASS** (all indices round-trip; all four negative cases reject). `lake build` green; M1 tests still pass.

- [ ] **Step 5: Commit** `feat: real Merkle path generation + reference verification with negative tests`.

---

## Self-Review

- **Spec coverage:** M2a = a real Merkle scheme (spec `2026-07-19-real-predicate-circuit-design.md` §M2, the off-circuit half). Task 1 = tree+root+domain separation; Task 2 = path gen + reference verify with negatives. M2b (in-circuit Blake3 membership + full-256-bit root binding across field limbs) is the follow-up plan.
- **Placeholders:** none — hashing convention and both function contracts are concrete; `verifyProof` is the exact reference M2b must match.
- **Type consistency:** `leafHash`/`nodeHash : ByteArray → ByteArray`; `generateProof : Array ByteArray → Nat → Option MerkleProof`; `verifyProof : ByteArray → MerkleProof → Bool`. `MerkleProof` fields (`rootHash`, `path`, `isLeft`) match `CoreTypes`. The fold direction in `verifyProof` (sibling side) matches how `generateProof` records `isLeft`.
