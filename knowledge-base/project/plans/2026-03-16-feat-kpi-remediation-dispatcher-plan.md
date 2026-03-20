---
title: "feat: KPI remediation dispatcher"
type: feat
date: 2026-03-16
semver: patch
deepened: 2026-03-16
---

## Enhancement Summary

**Deepened on:** 2026-03-16
**Sections enhanced:** 3 (SpecFlow Analysis, Test Scenarios, MVP)
**Research sources:** GitHub Docs (GITHUB_TOKEN permissions), GitHub Changelog (workflow_dispatch exception), cli/cli issue tracker, project learnings (shell-script-defensive-patterns)

### Key Improvements

1. Confirmed `GITHUB_TOKEN` can trigger `workflow_dispatch` -- explicit GitHub exception since Sep 2022 (not blocked by recursive prevention)
2. Validated `actions: write` is mandatory when explicit permissions are declared (HTTP 403 without it)
3. Added edge case for `gh` CLI panic on unexpected HTTP codes -- `|| echo` fallback absorbs non-zero exits including crashes
4. Added Discord notification timing consideration -- message says "will be dispatched" (future tense) since it fires before the dispatch step

### Learnings Applied

- **Shell Script Defensive Patterns** (2026-03-13): The `|| echo "::warning::"` fallback per command is the correct pattern -- avoids `set -e` short-circuit between independent calls. Each `gh workflow run` is independent; one failure must not block the others.

# feat: KPI remediation dispatcher -- auto-trigger CMO workflows on KPI miss

## Overview

Add a lightweight `gh workflow run` dispatcher step to the existing `scheduled-weekly-analytics.yml` workflow. When `kpi_miss=true` (already emitted to `GITHUB_OUTPUT` by `check_kpi_miss()` in `scripts/weekly-analytics.sh`), dispatch the three standalone CMO workflows:

- `scheduled-seo-aeo-audit.yml`
- `scheduled-growth-execution.yml`
- `scheduled-content-generator.yml`

This closes the feedback loop: weekly analytics detects underperformance, and the CMO execution stack responds automatically without manual intervention.

Deferred from #638 -- a 60-turn cascade agent re-implementing all three workflows was overengineered. The standalone workflows already exist and accept `workflow_dispatch`; this feature just triggers them on KPI miss.

Closes #640

## Acceptance Criteria

- [x] New workflow step "Dispatch CMO remediation workflows" runs after the KPI miss Discord notification step
- [x] Step condition: `if: steps.analytics.outputs.kpi_miss == 'true'`
- [x] Step dispatches all three workflows via `gh workflow run` using `GH_TOKEN`
- [x] When no KPI miss (`kpi_miss != 'true'`), no workflows are dispatched (step is skipped)
- [x] Discord KPI miss notification message is updated to document which workflows were triggered
- [x] Workflow file retains its existing security comment header

## Non-goals

- Modifying `scripts/weekly-analytics.sh` -- the KPI detection logic is already correct
- Adding new inputs or parameters to the three target workflows
- Creating a separate workflow file for remediation dispatch
- Adding retry logic for `gh workflow run` failures (GitHub handles queueing)

## Test Scenarios

