# M5 Merkle Binding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the production certificate path prove the fused predicate + Merkle-membership circuit so a certificate's `commitment` is bound by its proof.

**Architecture:** A new non-module file `ZkIpProtocol/FusedCircuit.lean` owns the merged Aiur toplevel, the lazily cached `AiurSystem`, and the encoders (`rootWords`, `pathBytes`, `fusedIO`) that today live in six test copies. `STARKIntegration.lean` loses `PredicateCircuit`/`CircuitABI`/`toAiurBytecode` and its prove/verify/certificate functions take `(threshold, root, leaf, path)` instead. `Api.lean` derives the witness from `attributes[attributeIndex]`, recomputes the root, and shares one `generateFromJson` with the batch handler in `Main.lean`.

**Tech Stack:** Lean 4.29, ix/Aiur (pinned fork `0ponn/ix@794037e`), Blake3 in-circuit gadget, Lake test executables.

**Spec:** `docs/superpowers/specs/2026-10-03-m5-merkle-binding-design.md`

## Global Constraints

- Circuit entry is `merkle_predicate_batch1` (variable depth). Never `merkle_predicate` (depth 3 only).
- Claim layout: `[0, funIdx, threshold, r0..r7, 1]`, 12 elements, each serialized as 8-byte big-endian in `STARKProof.publicInputs`.
- Root words: word `i` = LE u32 of root bytes `[4i, 4i+3]`; eight words.
- Leaf encoding: `attrLeafBytes` (4-byte LE). Every attribute value and threshold `< 2^32`, enforced at the Nat level before any `G.ofNat`.
- Path encoding: per level, one direction byte (`1` = sibling on the left, i.e. `isLeft = true`) then 32 sibling bytes, leaf level first. Depth 0 is an empty path.
- Production parameters stay `logBlowup := 2`, `numQueries := 100`, PoW 20 bits (`starkCommitmentParams`, `starkFriParams`, moved to `FusedCircuit.lean`).
- No `Proof.ofBytes` on bytes that did not come from `toBytes` in the same process; verification uses `ofBytesChecked`.
- Test executables must be named explicitly: `lake build <exe>` then run `.lake/build/bin/<name>`. A bare `lake build` only builds the library.
- No em-dashes in code, comments, strings, or docs.
- Commit after every task; messages state intent; end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Review Focus

Inputs the spec implies but no existing test exercises. Each gets a test in the task named.

1. One attribute (depth 0, empty path): must prove and verify. Task 2 `proveVerify` builds a single-leaf tree.
2. Odd leaf count (5): `generateProof` duplicates the last node; the circuit must accept the resulting sibling. Task 5.
3. `attributeIndex` out of range: 400, not a crash from `generateProof` returning `none`. Task 3.
4. Attribute value exactly `2^32 - 1` with threshold `2^32 - 2`: proves (boundary of the u32 guard). Task 2.
5. Certificate whose `proof.publicInputs` has 12 entries but `claim[1]` is a different function index (a proof of some other entry in the merged toplevel): rejected by the `funIdx` check. Task 2 `funIdxBindingCheck` tampers the serialized entry.

---

### Task 1: FusedCircuit.lean, the shared toplevel, system cache, and encoders

**Files:**
- Create: `ZkIpProtocol/FusedCircuit.lean`
- Modify: `Tests/Validation/MerklePredicate.lean:45-73` (delete local `commitmentParameters`, `friParameters`, `merkleToplevel`, `rootWords`, `publicArgs`, `outputOne`; keep `buildIO`, it is the depth-3 7-channel layout for `merkle_predicate`, which this test still targets)
- Modify: `lakefile.lean` (no change expected; `ZkIpProtocol` lib globs the directory. Verify.)

**Interfaces:**
- Produces:
  ```lean
  namespace ZkIpProtocol
  def starkCommitmentParams : Aiur.CommitmentParameters   -- moved from STARKIntegration (Task 2 deletes the old copy)
  def starkFriParams : Aiur.FriParameters
  structure FusedSystem where
    bytecode : Aiur.Bytecode.Toplevel
    funIdx : Aiur.Bytecode.FunIdx          -- of merkle_predicate_batch1
    system : Aiur.AiurSystem
  def fusedToplevel : Except Aiur.Global Aiur.Source.Toplevel
  def buildFusedSystem (c : Aiur.CommitmentParameters) (f : Aiur.FriParameters) : Except String FusedSystem
  def fusedSystem : IO FusedSystem        -- lazy, cached, production params
  def fusedClaimSize : Nat := 12
  def rootWordNats (root : ByteArray) : Array Nat          -- 8 LE u32 words
  def rootWords (root : ByteArray) : Array Aiur.G := (rootWordNats root).map Aiur.G.ofNat
  def fusedPublicInputs (threshold : Nat) (root : ByteArray) : Array Nat := #[threshold] ++ rootWordNats root
  def pathBytes (proof : MerkleProof) : Array Aiur.G     -- dir ‖ sib per level
  def fusedIO (leaf : ByteArray) (proof : MerkleProof) : Aiur.IOBuffer
  def outputOne : Array Aiur.G := #[Aiur.G.ofNat 1]
  ```
- Spike result to record in the file header: whether a non-module file that imports `ZkIpProtocol.MerkleCircuit` can still write a bare `G` identifier. If not, library files that import `FusedCircuit` must write `Aiur.G` (Task 2 does the rename; counts are small: Api 10, STARKIntegration 13, Performance 4, Advertisement 1).

- [ ] **Step 1: Write the failing test** by making `MerklePredicate.lean` consume the new names. Replace lines 45-63 (`commitmentParameters` through `publicArgs`) and the `outputOne` def with:

