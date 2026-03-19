---
title: Add integration_id to CLA Required Ruleset Status Check
type: chore
date: 2026-03-19
---

# Add integration_id to CLA Required Ruleset Status Check

## Overview

Harden the CLA Required repository ruleset (ID 13304872) by adding `integration_id` to the `cla-check` required status check and adding `github-actions[bot]` to the bypass actors list. This eliminates the current soft-bypass vulnerability where any actor with `statuses: write` can satisfy the CLA check by posting a synthetic success status.

## Problem Statement / Motivation

The CLA Required ruleset currently requires a `cla-check` status but does not specify an `integration_id`:

```json
"required_status_checks": [
  { "context": "cla-check" }
]
```

This means any actor with `statuses: write` permission can satisfy the CLA check by posting a synthetic success status via the GitHub Statuses API. While this is low-risk in a single-developer repo, it weakens CLA enforcement to convention-only.

Additionally, bot workflows (`scheduled-weekly-analytics.yml`, `scheduled-content-publisher.yml`) currently post synthetic `cla-check` statuses to bypass the ruleset for automated PRs. This is a workaround that should be replaced by proper ruleset bypass configuration.

Found during PR #771 review by the security-sentinel agent.

## Current State

### Ruleset Configuration

```json
{
  "id": 13304872,
  "name": "CLA Required",
  "rules": [{
    "type": "required_status_checks",
    "parameters": {
      "required_status_checks": [
        { "context": "cla-check" }
      ]
    }
  }],
  "bypass_actors": [
    { "actor_id": null, "actor_type": "OrganizationAdmin", "bypass_mode": "always" },
    { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" },
    { "actor_id": 262318, "actor_type": "Integration", "bypass_mode": "always" },
    { "actor_id": 1236702, "actor_type": "Integration", "bypass_mode": "always" }
  ]
}
```

### How CLA Check Currently Works

- **Human PRs:** The CLA Assistant workflow (`.github/workflows/cla.yml`) runs a GitHub Actions job named `cla-check`. This creates a **check run** under the `github-actions` app (ID 15368).
- **Bot PRs:** `scheduled-weekly-analytics.yml` and `scheduled-content-publisher.yml` post a synthetic **commit status** with `context: cla-check` via the Statuses API (also under `github-actions` app because they use `GITHUB_TOKEN`).

### Key Technical Finding

Both the real CLA check and synthetic bot statuses are created by the `github-actions` app (ID 15368). The `contributor-assistant/github-action` runs as a GitHub Actions workflow, so GitHub reports it under `github-actions`, not under a separate CLA-specific app. This means `integration_id: 15368` restricts the check to GitHub Actions workflows but does not distinguish between the real CLA workflow and synthetic statuses posted by other workflows.

### Existing Bypass Actors

| actor_id | actor_type | Identity |
|----------|-----------|----------|
| null | OrganizationAdmin | Org admins |
| 5 | RepositoryRole | Admin role |
| 262318 | Integration | Unknown (likely a previously installed app) |
| 1236702 | Integration | Claude app |

## Proposed Solution

### Two-Part Fix

**Part 1: Add `integration_id` to `cla-check` required status**

Set `integration_id: 15368` (the `github-actions` app) on the `cla-check` required status check. This prevents any non-GitHub-Actions actor from spoofing the CLA check via the Statuses API. While it does not distinguish between different GitHub Actions workflows, it reduces the attack surface significantly -- only actors with write access to the repo's workflows can create a passing check.

**Part 2: Add `github-actions[bot]` to bypass actors and remove synthetic statuses**

Add the `github-actions` app (ID 15368) as a bypass actor on the CLA Required ruleset with `bypass_mode: "pull_request"`. This allows bot PRs created by GitHub Actions workflows to bypass the CLA check entirely, eliminating the need for synthetic `cla-check` statuses.

Then remove the synthetic `cla-check` status posting from both bot workflows.

### Why Bypass Instead of Synthetic Status

1. **Cleaner:** Bypass is the intended mechanism for exempting actors from rulesets
2. **Auditable:** GitHub's ruleset bypass log shows which actors bypassed and when
3. **Less fragile:** No risk of the synthetic status being posted before the PR is created, or failing silently
4. **Eliminates the vulnerability:** With bypass, bot PRs never need to satisfy `cla-check`, so there's no synthetic status to spoof

### Bypass Mode Choice

Use `bypass_mode: "pull_request"` (not `"always"`). This means github-actions can bypass when acting via pull requests but not when pushing directly. This preserves the CLA check for any future scenario where a workflow might push directly to main.

