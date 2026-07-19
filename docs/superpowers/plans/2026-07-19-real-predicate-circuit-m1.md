# Real Predicate Circuit — Milestone 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Replace the vacuous, secret-leaking STARK circuit with a real Aiur circuit that constrains `attributeValue > threshold`, keeps `attributeValue` out of the public claim, and makes verification bind to caller-supplied inputs.

**Architecture:** Author the circuit in Aiur's `⟦ ⟧` DSL (`Ix.Aiur.Meta`) instead of manual `Source.Term` construction. Constrain the predicate with `u32_less_than` + `assert_eq!`. Carry `attributeValue` as private witness through an IO channel (`io_read`), so the public claim (`[channel, funIdx] ++ args ++ output`) contains only `threshold` and the output.

**Tech Stack:** Lean 4.29, Ix/Aiur (`Ix.Aiur.Meta` DSL, `AiurSystem.build/prove/verify`, `IOBuffer`), Goldilocks field.

## Global Constraints

- Lean toolchain `leanprover/lean4:v4.29.0`; ix at `main`. Do not change.
- Circuit authored via the `⟦ ⟧` DSL from `Ix.Aiur.Meta` (see reference `Tests/Aiur/Aiur.lean` in `.lake/packages/ix`). Do not resurrect the manual-`Term` stub.
- Public claim = `args ++ output`. `attributeValue` MUST NOT appear in `args` or in the emitted `STARKProof.publicInputs`/JSON. It is private witness via an IO channel.
- The constraint primitive is `assert_eq!`; a false predicate MUST make the proof fail to produce or fail to verify — never silently pass.
- Every constraint gets a NEGATIVE test that violates it and must fail. A circuit that only passes positive cases is the exact bug being fixed.
- Keep `lake build` green; keep `Tests.STARKTests`, `Tests.Validation.ProveVerifyRoundtrip`, `Tests.Validation.CpuBaseline` runnable.
- Work on branch `gpu-proving-backend` (continues the same branch).

## Reference material (read before Task 1)

- `.lake/packages/ix/Tests/Aiur/Aiur.lean` — how `⟦ pub fn f(x: G) -> G { ... } ⟧` circuits are written (arithmetic, `match`).
- `.lake/packages/ix/Tests/Aiur/Hashes.lean` — how private data is supplied via `IOBuffer` and read with the IO channel model.
- `.lake/packages/ix/Ix/Aiur/Meta.lean` — DSL syntax: `assert_eq!(a,b); ret`, `u32_less_than(a,b)`, `u8_less_than(a,b)`, `io_read(ch,idx,len)`, `io_get_info(ch,key)`, `u8_bit_decomposition`, `to_field`.
- Current stub to replace: `ZkIpProtocol/STARKIntegration.lean` `PredicateCircuit.toAiurBytecode` (~line 72), `generateSTARKProof` (~line 88), `verifySTARKProof` (~line 147).

---

### Task 1: Real constrained predicate circuit (fixes Critical 1)

Replace the stub (`ret (var "attr")`, which constrains nothing) with a DSL circuit that constrains `threshold < attributeValue`. Keep `attributeValue` as a public arg FOR NOW (Task 2 makes it private) so this task isolates the "does the constraint actually bind" question.

**Files:**
- Modify: `ZkIpProtocol/STARKIntegration.lean` (`toAiurBytecode`; add `import Ix.Aiur.Meta`)
- Create: `Tests/Validation/PredicateSoundness.lean`
- Modify: `lakefile.lean` (add `lean_exe Tests.Validation.PredicateSoundness`)

**Interfaces:**
- Consumes: `AiurSystem.build/prove/verify`, `generateSTARKProof`/`verifySTARKProof` (existing signatures for now).
- Produces: a `toAiurBytecode` whose Aiur function is `predicate_check(threshold: G, attr: G) -> G` that does `assert_eq!(u32_less_than(threshold, attr), 1); 1`. ABI: 2 inputs, 1 output.

- [ ] **Step 1: Write the failing soundness test**

Create `Tests/Validation/PredicateSoundness.lean`. Mirror the fixture style of `Tests/STARKTests.lean` (build a `PredicateCircuit`, call `generateSTARKProof` then `verifySTARKProof`). Two cases:

```lean
import ZkIpProtocol.STARKIntegration
import ZkIpProtocol.MerkleCommitment
import Ix.Aiur.Goldilocks

namespace Tests.Validation
open ZkIpProtocol Aiur

-- helper: build a circuit for a given attr/threshold and run prove->verify
def proveVerify (attr threshold : Nat) : IO Bool := do
  let merkleRoot ← buildMerkleTree #[]      -- root unused by the predicate in M1
  let circuit : PredicateCircuit :=
    { attributeValue := attr, merkleRoot, threshold,
      operator := ">", merkleProof := { rootHash := merkleRoot, path := #[], isLeft := #[] },
      output := true }
  let publicInputs : Array G := #[G.ofNat threshold]
  let privateInputs : Array G := #[G.ofNat attr]
  match ← generateSTARKProof circuit publicInputs privateInputs with
  | none => return false               -- could not prove
  | some proof => verifySTARKProof proof publicInputs circuit

def main : IO Unit := do
  -- positive: 1500 > 1000 must verify
  if !(← proveVerify 1500 1000) then throw (IO.userError "positive case failed to verify")
  IO.println "✓ positive: 1500 > 1000 verifies"
  -- negative: 500 > 1000 is false; must NOT verify (and ideally not prove)
  if (← proveVerify 500 1000) then throw (IO.userError "NEGATIVE case verified — constraint not binding!")
  IO.println "✓ negative: 500 > 1000 rejected"
  -- boundary: 1000 > 1000 is false; must NOT verify
  if (← proveVerify 1000 1000) then throw (IO.userError "boundary case verified — off-by-one")
  IO.println "✓ boundary: 1000 > 1000 rejected"
  IO.println "All predicate soundness tests passed"

end Tests.Validation
```

Add the exe to `lakefile.lean`:
```lean
lean_exe Tests.Validation.PredicateSoundness where
  root := `Tests.Validation.PredicateSoundness
  srcDir := "."
  supportInterpreter := true