```lean
open ZkIpProtocol (starkCommitmentParams starkFriParams fusedToplevel rootWords outputOne)

def commitmentParameters : Aiur.CommitmentParameters := { logBlowup := 1, capHeight := 0 }
def friParameters : Aiur.FriParameters :=
  { logFinalPolyLen := 0, maxLogArity := 1, numQueries := 100
    commitProofOfWorkBits := 20, queryProofOfWorkBits := 0 }

/-- Public args for the fused circuit: `threshold` followed by the 8 root words. -/
def publicArgs (threshold : Nat) (root : ByteArray) : Array Aiur.G :=
  #[Aiur.G.ofNat threshold] ++ rootWords root
```
and change `match merkleToplevel with` to `match fusedToplevel with`. Add `import ZkIpProtocol.FusedCircuit`. (The test keeps its own logBlowup-1 params; those are the documented study settings.)

- [ ] **Step 2: Run to verify it fails**

Run: `lake build Tests.Validation.MerklePredicate 2>&1 | grep -E "^error" | head`
Expected: `unknown identifier 'fusedToplevel'` (or unknown module `ZkIpProtocol.FusedCircuit`).

- [ ] **Step 3: Create `ZkIpProtocol/FusedCircuit.lean`**

```lean
/-
The production circuit: `merkle_predicate_batch1` from `MerkleCircuit.lean`,
merged with ix's `core`, `byteStream` and `blake3` toplevels, compiled once
per process and cached together with its `AiurSystem`.

This file also owns the encoders both the prover and the verifier need so
they are defined exactly once: root words, path bytes, IO buffer layout.

Spike note (2026-10-03): <record here whether bare `G` parses after
importing MerkleCircuit; see Task 1 of the M5 plan>.
-/
import ZkIpProtocol.CoreTypes
import ZkIpProtocol.MerkleCommitment
import ZkIpProtocol.MerkleCircuit
import Ix.IxVM.Core
import Ix.IxVM.ByteStream
import Ix.IxVM.Blake3
import Ix.Aiur.Compiler
import Ix.Aiur.Protocol

namespace ZkIpProtocol

/-- Shared STARK commitment parameters (production). -/
def starkCommitmentParams : Aiur.CommitmentParameters := { logBlowup := 2, capHeight := 0 }

/-- Shared STARK FRI parameters (production). -/
def starkFriParams : Aiur.FriParameters :=
  { logFinalPolyLen := 0, maxLogArity := 1, numQueries := 100
    commitProofOfWorkBits := 20, queryProofOfWorkBits := 0 }

/-- Compiled fused circuit plus the prover/verifier system built for it. -/
structure FusedSystem where
  bytecode : Aiur.Bytecode.Toplevel
  funIdx : Aiur.Bytecode.FunIdx
  system : Aiur.AiurSystem

/-- The merged source toplevel: ix `core` + `byteStream` + `blake3` + our Merkle circuit. -/
def fusedToplevel : Except Aiur.Global Aiur.Source.Toplevel := do
  let t ← IxVM.core.merge IxVM.byteStream
  let t ← t.merge IxVM.blake3
  t.merge MerkleCircuit.merkleCircuit

/-- Entry the production path proves. Variable depth via `merkle_fold`. -/
def fusedEntry : Lean.Name := MerkleCircuit.merkleBatchEntry 1

def buildFusedSystem (c : Aiur.CommitmentParameters) (f : Aiur.FriParameters)
    : Except String FusedSystem := do
  let toplevel ← match fusedToplevel with
    | .ok t => pure t
    | .error g => .error s!"fused toplevel merge failed on clashing name: {g}"
  let compiled ← toplevel.compile
  let funIdx ← match compiled.getFuncIdx fusedEntry with
    | some i => pure i
    | none => .error s!"{fusedEntry} not found after compile"
  pure { bytecode := compiled.bytecode, funIdx, system := Aiur.AiurSystem.build compiled.bytecode c f }

initialize fusedSystemRef : IO.Ref (Option FusedSystem) ← IO.mkRef none

/-- The production system, built on first use and cached for the process. -/
def fusedSystem : IO FusedSystem := do
  if let some s ← fusedSystemRef.get then return s
  match buildFusedSystem starkCommitmentParams starkFriParams with
  | .error e => throw (IO.userError e)
  | .ok s =>
    fusedSystemRef.set (some s)
    return s

/-- `[0, funIdx] ++ [threshold, r0..r7] ++ [1]`. -/
def fusedClaimSize : Nat := 12

/-- The 32-byte root as eight little-endian u32 words, word `i` from bytes `[4i, 4i+3]`. -/
def rootWordNats (root : ByteArray) : Array Nat :=
  (Array.range 8).map fun i =>
    let bt (j : Nat) : Nat := (root.get! (4 * i + j)).toNat
    bt 0 + 0x100 * bt 1 + 0x10000 * bt 2 + 0x1000000 * bt 3

def rootWords (root : ByteArray) : Array Aiur.G := (rootWordNats root).map Aiur.G.ofNat

/-- Public inputs of the fused claim, as Nats so range guards run before `G.ofNat`. -/
def fusedPublicInputs (threshold : Nat) (root : ByteArray) : Array Nat :=
  #[threshold] ++ rootWordNats root

/-- Flat path stream: per level `dir` (1 = sibling on the left) then the 32 sibling bytes. -/
def pathBytes (proof : MerkleProof) : Array Aiur.G :=
  (Array.range proof.path.size).foldl (init := #[]) fun acc j =>
    (acc.push (Aiur.G.ofUInt8 (if proof.isLeft[j]! then 1 else 0)))
      ++ (proof.path[j]!).data.map Aiur.G.ofUInt8

/-- Private witness for `batch_item 0`: channel 0 key `[0]` = leaf bytes, channel 1 key `[0]` = path. -/
def fusedIO (leaf : ByteArray) (proof : MerkleProof) : Aiur.IOBuffer :=
  let b := (default : Aiur.IOBuffer).extend 0 #[Aiur.G.ofNat 0] (leaf.data.map Aiur.G.ofUInt8)
  b.extend 1 #[Aiur.G.ofNat 0] (pathBytes proof)

def outputOne : Array Aiur.G := #[Aiur.G.ofNat 1]

end ZkIpProtocol
```

