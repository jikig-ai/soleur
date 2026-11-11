---
branch: feat-one-shot-12626-webplat-monitor-timeout
issue: 12626
plan: knowledge-base/project/plans/2026-11-11-fix-webplat-monitor-timeout-plan.md
created: 2026-11-11
---

# Decision Challenges — feat-one-shot-12626-webplat-monitor-timeout

Headless run note: this session runs inside the Devin subagent harness where
nested Task spawns are unavailable, so no `soleur:engineering:cto` ruling could
be obtained. Per `technical-ruling-delegation.md` / `hr-technical-fork-is-not-an-operator-question`,
every **technical** row below is `pending - assumed: <default>` and needs a CTO
ruling (or parent-agent escalation) before implementation locks the shape. Rows
marked `mechanical` were auto-applied by the plan-review consolidation.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Fix arm: dedicated `test-webplat-mutations` job + `VITEST_SHARD` gate (arm B) vs. raise step timeout only (arm A) vs. `--rows` split in the vitest arm (arm C) vs. pin-to-one-leg + raise (arm D) | technical | **pending - assumed: arm B** (dedicated job + gate). Rationale recorded in plan `## Alternative Approaches Considered`; arm A masks duplication and re-opens the edge on the next row expansion. CTO may legitimately prefer arm A as a minimal-diff hotfix with B as follow-up — if so, the gate/job work below descopes. |
| Whole-battery-per-leg now vs. `--rows` row-split of `approval-guard1-mutation` in the same slice | technical | **pending - assumed: whole-per-leg, `--rows` deferred**. Current ~343 rows / ~25–30 min nominal fit under a derived ~45-min step ceiling; the split pulls the shard-totality `-<letter>` + manifest contract into the diff. |
| Scope of the move: all three webplat batteries vs. only `approval-guard1-mutation` (the observed outlier) | technical | **pending - assumed: all three** (uniform mechanism; `destroy-ask-mutation` is also duplicated leg cost; a 3-row matrix is the same shape as 1-row). A minimal-diff ruling could trim to guard1 only. |
| Apply the dedicated job in `ci.yml` as well as `main-health-monitor.yml` | technical | **pending - assumed: both**. The duplication exists identically in PR legs and `ci.yml`'s own flip-trigger comment names the same fix; monitor-only would leave PR legs on the same edge. |
| Step/job ceiling values for the new legs (plan assumes step 45 / job 60 monitor, step 45 / job 45–50 ci, per `roundup5(measured_max × 1.5)`) | technical | **pending - assumed: as planned**. The derivation rule is the repo's own convention (measured max × 1.5 → round up to 5); the numbers re-derive at implementation from current leg-report `elapsed_s` data. |
| Brand-survival threshold `none` | taste | **pending - assumed: none**. Internal CI topology only; challengeable per the User-Brand Impact section's own note. Single-signal classification — escalate if a reviewer judges monitor red-as-user-visible (e.g. shield/flair surfaces). |
| Guard extension: extend `main-health-monitor-workflow.test.sh` for leg census vs. new sibling test for battery-gate coverage | technical | **pending - assumed: extend existing guard + add gate assertions where the repo's guard conventions place them** (implementation review picks the file; Guard Contract in plan names the property and mutation matrix). |

## Standing Panel / Plan-Review Resolution Log (2026-11-11, sequential-fallback)

Panel executed inline (roles: dhh-rails-reviewer, kieran-rails-reviewer,
code-simplicity-reviewer, cto-devex) — `Reviewed-Coverage: sequential-fallback`.

| Finding | Lens | Class | Resolution |
|---------|------|-------|------------|
| `grep -c 'test-webplat-mutations' = "4"` discoverability probe brittle (count drifts with comment/needs occurrences) | dhh + code-simplicity | mechanical | auto-applied — probe switched to `grep -n` + substring `expected_output` |
| Direct battery invocation must copy `shard-totality-mutations` shape verbatim incl. exit-code → step-failure propagation and `elapsed_s`/leg-report emission | kieran | mechanical | auto-applied — citation tightened in Proposed Solution item 2 |
| AC-5 depended on ambient scheduled run (`cq-ac-must-not-depend-on-concurrent-sessions`) | kieran (standing check) | mechanical | auto-applied — re-expressed against `workflow_dispatch`-controlled run with deterministic core noted |
| New matrix legs report as `test-webplat-mutations (battery)` — required-check/ruleset + `required-checks-merge-group-coverage.test.sh` sync needed if ruleset pins leg names | cto | mechanical | auto-applied — added to Dependencies & Risks |
| "Just raise the timeout" — arm-B-vs-arm-A is a real fork, not a mechanical simplification | dhh | technical | routed to Decision Classes row 1 (CTO) — not silently applied |
