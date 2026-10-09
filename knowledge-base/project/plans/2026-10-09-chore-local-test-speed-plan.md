---
title: "chore: get local test runs under the fast-feedback budget and align the suite with the test pyramid"
date: 2026-10-09
slug: chore-local-test-speed
branch: feat-one-shot-9763-local-test-speed
issue: 9763
closes: 9763
type: chore
lane: engineering
---

## Enhancement Summary

**Deepened on:** 2026-10-09
**Mode:** inline deepen (no Task/Workflow spawn in this harness — passes executed inline by the orchestrator)
**Owner decisions already taken (from the /go kickoff):** proposals 1 and 3 are authorized — split cheap local ratchets from CI-gated mutation batteries, and demote `ship` Phase 4's local battery to the fast tier while CI remains the complete merge gate.

### Key Decisions (deepen pass)

1. Split axis: `ALWAYS_ON_SUITES` is split at the **10 s committed-weight line** (suite-durations.tsv measured weights): 126 cheap ratchets (≈198 s total) stay always-on; 29 heavier suites (≈1100 s) move to a `CI_HEAVY_SUITES` list that `--affected` skips unless the diff touches the suite or its declared consumed edges. CI legs (TEST_GROUP shards, merge_group, push) are untouched — they already run everything.
2. Proposal 3 collapses into the same change: after the split, `ship` Phase 4's `test-all.sh --affected` **is** the fast tier; the demotion is documented in ship/SKILL.md and battery-owed text, not a new mode.
3. Proposal 4 lands as a deterministic lint, not a wall-clock gate: a sub-second always-on suite asserts Σ(committed weights of ALWAYS_ON_SUITES) ≤ 300 s AND every always-on suite ≤ 10 s — the ratchet that keeps the fast tier fast, without timing flakiness.
4. Proposal 2 (result caching keyed by consumed-file hashes): **rejected** — staleness semantics (consumed-edge drift, ambient env) plus a new cache-invalidation class buys ~2 min on a tier that is already ≤ ~4 min post-split; the complexity-to-saving ratio is poor. Recorded as a decision on the issue.
5. The 20-slowest-suites table comes from `scripts/suite-durations.tsv` (committed measured weights), refreshed once by a real `--affected` run on this (now idle) machine during implementation for the before/after evidence.

### New Considerations Discovered

- `AFFECTED_CONSUMED_EDGES` already implements the ADR-262 shape (`label|ARRAY_NAME`) — the 29 moved suites get edge declarations via `scripts/lib/test-relevance-paths.sh` where a subject exists, and fall back to "own-file + CI" where the suite is meta (e.g., `test-contention` has no narrower subject than the runner itself).
- `test-all.sh`'s affected epilogue prints decline reasons — the new decline class needs a `[skip] (ci-tier)` line so a skipped heavy suite reads as tiered, not lost.
- `fanout-suite-scope.test.sh` + `fullsuite-merge-gate.test.ts` pin the `--affected`/`--full` dispatch flags — they must stay byte-identical; only selection internals change.
- `guard-vacuity-floor` (33 s, always-on) derives its population from suite shape — removing suites from ALWAYS_ON doesn't break it, but its own weight keeps it above the cap → it moves to CI tier too (its derived-population semantics are unaffected by which list a suite sits on).
- `lint-skill-body-budget` bit on #9762 at 362 KB — work/SKILL.md headroom is ~9 B now; any SKILL.md text added here must be byte-frugal or move a block to references/.

## Overview

Issue #9763: local `ship` Phase 4 battery ran >25 min on PR #9751 because `--affected` always runs the full always-on ratchet set (155 labels, ≈1298 s committed weight) plus edge-selected suites. The owner's fast-feedback target is <5 min local; CI is already the complete merge gate (4-leg shard matrix + `test` aggregator on pull_request/merge_group). This PR makes the local tier actually fast by moving the 29 heaviest always-on suites to a CI-gated tier, documents the ship-time demotion, and adds a deterministic budget ratchet so the tier cannot regrow.

## Context

### Relevant Prior Work