**Risk assessment:** All current bot workflows already use the PR-based commit pattern (post-#771), so `"pull_request"` mode is sufficient. The `"always"` mode would also work but is unnecessarily permissive.

## Technical Considerations

### GitHub API Call

```bash
# Update ruleset via PUT
gh api repos/jikig-ai/soleur/rulesets/13304872 \
  --method PUT \
  --input ruleset-update.json
```

The JSON payload must include the complete ruleset configuration (not just the changed fields), because the PUT endpoint replaces the entire ruleset.

### Workflow Changes

Two workflows need the synthetic `cla-check` status removed:

1. `.github/workflows/scheduled-weekly-analytics.yml` (lines 104-108)
2. `.github/workflows/scheduled-content-publisher.yml` (lines 88-92)

The `statuses: write` permission can also be removed from both workflows since it was only needed for the synthetic status. However, keep it if any other step requires it.

### Issue #772 Interaction

Issue #772 tracks 7 other Claude Code agent workflows that still use `git push origin main` and will eventually need the PR-based commit pattern. When those workflows are migrated (per #772), they will NOT need synthetic `cla-check` statuses if the bypass actor is already in place. This fix simplifies #772's implementation.

### Rollback

If the bypass causes issues, revert by:
1. Removing the `github-actions` bypass actor from the ruleset
2. Re-adding the synthetic `cla-check` status to both bot workflows
3. Removing the `integration_id` from the required status check

All three steps are reversible via the GitHub API without code changes.

## Implementation Phases

### Phase 1: Update Ruleset via GitHub API

Update the CLA Required ruleset (ID 13304872) via the GitHub Rulesets API:

1. Add `integration_id: 15368` to the `cla-check` required status check
2. Add `{ "actor_id": 15368, "actor_type": "Integration", "bypass_mode": "pull_request" }` to `bypass_actors`

**File:** No file changes -- this is a GitHub API call only.

### Phase 2: Remove Synthetic CLA Status from Bot Workflows

**Modify:** `.github/workflows/scheduled-weekly-analytics.yml`
- Remove the 4-line block that posts synthetic `cla-check` status (lines 101-108)
- Remove `statuses: write` from permissions if no longer needed

**Modify:** `.github/workflows/scheduled-content-publisher.yml`
- Remove the 5-line block that posts synthetic `cla-check` status (lines 85-92)
- Remove `statuses: write` from permissions if no longer needed

### Phase 3: Verify

1. Trigger `scheduled-weekly-analytics.yml` manually (`gh workflow run`)
2. Verify the bot PR auto-merges without needing a `cla-check` status
3. Open a test human PR and verify the CLA check still runs and blocks merge without a signature

## Acceptance Criteria

- [ ] CLA Required ruleset `cla-check` has `integration_id: 15368`
- [ ] CLA Required ruleset `bypass_actors` includes `github-actions` (ID 15368) with `bypass_mode: "pull_request"`
- [ ] `scheduled-weekly-analytics.yml` no longer posts synthetic `cla-check` status
- [ ] `scheduled-content-publisher.yml` no longer posts synthetic `cla-check` status
- [ ] Bot PR from `scheduled-weekly-analytics.yml` auto-merges without CLA check (bypass active)
- [ ] Human PR still requires CLA signature via the CLA Assistant workflow
- [ ] `statuses: write` permission removed from both bot workflows (if no longer needed)

## Test Scenarios

- Given a bot PR from `scheduled-weekly-analytics.yml`, when the PR is created, then it auto-merges without needing a `cla-check` status (bypass active)
- Given a human PR from an unsigned contributor, when the CLA check runs, then the PR is blocked until the CLA is signed
- Given a human PR from a signed contributor, when the CLA check runs, then the PR passes immediately
- Given an actor with `statuses: write` but no GitHub Actions access, when they try to post a synthetic `cla-check` status, then the ruleset rejects it because `integration_id` does not match
- Given the CLA Required ruleset, when inspected via API, then `integration_id: 15368` is present on `cla-check` and `github-actions` (15368) is in `bypass_actors`

## Dependencies & Risks

| Risk | Mitigation |
|---|---|
| `bypass_mode: "pull_request"` doesn't work for GitHub Actions bot | Verified: all bot workflows use PR-based pattern post-#771. Fallback: switch to `"always"` |
| Removing synthetic status breaks bot PRs before bypass is active | Apply Phase 1 (ruleset update) BEFORE Phase 2 (workflow changes). Ordering is critical. |
| `integration_id: 15368` blocks legitimate CLA check | The CLA workflow runs as github-actions (15368), so integration_id: 15368 matches correctly |
| Unknown bypass actor 262318 may be stale | Out of scope for this issue. File a separate cleanup issue if needed. |

## References & Research

### Internal References

- Issue: #773 (this fix)
- Issue: #772 (related: 7 agent workflows needing PR-based commit pattern)
- PR: #771 (content publisher fix that surfaced this issue)
- Learning: `knowledge-base/learnings/2026-03-19-content-publisher-cla-ruleset-push-rejection.md`
- Learning: `knowledge-base/project/learnings/2026-02-26-cla-system-implementation-and-gdpr-compliance.md`
- Plan: `knowledge-base/project/plans/2026-02-26-feat-cla-contributor-agreements-plan.md`
- CLA workflow: `.github/workflows/cla.yml`
- Bot workflows: `.github/workflows/scheduled-weekly-analytics.yml`, `.github/workflows/scheduled-content-publisher.yml`

### External References

- GitHub Rulesets API: https://docs.github.com/en/rest/repos/rules
- GitHub Apps reference (github-actions app ID 15368): verified via `gh api /apps/github-actions`
- CLA Assistant Action: https://github.com/contributor-assistant/github-action

### Related Work

- Issue: #773
- Issue: #772
- PR: #771
