---
title: "Adding a CI leg means mirroring every test-webplat-naming surface — the guards make a miss loud, so grep first and mirror all of them"
date: 2026-11-11
category: best-practices
module: ci.yml / main-health-monitor.yml leg wiring
tags: [ci-leg, lockstep-surfaces, aggregator, push-dedupe, draft-light, oracle-lane, ceiling-derivation, expected-legs]
issues: ["#12626", "#12279", "#12262"]
pr: "#12654"
---

# Learning: adding a CI leg means mirroring every `test-webplat`-naming surface — the guards make a miss loud, so grep first and mirror all of them

## Problem

PR #12654 split the three web-platform mutation batteries off the `test-webplat` shards onto a dedicated `test-webplat-mutations` leg (issue #12626). The change is conceptually one job, but this repo pins CI leg membership in roughly ten lockstep surfaces, each guarded — a miss does not stay silent, it fails a guard somewhere downstream, which turns "add a job" into "find every pinned census and update it in the same diff".

## Solution

The surfaces the diff had to touch, as a checklist for the next leg addition:

1. **`ci.yml` aggregator (`test` job):** `needs:` entry, the `env:`/`entries:` wiring that maps each leg's result into the aggregate verdict, and the job-name `oracle_re` grammar — the `test` aggregate's NAME and EXISTENCE are load-bearing for branch-protection ruleset 14145388, so the leg joins `needs:` rather than the ruleset (per the CTO ruling: `ruleset-ci-required.tf` pins only `test`; no Terraform/ruleset edit needed for a new member leg).
2. **`scripts/ci-push-dedupe.test.sh`:** GATED / DL / OR pinned sets and the aggregate-digest pin — the 7-leg proof had to be re-derived and `AGG_DIGEST` re-pinned.
3. **`scripts/ci-draft-light.test.sh`:** the HEAVY/OR/LEGS five-family census counts every leg.
4. **`scripts/ci-oracle-lane.sh` + `scripts/ci-oracle-lane.test.sh`:** the six-leg grammar and `SKIP_SET`; the diagrams carve-out keeps both web-platform legs.
5. **`main-health-monitor.yml` + `plugins/soleur/test/main-health-monitor-workflow.test.sh`:** `LEG_JOBS`, `EXPECTED_LEGS` (15→18), the `R_*` env the filer reads, and the filer/closer arms — plus, for a leg that bypasses the runner, a verdict-token shim (see `2026-11-11-a-completed-but-failing-leg-filed-as-did-not-complete.md`).
6. **`plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`:** the `MUTATIONS_RESULT` fixture row and the assertion floors (147→152 / 156).
7. **`plugins/soleur/test/terraform-target-parity.test.ts`:** the needs-line fixture.
8. **`ci.yml` leg-shape comments:** the census comment enumerating the leg family ("single legs" / "each leg invokes test-all.sh") — two of its claims went false the moment the leg landed; correct them in the same diff.
9. **`scripts/test-all.sh` registrations:** the three batteries' unconditional `run_suite` calls became `VITEST_SHARD`-unset-gated `skip_suite` declines (reason `test-webplat-mutations`), verified via `--enumerate-commands` printing `SUITE_COMMAND_DECLINED` on shards 1-2.

Ceiling derivation rule in use: `timeout-minutes` = `roundup5(measured_max × 1.5)`; the monitor job ceiling has a guard-enforced floor of step ceiling + 15 min.

## Key Insight

The playbook is mechanical: `git grep -n 'test-webplat'` across `.github/workflows/`, `scripts/`, and `plugins/soleur/test/` enumerates every naming surface; each hit is either a pinned set that needs the new member or a comment census that needs the new census. The guards (push-dedupe, draft-light, oracle-lane, aggregator-diagnosis floors, terraform-parity) are what make the checklist complete — run them after mirroring, and a missed surface fails loudly rather than silently drifting.

The deeper lesson is WHY dedicated legs beat ceiling raises for growing workloads: raising `ci.yml` `test-webplat` 25→35 (#12279) went stale in ~4 days because the battery growth rate outran it — a fixed ceiling on a growing leg is a race you keep re-entering. A dedicated leg with a ceiling DERIVED from the measured max (`roundup5(measured × 1.5)`, re-derived when the battery set changes) bounds the growth instead of racing it. Prior art: `2026-11-07-a-required-shard-on-its-timeout-edge-made-the-merge-queue-a-coin-flip.md` (#12262 — a required shard straddling its timeout made merges a coin flip).

Cost note recorded for the next leg designer: `test-webplat-mutations` carries no applicability classifier, so it pays ~3×25-30 leg-min even on KB-only PRs (the `shard-totality-mutations` job does skip on markdown-only diffs via `ci-shard-totality-classify.sh`). A named follow-up in the #9729 class — cost, not correctness.

## Session Errors

The shared session-error inventory lives in `2026-11-11-a-completed-but-failing-leg-filed-as-did-not-complete.md` (items 1-6). Errors specific to this surface-mirroring work:

1. **The `ci.yml:1516` leg-shape comment carried two claims the diff itself falsified** ("single legs" census, "each leg invokes test-all.sh") and shipped until the P3 review round. Recovery: corrected in the fix-round commit. **Prevention:** when a diff adds a leg, re-read the workflow's own census comments — the diff is the thing that makes them stale.

## Tags
category: best-practices
module: ci.yml / main-health-monitor.yml leg wiring