If `rootWords` needs the test's exact shape, it already matches (`Aiur.G.ofNat` of the same sum). If `(default : Aiur.IOBuffer).extend` key type is `Array G`, the `#[Aiur.G.ofNat 0]` form matches `BatchDisclosure.buildIO`.

- [ ] **Step 4: Build and run**

Run: `lake build Tests.Validation.MerklePredicate 2>&1 | grep -E "^error|Build completed"; .lake/build/bin/Tests-Validation-MerklePredicate | tail -3; echo exit=$?`
Expected: build completed, test prints its final OK line, exit 0.

Then the spike: temporarily add `import ZkIpProtocol.FusedCircuit` and a line `#check (G.ofNat 1 : G)` at the end of `ZkIpProtocol/STARKIntegration.lean`, run `lake build ZkIpProtocol 2>&1 | grep -E "^error" | head -3`, record the outcome in the FusedCircuit.lean header comment, and remove the temporary lines. If bare `G` fails to parse, Task 2 writes `Aiur.G` in every library file it touches.

- [ ] **Step 5: Commit**

```bash
git add ZkIpProtocol/FusedCircuit.lean Tests/Validation/MerklePredicate.lean
git commit -m "feat: FusedCircuit, one merged toplevel, cached AiurSystem, shared encoders"
```

---

### Task 2: Prove and verify the fused circuit from STARKIntegration

**Files:**
- Modify: `ZkIpProtocol/STARKIntegration.lean` (rewrite from line 20 to the end; delete `PredicateCircuit`, `CircuitABI`, `toAiurBytecode`, `verifyMerkleCommitment`, `verifyAttributeInMerkleTree`, the `[Hash ByteArray]` binder, the old params)
- Modify: `ZkIpProtocol/CoreTypes.lean` (add `IPAttribute.value`)
- Delete: `ZkIpProtocol/Optimization.lean` (only consumer of `PredicateCircuit` as a type; fabricates empty proofs)
- Modify: `ZkIpProtocol.lean:6-36` (drop `Optimization` import; `advertiseAndDisclose` takes `attributeIndex : Nat`, calls `generateCertificateWithSTARK`, returns `none` when it yields `none`)
- Modify: `ZkIpProtocol/Performance.lean:53-110,147-160` (`profileSTARKProof (threshold : Nat) (root : ByteArray) (leaf : ByteArray) (path : MerkleProof)` uses `fusedSystem`; `analyzeCircuitComplexity` takes no circuit and counts constraints of `(← fusedSystem).bytecode`)
- Modify: `ZkIpProtocol/Advertisement.lean:54-78` (`verifyCertificate cert := verifySTARKProof cert.proof cert.predicate.threshold cert.commitment`)
- Modify: `ZkIpProtocol/Api.lean:296-330,341-403` minimal compile fixes only: `generateCertificateWithSTARK ixonWithRoot predicate 0`; self-verify and handleVerify call `verifySTARKProof cert.proof threshold cert.commitment`; the circuit records are deleted. Request semantics change in Task 3.
- Modify: `Main.lean:60-67` same minimal fix.
- Modify: `Tests/Validation/CpuBaseline.lean`, `Tests/Validation/ProveVerifyRoundtrip.lean`, `Tests/STARKTests.lean`: fixtures build `leaves := attrs.map attrLeafBytes`, `root ← buildMerkleTree leaves`, `path := (generateProof leaves i).get!`, and call the new signatures. Delete `natToByteArray`-based `attrBytesOf` helpers. In `STARKTests.lean` delete `testMerkleRootBinding` (lines 111-160, the PENDING M2 block) and its call; adapt `analyzeCircuitComplexity`/`profileSTARKProof` calls (lines 182-185).
- Test: `Tests/Validation/PredicateSoundness.lean` (rewrite the library-level checks)

**Interfaces:**
- Consumes: everything in Task 1.
- Produces:
  ```lean
  def IPAttribute.value : IPAttribute → Nat
  def generateSTARKProof (threshold : Nat) (root : ByteArray) (leaf : ByteArray) (path : MerkleProof)
      : IO (Option STARKProof)
  def verifySTARKProof (proof : STARKProof) (threshold : Nat) (root : ByteArray) : IO Bool
  def generateCertificateWithSTARK (ixon : Ixon) (predicate : IPPredicate) (attributeIndex : Nat)
      : IO (Option ZKCertificate)
  ```
  `generateCertificateWithSTARK` recomputes the root from `ixon.attributes`; if `ixon.merkleRoot` is non-empty and differs, returns `none`. The certificate's `commitment` is always the recomputed root. Requires `predicate.operator == ">"`.

- [ ] **Step 1: Write the failing tests.** Replace the library-level section of `PredicateSoundness.lean` (`proveVerify`, `leakCheck`, `bindingCheck`, `outOfRangeGuardCheck`, `arityBypassCheck`, `certificateNatRangeGuardCheck`, `noMockCertificateCheck`) with:

