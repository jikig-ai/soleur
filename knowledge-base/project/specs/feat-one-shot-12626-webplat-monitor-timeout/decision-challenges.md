---
branch: feat-one-shot-12626-webplat-monitor-timeout
issue: 12626
plan: knowledge-base/project/plans/2026-11-11-fix-webplat-monitor-timeout-plan.md
created: 2026-11-11
---

# Decision Challenges — feat-one-shot-12626-webplat-monitor-timeout

Headless run note: this session runs inside the Devin subagent harness where
the planning seat could not nest a CTO spawn, so every **technical** row below
was written `pending - assumed: <default>` and then ruled by a parent-spawned
batched `soleur:engineering:cto` consult on 2026-11-11 (one spawn, all rows).
Rows marked `mechanical` were auto-applied by the plan-review consolidation.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Fix arm: dedicated `test-webplat-mutations` job + `VITEST_SHARD` gate (arm B) vs. raise step timeout only (arm A) vs. `--rows` split in the vitest arm (arm C) vs. pin-to-one-leg + raise (arm D) | technical | Ruled by CTO agent, 2026-11-11: confirm arm B (dedicated `test-webplat-mutations` job + `VITEST_SHARD`-unset gate in the webplat arm) - arm A already shipped once (#12279, ci.yml:1551 25→35) and went stale in ~4 days; the workflow's own comment at ci.yml:1548–1550 names "give them their own job" as the flip trigger and the batteries running in FULL on BOTH shards is the structural defect; arm C pulls a `--rows` tiling contract into the vitest arm for machinery this battery does not implement today; arm D keeps battery+vitest conflated on one leg and is strictly worse. |
| Whole-battery-per-leg now vs. `--rows` row-split of `approval-guard1-mutation` in the same slice | technical | Ruled by CTO agent, 2026-11-11: confirm whole-battery-per-leg, `--rows` deferred to the named follow-up - a 3-leg per-battery matrix bounds each battery on its own leg (~25 min nominal / WALL_BUDGET_S=3000 advisory vs a derived ~45-min step); approval-guard1-mutation.test.sh supports only `[--only <ERE>] [--list] [--check-anchors]`, so the lever needs a new `--rows` arm PLUS the shard-totality contiguous-tiling/`-<letter>`/totality-pin contract — correctly out of this diff. |
| Scope of the move: all three webplat batteries vs. only `approval-guard1-mutation` (the observed outlier) | technical | Ruled by CTO agent, 2026-11-11: confirm all three - all three are unconditional `run_suite` sites in the same arm (test-all.sh:7387/7391/7395) paying the same duplicated-leg cost (destroy-ask's own advisory is WALL_BUDGET_S=900); a 3-row `matrix.battery` is the identical job shape as a 1-row, and moving only the current outlier leaves two unbounded duplicated batteries on the same edge plus an asymmetric registration contract. |
| Apply the dedicated job in `ci.yml` as well as `main-health-monitor.yml` | technical | Ruled by CTO agent, 2026-11-11: confirm both workflows - the duplication is byte-identical in ci.yml's `test-webplat` legs (its own comment documents the same edge) so monitor-only leaves every PR/merge_group paying 2× battery cost; the new job MUST join `test`'s `needs:` (keeps battery failures merge-blocking) and is classified into the mandatory push-dedupe/draft-light gated sets and the oracle lane-skippable set in the same lockstep `test-webplat` carries. |
| Step/job ceiling values for the new legs (plan assumes step 45 / job 60 monitor, step 45 / job 45–50 ci, per `roundup5(measured_max × 1.5)`) | technical | Ruled by CTO agent, 2026-11-11: confirm `roundup5(measured_max × 1.5)` — monitor step 45 / job 60 as planned; ci.yml leg uses the copied shard-totality job-level-only ceiling (~45–50), no step ceiling - the rule matches the file's own derivations (monitor webplat 17.2×1.5→30, `test-scripts-heavy` declared-budget 2500000ms×1.5→65); 60 satisfies the guard's enforced job ≥ step+15 floor; `measured_max` re-derives at implementation from leg `elapsed_s` + the battery's ~25-min header estimate, with the derivation comment naming the figure. |
| Brand-survival threshold `none` | taste | Ruled by CTO agent, 2026-11-11: confirm `none` - internal CI topology only; the worst case is degraded internal signal (a miswired gate silently dropping mutation coverage, or a still-red monitor), not user-visible behavior — and the leg-census + gate-pair guards exist precisely to make the silent-drop case loud. |
| Guard extension: extend `main-health-monitor-workflow.test.sh` for leg census vs. new sibling test for battery-gate coverage | technical | Ruled by CTO agent, 2026-11-11: extend both existing guards, no new sibling file - leg census/margin/envelope goes in `main-health-monitor-workflow.test.sh` where the `LEG_JOBS` tuple (line 116) is the single-point extension propagating to filer-OR, closer-AND, needs-decl, lockstep-count, ceiling-arithmetic and EXPECTED_LEGS assertions; the `VITEST_SHARD` `run_suite`/`skip_suite` pair assertions belong in `scripts/test-all-webplat-gate.test.sh`, which already owns the `want_webplat`-block extraction and the `mutate()` harness the Guard Contract's 4-row mutation matrix needs. |

## Standing Panel / Plan-Review Resolution Log (2026-11-11, sequential-fallback)

Panel executed inline (roles: dhh-rails-reviewer, kieran-rails-reviewer,
code-simplicity-reviewer, cto-devex) — `Reviewed-Coverage: sequential-fallback`.

| Finding | Lens | Class | Resolution |
|---------|------|-------|------------|
| `grep -c 'test-webplat-mutations' = "4"` discoverability probe brittle (count drifts with comment/needs occurrences) | dhh + code-simplicity | mechanical | auto-applied — probe switched to `grep -n` + substring `expected_output` |
| Direct battery invocation must copy `shard-totality-mutations` shape verbatim incl. exit-code → step-failure propagation and `elapsed_s`/leg-report emission | kieran | mechanical | auto-applied — citation tightened in Proposed Solution item 2 |
| AC-5 depended on ambient scheduled run (`cq-ac-must-not-depend-on-concurrent-sessions`) | kieran (standing check) | mechanical | auto-applied — re-expressed against `workflow_dispatch`-controlled run with deterministic core noted |
| New matrix legs report as `test-webplat-mutations (battery)` — required-check/ruleset + `required-checks-merge-group-coverage.test.sh` sync needed if ruleset pins leg names | cto | mechanical | auto-applied — added to Dependencies & Risks |
| "Just raise the timeout" — arm-B-vs-arm-A is a real fork, not a mechanical simplification | dhh | routed | technical fork routed to Decision Classes row 1 (CTO) — not silently applied |
