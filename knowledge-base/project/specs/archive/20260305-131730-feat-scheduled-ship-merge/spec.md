# Feature: Scheduled Ship-Merge Workflow

## Problem Statement

PRs accumulate waiting for manual `/ship` invocation. The `--headless` flag convention is implemented but has no CI consumer. Manual shipping is a repeatable, mechanical process consuming developer attention for routine PRs.

## Goals

- Automatically ship qualifying PRs on a daily schedule using `soleur:ship --headless`
- Define clear, machine-testable qualifying criteria (age + CI + opt-out labels)
- Prevent re-processing with label-based deduplication
- Bound cost with single-PR-per-run batching and `--max-turns` limits

## Non-Goals

- Multi-PR batching or matrix strategies
- New `ship-merge` skill (reuse existing ship)
- Extending ship with `--pr` flag
- Processing draft PRs
- Dollar-based cost caps (CLI doesn't support this)

## Functional Requirements

### FR1: PR Selection

The workflow selects the oldest open PR matching ALL criteria:

- Not a draft
- Open for 24+ hours
- CI checks passing
- No `ship/scheduled` label
- No `ship/failed` label
- No `no-auto-ship` label

If no PR qualifies, the workflow exits successfully with no action.

### FR2: Deduplication Labels

- `ship/scheduled` applied at processing start, removed on success
- `ship/failed` applied on failure, with a PR comment explaining the failure
- `no-auto-ship` user-applied opt-out label

### FR3: Full Ship Pipeline

The workflow invokes `skill: soleur:ship --headless` which runs compound, tests, PR update, semver labeling, conflict resolution, and auto-merge.

### FR4: Failure Handling

On failure:

- Apply `ship/failed` label
- Post PR comment with failure details
- Do not retry without human intervention

### FR5: Concurrency

Concurrency group prevents parallel scheduled runs. Manual `/ship` invocations are not coordinated (accepted risk).

## Technical Requirements

- **TR1:** GitHub Actions workflow using `claude-code-action` with SHA-pinned action reference
- **TR2:** `--max-turns 40`, `timeout-minutes: 30`, model `claude-sonnet-4-6`
- **TR3:** Concurrency group `schedule-ship-merge`, cancel-in-progress false
- **TR4:** Pre-create labels `ship/scheduled`, `ship/failed`, `no-auto-ship` in selection step
- **TR5:** Plugin loaded via `plugin_marketplaces` + `plugins` inputs (same pattern as bug-fixer)
- **TR6:** Permissions: `contents: write`, `pull-requests: write`, `issues: write`, `id-token: write`

## Acceptance Criteria

- [ ] `scheduled-ship-merge.yml` workflow file created
- [ ] PR selection query correctly filters by age, CI, labels, and draft status
- [ ] `ship/scheduled` label applied at start, removed on success
- [ ] `ship/failed` label + PR comment on failure
- [ ] Concurrency group prevents parallel runs
- [ ] `workflow_dispatch` trigger for manual testing
- [ ] Cost controls: `--max-turns 40`, `timeout-minutes: 30`
