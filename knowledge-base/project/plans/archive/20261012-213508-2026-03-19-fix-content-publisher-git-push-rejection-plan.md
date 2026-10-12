---
title: "fix: content publisher git push rejected by CLA Required ruleset"
type: fix
date: 2026-03-19
semver: patch
---

# fix: content publisher git push rejected by CLA Required ruleset

## Enhancement Summary

**Deepened on:** 2026-03-19
**Sections enhanced:** 5 (Proposed Solution, Technical Considerations, If Condition, Permissions, Risks)
**Research sources:** 6 project learnings applied, weekly analytics workflow pattern, GitHub Statuses API docs, failed run log analysis (run IDs 23200184350, 23300396759)

### Key Improvements

1. Added precise `if` condition fix with `always()` guard to handle the GitHub Actions expression evaluation edge case where `failure()` prevents step output access
2. Added GITHUB_TOKEN cascade limitation analysis -- bot PRs will NOT trigger the CLA workflow, so synthetic status is the only path (confirmed by learning `2026-02-12-github-actions-auto-release-permissions`)
3. Added stale branch cleanup consideration -- `ci/content-publisher-*` branches accumulate unless auto-deleted or manually pruned
4. Added `2026-03-16-soleur-vs-anthropic-cowork.md` to the stale files list (was missed in initial analysis -- publish_date 2026-03-16 predates both failures)

### New Considerations Discovered

- The current `if: success() || steps.publish.outputs.exit_code == '0'` condition is incorrect for the partial failure case -- when the publish step exits with code 2, the workflow wrapper catches it and exits 0 (line 67 of the workflow), so `success()` is true. But if the script exits with code 1 (fatal), the step fails and `steps.publish.outputs.exit_code` is available only if `always()` is used in the condition
- The `2026-03-16-soleur-vs-anthropic-cowork.md` file has `publish_date: 2026-03-16` and `status: scheduled` -- it was published on March 16 (before the first failure), meaning it was published successfully and its status was committed before the CLA ruleset broke pushes. Need to verify against run logs whether March 16 succeeded

## Overview

The Scheduled Content Publisher workflow has failed twice this week (March 17 and March 19) despite successfully publishing all content to Discord and X/Twitter. The failure occurs in the "Commit status updates" step when `git push` to `main` is rejected by the `CLA Required` repository ruleset (ID 13304872), which requires a `cla-check` status check that direct pushes from `github-actions[bot]` cannot satisfy.

Additionally, because the status update (`status: scheduled` -> `status: published`) never commits back, the content files remain in `status: scheduled` state, causing stale content warnings on subsequent runs and the risk of duplicate posts if the script were re-run naively.

## Root Cause Analysis

**Error from both failed runs:**

```
remote: error: GH013: Repository rule violations found for refs/heads/main.
remote: - Required status check "cla-check" is expected.
! [remote rejected] main -> main (push declined due to repository rule violations)
```

**Sequence of events:**

1. Content publisher runs successfully -- posts to Discord and X, updates `status: published` in local working copy via `sed -i`
2. `git add` + `git commit` succeeds locally
3. `git push` to `main` fails because the `CLA Required` ruleset blocks pushes without a passing `cla-check` status
4. The step exits non-zero, triggering the Discord failure notification
5. Content is already posted to social media, but the status files on `main` still say `status: scheduled`
6. Next run sees the same files as "stale scheduled content" and warns

**Why this started failing:** The `CLA Required` ruleset (ID 13304872) was added to the repository after the content publisher workflow was initially designed. The original plan (from `2026-03-11-feat-scheduled-content-publisher-workflow-plan.md`) assumed direct push to `main` would work, which was true at the time.

**Existing learning applies:** `2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md` documents this exact class of problem and notes that `github-actions[bot]` cannot be granted bypass via API for the CLA ruleset.

### Research Insights: Why Synthetic CLA Status Is Required

