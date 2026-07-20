module
/-
In-circuit single-level Blake3 Merkle check (M2b Task 2).

Authored in the readable `⟦ ⟧` Aiur DSL (a fresh `module` with NO `abbrev G`,
so the surface syntax is available). These functions are merged with ix's
`core` + `byteStream` + `blake3` toplevels (see `Blake3Circuit.lean`) before
compilation.

The load-bearing fact (proved by the M2b spike): the in-circuit `blake3`
gadget's digest equals `Blake3.Rust.hash` = the M2a scheme's `Hash.hash`.
This module recomputes the M2a `leafHash`/`nodeHash` in-circuit and binds the
resulting node to a public root.

M2a reference recomputed here (ZkIpProtocol/MerkleCommitment.lean):
  leafHash(b)    = Blake3(0x00 ++ b)
  nodeHash(l, r) = Blake3(0x01 ++ l ++ r)
  one verifyProof fold step: if sibIsLeft then nodeHash(sib, acc)
                                          else nodeHash(acc, sib)

`ByteStream = List‹U8›` (in-order: head = first byte). We CONSTRUCT the node
preimage in-circuit by consing `0x01` and concatenating the 32-byte operands
(NOT reading the 65-byte blob from IO), then hash it with the constrained
`blake3` call. `#read_byte_stream` is the unconstrained witness-read; `blake3`
and the preimage `store`s are constrained.
-/
public import Ix.Aiur.Meta

public section

namespace ZkIpProtocol.MerkleCircuit

open Aiur

