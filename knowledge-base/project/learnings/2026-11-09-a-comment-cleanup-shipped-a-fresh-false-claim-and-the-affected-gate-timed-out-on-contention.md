---
title: "A comment-cleanup PR shipped a fresh false claim (caught by 5 seats) and the affected gate timed out on box contention"
date: 2026-11-09
category: workflow-patterns
tags: [review-findings, ci, oracle-lane, affected-gate, contention]
branch: feat-one-shot-12375-oracle-lane-nits
pr: 12475
---

## Problem

Two incidents in the #12375 one-shot (oracle-lane post-unlock comment/test nits):

1. **A PR whose purpose was removing false lock-state comments introduced a new false claim.** The `ci-draft-light.test.sh:99` rewrite asserted "a non-`on` switch … leaves `oracle_only` true while `active` stays false" — but the driver returns at `O1-SWITCH-GATE` (`ci-oracle-lane.sh:303`) *before* classification, so a non-`on` switch emits `oracle_only=false`. The claim was copied from plan text the planner had written, never re-derived against the driver. Five of ten review seats flagged it (P2). One grep of the driver would have falsified it at write time.
2. **`gate-or-skip.sh` (`test-all.sh --affected`, 220 selected suites) hit its 2400s wrapper timeout** on a box running several sibling pipelines (load ~30): `reason=failed-before-budget` with ~100 `[UNACCOUNTED]` suites — unresolved coverage, not a pass and not a failure of the diff.

## Solution

1. Dropped the false disjunct (env re-lock is the only `oracle_only=true ∧ active=false` state) and swept every carrier of the same claim — including the plan/tasks docs that propagated it. The seat fix-round verified all ten findings FIXED (VERDICT: CLEAN) and the battery re-ran green (5043 rows, 33/33 mutants; `MIN_ROWS` re-derived).
2. On gate timeout, ran the four suites that pin the changed surfaces directly (`ci-oracle-lane`, `ci-draft-light`, `ci-push-dedupe`, `c4-likec4-version-pin`) — all green — and reported the remaining affected set as unresolved rather than as coverage.

## Key Insight

- **A cleanup PR that rewrites claims about a gate is itself a claim-writer**: prose the diff adds about a mechanism's semantics needs the same falsify-it-with-one-command treatment as code. Plan text is not evidence — it is a draft claim awaiting its own verification.
- **`failed-before-budget` is unresolved coverage, never a pass and never "the diff broke something"**: the honest fallback is to name the suites that pin the changed surfaces and run them directly, reporting the rest as unmeasured.
- Sweep-value selection in a discrimination sweep must include the prefix class: `{0,true,on}` pins `-n`-loosening but not `=~ ^1`; `10` closes it for one loop iteration.

## Tags

review, ci, mutation-battery, oracle-lane, affected-gate