Per learning `2026-02-12-github-actions-auto-release-permissions`, GITHUB_TOKEN releases/PRs do **not** trigger other workflows. This means a bot PR created by `github-actions[bot]` will **never** trigger the `cla.yml` workflow (which runs on `pull_request_target`). The CLA check will never run organically on bot PRs, so the synthetic status via Statuses API is the only viable path. This is consistent with the pattern already running in `scheduled-weekly-analytics.yml`.

Per learning `2026-03-02-claude-code-action-token-revocation-breaks-persist-step`, using the Claude App's identity for pushing is an alternative, but it only works inside `claude-code-action` steps. The content publisher is a pure shell script (no LLM), so this path does not apply.

## Proposed Solution

Adopt the PR-based commit pattern already proven in `scheduled-weekly-analytics.yml` (lines 89-114):

1. Create a timestamped branch (`ci/content-publisher-YYYY-MM-DD-HHMMSS`)
2. Commit status updates to the branch
3. Set synthetic `cla-check` status to `success` via the GitHub Statuses API (bot PRs have no human contributor to sign a CLA)
4. Create a PR and queue auto-merge via `gh pr merge --squash --auto`

This pattern is established, tested, and running successfully in the Weekly Analytics workflow.

### Why not other approaches

| Alternative | Why rejected |
|---|---|
| Add `github-actions[bot]` as ruleset bypass actor | The `CLA Required` ruleset has `bypass_actors: null` and the GitHub API does not support adding bypass actors for required status check rulesets programmatically |
| Disable the CLA check | Weakens contributor compliance for all PRs |
| Use a PAT with admin bypass | Requires managing a separate secret; violates least-privilege |
| Skip the commit entirely | Content files would permanently stay `status: scheduled`, causing duplicate stale warnings and risk of re-posting |
| Push inside `claude-code-action` | Content publisher is a pure shell script with no LLM -- `claude-code-action` is not used |

### Research Insights: Pattern Comparison With Weekly Analytics

The `scheduled-weekly-analytics.yml` implementation (lines 89-114) is the canonical reference. Key differences to note when adapting:

1. **Weekly analytics uses `actions: write` permission** for dispatching remediation workflows -- content publisher does not need this permission
2. **Weekly analytics creates the branch inline** with `git checkout -b` -- this is correct and should be replicated exactly
3. **Weekly analytics uses `|| gh pr merge "$BRANCH" --squash`** as a fallback for when auto-merge is not enabled -- this handles the edge case where auto-merge is disabled on the repo
4. **The auto-delete branch setting** on the repository (if enabled) will clean up merged `ci/content-publisher-*` branches. If not enabled, these accumulate. Per learning `2026-02-09-worktree-cleanup-gap-after-merge`, stale branches are a known pattern in this repo

## Technical Considerations

### Workflow changes (`scheduled-content-publisher.yml`)

The "Commit status updates" step needs to be rewritten. The `if` condition also needs updating.

**Required permissions update:** Add `pull-requests: write` and `statuses: write` to the workflow permissions block. Current permissions are `contents: write` and `issues: write`.

### Research Insights: `if` Condition Analysis

The current workflow step condition is:

```yaml
if: success() || steps.publish.outputs.exit_code == '0'
```

This condition has a subtle interaction with the exit code handling:

**Current exit code flow (lines 61-68 of the workflow):**

```yaml
run: |
  exit_code=0
  bash scripts/content-publisher.sh || exit_code=$?
  echo "exit_code=$exit_code" >> "$GITHUB_OUTPUT"
  if [[ "$exit_code" -eq 2 ]]; then
    echo "::warning::Partial failure..."
    exit 0
  fi
  exit "$exit_code"
```

- **Exit code 0 (success):** Step succeeds -> `success()` is true -> commit step runs
- **Exit code 2 (partial failure):** Script exits 2, wrapper catches it, exits 0 -> `success()` is true -> commit step runs (correct)
- **Exit code 1 (fatal):** Step fails -> `success()` is false -> need `steps.publish.outputs.exit_code` -> BUT the output was written before the exit, so it IS available