/-- Merkle circuit functions in the Aiur DSL. Merged with `core` (lists),
`byteStream` (`read_byte_stream`, `U64`), and `blake3` (the gadget). -/
def merkleCircuit := ⟦
  -- Serialize a blake3 digest `[[U8; 4]; 8]` into a 32-byte `ByteStream`
  -- (in byte order, digest[0][0] first) prepended in front of `tail`.
  fn digest_to_stream(d: [[U8; 4]; 8], tail: ByteStream) -> ByteStream {
    store(ListNode.Cons(d[0][0],
    store(ListNode.Cons(d[0][1],
    store(ListNode.Cons(d[0][2],
    store(ListNode.Cons(d[0][3],
    store(ListNode.Cons(d[1][0],
    store(ListNode.Cons(d[1][1],
    store(ListNode.Cons(d[1][2],
    store(ListNode.Cons(d[1][3],
    store(ListNode.Cons(d[2][0],
    store(ListNode.Cons(d[2][1],
    store(ListNode.Cons(d[2][2],
    store(ListNode.Cons(d[2][3],
    store(ListNode.Cons(d[3][0],
    store(ListNode.Cons(d[3][1],
    store(ListNode.Cons(d[3][2],
    store(ListNode.Cons(d[3][3],
    store(ListNode.Cons(d[4][0],
    store(ListNode.Cons(d[4][1],
    store(ListNode.Cons(d[4][2],
    store(ListNode.Cons(d[4][3],
    store(ListNode.Cons(d[5][0],
    store(ListNode.Cons(d[5][1],
    store(ListNode.Cons(d[5][2],
    store(ListNode.Cons(d[5][3],
    store(ListNode.Cons(d[6][0],
    store(ListNode.Cons(d[6][1],
    store(ListNode.Cons(d[6][2],
    store(ListNode.Cons(d[6][3],
    store(ListNode.Cons(d[7][0],
    store(ListNode.Cons(d[7][1],
    store(ListNode.Cons(d[7][2],
    store(ListNode.Cons(d[7][3], tail
    ))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))
  }

  -- Little-endian recompose one 4-byte digest word into a single `G` (< 2^32),
  -- matching the M2b root-binding layout (8x u32 words).
  fn word_le(w: [U8; 4]) -> G {
    to_field(w[0]) + 0x100 * to_field(w[1])
      + 0x10000 * to_field(w[2]) + 0x1000000 * to_field(w[3])
  }

  -- nodeHash with the M2a verifyProof fold direction:
  --   dir == 0 => acc is the current node (left), sib is right  => nodeHash(acc, sib)
  --   dir != 0 => sib is left, acc is right                     => nodeHash(sib, acc)
  -- Builds `0x01 ++ left ++ right` in-circuit and hashes it (constrained).
  --
  -- BOOLEAN CONSTRAINT (Codex Minor from 0PO-545): `dir * (dir - 1) == 0` forces
  -- `dir ∈ {0, 1}` so a noncanonical direction byte (e.g. 2) cannot alias the
  -- `_ =>` arm. Applied here so EVERY level using `node_from` is constrained.
  fn node_from(acc: [[U8; 4]; 8], sib: ByteStream, dir: U8) -> [[U8; 4]; 8] {
    assert_eq!(to_field(dir) * (to_field(dir) - 1), 0);
    match dir {
      0 =>
        let preimage = store(ListNode.Cons(1u8, digest_to_stream(acc, sib)));
        blake3(preimage),
      _ =>
        let acc_stream = digest_to_stream(acc, store(ListNode.Nil));
        let preimage = store(ListNode.Cons(1u8, list_concat(sib, acc_stream)));
        blake3(preimage),
    }
  }

  -- SUB-SPIKE entry (M2b Task 2, step 1). `acc` (channel 0) and `sib`
  -- (channel 1) are 32-byte streams read from IO; we build `0x01 ++ acc ++ sib`
  -- in-circuit and hash. Output must equal `nodeHash(acc, sib)`.
  pub fn node_hash_test() -> [[U8; 4]; 8] {
    let (ai, al) = io_get_info(0, [0]);
    let acc = #read_byte_stream(0, ai, al);
    let (si, sl) = io_get_info(1, [0]);
    let sib = #read_byte_stream(1, si, sl);
    let preimage = store(ListNode.Cons(1u8, list_concat(acc, sib)));
    blake3(preimage)
  }

  -- Single-level membership entry (M2b Task 2, steps 2-3).
  -- Public args: 8x u32 root words (little-endian), r0..r7.
  -- Private IO: leaf bytes (channel 0), 32-byte sibling (channel 1),
  --             direction byte (channel 2; 0 => acc left, 1 => sib left).
  -- Computes acc = leafHash(leaf) = blake3(0x00 ++ leaf), then the node, and
  -- asserts each recomposed node word equals the public root word. Output 1.
  pub fn merkle_single(
    r0: G, r1: G, r2: G, r3: G, r4: G, r5: G, r6: G, r7: G
  ) -> G {
    let (li, ll) = io_get_info(0, [0]);
    let leaf = #read_byte_stream(0, li, ll);
    let (si, sl) = io_get_info(1, [0]);
    let sib = #read_byte_stream(1, si, sl);
    let (di, dl) = io_get_info(2, [0]);
    let dir_stream = #read_byte_stream(2, di, dl);
    let ListNode.Cons(dir, _) = load(dir_stream);
    let leaf_pre = store(ListNode.Cons(0u8, leaf));
    let acc = blake3(leaf_pre);
    let node = node_from(acc, sib, dir);
    assert_eq!(word_le(node[0]), r0);
    assert_eq!(word_le(node[1]), r1);
    assert_eq!(word_le(node[2]), r2);
    assert_eq!(word_le(node[3]), r3);
    assert_eq!(word_le(node[4]), r4);
    assert_eq!(word_le(node[5]), r5);
    assert_eq!(word_le(node[6]), r6);
    assert_eq!(word_le(node[7]), r7);
    1
  }

  -- Fixed-depth (3) multi-level membership entry (M2b Task 3).
  -- Public args: 8x u32 root words (little-endian), r0..r7.
  -- Private IO (one channel each, all under key [0]):
  --   channel 0        : leaf bytes
  --   channels 1,2,3   : the 3 sibling digests (32 bytes each), level 0..2
  --   channels 4,5,6   : the 3 direction bytes (0 => acc left, 1 => sib left)
  -- Fold: acc0 = leafHash(leaf) = blake3(0x00 ++ leaf); then for each level i,
  -- acc_{i+1} = node_from(acc_i, sib_i, dir_i) (reuses digest_to_stream to feed
  -- acc_i back as bytes). Final acc3 = recomputed root, bound to the public root.
  -- Each dir_i is Boolean-constrained inside `node_from`. Output 1.
  pub fn merkle_path(
    r0: G, r1: G, r2: G, r3: G, r4: G, r5: G, r6: G, r7: G
  ) -> G {
    let (li, ll) = io_get_info(0, [0]);
    let leaf = #read_byte_stream(0, li, ll);
    let (s0i, s0l) = io_get_info(1, [0]);
    let sib0 = #read_byte_stream(1, s0i, s0l);
    let (s1i, s1l) = io_get_info(2, [0]);
    let sib1 = #read_byte_stream(2, s1i, s1l);
    let (s2i, s2l) = io_get_info(3, [0]);
    let sib2 = #read_byte_stream(3, s2i, s2l);
    let (d0i, d0l) = io_get_info(4, [0]);
    let dstr0 = #read_byte_stream(4, d0i, d0l);
    let ListNode.Cons(dir0, _) = load(dstr0);
    let (d1i, d1l) = io_get_info(5, [0]);
    let dstr1 = #read_byte_stream(5, d1i, d1l);
    let ListNode.Cons(dir1, _) = load(dstr1);
    let (d2i, d2l) = io_get_info(6, [0]);
    let dstr2 = #read_byte_stream(6, d2i, d2l);
    let ListNode.Cons(dir2, _) = load(dstr2);
    let leaf_pre = store(ListNode.Cons(0u8, leaf));
    let acc0 = blake3(leaf_pre);
    let acc1 = node_from(acc0, sib0, dir0);
    let acc2 = node_from(acc1, sib1, dir1);
    let acc3 = node_from(acc2, sib2, dir2);
    assert_eq!(word_le(acc3[0]), r0);
    assert_eq!(word_le(acc3[1]), r1);
    assert_eq!(word_le(acc3[2]), r2);
    assert_eq!(word_le(acc3[3]), r3);
    assert_eq!(word_le(acc3[4]), r4);
    assert_eq!(word_le(acc3[5]), r5);
    assert_eq!(word_le(acc3[6]), r6);
    assert_eq!(word_le(acc3[7]), r7);
    1
  }
⟧

/-- Entry name for the sub-spike node-hash circuit. -/
def nodeHashEntry : Lean.Name := `node_hash_test

/-- Entry name for the single-level membership circuit. -/
def merkleSingleEntry : Lean.Name := `merkle_single

/-- Entry name for the fixed-depth-3 multi-level membership circuit. -/
def merklePathEntry : Lean.Name := `merkle_path

end ZkIpProtocol.MerkleCircuit

end
