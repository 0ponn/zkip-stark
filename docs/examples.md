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

## Batch Verification

```lean
import ZkIpProtocol.Batching

-- Verify multiple attributes in a single proof
let predicates : Array IPPredicate := #[
  { threshold := 500, operator := ">=" },
  { threshold := 3, operator := ">" },
  { threshold := 80, operator := ">=" }
]

let batchResult ← verifyBatchPredicates
  ixon
  predicates
  ipData

match batchResult with
| some proof => IO.println "Batch verification successful"
| none => IO.println "Batch verification failed"
```

## ZKMB Application

```lean
import ZkIpProtocol.ZKMB

-- Initialize ZKMB state
let initialState : ZKMBState := {
  stateProof := none
  stateRoot := ByteArray.empty
  packetCount := 0
  lastTimestamp := 0
  policy := defaultPolicy
}

-- Process TLS packet
let newState ← processTLSPacket
  initialState
  tlsPacket
  sessionKey

-- Verify compliance
let isCompliant ← verifyCompliance newState policy
```

## Recursive State Updates

```lean
import ZkIpProtocol.RecursiveProofs

-- Update state recursively
let updatedState ← updateStateRecursively
  currentState
  newTransition
  previousProof

-- Verify recursive proof
let isValid ← verifyRecursiveProof updatedState.stateProof
```