```lean
/-- One committed attribute: a depth-0 tree whose root is `leafHash leaf` and
whose path is empty. Prove and verify `attr > threshold` against it. -/
def proveVerify (attr threshold : Nat) : IO Bool := do
  let leaves := #[attrLeafBytes attr]
  let root ← buildMerkleTree leaves
  let some path := generateProof leaves 0 | throw (IO.userError "no path for index 0")
  match ← generateSTARKProof threshold root leaves[0]! path with
  | none => return false
  | some proof => verifySTARKProof proof threshold root

/-- Eight committed attributes (depth 3); returns (ixon, cert) for index 2 (2500 > 1000). -/
def eightLeafCertificate : IO (Ixon × ZKCertificate) := do
  let attrs : Array Nat := #[500, 1500, 2500, 3500, 4500, 5500, 6500, 7500]
  let ixon : Ixon := { id := 7, attributes := attrs.map IPAttribute.performance,
                       merkleRoot := ByteArray.empty, timestamp := 0 }
  let some cert := (← generateCertificateWithSTARK ixon { threshold := 1000, operator := ">" } 2)
    | throw (IO.userError "eightLeafCertificate: generation failed")
  pure (ixon, cert)

def leakCheck : IO Unit := do
  let (_, cert) ← eightLeafCertificate
  let secret := natToBytes8BE 2500
  if cert.proof.publicInputs.any (· == secret) then
    throw (IO.userError "LEAK: private attribute present in proof.publicInputs")
  if cert.proof.publicInputs.size != fusedClaimSize then
    throw (IO.userError s!"claim has {cert.proof.publicInputs.size} entries, expected {fusedClaimSize}")
  IO.println "✓ no leak: attribute absent from the 12-element public claim"

def bindingCheck : IO Unit := do
  let (_, cert) ← eightLeafCertificate
  if ← verifySTARKProof cert.proof 2000 cert.commitment then
    throw (IO.userError "verify accepted a different threshold")
  if !(← verifySTARKProof cert.proof 1000 cert.commitment) then
    throw (IO.userError "verify rejected the correct threshold")
  IO.println "✓ verify binds to the threshold"

/-- The commitment is bound: flipping one root byte must fail verification. -/
def commitmentSwapCheck : IO Unit := do
  let (_, cert) ← eightLeafCertificate
  let swapped := cert.commitment.set! 0 (cert.commitment.get! 0 ^^^ 0x01)
  if ← verifySTARKProof cert.proof 1000 swapped then
    throw (IO.userError "verify accepted a certificate with a different commitment")
  if !(← verifyCertificate { cert with commitment := swapped }) then pure () else
    throw (IO.userError "verifyCertificate accepted a swapped commitment")
  IO.println "✓ commitment is bound: one flipped root byte fails verification"

/-- `claim[1]` must be the fused entry's funIdx. Rewrite it to another value. -/
def funIdxBindingCheck : IO Unit := do
  let (_, cert) ← eightLeafCertificate
  let tampered := cert.proof.publicInputs.set! 1 (natToBytes8BE 0)
  if ← verifySTARKProof { cert.proof with publicInputs := tampered } 1000 cert.commitment then
    throw (IO.userError "verify accepted a claim for a different function index")
  IO.println "✓ verify binds to the fused entry's funIdx"

def outOfRangeGuardCheck : IO Unit := do
  let leaves := #[attrLeafBytes 5]
  let root ← buildMerkleTree leaves
  let some path := generateProof leaves 0 | throw (IO.userError "no path")
  match ← generateSTARKProof (2 ^ 32) root leaves[0]! path with
  | some _ => throw (IO.userError "threshold 2^32 should be rejected before the prover")
  | none => IO.println "✓ threshold >= 2^32 rejected before the prover"
  if ← verifySTARKProof default (2 ^ 32) root then
    throw (IO.userError "verify accepted threshold 2^32")
  IO.println "✓ verify rejects threshold >= 2^32"

/-- u32 boundary: attr = 2^32 - 1 against threshold 2^32 - 2 proves. -/
def u32BoundaryCheck : IO Unit := do
  if !(← proveVerify (2 ^ 32 - 1) (2 ^ 32 - 2)) then
    throw (IO.userError "boundary attr 2^32-1 > 2^32-2 failed to prove/verify")
  IO.println "✓ u32 boundary proves"

def certificateGuardsCheck : IO Unit := do
  let ixon : Ixon := { id := 1, attributes := #[.performance 1500], merkleRoot := ByteArray.empty, timestamp := 0 }
  if (← generateCertificateWithSTARK ixon { threshold := 2 ^ 32, operator := ">" } 0).isSome then
    throw (IO.userError "threshold 2^32 certified")
  let big : Ixon := { ixon with attributes := #[.performance (2 ^ 32)] }
  if (← generateCertificateWithSTARK big { threshold := 1000, operator := ">" } 0).isSome then
    throw (IO.userError "attribute 2^32 certified")
  if (← generateCertificateWithSTARK ixon { threshold := 1000, operator := ">=" } 0).isSome then
    throw (IO.userError "operator >= certified; circuit only proves >")
  if (← generateCertificateWithSTARK ixon { threshold := 1000, operator := ">" } 3).isSome then
    throw (IO.userError "out-of-range attributeIndex certified")
  let wrongRoot : Ixon := { ixon with merkleRoot := ByteArray.mk (Array.replicate 32 0) }
  if (← generateCertificateWithSTARK wrongRoot { threshold := 1000, operator := ">" } 0).isSome then
    throw (IO.userError "mismatched client root certified")
  IO.println "✓ certificate guards: range, operator, index, client root"

def noMockCertificateCheck : IO Unit := do
  let ixon : Ixon := { id := 1, attributes := #[.performance 500], merkleRoot := ByteArray.empty, timestamp := 0 }
  match ← generateCertificateWithSTARK ixon { threshold := 1000, operator := ">" } 0 with
  | some cert => throw (IO.userError s!"false predicate certified (vkId={cert.proof.vkId})")
  | none => IO.println "✓ false predicate yields no certificate"
```
Update `main` to call: `proveVerify 1500 1000` positive, `proveVerify 500 1000` and `proveVerify 1000 1000` negative, then `leakCheck`, `bindingCheck`, `commitmentSwapCheck`, `funIdxBindingCheck`, `outOfRangeGuardCheck`, `u32BoundaryCheck`, `certificateGuardsCheck`, `noMockCertificateCheck`. Keep the API checks (`apiM1VerifyCheck` renamed `apiVerifyCheck` and built from `eightLeafCertificate`, `apiVerifyThresholdRangeGuardCheck`, `apiVerifyGarbageProofCheck`, `verifyCertificateThresholdWrapCheck`) and adapt them to `eightLeafCertificate`.

