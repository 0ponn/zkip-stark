# Security review packet: zkip-stark zero-knowledge certificates

For an outside reviewer. This page states exactly what the system claims, how
it gets there, what went wrong on the way, and the questions where we most
need a cryptographer's judgment. Reading time is about 30 minutes. All
reviews so far were done by AI models (Claude, gpt-5.4, gpt-oss); none by a
person with cryptography training.

## 1. What it is

An owner commits a list of numeric attributes (for example
`performance = 1500`, `security = 8`) to a Blake3 Merkle root. A certificate
then proves, for up to 8 named attributes, that each committed value is
greater than a public threshold, without revealing the values. One STARK proof
covers all of them. A verifier needs only the certificate.

## 2. The statement

Public: the root `R`, and per disclosure `i` a label `L_i` and a threshold
`T_i < 2^32`.

Private: per disclosure, a value `v_i < 2^32` and a Merkle path `P_i` of
exactly 32 levels.

Relation: for every `i`,

- `leaf_i = attrId(L_i) ++ le32(v_i)` (36 bytes), where
  `attrId(L) = Blake3(0x02 ++ utf8(L))`;
- `Blake3(0x00 ++ leaf_i)` folds through `P_i` to `R`, with internal nodes
  `Blake3(0x01 ++ left ++ right)`;
- `P_i` walks to slot `slot(L_i)`, the first little-endian u32 word of
  `attrId(L_i)`: the tree is keyed by label, so it holds at most one value
  per label. Empty subtrees are `E_0 = Blake3(0x04)` and
  `E_(l+1) = Blake3(0x01 ++ E_l ++ E_l)`;
- `v_i > T_i`.

Labels are `performance`, `security`, `efficiency` or `custom/<name>`.

Public claim (Goldilocks elements):
`[0, funIdx] ++ per item [T_i, attrId_i as 8 LE u32 words] ++ [R as 8 LE u32 words] ++ [1]`.
A batch of K disclosures uses the circuit entry for the smallest of
{1, 2, 4, 8} that is at least K. The list is padded by repeating its last
item, and the verifier pads identically.

## 3. Privacy claims

Hidden: every `v_i`, every path `P_i`, the tree's size (up to 65,536
attributes; every path is 32 levels), and every attribute not disclosed. A
disclosed leaf's position is its label's slot, which is public.

Public by design: the labels, the thresholds, the root, and the entry size
(1, 2, 4 or 8).

The claim we want checked: **a proof reveals nothing about the private witness
beyond the truth of the statement**, under the parameters in section 4. There
is no written proof of this. The argument is the construction in section 5
plus attack tests. Turning it into a proof, or showing where one fails, is the
review we are asking for.

## 4. Construction

