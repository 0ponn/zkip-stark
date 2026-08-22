# Examples

## Basic Certificate Generation

```lean
import ZkIpProtocol

-- Create IP metadata
let ixon : Ixon := {
  id := 1
  attributes := #[
    IPAttribute.performance 1000,
    IPAttribute.security 5,
    IPAttribute.efficiency 90
  ]
  merkleRoot := <computed-root>
  timestamp := 1234567890
}

-- Define predicate: performance >= 500
let predicate : IPPredicate := {
  threshold := 500
  operator := ">="
}

-- Generate certificate
let cert ← generateCertificateWithSTARK
  ixon
  predicate
  privateAttribute
  ipData
  attributeIndex
  hashInstance

match cert with
| some c => IO.println s!"Certificate generated: {c.ipId}"
| none => IO.println "Certificate generation failed"
```

## Certificate Verification

```lean
-- Verify a certificate
let isValid ← verifyCertificate certificate

if isValid then
  IO.println "Certificate is valid"
  -- Proceed with trusted operations
else
  IO.println "Certificate verification failed"
  -- Reject or handle error
```

## Batched K-Attribute Disclosure

Real, working batching disclosing several attributes under one shared Merkle
root in a single proof — see `Tests/Validation/BatchDisclosure.lean` and
`ZkIpProtocol/MerkleCircuit.lean` for the actual API.

## Not Implemented

The following were never implemented in this repository. Their P0-era
scaffolding (fictional APIs, stale struct fields) never compiled and has
been deleted — treat any example below as a design sketch, not working
code:

- **Multi-attribute STARK-proof batching** (`Batching.lean`,
  `verifyBatchPredicates`)
- **ZKMB application** — a TLS 1.3 zero-knowledge middlebox (`ZKMB.lean`,
  `ZKMBState`, `processTLSPacket`)
- **Recursive proof composition / recursive state updates**
  (`RecursiveProofs.lean`, `updateStateRecursively`)

