# ICICLE FRI-first GPU feasibility spike (0PO-554)

**Date:** 2026-07-20
**Type:** RESEARCH ONLY — no CUDA installed, no code built, no prover code shipped.
**Question:** Can a GPU (ICICLE) FRI-first acceleration backend accelerate this
prover's dominant cost (79% in `stark/fri_open`, Blake3 Merkle openings), and
exactly how do we integrate it?
**Feeds:** `docs/superpowers/notes/2026-07-20-proof-phase-profile.md` (the profile
that established the proof is FRI-bound, not NTT-bound).

## TL;DR verdict

**Viable, but it is NOT free reuse.** The 79% is trait-reachable — Plonky3 routes
*all* FRI Merkle hashing through the `p3_commit::Mmcs` trait and all LDE through
`TwoAdicSubgroupDft`, so a GPU `Mmcs` + GPU `Dft` swap accelerates the hot path
without touching p3-fri internals. And the feared gap (Blake3 on GPU) is **closed**:
ICICLE ships a GPU Blake3 hash and a hasher-agnostic GPU Merkle tree.

The real work is that **no maintained ICICLE→Plonky3 prover backend exists.** The
public "AIR-ICICLE" integration is trace-gen + constraint parsing only and states
outright it has no backend prover. So we must *write* two adapters against ICICLE's
Rust bindings: a GPU `TwoAdicSubgroupDft` and a GPU `Mmcs` that reproduces
Plonky3's exact `MerkleTreeMmcs<…Blake3…>` byte layout. Biggest risk is
**byte-exact Blake3 Merkle compatibility** (so the unchanged verifier accepts the
GPU-built commitments) and keeping committed trees GPU-resident across query opens.
Effort: medium, ~2–4 focused weeks for a working FRI-first backend.

---

## 1. ICICLE capability (field / primitives / hashes)

**Repo:** github.com/ingonyama-zk/icicle. Current line is **v4.x** (v3.6 Metal,
v3.7 Goldilocks field, v3.8 FRI Rust wrappers + Merkle serialization, v3.9
Goldilocks-Ext + "FRI with Poseidon", v4.0 OO field API / lattice / ML-KEM).

- **Goldilocks on GPU: YES.** Added v3.7; Goldilocks extension field added v3.9;
  Goldilocks is implemented on top of `icicle-math` for backend-specific
  optimizations. This is our field.
- **NTT/DFT: YES** — core primitive since v1.
- **FRI: YES** (GPU) — Rust wrappers landed v3.8; v3.9 shipped "FRI with Poseidon".
  Note this is *ICICLE's own* FRI protocol/layout, Poseidon-oriented (see §3 — we
  do NOT use it wholesale).
- **Merkle-tree building / hashing on GPU: YES**, hasher-agnostic. The Merkle API
  takes per-layer hashers, so leaf-hasher and compression can differ, and you can
  mix hashers within one tree.