- Given weekly analytics detects `kpi_miss=true`, when the dispatcher step runs, then `gh workflow run` is called for all three CMO workflows
- Given weekly analytics detects `kpi_miss=false`, when the workflow completes, then the dispatcher step is skipped entirely
- Given `GH_TOKEN` lacks `actions:write` permission, when the dispatcher step runs, then `gh workflow run` fails with a clear error (caught by existing failure notification step)
- Given one of the three workflows does not exist (deleted), when the dispatcher step runs, then the remaining workflows are still dispatched (no `set -e` short-circuit between calls)
- Given `gh workflow run` panics (cli/cli#10519 nil pointer dereference), when the `||` fallback fires, then the step logs a `::warning::` annotation and continues to the next dispatch
- Given the workflow runs on schedule (Monday 06:00 UTC), when KPI miss is detected, then the dispatched workflows run on their own schedules (no input passthrough needed -- they are standalone)
- Given the Discord webhook is not configured, when KPI miss triggers dispatch, then workflows are still dispatched (dispatch step has no dependency on Discord step success)

## SpecFlow Analysis

### Token Permissions

The workflow currently declares `contents: write`, `pull-requests: write`, `statuses: write`. The `gh workflow run` command requires `actions: write` to trigger workflow dispatches.

**Research confirmation:** [GitHub Changelog (Sep 2022)](https://github.blog/changelog/2022-09-08-github-actions-use-github_token-with-workflow_dispatch-and-repository_dispatch/) explicitly allows `GITHUB_TOKEN` to trigger `workflow_dispatch` and `repository_dispatch` events -- this is an exception to the general rule that `GITHUB_TOKEN`-triggered events do not create new workflow runs. The exception exists because these are explicit calls, not implicit event chains.

**Critical:** When a workflow declares explicit `permissions`, only listed permissions are granted -- all others default to `none`. Since this workflow already lists explicit permissions, omitting `actions: write` results in HTTP 403: `Resource not accessible by integration` ([GitHub Docs: Controlling permissions for GITHUB_TOKEN](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/controlling-permissions-for-github_token)).

**Decision:** Add `actions: write` to the `permissions` block.

### Step Ordering

The dispatcher step must run **after** the Discord KPI miss notification (so the notification goes out even if dispatch fails) and **before** the "Create PR with snapshot" step (so dispatch is not blocked by PR creation). Insert as a new step between the existing "Discord notification (KPI miss)" and "Create PR with snapshot" steps.

### Failure Mode

If `gh workflow run` fails for any workflow, the step should log a warning but continue dispatching the remaining workflows. Use `|| echo "::warning::Failed to dispatch <name>"` after each call rather than relying on `set -e`.

**Research insight:** The `gh` CLI has a known issue ([cli/cli#10519](https://github.com/cli/cli/issues/10519)) where `gh workflow run` can panic with a nil pointer dereference on unexpected HTTP error codes (not just 404). The `|| echo` fallback absorbs any non-zero exit, including crashes, ensuring subsequent dispatches proceed. This aligns with the project's shell-script-defensive-patterns learning: independent operations should not share a failure path.

### Discord Message Enhancement

Update the existing KPI miss Discord notification to append a line indicating remediation workflows will be dispatched. This gives the CMO visibility into the automated response.

**Timing note:** The Discord notification step runs before the dispatch step (by design -- notification must succeed even if dispatch fails). The message should use future tense ("will be dispatched") since at notification time, dispatch has not yet occurred. An alternative is to move notification after dispatch, but that couples notification reliability to dispatch reliability -- the current ordering is correct.

## MVP

### .github/workflows/scheduled-weekly-analytics.yml (changes only)

```yaml
# Add to permissions block:
permissions:
  contents: write
  pull-requests: write
  statuses: write
  actions: write

# New step -- insert after "Discord notification (KPI miss)", before "Create PR with snapshot":
- name: Dispatch CMO remediation workflows
  if: steps.analytics.outputs.kpi_miss == 'true'
  env:
    GH_TOKEN: ${{ github.token }}
  run: |
    echo "KPI miss detected -- dispatching CMO remediation workflows"
    gh workflow run scheduled-seo-aeo-audit.yml || echo "::warning::Failed to dispatch scheduled-seo-aeo-audit.yml"
    gh workflow run scheduled-growth-execution.yml || echo "::warning::Failed to dispatch scheduled-growth-execution.yml"
    gh workflow run scheduled-content-generator.yml || echo "::warning::Failed to dispatch scheduled-content-generator.yml"
    echo "CMO remediation workflows dispatched"
```

### Discord message update (in existing KPI miss notification step)

Append to the `MESSAGE` printf:

```text
\n\nRemediation: SEO audit, growth execution, and content generator workflows will be dispatched.
```

## References

### Internal

- Parent issue: #638 (closed -- CMO autonomous execution umbrella)
- Target issue: #640
- Workflow file: `.github/workflows/scheduled-weekly-analytics.yml`
- KPI detection: `scripts/weekly-analytics.sh` (`check_kpi_miss()` function, line ~144)
- Target workflows (all on `origin/main`, all have `workflow_dispatch` trigger):
  - `.github/workflows/scheduled-seo-aeo-audit.yml`
  - `.github/workflows/scheduled-growth-execution.yml`
  - `.github/workflows/scheduled-content-generator.yml`
- Learning: `knowledge-base/learnings/2026-03-13-shell-script-defensive-patterns.md` (independent operations, fallback patterns)

### External

- [GitHub Changelog: GITHUB_TOKEN with workflow_dispatch](https://github.blog/changelog/2022-09-08-github-actions-use-github_token-with-workflow_dispatch-and-repository_dispatch/) -- confirms GITHUB_TOKEN can trigger workflow_dispatch
- [GitHub Docs: Controlling permissions for GITHUB_TOKEN](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/controlling-permissions-for-github_token) -- explicit permissions override defaults
- [gh workflow run CLI reference](https://cli.github.com/manual/gh_workflow_run) -- command syntax and behavior
- [cli/cli#10519](https://github.com/cli/cli/issues/10519) -- `gh workflow run` panic on unexpected HTTP codes
