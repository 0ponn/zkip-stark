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

  -- RECURSIVE variable-depth fold over an authentication path (M3 Task 1).
  -- `path` is a flat `ByteStream` of 33-byte level records, level 0 (closest to
  -- the leaf) FIRST: each record is `dir_byte ++ 32 sibling bytes`. The fold
  -- consumes one record per step and applies `node_from`, terminating when the
  -- stream is exhausted (`ListNode.Nil`) and returning the final root digest.
  --
  -- This is blake3-style layer recursion: it reproduces exactly the M2a
  -- `verifyProof` fold (`if sibIsLeft then nodeHash(sib, acc) else
  -- nodeHash(acc, sib)`) for ANY depth D, because each step is one `node_from`
  -- with the same dir convention (dir=0 => acc left; dir=1 => sib left) and the
  -- same Boolean constraint (`dir*(dir-1)==0`, enforced inside `node_from`).
  --
  -- WELL-FORMEDNESS: `list_take(rest, 32)` / `list_drop(rest, 32)` require each
  -- non-empty record to carry a full 32-byte sibling; a short trailing chunk
  -- makes the `Cons` pattern in `list_take` fail => the malformed witness is
  -- rejected. So the stream length must be exactly 33*D.
  fn merkle_fold(acc: [[U8; 4]; 8], path: ByteStream) -> [[U8; 4]; 8] {
    match load(path) {
      ListNode.Nil => acc,
      ListNode.Cons(dir, rest) =>
        let sib = list_take(rest, 32);
        let tail = list_drop(rest, 32);
        let acc_next = node_from(acc, sib, dir);
        merkle_fold(acc_next, tail),
    }
  }

  -- Variable-depth multi-level membership entry (M3 Task 1; was fixed-depth 3).
  -- Public args: 8x u32 root words (little-endian), r0..r7.
  -- Private IO (all under key [0]):
  --   channel 0 : leaf bytes
  --   channel 1 : the authentication path as a flat ByteStream, level 0 first,
  --               each level = dir_byte (0 => acc left, 1 => sib left) ++ 32
  --               sibling-digest bytes. Length = 33 * depth.
  -- Fold: acc0 = leafHash(leaf) = blake3(0x00 ++ leaf); then walk `path` via the
  -- recursive `merkle_fold`, one `node_from` per level. The final digest is the
  -- recomputed root, bound to the public root. Depth is now a knob set purely by
  -- the length of the channel-1 witness. Each dir is Boolean-constrained inside
  -- `node_from`. Output 1.
  pub fn merkle_path(
    r0: G, r1: G, r2: G, r3: G, r4: G, r5: G, r6: G, r7: G
  ) -> G {
    let (li, ll) = io_get_info(0, [0]);
    let leaf = #read_byte_stream(0, li, ll);
    let (pi, pl) = io_get_info(1, [0]);
    let path = #read_byte_stream(1, pi, pl);
    let leaf_pre = store(ListNode.Cons(0u8, leaf));
    let acc0 = blake3(leaf_pre);
    let root = merkle_fold(acc0, path);
    assert_eq!(word_le(root[0]), r0);
    assert_eq!(word_le(root[1]), r1);
    assert_eq!(word_le(root[2]), r2);
    assert_eq!(word_le(root[3]), r3);
    assert_eq!(word_le(root[4]), r4);
    assert_eq!(word_le(root[5]), r5);
    assert_eq!(word_le(root[6]), r6);
    assert_eq!(word_le(root[7]), r7);
    1
  }

  -- FUSED predicate + depth-3 Merkle membership (M2b Task 4). Proves ONE
  -- statement: "I know a private `attr` and a depth-3 Merkle path such that
  --   (1) attr > threshold  AND
  --   (2) leafHash(encode(attr)) is a member of the tree with the public root",
  -- where `encode(attr)` is the canonical 4-byte little-endian encoding
  -- (`ZkIpProtocol.attrLeafBytes`).
  --
  -- Public args: `threshold` (G) + 8x u32 root words (little-endian), r0..r7.
  -- Private IO (one channel each, under key [0]):
  --   channel 0        : the 4 LE attr bytes = the leaf bytes
  --   channels 1,2,3   : the 3 sibling digests (32 bytes each), level 0..2
  --   channels 4,5,6   : the 3 direction bytes (0 => acc left, 1 => sib left)
  --
  -- THE ATTR↔LEAF BINDING (what closes ad-switch): the SAME 4 bytes read on
  -- channel 0 are consumed BOTH ways — (a) recomposed little-endian into the
  -- field element `attr` that the predicate `u32_less_than(threshold, attr)`
  -- ranges over, and (b) hashed as the leaf preimage `0x00 ++ bytes` for the
  -- membership fold. A prover therefore cannot advertise a predicate value that
  -- differs from the committed leaf: changing the advertised value changes the
  -- 4 bytes, which changes the leaf hash, which breaks the root binding. Each
  -- byte is a `U8` (domain < 256), so the recomposed `attr` is < 2^32,
  -- matching the M1 u32 predicate domain. Output 1.
  pub fn merkle_predicate(
    threshold: G,
    r0: G, r1: G, r2: G, r3: G, r4: G, r5: G, r6: G, r7: G
  ) -> G {
    let (li, ll) = io_get_info(0, [0]);
    -- Constrain channel 0 stream length to exactly 4 bytes, closing ad-switch
    -- algebraically: if the stream is longer, the leaf cannot be purely f(attr).
    assert_eq!(ll, 4);
    let attr_bytes = #read_byte_stream(0, li, ll);
    -- (a) recompose the 4 LE bytes into the u32 field element `attr`.
    let ListNode.Cons(b0, t1) = load(attr_bytes);
    let ListNode.Cons(b1, t2) = load(t1);
    let ListNode.Cons(b2, t3) = load(t2);
    let ListNode.Cons(b3, _) = load(t3);
    let attr = to_field(b0) + 0x100 * to_field(b1)
      + 0x10000 * to_field(b2) + 0x1000000 * to_field(b3);
    -- the M1 predicate: attr > threshold.
    assert_eq!(u32_less_than(threshold, attr), 1);
    -- (b) membership: leaf = leafHash(attr_bytes) = blake3(0x00 ++ attr_bytes),
    -- then fold the depth-3 path and bind the recomputed root to the public one.
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
    let leaf_pre = store(ListNode.Cons(0u8, attr_bytes));
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

  -- Next 4 bytes of `s` as one little-endian u32 field element, and the rest.
  fn take_word(s: ByteStream) -> (G, ByteStream) {
    let ListNode.Cons(b0, t1) = load(s);
    let ListNode.Cons(b1, t2) = load(t1);
    let ListNode.Cons(b2, t3) = load(t2);
    let ListNode.Cons(b3, t4) = load(t3);
    (to_field(b0) + 0x100 * to_field(b1)
      + 0x10000 * to_field(b2) + 0x1000000 * to_field(b3), t4)
  }

  -- The next 32 bytes of `s` as a digest, and the rest. A short stream fails
  -- a `Cons` pattern, so a truncated path is rejected.
  fn read_digest(s: ByteStream) -> ([[U8; 4]; 8], ByteStream) {
    let ListNode.Cons(x0, t0) = load(s);
    let ListNode.Cons(x1, t1) = load(t0);
    let ListNode.Cons(x2, t2) = load(t1);
    let ListNode.Cons(x3, t3) = load(t2);
    let ListNode.Cons(x4, t4) = load(t3);
    let ListNode.Cons(x5, t5) = load(t4);
    let ListNode.Cons(x6, t6) = load(t5);
    let ListNode.Cons(x7, t7) = load(t6);
    let ListNode.Cons(x8, t8) = load(t7);
    let ListNode.Cons(x9, t9) = load(t8);
    let ListNode.Cons(x10, t10) = load(t9);
    let ListNode.Cons(x11, t11) = load(t10);
    let ListNode.Cons(x12, t12) = load(t11);
    let ListNode.Cons(x13, t13) = load(t12);
    let ListNode.Cons(x14, t14) = load(t13);
    let ListNode.Cons(x15, t15) = load(t14);
    let ListNode.Cons(x16, t16) = load(t15);
    let ListNode.Cons(x17, t17) = load(t16);
    let ListNode.Cons(x18, t18) = load(t17);
    let ListNode.Cons(x19, t19) = load(t18);
    let ListNode.Cons(x20, t20) = load(t19);
    let ListNode.Cons(x21, t21) = load(t20);
    let ListNode.Cons(x22, t22) = load(t21);
    let ListNode.Cons(x23, t23) = load(t22);
    let ListNode.Cons(x24, t24) = load(t23);
    let ListNode.Cons(x25, t25) = load(t24);
    let ListNode.Cons(x26, t26) = load(t25);
    let ListNode.Cons(x27, t27) = load(t26);
    let ListNode.Cons(x28, t28) = load(t27);
    let ListNode.Cons(x29, t29) = load(t28);
    let ListNode.Cons(x30, t30) = load(t29);
    let ListNode.Cons(x31, t31) = load(t30);
    ([[x0, x1, x2, x3], [x4, x5, x6, x7], [x8, x9, x10, x11], [x12, x13, x14, x15], [x16, x17, x18, x19], [x20, x21, x22, x23], [x24, x25, x26, x27], [x28, x29, x30, x31]], t31)
  }

  -- One level of the label-keyed tree (M12). Both orders build
  -- `0x01 ++ left ++ right` with the same calls, so a level costs the same rows
  -- whichever side the sibling is on: the trace shape does not depend on the
  -- slot, which comes from the (public) label.
  fn keyed_node(acc: [[U8; 4]; 8], sib: [[U8; 4]; 8], dir: U8) -> [[U8; 4]; 8] {
    assert_eq!(to_field(dir) * (to_field(dir) - 1), 0);
    match dir {
      0 => blake3(store(ListNode.Cons(1u8, digest_to_stream(acc, digest_to_stream(sib, store(ListNode.Nil)))))),
      _ => blake3(store(ListNode.Cons(1u8, digest_to_stream(sib, digest_to_stream(acc, store(ListNode.Nil)))))),
    }
  }

  -- Fold a path of `dir ++ 32 sibling bytes` records (level 0 first) from the
  -- leaf digest `acc`. Returns the root, the level count and the slot index
  -- `idx = sum of dir_j * 2^j` (dir = 1: the node is a right child). The level
  -- count is a plain counter: `2^levels` would not do, because 2 has order 192
  -- in Goldilocks, so 2^224 = 2^32 and a 224-level path could pass for 32.
  fn keyed_fold(acc: [[U8; 4]; 8], path: ByteStream, pow: G, idx: G, levels: G)
      -> ([[U8; 4]; 8], G, G) {
    match load(path) {
      ListNode.Nil => (acc, levels, idx),
      ListNode.Cons(dir, rest) =>
        let (sib, tail) = read_digest(rest);
        keyed_fold(keyed_node(acc, sib, dir), tail, pow * 2, idx + to_field(dir) * pow, levels + 1),
    }
  }

  -- ONE disclosed attribute (M3 Task 2, attribute-bound in M10). Proves
  -- "attr_i > threshold AND the leaf `attr_id ++ attr_i` is a member of the
  -- tree with the public root", where `attr_id = a0..a7` is PUBLIC (the
  -- attribute's identity, `ZkIpProtocol.attrIdOf label`) and `attr_i` is
  -- private. Returns 1.
  --
  -- KEYED WITNESS LAYOUT:
  --   channel 0, key [i] : the 36 leaf bytes = attr_id (32) ++ 4 LE value
  --                        bytes; length-constrained to exactly 36.
  --   channel 1, key [i] : the authentication path, level 0 first, each level
  --                        = dir_byte ++ 32 sibling bytes, exactly 32 levels,
  --                        fed to `keyed_fold`; each dir is Boolean-constrained
  --                        and together they must spell the label's slot.
  --
  -- BINDING: the same 36 bytes are (a) checked word by word against the public
  -- attribute id, (b) recomposed (last 4) into the `attr` the predicate ranges
  -- over, and (c) hashed as the leaf preimage `0x00 ++ bytes`. So a proof is
  -- about one named, committed attribute: changing the advertised value or
  -- the attribute changes the leaf and breaks the root binding.
  fn batch_item(
    i: G, threshold: G,
    a0: G, a1: G, a2: G, a3: G, a4: G, a5: G, a6: G, a7: G,
    r0: G, r1: G, r2: G, r3: G, r4: G, r5: G, r6: G, r7: G
  ) -> G {
    let (li, ll) = io_get_info(0, [i]);
    assert_eq!(ll, 36);
    let leaf = #read_byte_stream(0, li, ll);
    let (w0, s1) = take_word(leaf);
    assert_eq!(w0, a0);
    let (w1, s2) = take_word(s1);
    assert_eq!(w1, a1);
    let (w2, s3) = take_word(s2);
    assert_eq!(w2, a2);
    let (w3, s4) = take_word(s3);
    assert_eq!(w3, a3);
    let (w4, s5) = take_word(s4);
    assert_eq!(w4, a4);
    let (w5, s6) = take_word(s5);
    assert_eq!(w5, a5);
    let (w6, s7) = take_word(s6);
    assert_eq!(w6, a6);
    let (w7, s8) = take_word(s7);
    assert_eq!(w7, a7);
    let (attr, _) = take_word(s8);
    assert_eq!(u32_less_than(threshold, attr), 1);
    let (pi, pl) = io_get_info(1, [i]);
    let path = #read_byte_stream(1, pi, pl);
    let leaf_pre = store(ListNode.Cons(0u8, leaf));
    let acc0 = blake3(leaf_pre);
    -- Label-keyed tree (M12): exactly 32 levels, and the slot the path walks
    -- is the label's, `a0` (the first word of its attribute id). One label has
    -- one slot, so a root holds at most one value per label.
    let (root, levels, idx) = keyed_fold(acc0, path, 1, 0, 0);
    assert_eq!(levels, 32);
    assert_eq!(idx, a0);
    assert_eq!(word_le(root[0]), r0);
    assert_eq!(word_le(root[1]), r1);
    assert_eq!(word_le(root[2]), r2);
    assert_eq!(word_le(root[3]), r3);
    assert_eq!(word_le(root[4]), r4);
    assert_eq!(word_le(root[5]), r5);
    assert_eq!(word_le(root[6]), r6);
    assert_eq!(word_le(root[7]), r7);
    1
  }

  -- BATCHED K-attribute disclosure under a SHARED root (M3 Task 2). Public
  -- args: per item (t_i, a_i_0..a_i_7), items in order, then the 8 shared root
  -- words. Output = product of the K item results = 1 iff all K hold. K is a
  -- Lean-side knob (`merkleBatchEntry`) selecting among these entries.

  pub fn merkle_predicate_batch1(
    t0: G, a0_0: G, a0_1: G, a0_2: G, a0_3: G, a0_4: G, a0_5: G, a0_6: G, a0_7: G,
    r0: G, r1: G, r2: G, r3: G, r4: G, r5: G, r6: G, r7: G
  ) -> G {
    batch_item(0, t0, a0_0, a0_1, a0_2, a0_3, a0_4, a0_5, a0_6, a0_7, r0, r1, r2, r3, r4, r5, r6, r7)
  }

  pub fn merkle_predicate_batch2(
    t0: G, a0_0: G, a0_1: G, a0_2: G, a0_3: G, a0_4: G, a0_5: G, a0_6: G, a0_7: G,
    t1: G, a1_0: G, a1_1: G, a1_2: G, a1_3: G, a1_4: G, a1_5: G, a1_6: G, a1_7: G,
    r0: G, r1: G, r2: G, r3: G, r4: G, r5: G, r6: G, r7: G
  ) -> G {
    batch_item(0, t0, a0_0, a0_1, a0_2, a0_3, a0_4, a0_5, a0_6, a0_7, r0, r1, r2, r3, r4, r5, r6, r7)
      * batch_item(1, t1, a1_0, a1_1, a1_2, a1_3, a1_4, a1_5, a1_6, a1_7, r0, r1, r2, r3, r4, r5, r6, r7)
  }

  pub fn merkle_predicate_batch4(
    t0: G, a0_0: G, a0_1: G, a0_2: G, a0_3: G, a0_4: G, a0_5: G, a0_6: G, a0_7: G,
    t1: G, a1_0: G, a1_1: G, a1_2: G, a1_3: G, a1_4: G, a1_5: G, a1_6: G, a1_7: G,
    t2: G, a2_0: G, a2_1: G, a2_2: G, a2_3: G, a2_4: G, a2_5: G, a2_6: G, a2_7: G,
    t3: G, a3_0: G, a3_1: G, a3_2: G, a3_3: G, a3_4: G, a3_5: G, a3_6: G, a3_7: G,
    r0: G, r1: G, r2: G, r3: G, r4: G, r5: G, r6: G, r7: G
  ) -> G {
    batch_item(0, t0, a0_0, a0_1, a0_2, a0_3, a0_4, a0_5, a0_6, a0_7, r0, r1, r2, r3, r4, r5, r6, r7)
      * batch_item(1, t1, a1_0, a1_1, a1_2, a1_3, a1_4, a1_5, a1_6, a1_7, r0, r1, r2, r3, r4, r5, r6, r7)
      * batch_item(2, t2, a2_0, a2_1, a2_2, a2_3, a2_4, a2_5, a2_6, a2_7, r0, r1, r2, r3, r4, r5, r6, r7)
      * batch_item(3, t3, a3_0, a3_1, a3_2, a3_3, a3_4, a3_5, a3_6, a3_7, r0, r1, r2, r3, r4, r5, r6, r7)
  }

  pub fn merkle_predicate_batch8(
    t0: G, a0_0: G, a0_1: G, a0_2: G, a0_3: G, a0_4: G, a0_5: G, a0_6: G, a0_7: G,
    t1: G, a1_0: G, a1_1: G, a1_2: G, a1_3: G, a1_4: G, a1_5: G, a1_6: G, a1_7: G,
    t2: G, a2_0: G, a2_1: G, a2_2: G, a2_3: G, a2_4: G, a2_5: G, a2_6: G, a2_7: G,
    t3: G, a3_0: G, a3_1: G, a3_2: G, a3_3: G, a3_4: G, a3_5: G, a3_6: G, a3_7: G,
    t4: G, a4_0: G, a4_1: G, a4_2: G, a4_3: G, a4_4: G, a4_5: G, a4_6: G, a4_7: G,
    t5: G, a5_0: G, a5_1: G, a5_2: G, a5_3: G, a5_4: G, a5_5: G, a5_6: G, a5_7: G,
    t6: G, a6_0: G, a6_1: G, a6_2: G, a6_3: G, a6_4: G, a6_5: G, a6_6: G, a6_7: G,
    t7: G, a7_0: G, a7_1: G, a7_2: G, a7_3: G, a7_4: G, a7_5: G, a7_6: G, a7_7: G,
    r0: G, r1: G, r2: G, r3: G, r4: G, r5: G, r6: G, r7: G
  ) -> G {
    batch_item(0, t0, a0_0, a0_1, a0_2, a0_3, a0_4, a0_5, a0_6, a0_7, r0, r1, r2, r3, r4, r5, r6, r7)
      * batch_item(1, t1, a1_0, a1_1, a1_2, a1_3, a1_4, a1_5, a1_6, a1_7, r0, r1, r2, r3, r4, r5, r6, r7)
      * batch_item(2, t2, a2_0, a2_1, a2_2, a2_3, a2_4, a2_5, a2_6, a2_7, r0, r1, r2, r3, r4, r5, r6, r7)
      * batch_item(3, t3, a3_0, a3_1, a3_2, a3_3, a3_4, a3_5, a3_6, a3_7, r0, r1, r2, r3, r4, r5, r6, r7)
      * batch_item(4, t4, a4_0, a4_1, a4_2, a4_3, a4_4, a4_5, a4_6, a4_7, r0, r1, r2, r3, r4, r5, r6, r7)
      * batch_item(5, t5, a5_0, a5_1, a5_2, a5_3, a5_4, a5_5, a5_6, a5_7, r0, r1, r2, r3, r4, r5, r6, r7)
      * batch_item(6, t6, a6_0, a6_1, a6_2, a6_3, a6_4, a6_5, a6_6, a6_7, r0, r1, r2, r3, r4, r5, r6, r7)
      * batch_item(7, t7, a7_0, a7_1, a7_2, a7_3, a7_4, a7_5, a7_6, a7_7, r0, r1, r2, r3, r4, r5, r6, r7)
  }
⟧

/-- Entry name for the sub-spike node-hash circuit. -/
def nodeHashEntry : Lean.Name := `node_hash_test

/-- Entry name for the single-level membership circuit. -/
def merkleSingleEntry : Lean.Name := `merkle_single

/-- Entry name for the fixed-depth-3 multi-level membership circuit. -/
def merklePathEntry : Lean.Name := `merkle_path

/-- Entry name for the fused predicate + depth-3 membership circuit (M2b Task 4). -/
def merklePredicateEntry : Lean.Name := `merkle_predicate

/-- M3 Task 2/3 knob: select the batched-disclosure entry for a given batch size K.
The circuit ships concrete entries for the scaling-study points K ∈ {1, 2, 4, 8}
(each with K public thresholds ++ 8 shared root words); this is the Lean-side
parameter the scaling study (Task 3) varies to grow the trace. -/
def merkleBatchEntry (k : Nat) : Lean.Name :=
  match k with
  | 1 => `merkle_predicate_batch1
  | 2 => `merkle_predicate_batch2
  | 4 => `merkle_predicate_batch4
  | _ => `merkle_predicate_batch8

end ZkIpProtocol.MerkleCircuit

end
