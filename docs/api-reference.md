# API Reference

## Core Types

### Ixon
IP Exchange Object Notation - the core IP data object.

```lean
structure Ixon where
  id : Nat
  attributes : Array IPAttribute
  merkleRoot : ByteArray
  timestamp : Nat
```

### IPAttribute
IP attribute types for Advertisements.

```lean
inductive IPAttribute where
  | performance (n : Nat)
  | security (n : Nat)
  | efficiency (n : Nat)
  | custom (s : String) (n : Nat)
```

### IPPredicate
IP Predicate for compliance checking.

```lean
structure IPPredicate where
  threshold : Nat
  operator : String
```

### ZKCertificate
The output of a successful verified disclosure.

```lean
structure ZKCertificate where
  ipId : Nat
  commitment : ByteArray
  predicate : IPPredicate
  proof : STARKProof
  timestamp : Nat
```

## Main Functions

### generateCertificateWithSTARK
Generate a ZK certificate with STARK proof.

```lean
def generateCertificateWithSTARK
  (ixon : Ixon)
  (predicate : IPPredicate)   -- operator must be ">"
  (attributeIndex : Nat)      -- which of ixon.attributes to prove
  : IO (Option ZKCertificate)
```

The Merkle root is recomputed from `ixon.attributes` (leaves are `attrLeafBytes value`,
4-byte little-endian); a non-empty `ixon.merkleRoot` that differs yields `none`. The
returned certificate's `commitment` is that root. All values must be `< 2^32`.

### verifyCertificate
Verify a ZK certificate.

```lean
def verifyCertificate (cert : ZKCertificate) : IO Bool
```

### buildMerkleTree
Build a Merkle tree from data array.

```lean
def buildMerkleTree (data : Array ByteArray) : ByteArray
```

### generateSTARKProof
Generate a STARK proof for a predicate circuit.

```lean
def generateSTARKProof
  (publicInputs : Array G)
  (privateInputs : Array G)
  (circuit : PredicateCircuit)
  : IO (Option STARKProof)
```

### verifySTARKProof
Verify a STARK proof.

```lean
def verifySTARKProof
  (proof : STARKProof)
  (publicInputs : Array G)
  (circuit : PredicateCircuit)
  : IO Bool
```

## Modules

- `ZkIpProtocol.STARKIntegration` - STARK proof integration
- `ZkIpProtocol.MerkleCommitment` - Merkle tree operations
- `ZkIpProtocol.MerkleCircuit` - In-circuit Merkle path verification and batched disclosure
- `ZkIpProtocol.Advertisement` - Certificate generation
- `ZkIpProtocol.Api` - HTTP REST API

Batch proof support, recursive verification, and the ZKMB middlebox were
never implemented — their P0-era scaffolding never compiled and has been
deleted from the repository.

