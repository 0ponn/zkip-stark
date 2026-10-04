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

The label-keyed Merkle root is recomputed from `ixon.attributes`, whose labels must be
distinct (`keyedLeaves`). Each leaf is
`attrLeaf label value`: the 32-byte attribute id `Blake3(0x02 ++ label)` followed by
the value as 4 little-endian bytes, where `label` is `performance`, `security`,
`efficiency` or `custom/<name>`. A non-empty `ixon.merkleRoot` that differs yields
`none`. The returned certificate's `commitment` is that root and its
`attributeLabel` (JSON `attribute`) names the proved attribute; the proof binds both.
All values must be `< 2^32`.

### generateCertificate
Several disclosures in one certificate and one proof.

```lean
def generateCertificate
  (ixon : Ixon)
  (requests : Array (Nat × IPPredicate))  -- (attributeIndex, predicate), 1 to 8, distinct indices
  : IO (Option ZKCertificate)
```

The certificate's `disclosures` list each proved attribute's label and predicate, in
request order. Circuit entries exist for 1, 2, 4 and 8 disclosures; other counts use the
next entry, padded by repeating the last disclosure (the verifier pads identically).
`generateCertificateWithSTARK` is the single-disclosure case.

### verifyCertificate
Verify a ZK certificate.

```lean
def verifyCertificate (cert : ZKCertificate) : IO Bool
```

### keyedLeaves / keyedRoot / keyedProof
The production commitment: a label-keyed sparse Merkle tree, 32 levels, one slot per
label (`labelSlot label` = the first little-endian u32 word of `attrIdOf label`).

```lean
def keyedLeaves (attrs : Array IPAttribute) : Except String (Array (Nat × ByteArray))
def keyedRoot (leaves : Array (Nat × ByteArray)) : ByteArray
def keyedProof (leaves : Array (Nat × ByteArray)) (slot : Nat) : MerkleProof
```

`keyedLeaves` refuses a label that appears twice, and two labels whose slots clash
(about 0.01% at 1,000 labels; rename one). Empty subtrees hash to fixed digests.

### buildMerkleTree
Build a positional Merkle tree from a data array (used by the legacy M2 spike circuits,
not by certificates).

```lean
def buildMerkleTree (data : Array ByteArray) : IO ByteArray
```

### generateSTARKProof
Prove `attr > threshold` for the committed leaf under `root`. `leaf` is the
36-byte `attrLeaf label value`; `path` is its 32-level `keyedProof leaves (labelSlot label)`. The
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

Recursive verification and the ZKMB middlebox were never implemented — their P0-era scaffolding never compiled and has been
deleted from the repository.

