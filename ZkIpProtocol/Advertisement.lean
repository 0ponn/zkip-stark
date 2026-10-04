-- ZkIpProtocol/Advertisement.lean
import ZkIpProtocol.CoreTypes
import ZkIpProtocol.STARKIntegration

namespace ZkIpProtocol

-- FIX: Use the correct namespace defined in CoreTypes.lean
-- 'open CoreTypes' was causing the 'unknown namespace' error.
open ZkIpProtocol

structure Advertisement where
  id : Nat
  provider : Nat
  price : Nat
  merkleProof : MerkleProof

/--
  Convert Advertisement to public inputs for the STARK circuit.
  Uses the newly defined 'natToByteArray' from CoreTypes.
-/
def Advertisement.toPublicInputs (adv : Advertisement) : Array ByteArray :=
  #[
    natToByteArray adv.id,
    natToByteArray adv.provider,
    natToByteArray adv.price,
    adv.merkleProof.rootHash
  ]

/-- Verify a ZK certificate against its own disclosures and commitment.

    The operator is not part of the STARK claim (the circuit only ever proves
    `>`), so it is checked here: a certificate relabelled with any other
    operator must not verify, or a relying party reading `predicate.operator`
    would be misled. Each attribute is in the claim (as its id), so a
    certificate relabelled with another attribute fails the proof check. -/
def verifyCertificate (cert : ZKCertificate) : IO Bool := do
  if cert.disclosures.isEmpty || cert.disclosures.size > maxDisclosures then return false
  if cert.disclosures.any (fun d => d.predicate.operator != ">" || !validAttributeLabel d.attributeLabel) then
    return false
  verifyDisclosureProof cert.proof
    (cert.disclosures.map fun d => (d.predicate.threshold, attrIdOf d.attributeLabel)) cert.commitment

end ZkIpProtocol