However, there is a more fundamental issue. When the publish step fails (exit 1), `success()` is false. In this case, the second part of the condition (`steps.publish.outputs.exit_code == '0'`) is evaluated, but `exit_code` was set to the actual exit code (1), not '0'. So the entire condition is false, and the commit step is correctly skipped for fatal errors.

**Recommended simplified condition:**

```yaml
if: always() && steps.publish.outputs.exit_code != '1'
```

This reads: "always run this step (even after failure), unless the publish step had a fatal error (exit code 1)." The `always()` is needed because without it, GitHub Actions skips the step entirely when a prior step fails -- the expression is not even evaluated.

But actually, the current condition works correctly for all three cases. The only change needed is: when the step *does* run and successfully creates the PR, we need `always()` to ensure the step runs even when a prior step in the job has failed. Since the current condition already uses `success()`, and exit code 2 is mapped to exit 0 by the wrapper, `success()` is true for both success and partial failure.

**Wait -- reviewing the current condition more carefully:** The condition `success() || steps.publish.outputs.exit_code == '0'` is redundant. If `success()` is true, the output check is irrelevant. If `success()` is false, `exit_code` is NOT '0' (it's '1' or missing), so the second clause is also false. The current condition is equivalent to just `success()`, which is the default.

**Corrected condition for the PR commit step:**

```yaml
if: success() || steps.publish.outputs.exit_code == '2'
```

This handles: exit 0 (success, commit), exit 2 caught by wrapper as exit 0 (success, commit), and theoretically if the wrapper ever changes, exit 2 not caught (failure but still should commit). However, since the wrapper already maps exit 2 to exit 0, this second clause is dead code today.

**Simplest correct approach:** Keep `if: success()` since the exit code 2 -> 0 mapping already ensures `success()` is true for partial failures.

### Stale content from previous failures

Files that were successfully published but whose status on `main` still says `status: scheduled`:

| File | Published On | Verified |
|------|-------------|----------|
| `02-operations-management.md` | 2026-03-17 | Run logs confirm Discord + X posts succeeded |
| `2026-03-17-soleur-vs-notion-custom-agents.md` | 2026-03-17 | Run logs confirm Discord + X posts succeeded |
| `03-competitive-intelligence.md` | 2026-03-19 | Run logs confirm Discord + X posts succeeded |
| `2026-03-19-soleur-vs-cursor.md` | 2026-03-19 | Run logs confirm Discord + X posts succeeded |

Additionally, `2026-03-16-soleur-vs-anthropic-cowork.md` has `publish_date: 2026-03-16` and `status: scheduled`. The March 16 run (ID 23149951182) succeeded with conclusion `success`, so this file's status WAS committed to main. The stale state seen in the March 17 and 19 logs is because this file's publish_date is before today (March 17 / March 19), not because the commit failed. This file should already be `published` on main -- verify before including in the fix.

### Race condition: content already posted but status not updated

The current workflow design has a fundamental issue: content is posted to external platforms first, then status is updated. If the status update fails (as it has been), the content is already live but the file says `scheduled`. This is a data integrity problem but not a duplicate posting risk because the publish step itself succeeded and the workflow would need to be re-run manually to re-post.

The fix does not change this ordering (post first, update status second) since the alternative (update status first, then post) risks marking content as published when it actually failed to post.

### Research Insights: Permissions Best Practices

Per learning `2026-03-16-github-actions-workflow-dispatch-permissions`:

> When a GitHub Actions workflow already uses explicit `permissions`, you must explicitly add every new permission needed. The "default permissions" only apply when no `permissions` block exists.

The content publisher already declares explicit permissions (`contents: write`, `issues: write`). Adding `pull-requests: write` and `statuses: write` is required. Without `statuses: write`, the `gh api repos/.../statuses/...` call will return HTTP 403. Without `pull-requests: write`, the `gh pr create` and `gh pr merge` calls will fail.

Per learning `2026-02-21-github-actions-workflow-security-patterns`, all action references must be SHA-pinned. The existing `actions/checkout` reference is already SHA-pinned, and no new actions are added by this change.

## Acceptance Criteria

- [x] Status update step creates a PR instead of pushing directly to `main`
- [x] PR includes synthetic `cla-check` status via GitHub Statuses API
- [x] PR auto-merges via `gh pr merge --squash --auto`
- [ ] Workflow succeeds end-to-end on the daily cron schedule without Discord failure notifications
- [x] Previously stale content files (`02-operations-management.md`, `2026-03-17-soleur-vs-notion-custom-agents.md`, `03-competitive-intelligence.md`, `2026-03-19-soleur-vs-cursor.md`) are updated to `status: published`
- [x] Partial failures (exit code 2) still commit status updates for successfully published files
- [x] Workflow permissions include `pull-requests: write` and `statuses: write`

## Test Scenarios

- Given content is published successfully, when the commit step runs, then a PR is created with status updates and auto-merged
- Given the workflow runs and no content files match today's date, when the commit step runs, then no PR is created (no changes to commit)
- Given a partial failure (exit code 2) where one channel fails, when the commit step runs, then a PR is still created for the files that were successfully published
- Given the `cla-check` status is set on the PR commit, when auto-merge is queued, then the PR merges without waiting indefinitely
- Given a fatal error (exit code 1) in the publish step, when the commit step condition is evaluated, then the step is skipped (no PR created)
- Given two content files are published on the same day, when the commit step runs, then both files' status changes are included in a single PR

## Implementation Structure

### Files to modify

```text
.github/workflows/scheduled-content-publisher.yml   # Rewrite commit step, update permissions
knowledge-base/marketing/distribution-content/02-operations-management.md          # Fix status: scheduled -> published
knowledge-base/marketing/distribution-content/03-competitive-intelligence.md       # Fix status: scheduled -> published
knowledge-base/marketing/distribution-content/2026-03-17-soleur-vs-notion-custom-agents.md  # Fix status: scheduled -> published
knowledge-base/marketing/distribution-content/2026-03-19-soleur-vs-cursor.md       # Fix status: scheduled -> published
```

### Commit step replacement

```yaml
- name: Commit status updates via PR
  if: success()
  env:
    GH_TOKEN: ${{ github.token }}
  run: |
    git config user.name "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    git add knowledge-base/marketing/distribution-content/
    git diff --cached --quiet && echo "No changes to commit" && exit 0
    BRANCH="ci/content-publisher-$(date -u +%Y-%m-%d-%H%M%S)"
    git checkout -b "$BRANCH"
    git commit -m "ci: update content distribution status [skip ci]"
    git push -u origin "$BRANCH"
    # Set CLA check status to success -- bot PRs have no human
    # contributor to sign a CLA, and the CLA Required ruleset
    # blocks auto-merge without this status.
    SHA=$(git rev-parse HEAD)
    gh api "repos/${{ github.repository }}/statuses/$SHA" \
      -f state=success \
      -f context=cla-check \
      -f description="CLA not required for automated PRs"
    gh pr create \
      --title "ci: update content distribution status $(date -u +%Y-%m-%d)" \
      --body "Automated status update from content publisher workflow." \
      --base main \
      --head "$BRANCH"
    gh pr merge "$BRANCH" --squash --auto || gh pr merge "$BRANCH" --squash
```

### Research Insights: Implementation Notes

1. **`git checkout -b` vs `git switch -c`:** Both work. The weekly analytics workflow uses `git checkout -b`, so match that for consistency.

2. **`[skip ci]` in commit message:** This prevents the PR's squash merge commit from triggering workflows on push to main. Important because without it, the content publisher's own push trigger (cron) could create a recursive loop if push events were added in the future. Currently the workflow only triggers on `schedule` and `workflow_dispatch`, so this is defense-in-depth.

3. **`gh pr merge` fallback:** The `|| gh pr merge "$BRANCH" --squash` fallback handles the case where auto-merge is not enabled on the repository. This is the same pattern used in weekly analytics and is resilient to repository settings changes.

4. **Email for `github-actions[bot]`:** Use `41898282+github-actions[bot]@users.noreply.github.com` (the numeric prefix is the bot's user ID). This matches the weekly analytics pattern and the constitution's bot email convention.

5. **Status API timing:** The `gh api repos/.../statuses/$SHA` call must happen AFTER `git push` (so the SHA exists remotely) and BEFORE `gh pr merge --auto` (so the status check is satisfied). The linear ordering in the script handles this correctly.

### Permissions update

```yaml
permissions:
  contents: write
  issues: write
  pull-requests: write
  statuses: write
```

## Dependencies and Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Auto-merge races with other PRs | Low | Low | Concurrency group prevents overlapping content publisher runs; squash merge is atomic |
| Synthetic cla-check rejected by future ruleset changes | Low | Medium | Monitor for ruleset changes; pattern is shared with weekly analytics (two workflows would break simultaneously, increasing detection speed) |
| Branch name collision | Very Low | Low | Timestamp includes seconds for uniqueness |
| Stale `ci/content-publisher-*` branches accumulate | Low | Low | Repository auto-delete setting handles merged branches. If disabled, manual cleanup or a scheduled prune job would be needed |
| PR merge conflict with concurrent main changes | Very Low | Low | Content publisher only modifies frontmatter status fields in `distribution-content/` -- these files are rarely modified by other PRs |
| GITHUB_TOKEN rate limiting on Statuses API | Very Low | Low | Single API call per run; well within rate limits |

## References

### Internal

- `.github/workflows/scheduled-weekly-analytics.yml` -- proven PR-based commit pattern with synthetic `cla-check` (lines 89-114)
- `knowledge-base/project/learnings/2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md` -- documents the `github-actions[bot]` push restriction
- `knowledge-base/project/learnings/2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md` -- explains why the Claude App identity path does not apply here
- `knowledge-base/project/learnings/2026-02-12-github-actions-auto-release-permissions.md` -- confirms GITHUB_TOKEN cascade limitation (bot PRs do not trigger CLA workflow)
- `knowledge-base/project/learnings/2026-03-11-multi-platform-publisher-error-propagation.md` -- exit code 0/1/2 convention for the content publisher
- `knowledge-base/project/learnings/2026-03-16-github-actions-workflow-dispatch-permissions.md` -- explicit permissions required when extending workflows
- `knowledge-base/project/learnings/2026-02-21-github-actions-workflow-security-patterns.md` -- SHA pinning and security patterns for GHA workflows
- `knowledge-base/project/plans/2026-03-11-feat-scheduled-content-publisher-workflow-plan.md` -- original plan (assumed direct push)

### Failed run logs

- March 17 failure: run ID `23200184350` -- `GH013: Required status check "cla-check" is expected`
- March 19 failure: run ID `23300396759` -- identical error

### Learnings Applied

| Learning | Application |
|----------|------------|
| `2026-03-02-github-actions-auto-push-vs-pr-for-bot-content` | Confirmed root cause: CLA ruleset blocks `github-actions[bot]` pushes |
| `2026-03-02-claude-code-action-token-revocation` | Ruled out Claude App identity as alternative (not applicable to shell scripts) |
| `2026-02-12-github-actions-auto-release-permissions` | Confirmed GITHUB_TOKEN cascade blocks CLA workflow on bot PRs, requiring synthetic status |
| `2026-03-11-multi-platform-publisher-error-propagation` | Validated exit code convention (0/1/2) for `if` condition analysis |
| `2026-03-16-github-actions-workflow-dispatch-permissions` | Required explicit `pull-requests: write` and `statuses: write` permissions |
| `2026-02-21-github-actions-workflow-security-patterns` | Confirmed SHA pinning is already in place, no new actions needed |