- [ ] **Step 2: Run to verify it fails**

Run: `lake build Tests.Validation.PredicateSoundness 2>&1 | grep -E "^error" | head -5`
Expected: type errors on `generateSTARKProof` arity / unknown `fusedClaimSize` usage in the test.

- [ ] **Step 3: Rewrite `STARKIntegration.lean`**

Add `IPAttribute.value` to `CoreTypes.lean` after the `IPAttribute` inductive:
```lean
def IPAttribute.value : IPAttribute → Nat
  | .performance n | .security n | .efficiency n => n
  | .custom _ n => n
```

`STARKIntegration.lean` body (imports: `ZkIpProtocol.MerkleCommitment`, `ZkIpProtocol.CoreTypes`, `ZkIpProtocol.DebugLogger`, `ZkIpProtocol.FusedCircuit`, `Ix.Aiur.Protocol`, `Ix.Aiur.Compiler`):

```lean
namespace ZkIpProtocol
open Aiur

/-- Prove `attr > threshold` for the committed `leaf` under `root`.
`leaf` is the 4-byte `attrLeafBytes` of the private value; `path` is its
Merkle path. Only `threshold` and the root words are public. -/
def generateSTARKProof (threshold : Nat) (root : ByteArray) (leaf : ByteArray) (path : MerkleProof)
    : IO (Option STARKProof) := do
  if threshold ≥ 2 ^ 32 || leaf.size != 4 || root.size != 32 then
    debugLog "generateSTARKProof: input outside the circuit domain"
    return none
  let fs ← fusedSystem
  let args := (fusedPublicInputs threshold root).map Aiur.G.ofNat
  let io := fusedIO leaf path
  -- Execute first: a violated assert returns .error here, whereas the Rust
  -- prover aborts the process on the same condition.
  match fs.bytecode.execute fs.funIdx args io with
  | .error e =>
    debugLog s!"circuit execution failed (predicate or membership not satisfied): {e}"
    return none
  | .ok _ => pure ()
  let (claim, proof, _) := AiurSystem.prove fs.system fs.funIdx args io
  return some { publicInputs := claim.map (natToBytes8BE ·.val.toNat), proofData := proof.toBytes, vkId := "aiur_vk" }

/-- Verify a certificate proof against the certificate's own threshold and
commitment. The expected claim is derived entirely from those two values. -/
def verifySTARKProof (proof : STARKProof) (threshold : Nat) (root : ByteArray) : IO Bool := do
  if threshold ≥ 2 ^ 32 || root.size != 32 then return false
  let fs ← fusedSystem
  let mut claim : Array Aiur.G := #[]
  for bytes in proof.publicInputs do
    if bytes.size != 8 then return false
    claim := claim.push (Aiur.G.ofNat (bytesToNat8BE bytes))   -- see note
  if claim.size != fusedClaimSize then return false
  let expected := #[0, fs.funIdx.toNat] ++ fusedPublicInputs threshold root ++ #[1]
  if claim.map (·.val) != expected.map (Aiur.G.ofNat · |>.val) then return false
  let aiurProof ← match Aiur.Proof.ofBytesChecked proof.proofData with
    | .ok p => pure p
    | .error _ => return false
  match AiurSystem.verify fs.system claim aiurProof with
  | .ok () => return true
  | .error _ => return false
```
Note: keep the existing 8-byte BE decode expression from the current `verifySTARKProof` (lines 251-256) inline, or add `bytesToNat8BE` next to `natToBytes8BE` in `CoreTypes.lean`. Prefer the helper; it is the inverse of an existing function. `FunIdx` is a `Nat` alias in ix (`Bytecode.FunIdx`); if `.toNat` does not typecheck, use `fs.funIdx` directly.

```lean
/-- Certificate for `attributes[attributeIndex] > threshold` under the root of
all attributes. Recomputes the root; a non-empty `ixon.merkleRoot` that
differs is a client error and yields `none`. -/
def generateCertificateWithSTARK (ixon : Ixon) (predicate : IPPredicate) (attributeIndex : Nat)
    : IO (Option ZKCertificate) := do
  if predicate.operator != ">" then return none
  if predicate.threshold ≥ 2 ^ 32 then return none
  if ixon.attributes.any (·.value ≥ 2 ^ 32) then return none
  let leaves := ixon.attributes.map (attrLeafBytes ·.value)
  let root ← buildMerkleTree leaves
  if !ixon.merkleRoot.isEmpty && ixon.merkleRoot != root then return none
  let some path := generateProof leaves attributeIndex | return none
  let some proof ← generateSTARKProof predicate.threshold root leaves[attributeIndex]! path
    | return none
  return some { ipId := ixon.id, commitment := root, predicate, proof, timestamp := ixon.timestamp }
```
(`leaves[attributeIndex]!` is safe after `generateProof` returned `some`; if the linter objects, bind `let some leaf := leaves[attributeIndex]? | return none` first.)

Then the minimal caller fixes listed under Files. `Advertisement.verifyCertificate` becomes one line. Delete `Optimization.lean`; in `ZkIpProtocol.lean` replace the `generateOptimizedProof` call with `let some certificate ← generateCertificateWithSTARK ixon predicate attributeIndex | return none` and drop `config : OptimizationConfig` from the signature.

- [ ] **Step 4: Build everything and run**

Run:
```bash
lake build ZkIpProtocol Tests.Validation.PredicateSoundness Tests.Validation.CpuBaseline Tests.Validation.ProveVerifyRoundtrip Tests.STARKTests Main 2>&1 | grep -E "^error|Build completed"
for t in Validation-PredicateSoundness Validation-ProveVerifyRoundtrip STARKTests; do .lake/build/bin/Tests-$t >/dev/null 2>&1; echo "$t exit=$?"; done
```
Expected: build completed, all exit 0. `grep -rn "PredicateCircuit\|toAiurBytecode\|verifyAttributeInMerkleTree\|natToByteArray" ZkIpProtocol Tests Main.lean` returns only `natToByteArray`'s definition and `Advertisement.toPublicInputs` (not a leaf encoding).