```

- [ ] **Step 2: Run it, confirm it FAILS the right way**

Run: `lake exe Tests.Validation.PredicateSoundness`
Expected: FAIL on the NEGATIVE case (`NEGATIVE case verified — constraint not binding!`), because the current stub constrains nothing so `500 > 1000` still "verifies". If it fails on the positive case instead, the fixture is wrong — fix the fixture, not the circuit.

- [ ] **Step 3: Rewrite `toAiurBytecode` with a real constrained circuit**

Add `import Ix.Aiur.Meta` at the top of `STARKIntegration.lean`. Replace the stub body of `PredicateCircuit.toAiurBytecode` so the toplevel is authored via the DSL:

```lean
def PredicateCircuit.toAiurBytecode (_circuit : PredicateCircuit)
    : Except String (Bytecode.Toplevel × CircuitABI) := do
  let toplevel : Aiur.Source.Toplevel := ⟦
    pub fn predicate_check(threshold: G, attr: G) -> G {
      assert_eq!(u32_less_than(threshold, attr), 1);
      1
    }
  ⟧
  let compiled ← toplevel.compile.mapError toString
  let abi : CircuitABI :=
    { funIdx := compiled.getFuncIdx (Aiur.Global.mk `predicate_check).toName,
      privateInputCount := 1, publicInputCount := 1, outputCount := 1,
      claimSize := 2 + 1 + 1 + 1 }
  pure (compiled.bytecode, abi)
```

Notes for the implementer:
- Confirm the exact `compile`/`getFuncIdx`/`Toplevel` API against `Tests/Aiur/Common.lean` (it uses `toplevel.compile` and `compiled.getFuncIdx`); adapt names to what actually compiles.
- `u32_less_than(threshold, attr)` returns 1 iff `threshold < attr`, i.e. `attr > threshold` — the intended `>` semantics. If `u32_less_than` requires its inputs to be validated as u32 (< 2^32), add the range handling the DSL provides (`u8_bit_decomposition`/`u8_range_check`) until the negative test passes; the negative test is the oracle for "is the constraint real".
- The order of `args` passed by `generateSTARKProof` must match the function signature `(threshold, attr)`. Adjust the `args := publicInputs ++ privateInputs` construction if needed so positions line up.

- [ ] **Step 4: Run the soundness test, confirm all three cases pass**

Run: `lake build && lake exe Tests.Validation.PredicateSoundness`
Expected: PASS — positive verifies, negative and boundary rejected.

- [ ] **Step 5: Confirm existing tests still run**

Run: `lake exe Tests.Validation.ProveVerifyRoundtrip` (fixture may need its expected inputs updated to the new 2-arg signature — update it to match, it must still pass).
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ZkIpProtocol/STARKIntegration.lean Tests/Validation/PredicateSoundness.lean lakefile.lean Tests/Validation/ProveVerifyRoundtrip.lean
git commit -m "feat: real constrained predicate circuit (attr>threshold) replacing vacuous stub"
```

---

### Task 2: Move `attributeValue` to private witness (fixes Critical 2 — leak)

`attributeValue` is currently a public arg, so it lands in the claim and the emitted JSON. Move it into an IO-channel witness read with `io_read`, so the public claim is only `[threshold] ++ output`.

**Files:**
- Modify: `ZkIpProtocol/STARKIntegration.lean` (circuit reads attr from IO; `generateSTARKProof` puts attr in the `IOBuffer`, not `args`)
- Modify: `Tests/Validation/PredicateSoundness.lean` (add a leak assertion)

**Interfaces:**
- Consumes: `AiurSystem.prove` `IOBuffer` argument; `io_read(channel, idx, len)` in the DSL; `IOBuffer` construction per `Tests/Aiur/Hashes.lean` (`⟨.ofList [(0, data)], .ofList [((0, key), range)]⟩`).
- Produces: circuit `predicate_check(threshold: G) -> G` that reads `attr` from IO channel 0; `generateSTARKProof` supplying attr via `IOBuffer`; public claim without attr.

- [ ] **Step 1: Add the failing leak test**

In `PredicateSoundness.lean`, add a check that the serialized proof does not contain the secret. After a positive `generateSTARKProof`, assert the private value's byte-encoding is absent from every entry of `proof.publicInputs`:

```lean
def leakCheck (attr threshold : Nat) : IO Unit := do
  -- build as before but inspect the proof's public inputs
  ...
  let some proof := (← generateSTARKProof circuit #[G.ofNat threshold] #[G.ofNat attr]) | throw (IO.userError "prove failed")
  let secret := natToBytes8BE attr
  if proof.publicInputs.any (· == secret) then
    throw (IO.userError "LEAK: private attributeValue present in proof.publicInputs")
  IO.println "✓ no leak: attributeValue absent from public inputs"
```
Wire `leakCheck 1500 1000` into `main`.

- [ ] **Step 2: Run, confirm the leak test FAILS**

Run: `lake exe Tests.Validation.PredicateSoundness`
Expected: FAIL with `LEAK: ...` — today attr is a public arg so its 8-byte encoding is in `proof.publicInputs`.

- [ ] **Step 3: Make attr private via IO**

- Circuit: change the signature to `pub fn predicate_check(threshold: G) -> G { let attr = io_read(0, 0, 1)[0]; assert_eq!(u32_less_than(threshold, attr), 1); 1 }`. Confirm `io_read` return type indexing against `Meta.lean`/`Hashes.lean` (it returns an array of `len` field elements).
- `generateSTARKProof`: pass only `#[threshold]` as `args`; build an `IOBuffer` placing `#[G.ofNat attr]` on channel 0 (mirror the `IOBuffer` literal in `Hashes.lean`), and pass it to `AiurSystem.prove`. Update ABI: `publicInputCount := 1, privateInputCount := 1` (private now via IO, not args).
- Ensure `proof.publicInputs` is built from the claim which now excludes attr.

- [ ] **Step 4: Run, confirm leak test passes and soundness still holds**

Run: `lake build && lake exe Tests.Validation.PredicateSoundness`
Expected: PASS — positive verifies, negative/boundary rejected, AND no-leak passes.

- [ ] **Step 5: Commit**

```bash
git add ZkIpProtocol/STARKIntegration.lean Tests/Validation/PredicateSoundness.lean
git commit -m "feat: carry attributeValue as private IO witness so it is not in the public claim"
```

---

### Task 3: Bind verification to caller-supplied inputs (fixes the Important finding)

`verifySTARKProof` reconstructs the claim solely from `proof.publicInputs`, so a verifier cannot check the proof against an expected `threshold`. Make verify build the expected public claim from the caller's `publicInputs` and reject on mismatch. Fix `Advertisement.verifyCertificate` passing `#[]`.

**Files:**
- Modify: `ZkIpProtocol/STARKIntegration.lean` (`verifySTARKProof` uses caller `publicInputs`)
- Modify: `ZkIpProtocol/Advertisement.lean` (`verifyCertificate` passes the real expected public inputs, not `#[]`)
- Modify: `Tests/Validation/PredicateSoundness.lean` (verify-binding test)

**Interfaces:**
- Consumes: caller-supplied `publicInputs : Array G` (the `_publicInputs` arg that is currently ignored).
- Produces: `verifySTARKProof` that fails when the caller's expected `threshold` differs from the proof's.

- [ ] **Step 1: Add the failing verify-binding test**

```lean
-- prove for threshold=1000, then verify claiming threshold=2000 -> must be false
def bindingCheck : IO Unit := do
  ... (build circuit with threshold 1000, attr 1500, prove) ...
  let some proof := (← generateSTARKProof circuit #[G.ofNat 1000] #[G.ofNat 1500]) | throw (IO.userError "prove failed")
  if (← verifySTARKProof proof #[G.ofNat 2000] circuit) then
    throw (IO.userError "verify accepted a mismatched threshold — not bound to caller inputs")
  if !(← verifySTARKProof proof #[G.ofNat 1000] circuit) then
    throw (IO.userError "verify rejected the correct threshold")
  IO.println "✓ verify binds to caller-supplied threshold"
```
Wire into `main`.

- [ ] **Step 2: Run, confirm it FAILS**

Run: `lake exe Tests.Validation.PredicateSoundness`
Expected: FAIL with `verify accepted a mismatched threshold ...` — today `_publicInputs` is ignored.

- [ ] **Step 3: Bind verify to caller inputs**

In `verifySTARKProof`, build the expected claim using the caller's `publicInputs` for the public positions (threshold + expected output) rather than trusting `proof.publicInputs` wholesale, and pass that expected claim to `AiurSystem.verify`. Concretely: reconstruct `claim` so that the public arg positions come from the caller's `publicInputs`; if the proof's own claim disagrees with the caller's expected public inputs, return `false` before/at verification. Rename the `_publicInputs` parameter to `publicInputs` (it is now used).

- [ ] **Step 4: Fix the caller**

In `Advertisement.verifyCertificate` (~line 74), pass the actual expected public inputs (the threshold used, as `Array G`) instead of `#[]`.

- [ ] **Step 5: Run all soundness tests**

Run: `lake build && lake exe Tests.Validation.PredicateSoundness`
Expected: PASS — positive, negative, boundary, no-leak, and verify-binding all pass.

- [ ] **Step 6: Confirm the wider suite still runs**

Run: `lake exe Tests.STARKTests && lake exe Tests.Validation.ProveVerifyRoundtrip`
Expected: both run; update their expected public inputs if the signature change requires it (they must pass).

- [ ] **Step 7: Commit**

```bash
git add ZkIpProtocol/STARKIntegration.lean ZkIpProtocol/Advertisement.lean Tests/Validation/PredicateSoundness.lean Tests/STARKTests.lean Tests/Validation/ProveVerifyRoundtrip.lean
git commit -m "fix: bind STARK verification to caller-supplied public inputs"
```

---

## Self-Review

- **Spec coverage (M1):** Critical 1 (vacuous circuit) → Task 1. Critical 2 (leak) → Task 2. Important (verify not bound) → Task 3. The ZK-hiding caveat is documentation, not code, and is out of M1 code scope (spec §"Zero-knowledge caveat"). M2 (Merkle) is a separate plan. All M1 spec items map to a task.
- **Placeholders:** the circuit body is concrete DSL; the one genuine unknown (whether `u32_less_than` needs explicit u32 range-checks) is driven by the mandatory negative test, which is the correct oracle, not a placeholder.
- **Type consistency:** `predicate_check` signature evolves `(threshold, attr)` [Task 1] → `(threshold)` with `attr` via `io_read` [Task 2]; each task updates the ABI (`publicInputCount`/`privateInputCount`) and the `generateSTARKProof` arg/IO construction in lockstep. `verifySTARKProof(proof, publicInputs, circuit)` signature is stable; only the body's use of `publicInputs` changes [Task 3]. `natToBytes8BE` (from the earlier P0 work) is reused in the leak test.
