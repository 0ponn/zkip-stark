/-
Soundness oracle for the predicate circuit.

The predicate circuit must CONSTRAIN `attributeValue > threshold`. A vacuous
circuit (one that constrains nothing) would let every case "verify", so the
negative and boundary cases below are the real test: they must be rejected.

  positive : 1500 > 1000  -> proves AND verifies
  negative :  500 > 1000  -> must NOT verify (ideally fails to prove)
  boundary : 1000 > 1000  -> must NOT verify (off-by-one guard)
-/

import ZkIpProtocol.STARKIntegration
import ZkIpProtocol.MerkleCommitment
import Ix.Aiur.Goldilocks

namespace Tests.Validation
open ZkIpProtocol Aiur

/-- Build a circuit for a given attr/threshold and run prove -> verify. -/
def proveVerify (attr threshold : Nat) : IO Bool := do
  let merkleRoot ← buildMerkleTree #[]      -- root unused by the predicate in M1
  let circuit : PredicateCircuit :=
    { attributeValue := attr, merkleRoot, threshold,
      operator := ">", merkleProof := { rootHash := merkleRoot, path := #[], isLeft := #[] },
      output := true }
  let publicInputs : Array Aiur.G := #[Aiur.G.ofNat threshold]
  let privateInputs : Array Aiur.G := #[Aiur.G.ofNat attr]
  match ← generateSTARKProof circuit publicInputs privateInputs with
  | none => return false               -- could not prove
  | some proof => verifySTARKProof proof publicInputs circuit

/-- `attributeValue` is a secret witness; it must never appear in the public
claim that ships with the proof. Build a positive case and check the private
value's byte-encoding is absent from every entry of `proof.publicInputs`. -/
def leakCheck (attr threshold : Nat) : IO Unit := do
  let merkleRoot ← buildMerkleTree #[]
  let circuit : PredicateCircuit :=
    { attributeValue := attr, merkleRoot, threshold,
      operator := ">", merkleProof := { rootHash := merkleRoot, path := #[], isLeft := #[] },
      output := true }
  let publicInputs : Array Aiur.G := #[Aiur.G.ofNat threshold]
  let privateInputs : Array Aiur.G := #[Aiur.G.ofNat attr]
  let some proof := (← generateSTARKProof circuit publicInputs privateInputs)
    | throw (IO.userError "leakCheck: prove failed")
  let secret := natToBytes8BE attr
  if proof.publicInputs.any (· == secret) then
    throw (IO.userError "LEAK: private attributeValue present in proof.publicInputs")
  IO.println "✓ no leak: attributeValue absent from public inputs"

/-- `verifySTARKProof` must bind to the caller's expected public inputs: a
proof generated for one threshold must not verify against a different
expected threshold, even though the proof itself is valid. -/
def bindingCheck : IO Unit := do
  let merkleRoot ← buildMerkleTree #[]
  let circuit : PredicateCircuit :=
    { attributeValue := 1500, merkleRoot, threshold := 1000,
      operator := ">", merkleProof := { rootHash := merkleRoot, path := #[], isLeft := #[] },
      output := true }
  let publicInputs : Array Aiur.G := #[Aiur.G.ofNat 1000]
  let privateInputs : Array Aiur.G := #[Aiur.G.ofNat 1500]
  let some proof := (← generateSTARKProof circuit publicInputs privateInputs)
    | throw (IO.userError "bindingCheck: prove failed")
  if (← verifySTARKProof proof #[Aiur.G.ofNat 2000] circuit) then
    throw (IO.userError "verify accepted a mismatched threshold — not bound to caller inputs")
  if !(← verifySTARKProof proof #[Aiur.G.ofNat 1000] circuit) then
    throw (IO.userError "verify rejected the correct threshold")
  IO.println "✓ verify binds to caller-supplied threshold"

/-- `generateSTARKProof` must reject inputs outside the u32 domain the
predicate's `u32_less_than` operates over, rather than reaching
`AiurSystem.prove` — whose Rust synthesis path ABORTS the process
(`ExecError::U32OutOfRange`) on such a value, not a catchable Lean error. -/
def outOfRangeGuardCheck : IO Unit := do
  let merkleRoot ← buildMerkleTree #[]
  let threshold := 2 ^ 32  -- first value outside u32
  let circuit : PredicateCircuit :=
    { attributeValue := threshold + 1, merkleRoot, threshold,
      operator := ">", merkleProof := { rootHash := merkleRoot, path := #[], isLeft := #[] },
      output := true }
  let publicInputs : Array Aiur.G := #[Aiur.G.ofNat threshold]
  let privateInputs : Array Aiur.G := #[Aiur.G.ofNat (threshold + 1)]
  match ← generateSTARKProof circuit publicInputs privateInputs with
  | some _ => throw (IO.userError "out-of-range threshold (2^32) should have been rejected, not proved")
  | none => IO.println "✓ out-of-range guard: threshold = 2^32 rejected before reaching the prover"

end Tests.Validation

open Tests.Validation in
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
  -- leak: attributeValue must not appear in the public claim
  leakCheck 1500 1000
  -- verify must bind to the caller's expected public inputs
  bindingCheck
  -- guard: out-of-range (>= 2^32) inputs must be rejected, not crash the prover
  outOfRangeGuardCheck
  IO.println "All predicate soundness tests passed"