- [ ] **Step 5: Commit**

```bash
git add -A ZkIpProtocol ZkIpProtocol.lean Main.lean Tests
git commit -m "feat: prove and verify the fused predicate+membership circuit in production

Bind the certificate commitment into the STARK claim. Remove the ignored
PredicateCircuit, the two tautological Merkle checks and Optimization.lean."
```

---

### Task 3: API: witness from attributeIndex, recomputed root, one generate path

**Files:**
- Modify: `ZkIpProtocol/Api.lean:150-213` (SecurityValidation), `:240-330` (handleGenerate), `:341-403` (handleVerify unchanged beyond Task 2)
- Modify: `Main.lean:26-98` (batch handler calls `generateFromJson`)
- Test: `Tests/Validation/PredicateSoundness.lean` (API checks)

**Interfaces:**
- Produces:
  ```lean
  /-- Shared by /generate and /certificates/batch. Left = (status, message). -/
  def generateFromJson (json : Json) : IO (Except (Nat × String) ZKCertificate)
  namespace SecurityValidation
  def validateBeforeProofGeneration (witness threshold : Nat) (root : ByteArray) (publicInputs : Array Nat) : Option String
  ```
- Request shape for `/generate` and each batch entry: `{ id, attributes: [{type, value[, name]}], predicate: {threshold, operator: ">"}, attributeIndex?: Nat (default 0), merkleRoot?: hex, timestamp?: Nat }`. `privateAttribute` present: 400.

- [ ] **Step 1: Write the failing tests.** Add to `PredicateSoundness.lean`:

```lean
def genBody (attrs : Array Nat) (threshold : Nat) (index : Nat) (extra : List (String × Json) := []) : String :=
  Json.pretty (Json.mkObj ([
    ("id", Json.num 7),
    ("attributes", Json.arr (attrs.map fun v => Json.mkObj [("type", Json.str "performance"), ("value", Json.num v)])),
    ("predicate", Json.mkObj [("threshold", Json.num threshold), ("operator", Json.str ">")]),
    ("attributeIndex", Json.num index)] ++ extra))

def expectStatus (label : String) (body : String) (status : Nat) : IO Json := do
  let r ← handleGenerate body
  if r.statusCode != status then
    throw (IO.userError s!"{label}: expected {status}, got {r.statusCode}: {r.body}")
  match Json.parse r.body with
  | .ok j => pure j
  | .error e => throw (IO.userError s!"{label}: bad JSON: {e}")

def apiRoundTripCheck : IO Unit := do
  let attrs : Array Nat := #[500, 1500, 2500, 3500, 4500, 5500, 6500, 7500]
  let j ← expectStatus "generate" (genBody attrs 1000 2) 200
  let certJson := (j.getObjVal? "certificate").toOption.get!
  let v ← handleVerify (Json.pretty certJson)
  match Json.parse v.body >>= (·.getObjValAs? Bool "verified") with
  | .ok true => IO.println "✓ API round trip: 8 attributes, index 2, > 1000 verifies"
  | _ => throw (IO.userError s!"round trip failed to verify: {v.body}")
  -- swap one commitment byte in the JSON and verify again
  let some cert := parseZKCertificate certJson | throw (IO.userError "parse cert")
  let swapped := { cert with commitment := cert.commitment.set! 3 (cert.commitment.get! 3 ^^^ 0x80) }
  let v2 ← handleVerify (Json.pretty (certificateToJson swapped))
  match Json.parse v2.body >>= (·.getObjValAs? Bool "verified") with
  | .ok false => IO.println "✓ API verify rejects a swapped commitment"
  | _ => throw (IO.userError s!"swapped commitment verified: {v2.body}")

def apiRejectsCheck : IO Unit := do
  let attrs : Array Nat := #[500, 1500, 2500]
  let _ ← expectStatus "privateAttribute" (genBody attrs 1000 1 [("privateAttribute", Json.num 1500)]) 400
  let _ ← expectStatus "operator >=" (Json.pretty (Json.mkObj [
    ("id", Json.num 1), ("attributes", Json.arr #[Json.mkObj [("type", Json.str "performance"), ("value", Json.num 1500)]]),
    ("predicate", Json.mkObj [("threshold", Json.num 1000), ("operator", Json.str ">=")])])) 400
  let _ ← expectStatus "attr >= 2^32" (genBody #[2 ^ 32] 1000 0) 400
  let _ ← expectStatus "index out of range" (genBody attrs 1000 3) 400
  let _ ← expectStatus "mismatched merkleRoot" (genBody attrs 1000 1 [("merkleRoot", Json.str ("0x" ++ String.join (List.replicate 64 "0")))]) 400
  let _ ← expectStatus "false predicate" (genBody attrs 1000 0) 500
  IO.println "✓ API rejects: privateAttribute, >=, huge attribute, bad index, wrong root; false predicate is 500"
```
Call both from `main`.

- [ ] **Step 2: Run to verify it fails**

Run: `lake build Tests.Validation.PredicateSoundness 2>&1 | grep -E "^error" | head -3; .lake/build/bin/Tests-Validation-PredicateSoundness 2>&1 | tail -2`
Expected: build ok; `privateAttribute: expected 400, got 200` or the `Missing privateAttribute` 400 on the first generate (either way, the round trip fails before the swap check).

- [ ] **Step 3: Implement.** Replace `SecurityValidation` with:

```lean
namespace SecurityValidation
/-- The witness must not appear among the public inputs (it never can: the
only non-hash public input is `threshold`, and `witness == threshold` makes the
predicate false), and the public inputs must be exactly the fused layout. -/
def validateBeforeProofGeneration (witness threshold : Nat) (root : ByteArray) (publicInputs : Array Nat)
    : Option String :=
  if witness == threshold then some "private attribute equals the public threshold"
  else if publicInputs != fusedPublicInputs threshold root then
    some s!"public inputs must be [threshold] ++ 8 root words (got {publicInputs.size} elements)"
  else none
end SecurityValidation
```

