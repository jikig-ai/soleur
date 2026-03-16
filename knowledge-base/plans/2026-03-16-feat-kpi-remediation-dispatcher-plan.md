---
title: "feat: KPI remediation dispatcher"
type: feat
date: 2026-03-16
semver: patch
---

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

- [ ] New workflow step "Dispatch CMO remediation workflows" runs after the KPI miss Discord notification step
- [ ] Step condition: `if: steps.analytics.outputs.kpi_miss == 'true'`
- [ ] Step dispatches all three workflows via `gh workflow run` using `GH_TOKEN`
- [ ] When no KPI miss (`kpi_miss != 'true'`), no workflows are dispatched (step is skipped)
- [ ] Discord KPI miss notification message is updated to document which workflows were triggered
- [ ] Workflow file retains its existing security comment header

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

## SpecFlow Analysis

### Token Permissions

The workflow currently declares `contents: write`, `pull-requests: write`, `statuses: write`. The `gh workflow run` command requires the ability to trigger workflow dispatches. The default `GITHUB_TOKEN` in GitHub Actions has `actions: write` permission when the workflow has `contents: write` -- but this is implicit. To be explicit and safe, the `actions: write` permission should be added to the permissions block.

**Decision:** Add `actions: write` to the `permissions` block.

### Step Ordering

The dispatcher step must run **after** the Discord KPI miss notification (so the notification goes out even if dispatch fails) and **before** the "Create PR with snapshot" step (so dispatch is not blocked by PR creation). Insert as a new step between the existing "Discord notification (KPI miss)" and "Create PR with snapshot" steps.

### Failure Mode

If `gh workflow run` fails for any workflow, the step should log a warning but continue dispatching the remaining workflows. Use `|| echo "::warning::Failed to dispatch <name>"` after each call rather than relying on `set -e`.

### Discord Message Enhancement

Update the existing KPI miss Discord notification to append a line indicating remediation workflows will be dispatched. This gives the CMO visibility into the automated response.

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
\n\nRemediation: SEO audit, growth execution, and content generator workflows dispatched.
```

## References

- Parent issue: #638 (closed -- CMO autonomous execution umbrella)
- Target issue: #640
- Workflow file: `.github/workflows/scheduled-weekly-analytics.yml`
- KPI detection: `scripts/weekly-analytics.sh` (`check_kpi_miss()` function, line ~144)
- Target workflows (all on `origin/main`, all have `workflow_dispatch` trigger):
  - `.github/workflows/scheduled-seo-aeo-audit.yml`
  - `.github/workflows/scheduled-growth-execution.yml`
  - `.github/workflows/scheduled-content-generator.yml`
