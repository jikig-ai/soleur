---
title: "fix: content publisher git push rejected by CLA Required ruleset"
type: fix
date: 2026-03-19
semver: patch
---

# fix: content publisher git push rejected by CLA Required ruleset

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

## Proposed Solution

Adopt the PR-based commit pattern already proven in `scheduled-weekly-analytics.yml` (lines 89-114):

1. Create a timestamped branch (`ci/content-publisher-YYYY-MM-DD`)
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

## Technical Considerations

### Workflow changes (`scheduled-content-publisher.yml`)

The "Commit status updates" step needs to be rewritten. The `if` condition also needs updating -- currently it checks `success() || steps.publish.outputs.exit_code == '0'`, but the PR approach should also handle exit code 2 (partial failures where some content was published).

**Required permissions update:** Add `pull-requests: write` and `statuses: write` to the workflow permissions block. Current permissions are `contents: write` and `issues: write`.

### Stale content from previous failures

Files `02-operations-management.md` and `2026-03-17-soleur-vs-notion-custom-agents.md` were successfully published on March 17 (tweets are live, Discord posts sent) but their status on `main` still says `status: scheduled`. Similarly, `03-competitive-intelligence.md` and `2026-03-19-soleur-vs-cursor.md` were published on March 19 but remain `scheduled`.

These need a one-time manual fix: either push a PR updating their status to `published`, or include the fix in this PR's branch.

### Race condition: content already posted but status not updated

The current workflow design has a fundamental issue: content is posted to external platforms first, then status is updated. If the status update fails (as it has been), the content is already live but the file says `scheduled`. This is a data integrity problem but not a duplicate posting risk because the publish step itself succeeded and the workflow would need to be re-run manually to re-post.

The fix does not change this ordering (post first, update status second) since the alternative (update status first, then post) risks marking content as published when it actually failed to post.

## Acceptance Criteria

- [ ] Status update step creates a PR instead of pushing directly to `main`
- [ ] PR includes synthetic `cla-check` status via GitHub Statuses API
- [ ] PR auto-merges via `gh pr merge --squash --auto`
- [ ] Workflow succeeds end-to-end on the daily cron schedule without Discord failure notifications
- [ ] Previously stale content files (`02-operations-management.md`, `2026-03-17-soleur-vs-notion-custom-agents.md`, `03-competitive-intelligence.md`, `2026-03-19-soleur-vs-cursor.md`) are updated to `status: published`
- [ ] Partial failures (exit code 2) still commit status updates for successfully published files
- [ ] Workflow permissions include `pull-requests: write` and `statuses: write`

## Test Scenarios

- Given content is published successfully, when the commit step runs, then a PR is created with status updates and auto-merged
- Given the workflow runs and no content files match today's date, when the commit step runs, then no PR is created (no changes to commit)
- Given a partial failure (exit code 2) where one channel fails, when the commit step runs, then a PR is still created for the files that were successfully published
- Given the `cla-check` status is set on the PR commit, when auto-merge is queued, then the PR merges without waiting indefinitely

## Implementation Structure

### Files to modify

```text
.github/workflows/scheduled-content-publisher.yml   # Rewrite commit step, update permissions
knowledge-base/marketing/distribution-content/02-operations-management.md          # Fix status: scheduled -> published
knowledge-base/marketing/distribution-content/03-competitive-intelligence.md       # Fix status: scheduled -> published
knowledge-base/marketing/distribution-content/2026-03-17-soleur-vs-notion-custom-agents.md  # Fix status: scheduled -> published
knowledge-base/marketing/distribution-content/2026-03-19-soleur-vs-cursor.md       # Fix status: scheduled -> published
```

### Commit step replacement (pseudo-code)

```yaml
- name: Commit status updates via PR
  if: success() || steps.publish.outputs.exit_code == '2'
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
| Synthetic cla-check rejected by future ruleset changes | Low | Medium | Monitor for ruleset changes; pattern is shared with weekly analytics |
| Branch name collision | Very Low | Low | Timestamp includes seconds for uniqueness |

## References

### Internal

- `.github/workflows/scheduled-weekly-analytics.yml` -- proven PR-based commit pattern with synthetic `cla-check` (lines 89-114)
- `knowledge-base/project/learnings/2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md` -- documents the `github-actions[bot]` push restriction
- `knowledge-base/project/plans/2026-03-11-feat-scheduled-content-publisher-workflow-plan.md` -- original plan (assumed direct push)

### Failed run logs

- March 17 failure: run ID `23200184350` -- `GH013: Required status check "cla-check" is expected`
- March 19 failure: run ID `23300396759` -- identical error
