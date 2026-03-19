---
title: "security: remove squash fallback from automated PR workflows"
type: fix
date: 2026-03-19
semver: patch
---

# security: remove squash fallback from automated PR workflows

## Overview

All 9 automated CI workflows that create PRs use the pattern:

```bash
gh pr merge "$BRANCH" --squash --auto || gh pr merge "$BRANCH" --squash
```

The `|| gh pr merge "$BRANCH" --squash` fallback bypasses pending status checks. If `--auto` fails for any reason, the fallback performs an immediate squash merge regardless of whether required checks have passed. This was flagged by the security-sentinel agent during #772 review and tracked in #780.

## Problem Statement

The fallback was originally added to handle the case where auto-merge might not be enabled on the repository. However:

1. **Auto-merge IS enabled** on the repo (`allow_auto_merge: true`), so `--auto` should always succeed
2. **The only required check is `cla-check`** (ruleset ID 13304872), which is satisfied by a synthetic status posted earlier in the same workflow step -- it's already passing when `--auto` is called
3. **All bot commits use `[skip ci]`**, so no other CI checks run on these PRs
4. **If `--auto` genuinely fails**, it indicates a configuration problem (e.g., auto-merge was disabled, rulesets changed) that should be investigated, not silently bypassed

The immediate squash fallback masks configuration failures and bypasses the merge gate that rulesets enforce.

## Proposed Solution

Remove the `|| gh pr merge "$BRANCH" --squash` fallback from all 9 workflows. If `--auto` fails, the workflow step fails, the PR stays open for investigation, and the Discord failure notification fires.

### Change Pattern

In each workflow file, replace:

```bash
gh pr merge "$BRANCH" --squash --auto || gh pr merge "$BRANCH" --squash
```

With:

```bash
gh pr merge "$BRANCH" --squash --auto
```

### Affected Files (9 workflows)

1. `.github/workflows/scheduled-weekly-analytics.yml` (line 114)
2. `.github/workflows/scheduled-content-publisher.yml` (line 98)
3. `.github/workflows/scheduled-growth-audit.yml` (line 156)
4. `.github/workflows/scheduled-community-monitor.yml` (line 135)
5. `.github/workflows/scheduled-content-generator.yml` (line 161)
6. `.github/workflows/scheduled-growth-execution.yml` (line 107)
7. `.github/workflows/scheduled-competitive-analysis.yml` (line 81)
8. `.github/workflows/scheduled-campaign-calendar.yml` (line 81)
9. `.github/workflows/scheduled-seo-aeo-audit.yml` (line 92)

## Non-Goals

- Adding `test` as a required status check in rulesets (separate concern, tracked in #780 Related section)
- Removing `[skip ci]` from commit messages (separate concern)
- Removing CLA allowlist for `github-actions[bot]` (separate concern)
- Changing the PR-based commit pattern itself (working correctly)

## Acceptance Criteria

- [ ] All 9 workflows use `gh pr merge "$BRANCH" --squash --auto` without fallback
- [ ] No instances of `|| gh pr merge` remain in any workflow file
- [ ] Each workflow retains its Discord failure notification step (already present via `if: failure()`)
- [ ] Existing `[skip ci]` commit messages and synthetic `cla-check` status patterns are preserved unchanged

## Test Scenarios

- Given auto-merge is enabled and `cla-check` is satisfied, when the workflow runs `gh pr merge --squash --auto`, then auto-merge is queued and the PR merges after checks pass
- Given auto-merge is disabled on the repo, when the workflow runs `gh pr merge --squash --auto`, then the step fails, the PR stays open, and Discord failure notification fires
- Given `cla-check` synthetic status was not posted (bug in earlier step), when the workflow runs `gh pr merge --squash --auto`, then auto-merge is queued and waits for the check (instead of bypassing it)

## SpecFlow Analysis

### Edge Cases Verified

1. **Race condition: `--auto` queued but repo settings change before merge** -- GitHub handles this; auto-merge dequeues if requirements change. No fallback needed.
2. **Concurrent workflow runs creating PRs on same branch prefix** -- Each workflow uses unique branch names with timestamps (`ci/weekly-analytics-$(date -u +%Y-%m-%d)`). No conflict.
3. **`--auto` returns non-zero but merge succeeds anyway** -- Not possible; `--auto` either queues the merge (exit 0) or fails (exit non-zero). The merge itself is async.
4. **Network transient failure on `gh pr merge --auto`** -- Step fails, PR stays open, Discord notifies. This is the correct behavior -- a retry can be triggered manually via `workflow_dispatch`.

### Configuration Preconditions

- [x] `allow_auto_merge: true` on repo (verified)
- [x] CLA Required ruleset (ID 13304872) with `cla-check` as only required status check (verified)
- [x] No `test` or other required status checks in rulesets (verified)
- [x] All workflows post synthetic `cla-check` status before calling `gh pr merge` (verified)

## Context

- Found by: security-sentinel agent during #772 review
- Related PRs: #771 (content publisher migration), #774 (7 workflow migrations), #772 (original migration PR)
- Related issues: #780 (this issue)
- Related learnings: `2026-03-19-github-actions-bypass-actor-not-feasible.md`, `2026-03-19-content-publisher-cla-ruleset-push-rejection.md`
- Constitution reference: "Use `gh pr merge <number> --squash --auto` instead of `gh pr checks --watch` followed by `gh pr merge`"

## References

- GitHub auto-merge documentation: https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request
- Repository rulesets API: `gh api repos/jikig-ai/soleur/rulesets`
- AGENTS.md hard rule: "Use `gh pr merge <number> --squash --auto`, then poll"
