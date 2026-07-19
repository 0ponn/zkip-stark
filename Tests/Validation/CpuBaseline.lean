/-
Honest CPU proving baseline harness. No GPU. Measures end-to-end STARK
proving and verification wall-clock time on this machine, so later GPU
claims have a real number to beat.
-/

import ZkIpProtocol.IPMetadata
import ZkIpProtocol.MerkleCommitment
import ZkIpProtocol.STARKIntegration
import Ix.Aiur.Goldilocks

namespace Tests.Validation

open ZkIpProtocol

/-- Serialize an IP attribute to bytes by its numeric value (mirrors Tests/STARKTests.lean). -/
private def attrBytesOf (a : IPAttribute) : ByteArray :=
  natToByteArray (match a with
    | .performance n => n
    | .security n => n
    | .efficiency n => n
    | .custom _ n => n)

private def testIxon : Ixon := {
  id := 1
  attributes := #[
    IPAttribute.performance 1500,
    IPAttribute.security 8,
    IPAttribute.efficiency 95
  ]
  merkleRoot := ByteArray.empty
  timestamp := 1000
}

/-- Build the circuit + public/private inputs, exactly as STARKTests does. -/
def buildCircuit : IO (PredicateCircuit × Array Aiur.G × Array Aiur.G) := do
  let attrBytes : Array ByteArray := testIxon.attributes.map attrBytesOf
  let merkleRoot ← buildMerkleTree attrBytes
  let merkleProof : MerkleProof := { rootHash := merkleRoot, path := #[], isLeft := #[] }
  let circuit : PredicateCircuit := {
    attributeValue := 1500
    merkleRoot := merkleRoot
    threshold := 1000
    operator := ">"
    merkleProof
    output := true
  }
  -- M1 circuit ABI: `predicate_check(threshold) -> G`, only `threshold` public;
  -- `attr` is a private IO witness.
  let publicInputs : Array Aiur.G := #[Aiur.G.ofNat 1000]
  let privateInputs : Array Aiur.G := #[Aiur.G.ofNat 1500]
  return (circuit, publicInputs, privateInputs)

/-- Time one proof generation, returning (elapsed ms, the proof). -/
def timeProve (circuit : PredicateCircuit) (pub priv : Array Aiur.G) : IO (Nat × STARKProof) := do
  let t0 ← IO.monoMsNow
  let some proof ← generateSTARKProof circuit pub priv
    | throw (IO.userError "proof generation returned none")
  let t1 ← IO.monoMsNow
  return (t1 - t0, proof)

/-- Time verification of one proof, returning (elapsed ms, verified?). -/
def timeVerify (circuit : PredicateCircuit) (pub : Array Aiur.G) (proof : STARKProof) : IO (Nat × Bool) := do
  let t0 ← IO.monoMsNow
  let ok ← verifySTARKProof proof pub circuit
  let t1 ← IO.monoMsNow
  return (t1 - t0, ok)

end Tests.Validation

def main : IO Unit := do
  let (circuit, pub, priv) ← Tests.Validation.buildCircuit

  -- Warm-up: untimed, absorbs JIT / lazy init cost so it doesn't pollute the timed runs.
  IO.println "Warm-up proof generation (untimed)..."
  let _ ← Tests.Validation.timeProve circuit pub priv

  let runs := 5
  let mut times : Array Nat := #[]
  let mut lastProof : Option ZkIpProtocol.STARKProof := none
  for i in [0:runs] do
    let (t, proof) ← Tests.Validation.timeProve circuit pub priv
    IO.println s!"  run {i + 1}/{runs}: {t} ms"
    times := times.push t
    lastProof := some proof

  let sorted := times.qsort (· < ·)
  let median := sorted[runs / 2]!
  IO.println s!"CPU proving times (ms): {sorted.toList}"
  IO.println s!"median proving time: {median} ms"

  let some proof := lastProof
    | throw (IO.userError "no proof was generated")
  let (verifyMs, verified) ← Tests.Validation.timeVerify circuit pub proof
  IO.println s!"verify time: {verifyMs} ms"
  if verified then
    IO.println "verification: PASSED"
  else
    IO.println "verification: FAILED -- DONE_WITH_CONCERNS"
