# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-08-ci-s4-replay-norun-cause-hardening-plan.md
- Status: complete (plan + deepen run inline, sequential-fallback — no Task/Skill-tool subagents in this harness)

### Errors
None

### Decisions
- Cause already established 2026-11-07 (issue comment): H4 — `?head_sha=` search-backed listing dropped ~30% of existing runs at collect time; receipt re-derived this session, not trusted from the comment.
- Fix arm per the plan's decision rule: re-read through the true run — `ci_runs` retries once then corroborates via commit-keyed check-runs before any `no-run`.
- Evidence re-run on a fresh window (last 300 first-parent commits of origin/main); criteria b/c/d stay `unmeasured` — re-ruling is operator-reserved.
- Harness: sequential-fallback throughout (plan research fan-out, plan review seats, deepen agents, review seats, CTO rulings run inline; `Reviewed-Coverage: sequential-fallback` to be disclosed in the PR body).

### Components Invoked
soleur:one-shot (inline), soleur:plan (inline), soleur:deepen-plan (inline gates), worktree-manager, pipeline-tally, collision-precheck, pr-overlap-preflight, lint-guard-contract

## Operator Constraints
- Budget-owner go-ahead 2026-11-07 (issue comment): authorizes H1-H5 discriminating `gh api` reads, the cause receipt under the spec dir, and the criterion-a evidence re-run (collect/ejections/aggregate/verdict). Nothing beyond: no activation, no `CI_PR_AFFECTED`, no ruleset change, no re-ruling.
- Operator-reserved holds stay held: the full go/no-go re-ruling and the merge-queue/deploy levers are NOT covered by the go-ahead.
