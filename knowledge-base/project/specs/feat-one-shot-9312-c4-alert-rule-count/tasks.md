# Tasks: delete the C4 sentry_alert rule count (#9312)

Plan: knowledge-base/project/plans/2026-10-05-docs-delete-c4-sentry-alert-rule-count-plan.md

## Phase 1: Edit the edge description

- 1.1 Read model.c4 (edge `sentry -> founder`), views.c4 and spec.c4 once; confirm the description text matches the plan.
- 1.2 Replace the "40 of the 43 ... three deliberately set NoOne ..." clause with the qualitative sentence (no number, no rule names, points at issue-alerts.tf).
- 1.3 Reword "by design there and a defect anywhere else" to "by design only where issue-alerts.tf says so and a defect anywhere else".
- 1.4 Verify the diff is one changed line in model.c4.

## Phase 2: Re-render

- 2.1 Run `bash plugins/soleur/scripts/render-c4-model.sh`.
- 2.2 Verify model.likec4.json changed only on the mirrored `title` string.

## Phase 3: Verify

- 3.1 Run c4-model-freshness, c4-count-parity and render-c4-model tests; all pass.
- 3.2 Run the residual-sentence `git grep` (excluding archive and this feature's plan/tasks); no hits.
- 3.3 Check no doubled blank lines in the new markdown (plan, tasks).

## Phase 4: Ship

- 4.1 PR #9527 body contains `Closes #9312`.
- 4.2 No .github/workflows or .github/actions edits; admin merge allowed on green CI.
- 4.3 If only the e2e job (#8785 flake) is red, one `gh run rerun --failed`.