- **Hashes on GPU:** per `dev.ingonyama.com/api/cpp/hash`, ICICLE supports
  **Keccak-256, Keccak-512, SHA3-256, SHA3-512, Blake2s, Blake3, Poseidon,
  Poseidon2.** **Blake3 IS present** — this is the critical finding, because our
  79% hot path is Blake3 Merkle. The original spike worry ("GPU Merkle may be
  Poseidon/Keccak only") does not hold: Blake3 is a first-class GPU hash here.

**So the hash-availability gap is closed.** What is *not* provided is a
Plonky3-compatible Merkle construction (leaf packing + compression + digest
layout) — see §3/§5.

## 2. Plonky3 integration — is there an adapter?

**No prover backend.** The public integration is "AIR-ICICLE: Plonky3 on ICICLE"
(ingonyama.com/post/air-icicle-plonky3-on-part-1, HackMD @Ingonyama/air-icicle).
It provides:
- writing AIR circuits in Plonky3 with ICICLE field types,
- trace generation via ICICLE device-agnostic APIs,
- symbolic-constraint parsing.

It explicitly states: *"We haven't currently implemented a backend prover and will
do so in future work… build their own STARK provers using the ICICLE framework."*

So there is **no maintained impl of `p3_commit::Mmcs` or `p3_dft::TwoAdicSubgroupDft`
backed by ICICLE.** ICICLE exposes the building blocks (NTT, VecOps, Hash,
MerkleTree, FRI) as Rust bindings; the p3-trait adapters are the integration
surface we own. This is a "wrap ICICLE's Rust API behind the two p3 traits" job,
not a "flip a feature flag" job.

## 3. THE CRUX — is the 79% reachable via trait-swap?

**Yes, the dominant Merkle-hashing cost is trait-reachable.** Read against
Plonky3 rev `e9d75614` (the rev pinned in multi-stark `Cargo.toml`), local checkout
`~/.cargo/git/checkouts/plonky3-7d8a3b21a665a86f/e9d7561`.

Our config (multi-stark `src/types.rs`):
```
Mmcs   = MerkleTreeMmcs<Val, u8, SerializingHasher<Blake3>,
                        CompressionFunctionFromHasher<Blake3,2,32>, 2, 32>
Dft    = Radix2DitParallel<Val>
Pcs    = TwoAdicFriPcs<Val, Dft, Mmcs, ExtMmcs>   // Goldilocks
```

Where FRI does its hashing/NTT, and whether each is behind a swappable trait:

| Work | Location (rev e9d75614) | Behind a trait? |
|---|---|---|
| Trace/input LDE (NTT) | `fri/src/two_adic_pcs.rs:313,340` `self.dft.coset_lde_batch(...)` | **Yes** — `TwoAdicSubgroupDft` |
| Input-trace Merkle commit | `two_adic_pcs.rs:321,349` `self.mmcs.commit(ldes)` | **Yes** — `InputMmcs: Mmcs` |
| Commit-phase fold-layer Merkle build | `fri/src/prover.rs:210` `params.mmcs.commit_matrix(leaves)` | **Yes** — `FriMmcs: Mmcs` |
| **Query-phase Merkle path opens (the 79%)** | input opens `two_adic_pcs.rs:697` `self.mmcs…`; fold opens `prover.rs` `answer_query` `config.mmcs.open_batch(...)` | **Yes** — `Mmcs` |
| FRI folding arithmetic | `two_adic_pcs.rs:136` `fold_matrix` | **Yes** — `FriFoldingStrategy` trait (`config.rs:49`) |
| Barycentric / reduced-opening interp | `two_adic_pcs.rs:531` `interpolate_coset_with_precomputation`, `:221` `lagrange_interpolate_at` | **No** — inline in `open()` |
| final-poly IDFT | `prover.rs` `Radix2DFTSmallBatch::default().idft_algebra` | **No** — hardcoded, tiny |

**Conclusion:** every Merkle-hash operation in FRI (commit phase *and* query phase)
routes through the `Mmcs` trait, and all LDE routes through `TwoAdicSubgroupDft`.
The profiled 79% is dominated by exactly those (query-phase Blake3 path hashing +
the commit-phase fold-tree builds + input LDE), so a GPU `Mmcs` + GPU `Dft`
**reaches it without patching p3-fri**. Folding is also behind a trait
(`FriFoldingStrategy`) if we later want GPU folding. The only *un*-reachable slivers
are barycentric interpolation and the final-poly IDFT, which are inline in
`two_adic_pcs.rs::open()` — minority cost, leave on CPU initially, patch p3-fri only
if they become the next bottleneck.

Important corollary: **do NOT use ICICLE's own GPU FRI wholesale.** It implements
ICICLE's FRI layout (Poseidon-oriented) and would change the proof/transcript
format, breaking the unchanged multi-stark verifier. The trait-swap keeps
Plonky3's p3-fri orchestration and proof format intact — only the NTT and hashing
kernels move to GPU.

## 4. CUDA / toolchain requirement

- **CUDA Toolkit ≥ 12.0** for the ICICLE CUDA backend (older CUDA-11 GPUs may work
  but are unsupported). **CMake ≥ 3.18.**
- Target GPU here: **RTX 4070 Ti SUPER, Ada / compute capability 8.9.** Ada `sm_89`
  is supported from CUDA 12.0; install **CUDA 12.4+** (cleanest Ada codegen and
  matches ICICLE's prebuilt CUDA backend). Driver 610.43.03 already present is
  new enough — no driver constraint blocks CUDA 12.x on Ada.
- ICICLE ships a separate CUDA-backend package (licensed/downloaded at install);
  the frontend + Rust bindings are Apache-2.0. Plan for that split when installing.

## 5. Verdict, approach, effort, risks

**Verdict: GO (viable via trait-swap reuse), with adapters written by us.**

**Approach — fork chain, trait-swap, keep Plonky3 proof format:**
1. Fork `multi-stark` → `ix` → `zkip-stark` (existing design chain), branch
   `gpu-proving-backend`.
2. Add ICICLE Rust bindings (`icicle-core`, `icicle-hash`, `icicle-goldilocks`,
   NTT + Merkle) as an optional `gpu` feature.
3. Write **`IcicleDft: TwoAdicSubgroupDft<Goldilocks>`** wrapping ICICLE coset-LDE
   NTT — swap for `Radix2DitParallel` in `GoldilocksBlake3Config`.
4. Write **`IcicleBlake3Mmcs: Mmcs<Goldilocks>`** that reproduces Plonky3's
   `MerkleTreeMmcs<…SerializingHasher<Blake3>, CompressionFunctionFromHasher<
   Blake3,2,32>, 2, 32>` **byte-for-byte** (same Goldilocks→u8 serialization, same
   32-byte digest, arity-2 compression, same root/path layout) using ICICLE's GPU
   Blake3 + Merkle. Both the input `Mmcs` and the FRI `ExtMmcs` get GPU impls.
5. Keep committed Merkle trees resident on-device so `open_batch` per query is a
   device-side path fetch, not a host round-trip.
6. Verifier and proof format stay byte-identical — validate GPU proofs verify
   against the unchanged CPU verifier and match CPU-produced roots.

**Effort:** medium, ~2–4 focused weeks. NTT adapter is small (ICICLE NTT is mature);
the Merkle adapter is the bulk (byte-exact Plonky3 compat + on-device residency +
the batched/mixed-height MMCS semantics Plonky3 needs).

**Biggest risks (ranked):**
1. **Byte-exact Blake3 Merkle compatibility.** ICICLE has Blake3 + Merkle, but not
   Plonky3's specific leaf-serialization/compression/digest layout. If the GPU tree
   isn't bit-identical to `MerkleTreeMmcs`, the unchanged verifier rejects proofs.
   Mitigation: golden-vector test GPU root/path == CPU root/path before wiring FRI.
2. **Host↔device data movement.** numQueries=100 path opens are latency-sensitive;
   naive per-open transfers erase gains. Keep trees + LDEs on-device.
3. **Plonky3 MMCS semantics** — mixed-height multi-matrix commit (one tree over
   traces of differing lengths) must be matched by the GPU Merkle builder.
4. Inline barycentric interp / final IDFT are not trait-reachable; if they surface
   as the next bottleneck, a small p3-fri patch is needed (fork already in hand).

## Sources

- ICICLE repo & releases: https://github.com/ingonyama-zk/icicle ,
  https://github.com/ingonyama-zk/icicle/releases (v3.7 Goldilocks, v3.8 FRI Rust
  wrappers + Merkle, v3.9 Goldilocks-Ext + FRI-with-Poseidon, v4.0).
- GPU hash list (Blake3 present): https://dev.ingonyama.com/api/cpp/hash ,
  https://dev.ingonyama.com/icicle/primitives/hash
- AIR-ICICLE (Plonky3 integration, "no backend prover"):
  https://www.ingonyama.com/post/air-icicle-plonky3-on-icicle-part-1 ,
  https://hackmd.io/@Ingonyama/air-icicle
- CUDA ≥12.0 / CMake ≥3.18: ICICLE README + install docs.
- Trait seam (Plonky3 rev e9d75614): `fri/src/two_adic_pcs.rs:136,313,321,340,531`,
  `fri/src/prover.rs` (`commit_phase` `params.mmcs.commit_matrix`, `answer_query`
  `config.mmcs.open_batch`), `fri/src/config.rs:49` (`FriFoldingStrategy`).
- Config under test: multi-stark `src/types.rs` (`GoldilocksBlake3Config`,
  `MerkleTreeMmcs<…Blake3…,2,32>`, `Radix2DitParallel`, `TwoAdicFriPcs`).
