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
