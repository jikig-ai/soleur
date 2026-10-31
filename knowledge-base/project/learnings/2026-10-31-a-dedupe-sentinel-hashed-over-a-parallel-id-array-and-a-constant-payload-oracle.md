---
synced_to: [soleur:review]
---

# Learning: a dedupe sentinel whose identity lives in a parallel array can silently desync — and a constant-payload oracle cannot catch the swap it exists for

## Problem

The #11564 shard-balance watch dedupes its tracker comments with a sentinel
(`<!-- shard-balance-watch:v1 drift=<sha1> -->`) hashed over flag *identity* so a
persistent drift episode updates one tracker issue instead of filing weekly. The
first implementation kept that identity in a **parallel** `flag_ids` array built
next to `findings` — two writes per finding, free to desync from what the posted
comment actually reports. Two further defects sat in the same mechanism: the
dedupe capture scanned the issue body for a bare `drift=<40hex>`, so any earlier
bot-authored `drift=` string could shadow the sentinel's own hash; and the
watcher's "did this run carry artifacts?" check used a hand-rolled `find -path`
predicate that did not match the generator's canonical `ANY_ARTIFACT` name set —
a non-digit suffix (`suite-timings-scripts-x`) counted here but could never reach
the measurement. The original test oracle also mutated a **constant** payload
(`drift=000...1`), so a membership swap — the one change dedupe exists to catch —
was never exercised.

## Solution

Fix-round on PR #11728 (commit `6bbd5db520`): derive sentinel ids from the
`findings` array at hash time — the first ` committed=`/` max=` marker terminates
the identity fields — so the identity cannot desync from the reported set because
it *is* the reported set. Anchor the dedupe capture on the sentinel marker itself
(`capture($p + "(?<h>[0-9a-f]{40})")`). Replace the divergent artifact check with
`ARTIFACT_NAME_RE`, written at the site as a PINNED COPY of the generator's
`ANY_ARTIFACT` union minus the unreachable infra family, with the lockstep
obligation stated in the comment. Tests gained a computed-vs-computed arm (S16:
`sentinel_B` must differ from `sentinel_A` on a membership swap — both oracles
computed, neither constant), a sentinel-shadowing fixture (S17), and a
non-digit-suffix zero-row case (S18).

## Key Insight

Three faces of one defect: a value stored **parallel** to the thing it describes
(identity array vs findings), a pattern read **unanchored** from attacker-adjacent
text (bare `drift=` in a body the tracker itself edits), and a predicate
**copied** across languages held together by nothing (bash watcher vs python
generator). The repair pattern is uniform: derive from the source of truth, anchor
to the self-identifying marker, and where a copy is unavoidable, name it a pinned
copy and pin it with a test — a comment-only pin asserts the lockstep, it does not
enforce it. And a dedupe oracle tested only by mutating a constant is vacuous
against exactly the mutation it exists to catch; mutation arms must be
computed-vs-computed.

## Session Errors

1. **collision-precheck.sh exited 10 on open PR #11728 during plan** — Recovery:
   inspected; the PR is this pipeline's own auto-created draft on the same branch,
   a benign self-collision — Prevention: when a precheck flags an open PR on a
   one-shot branch, check `headRefName` against the current branch before
   treating it as foreign work.
2. **Review fan-out degraded to sequential-fallback (11 seats inline)** —
   Recovery: ran all seats inline and disclosed via `Reviewed-Coverage:
   sequential-fallback` on every deliverable — Prevention: already covered by
   `emit-review-trailer.sh --mode sequential-fallback` and learning
   `2026-10-29-running-review-seats-as-headless-devin-subprocesses.md`.
3. **Sentinel identity tracked in a parallel `flag_ids` array** — Recovery: derive
   ids from `findings` at hash time; S16 computed-vs-computed arm — Prevention:
   never carry a second array asserting what a first array contains; derive, and
   make the oracle's two arms computed values, not one computed vs one literal.
4. **Unanchored `drift=<40hex>` body scan could shadow the sentinel** — Recovery:
   anchor capture on the `<!-- shard-balance-watch:v1 ` marker; S17 fixture —
   Prevention: when extracting a self-written marker from a mutable document,
   capture relative to the marker, not to the payload shape.

## Tags

category: workflow-patterns
module: scripts/watch-shard-balance-11564.sh, scripts/regenerate-shard-manifest.py (CI drift-watch tooling)
related: 2026-10-26-posture-sentinel-must-track-the-diff-that-changes-the-posture.md, 2026-08-09-my-tests-pinned-a-constant-by-indexing-it-and-my-mutants-read-as-survivors.md, 2026-10-29-running-review-seats-as-headless-devin-subprocesses.md
issue: '#11564'