| Layer | What |
|---|---|
| Circuit language | Aiur (Lean DSL compiled to multi-table AIR with logUp lookups), from [argumentcomputer/ix](https://github.com/argumentcomputer/ix), fork `0ponn/ix` branch `zk` |
| Prover | [argumentcomputer/multi-stark](https://github.com/argumentcomputer/multi-stark), fork `0ponn/multi-stark` branch `zk-hiding-pcs` |
| PCS | Plonky3 `HidingFriPcs` (pinned rev e9d7561), 4 random codewords |
| Field | Goldilocks, challenge field its quadratic extension (D = 2) |
| Hash | Blake3 for Merkle commitments (salted leaves, 4 × 64-bit salt) and the Fiat-Shamir challenger |
| FRI | `log_blowup = 3` (rate 1/8), 38 queries, 16-bit query PoW, arity 2, 20-bit commit-phase PoW: 38 · 3 + 16 = 130 conjectured bits (was blowup 4, 100 queries, 200 bits; changed 2026-10-05 to cut the proof from 9.9 to 3.0 MB) |
| Prover randomness | ChaCha `StdRng` seeded from the OS (`rand::make_rng`, ix `crates/aiur/src/synthesis.rs`), prover-local; the verifier draws no randomness |

Upstream multi-stark states that it is **not** zero-knowledge (its
`verifier.rs` module docs). Everything ZK here comes from our fork, described
next.

## 5. What we added for zero-knowledge, and why

Each item names the code and the test that pins it.

1. **Hiding PCS throughout.** Traces are committed with `HidingFriPcs`
   (interleaved random rows, random columns), quotient chunks are randomized
   (eprint 2024/1037, section 4.2), and a random polynomial is added to the
   FRI batch. MMCS salts, blinding and masks all come from one shared CSPRNG
   stream, because cloned seeded generators would publish the blinding in the
   opened salts. Code: multi-stark `src/types.rs` (`GoldilocksBlake3ZkConfig`,
   `SharedRng`). Tests: ZK twins of every end-to-end test,
   `zk_proofs_of_same_witness_differ`, `zk_proof_without_randomization_rejected`.

2. **Minimum trace height.** A blinded `h`-row trace has only `h` random rows,
   and a review recovered a 4-row trace from one proof. The floor is
   Plonky3's own hiding budget from Plonky3 PR #2100,
   `next_pow2(2 · (D · points + num_queries))` with points = 2 (ζ, ζ·g), which
   gives **128 rows** at 38 queries. Our pinned Plonky3 rev predates that check, so the fork
   enforces it. Code: multi-stark `src/types.rs` (`min_trace_height`).
   Tests: `zk_min_trace_height_matches_plonky3_hiding_budget`,
   `zk_short_trace_refused`, `zk_short_trace_proof_rejected_by_shape`.

3. **Masked lookup accumulators.** The per-table logUp accumulators are
   public. Anyone who guessed a table's lookups could replay the transcript and
   confirm the guess; we reproduced this bit for bit. Each adjacent pair of
   tables now shares a secret 128-bit value: one table pushes it and the next
   pulls it, on a dedicated `MASK_TAG` channel (5 extra stage-1 columns per
   table). The pair cancels in the global sum and offsets every published
   accumulator. Claims tagged `MASK_TAG` are rejected, because the
   unconstrained mask could otherwise balance a forged claim. This requires
   D = 2, since the two secret base elements per link are uniform only over
   the quadratic extension. Code: multi-stark `src/system.rs`, `src/lookup.rs`.
   Tests: `zk_accumulators_do_not_confirm_witness`,
   `zk_unbalanced_mask_rejected`, `zk_mask_tag_claim_rejected`.

4. **Fixed trace shape.** Each proof publishes every table's height, and
   Aiur sizes tables by call count, so heights tracked the Merkle depth (up to
   8x between 1 and 5 attributes). Every path is now 32 levels, and a level
   costs the same rows whichever side its sibling is on (`keyed_node`), so
   the shape depends only on the entry size. Each entry size has one
   calibrated shape: the per-table maximum over synthetic witnesses (extreme
   and distinct values, thresholds and labels; distinct filler siblings),
   with 1/8 headroom over raw row counts, because content-addressed rows put a
   real witness about 3% above a synthetic one. The prover refuses any proof
   whose shape differs, and the verifier rejects one. A calibration miss therefore costs completeness, not
   privacy. Code: zkip-stark `ZkIpProtocol/FusedCircuit.lean`
   (`calibrationHeights`). Tests: `fixedTraceShapeCheck`,
   `multiDisclosureCheck`.

5. **Reproducible verifying key.** The preprocessed-table commitment is part
   of the verifying key and is never in the proof. It was salted from the
   live RNG, so only the proving process could verify. It is now committed
   through a second hiding PCS whose salts come from a fixed public seed, the
   constant `b"multi-stark/v0-zk/preprocessed!!"` (`StdRng::from_seed`). The
   preprocessed tables are fixed by the circuit, so neither party chooses
   them, and their salts are opened in every proof anyway. Code:
   multi-stark `StarkGenericConfig::preprocessing_pcs`, `SharedRng::fixed`.
   Test: `zk_proof_verifies_under_independently_built_system`.

## 6. Bugs found so far

These are listed because the pattern matters: all but the last were found
late, by a model review or by accident; the last was the first human review.

| Found | Issue | Fixed in |
|---|---|---|
| 2026-10-03 | 4-row trace recoverable from one proof | multi-stark c95ed66 (floor), 3bc3ab9 (raised to Plonky3's budget) |
| 2026-10-03 | Lookup accumulators confirmed a guessed witness | multi-stark 9609200 |
| 2026-10-03 | `MASK_TAG` claim forgeable through the mask channel | multi-stark f0687bd |
| 2026-10-03 | Trace heights leaked the Merkle depth | zkip-stark M8 |
| 2026-10-04 | Floor of 128 rows was below Plonky3's budget (208) | multi-stark 3bc3ab9 |
| 2026-10-04 | Verifying key differed per process | multi-stark 2788bff |
| 2026-10-04 | Leaf did not bind the attribute, so a certificate could be relabelled | zkip-stark M10 |
| 2026-10-04 | A root could commit one label twice, so a proof showed only "some value with this label passes" (found by a ZK Hack community member) | zkip-stark M12 (label-keyed tree) |

## 7. Questions for the reviewer, most important first

1. **Is 128 rows enough?** We adopted Plonky3's budget
   `2 · (D · points + queries)` without a derivation; Plonky3 does not
   document where the factor of 2 comes from. Our tables are opened at 2
   points with 38 queries (plus 16-bit query PoW). Do the FRI commit-phase openings (folded values at
   the sibling point) add leakage beyond this count, given 4 random codewords?
2. **Is the accumulator mask sound and hiding?** One 128-bit secret per
   adjacent pair of tables, carried as two base elements over a quadratic
   extension. Does anything else published (the final sum, the opened
   accumulator columns at ζ and ζ·g, the query openings) cancel the mask?
3. **Is the zero-knowledge argument complete?** Is the list in section 5 all
   that a hiding PCS needs on top of a multi-table logUp STARK? We suspect
   gaps we don't know to look for, for example lookup multiplicities or the
   preprocessed tables.
4. **What is the soundness level?** We have not computed it. Conjectured FRI
   security is 38 · 3 + 16 = 130 bits at ρ = 1/8; the proven (Johnson-bound)
   figure is about half the query term, roughly 57 + 16 bits, which is the
   number most worth checking; the challenge field is about 2^128; there is
   20-bit commit PoW. We chose the conjectured 128-bit target that most STARK
   deployments use. Plonky3 PR #2100 added
   multi-STARK soundness accounting that our pinned rev lacks.
5. **Does padding or calibration leak anything?** Repeating the last
   disclosure is visible in the claim. The shape depends only on the entry
   size, but it is calibrated empirically (with headroom), not derived.
6. **Is the label-keyed tree sound?** The slot is the first 32 bits of the
   label's id, the directions are witness bits pinned by
   `idx = sum of dir_j * 2^j == a0`, and a level counter `== 32` pins the
   depth. (A first version checked `2^levels == 2^32` instead; 2 has order 192
   in Goldilocks, so a 224-level path passed. Caught in self-review before
   merge; test "224-level path".)

## 8. Out of scope or known limits

- **Slot clashes.** Two different labels whose ids share their first 32 bits
  cannot be committed together (about 0.01% at 1,000 labels). This costs
  completeness only: a slot's leaf carries the full 32-byte id.
- **Root provenance.** Nothing here attests that the root describes true
  facts. The root is whatever the owner committed.
- **Server.** The HTTP server is a single long-running process with a bearer
  key on the proving endpoints, one connection at a time, and request size and
  time limits. It has had no security review of its own.
- **Recursion.** ix's in-circuit Lean verifier was not ported to the ZK
  transcript.
- **Statistical ZK.** The FRI-batch randomization is statistically
  zero-knowledge, as in Plonky3.

## 9. Reproduce

```bash
git clone https://github.com/0ponn/zkip-stark && cd zkip-stark
lake build && lake build Tests.Validation.PredicateSoundness
lake exe Tests.Validation.PredicateSoundness   # about 90 s, all certificate-level checks
git clone -b zk-hiding-pcs https://github.com/0ponn/multi-stark && cd multi-stark
cargo test --release                           # 43 tests, ZK twins and attacks
```

Pins: multi-stark `zk-hiding-pcs` 2788bff, ix `zk` 441fce5, Plonky3 e9d7561.
The label-keyed tree is in zkip-stark `ZkIpProtocol/MerkleCommitment.lean`
(`keyedLeaves`, `keyedRoot`, `keyedProof`) and `MerkleCircuit.lean`
(`keyed_fold`, `keyed_node`, `read_digest`).

## 10. Where to look

| Concern | File |
|---|---|
| Relation and circuit | zkip-stark `ZkIpProtocol/MerkleCircuit.lean` (`batch_item`, `merkle_fold`, `node_from`) |
| Leaf and attribute id | zkip-stark `ZkIpProtocol/MerkleCommitment.lean` |
| Claim layout, padding, calibration | zkip-stark `ZkIpProtocol/FusedCircuit.lean` |
| Prover and verifier entry points | zkip-stark `ZkIpProtocol/STARKIntegration.lean` |
| ZK config, floor, RNG, verifying-key salts | multi-stark `src/types.rs`, `src/config.rs` |
| Accumulator masks | multi-stark `src/system.rs`, `src/lookup.rs` |
| ZK prover and verifier | multi-stark `src/prover.rs`, `src/verifier.rs` (module docs state the ZK variant) |
| History and decisions | zkip-stark `REMEDIATION.md` (O3) |