- **ADR-262** — established the path-gating machinery (`_diff_touches --pr-gated`, `AFFECTED_CONSUMED_EDGES`, `label|ARRAY_NAME`) that withdrew four self-test mutation batteries from always-on. This PR generalizes it to a duration-based tier split.
- **#9766 (just merged)** — the test-pyramid review check; sibling issue, deliberately non-overlapping (review-time cost signals vs runner-time budgets).
- **#9323 (OPEN)** — CI-side path-gating of mutation batteries on PRs (~35 of 89 suite-minutes). Adjacent, not duplicate: that issue gates CI pull_request runs; this PR demotes *local* always-on weight. The consumed-edge declarations added here are the same mechanism that PR would extend on the CI lane.
- **#9564, #9729, #8163, #8098, #9700** — sibling test-infra issues; acknowledged, none blocks this scope.
- **battery-owed.sh** — already skips the local battery when CI verified the exact SHA; the tier split reduces what "owed" costs.

### Measured facts (issue + session)

- `AFFECTED_SUMMARY selected=220 of=583 always_on=148 edge=72` on a docs/shell diff — the always-on tail dominates.
- Committed weights (`suite-durations.tsv`): 155 always-on labels ≈ 1298 s total; 9 suites ≥30 s sum to 769 s (60% of always-on time).
- Cap math: ≤10 s → keep 126 suites ≈198 s; ≤15 s → 135 suites ≈302 s. The 10 s line is the only threshold that leaves headroom for edge-selected suites inside 300 s.
- This machine ran a full contended battery during #9762's ship (≈4.5 h with queue); the idle-machine `--affected` measurement runs during implementation.

## Functional Requirements

- **FR-1 — Tier split in the affected index.** `scripts/lib/test-affected-paths.sh`: add `CI_HEAVY_SUITES=(...)` — the 29 always-on labels whose committed weight exceeds `LOCAL_FAST_CAP_MS=10000`. The `--affected` selection skips a CI_HEAVY suite unless (a) the diff touches the suite's own file, or (b) a declared consumed edge fires. CI modes (`pull_request`, `merge_group`, `push`, `--full`) run them unconditionally as today.
- **FR-2 — Honest decline reporting.** `[skip] (ci-tier)` epilogue class in `test-all.sh` so a skipped heavy suite is visible with its reason (the suite ran in CI / on `--full`).
- **FR-3 — ship demotion documentation.** `plugins/soleur/skills/ship/SKILL.md` Phase 4 text: the local battery is the fast tier by construction (always-on = sub-10-s ratchets); heavy ratchets are CI-gated; `--full` remains the operator's complete local run. `battery-owed.sh` verdict text stays accurate.
- **FR-4 — Budget ratchet.** New sub-second always-on lint suite `scripts/test-all-fast-tier-budget` asserting: every `ALWAYS_ON_SUITES` label has committed weight ≤ 10 s, and Σ weights ≤ 300 s. Registered always-on itself (it is the guard, must be fast, and its job is to redden the PR that regresses the tier).
- **FR-5 — Measured evidence.** Before/after `--affected` timing on a docs-only diff on the idle machine + the 20-slowest table, recorded in the spec dir and on the issue.

## Acceptance Criteria

- [ ] **AC-1:** table of the 20 slowest suites (ms) from an idle-machine run attached (issue comment or spec file).
- [ ] **AC-2:** written budget: local commit-stage target (<5 min) + per-suite cap (10 s committed weight for always-on) documented.
- [ ] **AC-3:** each issue proposal dispositioned: P1 done (tier split), P2 rejected (recorded reason), P3 done (ship fast-tier documentation), P4 done (budget lint suite).
- [ ] **AC-4:** a local `--affected` run on a docs-only diff finishes inside the budget on the idle machine (measured, recorded).

## Guard Contract

### Guard 1 — fast-tier budget lint (`scripts/test-all-fast-tier-budget`)

**Property.** The local always-on tier cannot silently regrow: every `ALWAYS_ON_SUITES` label has committed weight ≤ `LOCAL_FAST_CAP_MS` (10 s) and the tier's Σ committed weight ≤ `LOCAL_FAST_TOTAL_CAP_MS` (300 s), and every suite name in either list stays registered (a heavy suite deleted from both lists reads as drift, not a pass).

