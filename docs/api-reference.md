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

The Merkle root is recomputed from `ixon.attributes`. Each leaf is
`attrLeaf label value`: the 32-byte attribute id `Blake3(0x02 ++ label)` followed by
the value as 4 little-endian bytes, where `label` is `performance`, `security`,
`efficiency` or `custom/<name>`. A non-empty `ixon.merkleRoot` that differs yields
`none`. The returned certificate's `commitment` is that root and its
`attributeLabel` (JSON `attribute`) names the proved attribute; the proof binds both.
All values must be `< 2^32`.

### verifyCertificate
Verify a ZK certificate.

```lean
def verifyCertificate (cert : ZKCertificate) : IO Bool
```

### buildMerkleTree
Build a Merkle tree from data array.

```lean
def buildMerkleTree (data : Array ByteArray) : IO ByteArray
```

### generateSTARKProof
Prove `attr > threshold` for the committed leaf under `root`. `leaf` is the
36-byte `attrLeaf label value`; `path` comes from `generateProof leaves index`. The
leaf's first 32 bytes (the attribute id) become public; the value stays private.

```lean
def generateSTARKProof (threshold : Nat) (root : ByteArray) (leaf : ByteArray) (path : MerkleProof)
  : IO (Option STARKProof)
```

### verifySTARKProof
Verify a proof against a threshold, a 32-byte attribute id (`attrIdOf label`) and
a 32-byte root; the full expected claim is derived from those three values.

```lean
def verifySTARKProof (proof : STARKProof) (threshold : Nat) (attrId root : ByteArray) : IO Bool
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