Replace `handleGenerate` with:

```lean
/-- Parse one generate request and produce a certificate, or (status, message). -/
def generateFromJson (json : Json) : IO (Except (Nat × String) ZKCertificate) := do
  let some ixon := parseIxon json | return .error (400, "Invalid Ixon format")
  let some predicate := (Json.getObjVal? json "predicate").toOption >>= parseIPPredicate
    | return .error (400, "Invalid predicate format")
  if (Json.getObjVal? json "privateAttribute").toOption.isSome then
    return .error (400, "privateAttribute was removed; send attributeIndex (the attribute to prove)")
  if predicate.operator != ">" then
    return .error (400, "operator must be \">\" (the circuit proves attribute > threshold)")
  if predicate.threshold ≥ 2 ^ 32 then return .error (400, "threshold must be < 2^32")
  if ixon.attributes.any (·.value ≥ 2 ^ 32) then return .error (400, "attribute values must be < 2^32")
  let attributeIndex := ((Json.getObjVal? json "attributeIndex" >>= Json.getNat?).toOption).getD 0
  let some witness := ixon.attributes[attributeIndex]?.map (·.value)
    | return .error (400, s!"attributeIndex {attributeIndex} out of range for {ixon.attributes.size} attributes")
  let root ← buildMerkleTree (ixon.attributes.map (attrLeafBytes ·.value))
  if !ixon.merkleRoot.isEmpty && ixon.merkleRoot != root then
    return .error (400, "merkleRoot does not match attributes")
  if let some msg := SecurityValidation.validateBeforeProofGeneration witness predicate.threshold root
      (fusedPublicInputs predicate.threshold root) then
    return .error (400, s!"Security validation failed: {msg}")
  let cert? ← try generateCertificateWithSTARK { ixon with merkleRoot := root } predicate attributeIndex
    catch ex => do (← IO.getStderr).putStrLn s!"Certificate generation exception: {ex}"; pure none
  let some cert := cert? | return .error (500, "Failed to generate certificate: predicate not satisfied or proof failed")
  -- The real post-generation check: the certificate's own proof verifies.
  if !(← verifySTARKProof cert.proof cert.predicate.threshold cert.commitment) then
    return .error (500, "Generated proof failed self-verification")
  return .ok cert

def handleGenerate (body : String) : IO HttpResponse := do
  let json ← match Json.parse body with
    | .ok j => pure j
    | .error err => return (← errorResponse 400 s!"Invalid JSON: {err}")
  match ← generateFromJson json with
  | .error (status, msg) => errorResponse status msg
  | .ok cert => return jsonResponse 200 (Json.mkObj [("success", Json.bool true), ("certificate", certificateToJson cert)])
```
`Main.lean` batch loop body becomes `match ← generateFromJson reqJson with | .ok cert => push cert JSON, succeeded+1 | .error (_, msg) => push {"error": msg}, failed+1`. Delete its `natToByteArray` block and `privateAttribute` parsing.

- [ ] **Step 4: Build and run**

Run: `lake build Tests.Validation.PredicateSoundness Main 2>&1 | grep -E "^error|Build completed"; .lake/build/bin/Tests-Validation-PredicateSoundness 2>&1 | tail -4; echo exit=$?`
Expected: all checks print ✓, exit 0.

- [ ] **Step 5: Commit**

```bash
git add ZkIpProtocol/Api.lean Main.lean Tests/Validation/PredicateSoundness.lean
git commit -m "feat: /generate proves attributes[attributeIndex] under a recomputed root

Replace privateAttribute with attributeIndex, reject mismatched client roots,
operators other than >, and out-of-u32 values. One generateFromJson serves
/generate and /certificates/batch."
```

---

### Task 4: Deduplicate the test harness and drop stale M1/M2 text

**Files:**
- Modify: `Tests/Validation/BatchDisclosure.lean:53-89`, `Tests/Validation/ScalingStudy.lean`, `Tests/Validation/ProofPhaseProfile.lean`, `Tests/Validation/MerkleCircuitSingle.lean`, `Tests/Validation/MerkleCircuitPath.lean`: delete local `merkleToplevel`, `rootWords`, `pathBytes`, `outputOne` and import `ZkIpProtocol.FusedCircuit`. Keep each file's own `logBlowup 1` study parameters and its K-specific `publicArgs`/`buildIO` (those take `Array Item`, not a `MerkleProof`). `pathBytes` there takes an `Item`; adapt by constructing a `MerkleProof` from the item: `pathBytes { rootHash := ByteArray.empty, path := it.sibs, isLeft := it.dirs.map (· == 1) }`.
- Modify: comments that say root binding "is a later M2 milestone": `ZkIpProtocol/Api.lean` (search `M2 milestone`, `M1 claim layout`), `ZkIpProtocol/STARKIntegration.lean` (any left), `ZkIpProtocol/CoreTypes.lean:8` ("required for Lean 4.24.0" becomes "required by `deriving Repr` on ByteArray fields").
- Modify: `Tests/Validation/ScalingStudy.lean:14` comment pointing at the gitignored `.superpowers/sdd/m3-task-1-report.md`; point at `docs/superpowers/notes/2026-07-20-scaling-study.md`.

- [ ] **Step 1: Make the change** (no new behavior; the tests are the test).
- [ ] **Step 2: Build every test executable and run the correctness set**

