# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-07-ci-strict-duplicate-key-guard-and-queue-stall-cause-plan.md
- Status: complete
- Draft PR: 12295
- cto_spawns=2 (rulings D8 to D12 batched, gate passes)

### Errors
None.

### Decisions
- Strict parse scans all workflows and action.yml files, as a new member step of quality-guards with its own aggregate row. No new required context.
- New suite auto-globbed by run-all.sh (MIN_SUITES 17 to 18). No scripts/test-all.sh edit.
- Stall cause is named per workflow_id: failed push run whose name equals its path, on the latest temp ref, with no merge_group run of that workflow. Lookup is fail-soft.
- actions: read added to merge-queue-stall-check.yml.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, soleur:engineering:cto (2 rounds, then 1 batched ruling)

## Operator Constraints

- constraint: Ref #9927 and Ref #12283 in the PR body, never Closes.
- constraint: Do not touch the dequeued duplicate-fetch-depth PR, CI_ORACLE_LANE, the SOLEUR-DEBT marker in ci.yml, or any apps/web-platform/infra path.
- constraint: If the diff touches scripts/test-all.sh it is a whole-ledger-void path; prefer a registration route that avoids it.
- constraint: Guard 1 is merge-blocking; only merge_group or workflow_dispatch runs on the merge SHA count as evidence; state run kind and leg with every CI claim.
- constraint: Review seats simulating GIT_DIR use a throwaway repo; check git log main -1, HEAD and git config --local --list afterwards.
- constraint: Use Monitor for waits; no sleep in Bash; run gh pr merge as a bare command.

## Review Phase (PANEL_SHA 551888d96d, tier aggregate pattern, 12 seats)

dedup: about 75 raw to 14 unique. Structural-cause roll-up: both guards' assembly was narrower than the property named (key identity, file set, host file) and both guards' fixtures held one member per axis.

| raw finding | canonical defect key | reporting seat(s) | planned fix |
|---|---|---|---|
| key identity narrower than GitHub (case-insensitive, merge key) | guard predicate is not the platform's | structural, quality, dataint, security | CTO item 1 |
| uppercase ext, dangling symlink, composite actions outside .github/actions | guard file-set narrower than loadable set | structural, security, quality, userimpact | CTO item 2 |
| guard cannot protect its own host file | uncovered path (stated residual) | structural, userimpact, architecture | CTO item 3 plus CODEOWNERS |
| title over 256 chars aborts filing | unbounded interpolation into title | userimpact, dataint, structural | fix inline |
| ref and path unvalidated into issue text | untrusted API strings into agent-runnable text | security, userimpact, structural | fix inline |
| cause overclaim, name equals path, non-merge_group workflow | predicate proves unloadable, not gates-queue | architecture, quality, history, dataint, userimpact, structural | CTO item 4 |
| PyYAML preinstalled unmeasured | D2 premise | history, quality | CTO item 5 |
| dup-suite single-member axes, crash scored as kill, no-arg default root | suite fixtures and harness | testdesign | fix inline |
| stall-suite single-member axes, ref text, latest-ref join, slack | suite fixtures | testdesign | fix inline |
| comment and doc drift (ADR inventory row, pr-quality-guards header, pr-fanout-ledger, C1-C13, headroom claim, D2 cite) | member-list claims in N places | pattern, history, perf, quality | fix inline |
| MIN_SUITES exact pin, unused vars, python -I, empty enqueuedAt | hygiene | pattern, architecture, sast, security, dataint | fix inline |
| suite weight, mutation re-runs whole battery | speed | perf, simplicity, testdesign | optional |
| loader seam deletion | taste | simplicity | declined pending CTO |
| PR 12303 textual conflict in pr-quality-guards.yml | queue-mate | history | rebase at ship |