**Assembly.** `ALWAYS_ON_SUITES` (≤10 s committed weight) + `CI_HEAVY_SUITES` (the 29 heavier labels) + own-file / consumed-edge fallback + `--affected` vs CI/`--full` mode predicate + this lint's census over both lists. Removing any conjunct breaks it: no split (status quo ~25 min), no edge fallback (heavy suite never runs locally when its subject changes — coverage gap), no CI arm (the merge gate silently shrinks), no budget lint (the tier regrows unnoticed). Chokepoint: `scripts/lib/test-affected-paths.sh` list membership and `test-all.sh`'s selection predicate — every local run passes through `--affected` selection.

**Mutation matrix.** Each row MUST drive the lint red (except the labelled must-PASS row); written from the design, pre-implementation:

- M1 — a >10 s suite moved back into `ALWAYS_ON_SUITES` → per-suite assertion reds.
- M2 — `LOCAL_FAST_CAP_MS` raised → the cap value pin reds.
- M3 — a label deleted from both lists → census drift assertion reds.
- M4 — the `[skip] (ci-tier)` epilogue class removed → epilogue drift pin reds.
- M5 — ship docs demoted without the list split → the 29-suite sum still violates the total cap.
- M6 — **must-PASS** — a new ≤5 s suite added to `ALWAYS_ON_SUITES` → lint stays green (the ratchet tolerates growth under the cap).

## Observability

```yaml
liveness_signal:
  what: AFFECTED_SUMMARY's always_on count + suite-durations.tsv weight column
  cadence: per local run; weights refreshed by regenerate-shard-manifest.py
  alert_target: budget lint reds when the tier regrows; epilogue shows ci-tier declines
  configured_in: scripts/lib/test-affected-paths.sh (lists), scripts/test-all.sh (selection), scripts/test-all-fast-tier-budget (guard)
error_reporting:
  destination: test-all stdout + budget-lint FAIL lines
  fail_loud: budget lint exits non-zero on tier regression
failure_modes:
  - mode: new heavy suite added to ALWAYS_ON (regrowth)
    detection: budget lint total-sum assertion
    alert_route: red always-on lint in every local run + CI
  - mode: a suite's committed weight drifts above cap (organic growth)
    detection: budget lint per-suite assertion on manifest regen
    alert_route: red lint; fix = move to CI_HEAVY or slim the suite
  - mode: heavy suite silently dropped from BOTH tiers (edit error)
    detection: registered-suite census pin in the budget lint
    alert_route: red lint
logs:
  where: test-all stdout; scripts/suite-durations.tsv
  retention: repo
discoverability_test:
  command: grep -q 'CI_HEAVY_SUITES' scripts/lib/test-affected-paths.sh && printf 'present'
  expected_output: present
```

## Test Scenarios

Each scenario names its pyramid layer (the convention #9766 landed).

- **unit** — Given the split lists and a docs-only diff, when `bash scripts/test-all.sh --print-selection` runs, then the 29 heavy labels appear as `ci_tier` declines and `always_on` count is ≤130.
- **unit** — Given `scripts/test-all-fast-tier-budget`, when it runs, then it asserts per-suite ≤10 s + total ≤300 s and exits 0 (and the M1/M2 mutation rows red).
- **integration** — Given a docs-only diff on the idle machine, when `bash scripts/test-all.sh --affected` runs, then wall-clock <300 s (the AC-4 measurement).
- **integration** — Given a diff touching `plugins/soleur/test/operator-ack-guard.test.sh`, when `--print-selection` runs, then that suite is selected despite the tier (own-file fallback arm).

## User-Brand Impact

- **Brand-survival threshold:** aggregate pattern — a mis-split could silently shrink the local checkpoint for every PR (the failure mode the ci-tier epilogue + budget lint + CI's untouched full battery collectively bound). No single-user incident path: the merge gate (CI) is unchanged.

## Deviation (Fix-Size)

Declared budget: ~250 lines / ~6 files (index lists, selection predicate, epilogue, budget suite, ship docs, spec/kb artifacts). The 29-label list move is mechanical; the risky edit is the mode predicate.

## Filing Discipline

- Deferred-scope-out issues: P2-caching rejection is a decision record, not a follow-up — no new issue. If #9323 later wants the CI_HEAVY list for CI path-gating, it consumes this list (recorded in that issue's context, no new filing).
