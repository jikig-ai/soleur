---
title: "Shard re-price checkpoint: measured-arm medians via --timings-dir + incumbent-preserving --durations seed"
date: 2026-10-31
category: workflow-patterns
tags: [ci, test-scripts, sharding, regenerate-shard-manifest, suite-timings, merge-queue]
related: [knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md, scripts/regenerate-shard-manifest.py]
---

## Problem

Post-merge of the Lever-A arm-sharding slice (epic #11556, merge `8598aae15e`),
the 7 `--rows` arm labels in `scripts/suite-durations.tsv` held CI-median x
local-share *estimates*. The runbook's ownership checkpoint required a re-price
from real CI timings once green artifact runs existed.

## Solution

1. Download `suite-timings-scripts-*` per green PR/merge_group run
   (`gh run download <id> -p 'suite-timings-scripts-*' -D <dir>` — `-p` is glob,
   `-n` is exact-name and matches nothing; `-p` also fetches the 3 heavy-leg
   artifacts, count light legs only).
2. Emit the fully-measured table via
   `--timings-dir <dir>... --manifest <scratch> --write` (redirected — committed
   files untouched).
3. Seed = committed table with ONLY the arm rows' ms replaced by measured
   medians; commit via `--durations seed.tsv --write`. A full
   `--timings-dir --write` reds `test-all-fast-tier-budget` on the always-on
   drift #11648 tracks — the merge commit itself used the seed mechanism.
4. Verify: 5-suite lint set (shard-manifest, regen, totality,
   runtime-coverage, fast-tier-budget) all green; arms on distinct legs;
   non-arm measured rows byte-identical.

## Key Insight

- `--runs N` can never price arm rows: it samples successful main `push` runs,
  and `push-dedupe` elides the `test-scripts` shards job there — no
  `suite-timings` artifacts exist on main pushes. Only merge_group/pull_request
  runs carry them (the plan-level CTO ruling, and runbook note, both say so).
- Seeded prices can be badly wrong in both directions: replay-a seeded 635 s
  measured 1033 s; affected-b 913 s -> 502 s. Observed post-split worst legs
  ran 33.7-36.8 min suite-time (vs the ~28-min bound and the 43-51 min
  baseline) — the residual gap is incumbent-price staleness, not arm packing.

## Session Errors

- **Runbook numbers written from memory, not recomputation** — Recovery: two
  P2s (floor-row count "97 incumbent (1200->1222)" vs actual 94 incumbent with
  2 moving; per-run ranges where AC-4 required per-run values) + two P3s
  ("24 re-seated" vs 21+3; "exactly 8 leg files" vs 11 incl. heavy) fixed
  inline by recomputing from the artifacts. Prevention: every count in a
  Measured-history entry recompute from the artifact dir or `git diff`
  directly before writing — same class as "counts carried from earlier
  narrative" findings in prior learnings.
- **Review seat globbed heavy-leg artifacts into a light-leg spread** —
  Recovery: disputed-with-evidence (heavy-leg3 = 1.3 min explains the
  out-of-band figure; light-only spread 16.1 min corroborated by the 20.5-min
  wall floor). Prevention: when disputing a per-leg figure, reproduce the
  seat's glob before accepting — `suite-timings-*/` matches heavy dirs too.
- **Commit trailers used `(Ref epic 11556)` vs `(Ref #NNNNN)` convention** —
  Recovery: noted, not fixed (rewriting pushed SHAs would invalidate the
  fix-round base; squash subject carries the convention). Prevention:
  `(Ref #N)` in commit messages from the first commit.
- **Transient infra flakes** — `draft-pr` TLS handshake timeout (push still
  landed; PR creation deferred to ship); one subagent spawn rate-limited
  (retried after the 2-min window). Recovery: retry/continue, no prevention —
  environmental.