Run:
```bash
lake build Tests.HashTests Tests.STARKTests Tests.Validation.ProveVerifyRoundtrip Tests.Validation.PredicateSoundness Tests.Validation.CpuBaseline Tests.Validation.MerkleScheme Tests.Validation.Blake3CircuitSpike Tests.Validation.MerkleNodeHashSpike Tests.Validation.MerkleCircuitSingle Tests.Validation.MerkleCircuitPath Tests.Validation.MerklePredicate Tests.Validation.BatchDisclosure Tests.Validation.ScalingStudy Tests.Validation.ProofPhaseProfile Main 2>&1 | grep -E "^error|Build completed"
for t in HashTests STARKTests Validation-ProveVerifyRoundtrip Validation-PredicateSoundness Validation-MerkleScheme Validation-MerkleCircuitSingle Validation-MerkleCircuitPath Validation-MerklePredicate Validation-BatchDisclosure; do .lake/build/bin/Tests-$t >/dev/null 2>&1; echo "$t exit=$?"; done
grep -rn "merkleToplevel\|def rootWords\|def pathBytes\|M2 milestone\|PENDING M2" Tests ZkIpProtocol | wc -l
```
Expected: build completed, all exit 0, grep count 0.

- [ ] **Step 3: Commit**

```bash
git add Tests ZkIpProtocol
git commit -m "refactor: share the fused-circuit encoders across tests; drop stale M1/M2 comments"
```

---

### Task 5: Depth coverage and timing at production parameters

**Files:**
- Test: `Tests/Validation/PredicateSoundness.lean` (depth cases)
- Modify: `Tests/Validation/CpuBaseline.lean` (timing sweep over leaf counts)
- Modify: `docs/performance.md` (replace the M1 numbers with the fused-circuit table)

- [ ] **Step 1: Write the depth tests**

```lean
/-- Depth coverage through the library path: 1 leaf (depth 0), 5 leaves (odd,
duplicated last node), 8 (perfect), 16. Each proves index `n-1` and verifies,
and a swapped commitment fails. -/
def depthCoverageCheck : IO Unit := do
  for n in [1, 5, 8, 16] do
    let attrs := (Array.range n).map (fun i => 1001 + i)
    let ixon : Ixon := { id := n, attributes := attrs.map IPAttribute.performance,
                         merkleRoot := ByteArray.empty, timestamp := 0 }
    let some cert := (← generateCertificateWithSTARK ixon { threshold := 1000, operator := ">" } (n - 1))
      | throw (IO.userError s!"depth coverage: {n} leaves failed to certify")
    if !(← verifyCertificate cert) then throw (IO.userError s!"depth coverage: {n} leaves failed to verify")
    let swapped := { cert with commitment := cert.commitment.set! 31 (cert.commitment.get! 31 ^^^ 0x01) }
    if ← verifyCertificate swapped then throw (IO.userError s!"depth coverage: {n} leaves verified a swapped root")
    IO.println s!"✓ {n} leaves (depth {cert.proof.publicInputs.size}): certify, verify, swapped root rejected"
```
(Print the actual path depth instead of the claim size if `MerkleProof` is reachable; otherwise drop the parenthetical.) Call from `main`.

- [ ] **Step 2: Run** `lake build Tests.Validation.PredicateSoundness && .lake/build/bin/Tests-Validation-PredicateSoundness | tail -6`. Expected: four ✓ lines. If the 5-leaf case fails, the circuit's `node_from` disagrees with `combineLevel`'s duplicate rule; stop, that is a real finding, report it.

- [ ] **Step 3: Timing sweep.** In `CpuBaseline.lean`, replace the fixture with a loop over `n ∈ [1, 8, 16, 1024]` that builds the tree, times `generateSTARKProof` and `verifySTARKProof` five times each at the production parameters (it uses `fusedSystem`, so no local params), and prints `n, depth, prove median ms, verify median ms, proof bytes`. Keep its existing `median` helper.

- [ ] **Step 4: Run** `lake build Tests.Validation.CpuBaseline && .lake/build/bin/Tests-Validation-CpuBaseline`. Record the table in `docs/performance.md` under a heading "Fused circuit, production parameters (logBlowup 2), 2026-10-03" and state the machine (i7-13700K, AVX2 only, no AVX-512).

- [ ] **Step 5: Commit**

```bash
git add Tests/Validation/PredicateSoundness.lean Tests/Validation/CpuBaseline.lean docs/performance.md
git commit -m "test: depth 0/odd/8/16 coverage; record fused-circuit timings at production params"
```

---

### Task 6: Docs, REMEDIATION status, handoff

**Files:**
- Modify: `README.md:181` and `docs/architecture.md:74` (the "~64-bit, first 8 bytes" binding text becomes "full 256-bit root bound as eight u32 words in the claim"); `README.md` request example (`attributeIndex`, no `privateAttribute`); `docs/index.md` and `docs/getting-started.md` request shapes if they show one.
- Modify: `REMEDIATION.md` O1 and O4 rows: status Done, commit shas, test names.
- Modify: `docs/superpowers/notes/2026-10-03-verify-hardening.md` "Parked" section: strike the Merkle item and the `AiurSystem.build` item (both closed by M5).
- Create: `docs/superpowers/notes/2026-10-03-m5-handoff.md`: one paragraph: what changed, what is verified (the test list and exit codes), what is next (K>1 batch API, type/name in the leaf, ApiTests replacement, isoc23Shim target), what is risky (Aiur ZK property still unverified; `initialize`-based cache is per process, not per thread-safe prover).

- [ ] **Step 1: Make the edits.** `grep -rn "privateAttribute\|first 8 bytes\|64-bit" README.md docs/*.md` must return nothing afterwards except historical notes under `docs/superpowers/`.
- [ ] **Step 2: Commit**

```bash
git add README.md docs REMEDIATION.md
git commit -m "docs: M5 shipped, commitment is bound; update API shape, binding claims, remediation status"
```

---

### After the tasks

1. Run the code-review skill on `main..HEAD` at high effort; hand the confirmed correctness findings to `hermes-local`, escalate to gpt-5.4 only if it flags something or errors.
2. Fix what survives, commit, push `gpu-proving-backend`.
