---
title: CI #3672 follow-ups bundle (#3692 + #3693)
date: 2026-05-12
status: draft
related_issues: [3692, 3693]
deferred_issues: [3694]
related_pr: 3709
parent_pr: 3672
lane: single-domain
brand_survival_threshold: internal-only
---

# CI #3672 follow-ups bundle

## Problem Statement

Three open follow-ups from PR #3672 (merged 2026-05-12) have differing ship-readiness gates:

- **#3692** — Bun FPE-class re-evaluation probe. No gate; informational. `.bun-version` currently 1.3.11 (6 patches past FPE-1.3.5 baseline).
- **#3693** — Suite-internal split of `apps/web-platform/test/`. Trigger condition (test-webplat >100s sustained) has no post-#3672 data yet; user has chosen to apply preemptively.
- **#3694** — `e2e` job synthetic-aggregator shard. Hard gate: ≥1 week post-#3672 stability. **Cannot be met today.** Excluded from this bundle.

## Goals

1. Ship **#3692** as a bun-version probe with explicit revert protocol.
2. Ship **#3693** webplat sub-directory split alongside the probe in the same PR.
3. Keep each as a **separate commit** in the branch so reverts are surgical.
4. Honor #3694's explicit deferral; track its re-evaluation date (2026-05-19 earliest).

## Non-Goals

- **NOT** shipping #3694 in this PR (gate unmet).
- **NOT** introducing `bun test --max-pool-size` or any in-process parallelism — that is a downstream re-evaluation only unlocked if #3692's probe shows FPE-class is gone.
- **NOT** changing the synthetic-aggregator pattern itself; only applying its outputs (test-webplat sub-suites become finer-grained, e2e shard remains for follow-up).
- **NOT** modifying `apps/telegram-bridge` or `plugins/soleur` test runners.

## Functional Requirements

- **FR1** — Bump `.bun-version` to latest 1.3.x patch on this branch.
- **FR2** — Run `bun test test/` and `bun test plugins/soleur/` on the probe branch and record SIGFPE-class outcome (fires / does-not-fire) in `knowledge-base/project/learnings/`.
- **FR3** — If FPE-class still fires, revert `.bun-version` in the same PR to the last known-good patch and record the failing patch.
- **FR4** — Split `apps/web-platform/test/` (currently 20 `.test.ts` files at the top level) into cohesive sub-directories. Sub-directory shape is plan-time decision based on file cohesion.
- **FR5** — Update `scripts/test-all.sh` line 37 (`run_suite "apps/web-platform" bun test apps/web-platform/`) to one `run_suite` per sub-directory.
- **FR6** — All existing tests pass post-split; no test removed, renamed, or skipped.
- **FR7** — Cross-link this PR back to issues #3692 and #3693 via `Closes #3692` + `Closes #3693` in body.
- **FR8** — #3694 remains open with a comment noting its re-evaluation date (2026-05-19 earliest).

## Technical Requirements

- **TR1** — Two commits, in order: (1) bun probe + revert decision, (2) webplat split + `test-all.sh` update.
- **TR2** — Synthetic-aggregator job in `.github/workflows/` continues to satisfy ruleset 14145388's required-context for `test` (no aggregator-name changes).
- **TR3** — `scripts/test-all.sh` `run_suite` per sub-directory must use `bun test <path>` form (matches existing pattern); do not switch to a glob.
- **TR4** — If FPE-class fires in the probe, the probe finding is recorded in a learnings file with the failing patch identified so the next minor-version probe has prior art.

## Acceptance Criteria

- [ ] Probe finding recorded in learnings, regardless of outcome.
- [ ] `bun test test/` and `bun test plugins/soleur/` exit 0 in CI.
- [ ] `scripts/test-all.sh` `run_suite` per sub-suite all green.
- [ ] No change to the `test` aggregator job name (ruleset 14145388 still satisfied).
- [ ] #3692 + #3693 closed by merge; #3694 left open with a comment noting earliest re-evaluation date.

## Deferred Work

- **#3694 (e2e shard)** — re-evaluate ≥2026-05-19 once #3672 has ≥1 week of post-merge stability. Open as its own PR at that time.
- **Bun `--max-pool-size`** — only re-evaluate if #3692's probe shows FPE-class no longer fires in 1.3.11+.
