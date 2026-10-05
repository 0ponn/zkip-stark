# Session handoff, 2026-10-05

Follows `2026-10-04-session-handoff-2.md`.

## State

| repo | branch | head |
|---|---|---|
| zkip-stark | main | 9987cba |
| 0ponn/ix | zk | 441fce5 (unchanged) |
| 0ponn/multi-stark | zk-hiding-pcs | 2788bff (unchanged) |
| 0ponn/open-dissolve-site (0pon.com) | main | includes #48, #49, #51 |

Everything is merged; no bench branches remain. CI is green.

## Shipped this session

- **M12, label-keyed tree (#20).** A 32-level sparse Merkle tree keyed by
  label, so a root holds one value per label (the gap a ZK Hack reviewer
  found). The circuit pins the depth with a level counter. Self-review caught
  that `2^levels == 2^32` wraps in Goldilocks (2^224 = 2^32); gpt-5.4 missed
  it.
- **M13, long-running server (#21).** One process, one connection at a
  time, 127.0.0.1 by default, `ZKIP_API_KEY` bearer on generate and batch,
  request limits, `scripts/serve.sh` (4 threads). The container runs as a
  non-root user with only the binary.
- **M14, smaller proofs (#22).** 9.9 MB to 3.0 MB, verify about 12 ms.
  Unused circuits are pruned (27% of the columns), and the parameters are now
  blowup 8, 38 queries, 16-bit query PoW (130 conjectured bits). The proven
  bound fell from about 100 to about 73 bits; the review packet asks a
  reviewer to check that first.
- **0pon.com/proof is live.** A plain page asking three written questions
  (the operator does not want to offer calls). Getting it live needed
  open-dissolve-site #48: TanStack Start 1.168, because Vercel had blocked
  every deploy since 2026-09-30 as vulnerable. 0pon.com deploys from
  open-dissolve-site, not the stale 0ponn/0pon repo.

## Outreach (details in engram, not here: the repo is public)

- Plonky3 Telegram (the factor of 2), ZK Hack #discussions (masks,
  completeness), and multi-stark #89 are all waiting on replies.
- Procurement discovery has started: a LinkedIn post plus four connection
  notes to US GRC and third-party-risk people. Drafts are in
  `/home/mlayug/Documents/0pon/zkip-stark-outreach/procurement-vendors.md`.

## Next

1. Read the replies against the three questions. Question 3 (who must vouch
   for the number) decides whether roots need auditor signing.
2. Around 2026-10-11, ping the multi-stark #89 maintainers if it is still
   quiet (the draft needs operator approval).
3. Only if demand shows: recursion to get to kilobyte-sized proofs (weeks).

## Risks

- The proven security bound (about 73 bits) needs a cryptographer's sign-off.
- Trace-shape calibration is empirical with 1/8 headroom; a miss refuses a
  proof (completeness), it never leaks.
- open-dissolve-site carries a fragile build (Lovable config, Cloudflare
  plugin, unenv `process` swap); the absolute `build.outDir` is load-bearing.
