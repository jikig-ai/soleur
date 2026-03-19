---
title: Add integration_id to CLA Required Ruleset Status Check
type: chore
date: 2026-03-19
---

## Enhancement Summary

**Deepened on:** 2026-03-19
**Sections enhanced:** 6 (Proposed Solution, Technical Considerations, Implementation Phases, Acceptance Criteria, Test Scenarios, Dependencies & Risks)
**Research sources:** GitHub Rulesets API docs, GitHub Community Discussions (#86534, #144508, #162623, #43460), GitHub Changelog, learnings (CLA push rejection, CLA GDPR compliance, auto-push vs PR pattern)

### Key Improvements
1. **Critical risk discovered:** Auto-merge (`gh pr merge --auto`) may not respect bypass actors for required status checks -- this is a known GitHub limitation with rulesets. The plan is restructured to a phased approach that keeps synthetic statuses until bypass is verified working.
2. **PUT payload format documented:** The GitHub API `PUT /rulesets/{id}` replaces the entire ruleset. A complete JSON payload is now provided to prevent accidental field loss.
3. **`bypass_mode: "always"` recommended over `"pull_request"`:** The `"pull_request"` mode means the actor can only bypass when merging PRs, but `gh pr merge` (the immediate non-auto path) needs bypass to work for the merge command itself, not just for the PR creation. Using `"always"` is safer and matches the existing bypass actors' configuration.

### New Considerations Discovered
- GitHub rulesets bypass actors do NOT skip status checks -- checks still run and may fail, but bypass actors can merge anyway. However, `gh pr merge --auto` waits for checks to pass regardless of bypass status.
- The `security_reminder_hook` will trigger when editing `.github/workflows/*.yml` files. This is advisory only, but the agent should expect and re-attempt edits.
- The existing bot workflows use `gh pr merge --squash --auto || gh pr merge --squash` with a fallback. The non-auto fallback is the path that bypass enables.

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
      "strict_required_status_checks_policy": false,
      "do_not_enforce_on_create": false,
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

### Research Insight: Check Run vs Commit Status

Verified via API inspection of actual PRs:
- **PR #769 (human):** `cla-check` appears as a **check run** (via `GET /commits/{sha}/check-runs`) with `app.id: 15368`, `app.slug: github-actions`
- **PR #633 (bot):** `cla-check` appears as a **commit status** (via `GET /commits/{sha}/status`) with no creator metadata

Both satisfy the ruleset's `required_status_checks` because GitHub treats check runs and commit statuses as equivalent for status check matching purposes.

### Existing Bypass Actors

| actor_id | actor_type | Identity | Verified |
|----------|-----------|----------|----------|
| null | OrganizationAdmin | Org admins | Yes (built-in) |
| 5 | RepositoryRole | Admin role | Yes (built-in) |
| 262318 | Integration | Unknown (likely a previously installed app) | No -- could not resolve via API |
| 1236702 | Integration | Claude app | Yes (`gh api /apps/claude` -> ID 1236702; org installation 107541094) |

## Proposed Solution

### Three-Phase Fix (Revised from Two-Part)

The original plan proposed removing synthetic cla-check statuses from bot workflows in the same PR as adding bypass. Research uncovered a critical risk: **GitHub auto-merge (`gh pr merge --auto`) may not respect bypass actors for required status checks.** This is a [known limitation](https://github.com/orgs/community/discussions/162623) with rulesets that has no ETA for resolution.

The revised approach uses a phased strategy:

**Phase 1 (This PR): Ruleset hardening + bypass actor**
- Add `integration_id: 15368` to `cla-check` required status check
- Add `github-actions` (ID 15368) to bypass actors with `bypass_mode: "always"`
- Keep synthetic `cla-check` statuses in bot workflows (safety net)

**Phase 2 (Follow-up PR): Remove synthetic statuses after verification**
- After Phase 1 merges, trigger a bot workflow manually
- If auto-merge works WITHOUT synthetic status -> remove synthetic statuses in a follow-up PR
- If auto-merge fails WITHOUT synthetic status -> keep synthetic statuses, bypass provides defense-in-depth only

### Part 1: Add `integration_id` to `cla-check` required status

Set `integration_id: 15368` (the `github-actions` app) on the `cla-check` required status check. This prevents any non-GitHub-Actions actor from spoofing the CLA check via the Statuses API. While it does not distinguish between different GitHub Actions workflows, it reduces the attack surface significantly -- only actors with write access to the repo's workflows can create a passing check.

### Research Insights: integration_id Behavior

- The `integration_id` field is optional in `required_status_checks`. When set, GitHub verifies that the status was posted by the specified app.
- The GitHub API expects `integration_id` as a numeric value (not a string).
- The app (ID 15368) must be installed in the repository with `statuses:write` permission AND must have recently submitted a check run for the specified context. The CLA workflow already satisfies this.
- Per [Terraform provider issue #2317](https://github.com/integrations/terraform-provider-github/issues/2317), the `integration_id` value can behave inconsistently in some edge cases. This is a Terraform-specific issue and does not affect the REST API.

### Part 2: Add `github-actions[bot]` to bypass actors

Add the `github-actions` app (ID 15368) as a bypass actor on the CLA Required ruleset with `bypass_mode: "always"`.

### Research Insights: Bypass Behavior

**Bypass does NOT skip checks -- it allows merge despite failures.** Per [GitHub Community Discussion #86534](https://github.com/orgs/community/discussions/86534), bypass actors' checks still run and may fail, but the actor gains permission to merge despite failures. The selected actor "can then choose to bypass any branch protections and merge that pull request."

**`bypass_mode: "always"` vs `"pull_request"`:** Use `"always"` (not `"pull_request"`). Rationale:
1. All existing bypass actors use `"always"` -- consistency matters
2. `"pull_request"` mode restricts bypass to "when acting via pull requests," but the merge command itself may not be recognized as "acting via PR" depending on GitHub's internal evaluation
3. Bot workflows already use the PR-based pattern (post-#771), so `"always"` does not create new risk -- direct pushes from `github-actions[bot]` would still be blocked by the `Force Push Prevention` ruleset (ID 13044280)

**Auto-merge compatibility risk:** [Discussion #162623](https://github.com/orgs/community/discussions/162623) documents that `gh pr merge --auto` may not respect bypass actors when rulesets (not classic branch protection) are used. Auto-merge waits for all required checks to pass, regardless of bypass status. The existing bot workflows have a fallback path (`|| gh pr merge --squash`) that performs an immediate merge, which SHOULD work with bypass. But this needs verification.

### Part 3: Keep synthetic statuses (for now)

Do NOT remove synthetic `cla-check` statuses from bot workflows in this PR. The synthetic statuses serve as a safety net: even if bypass does not work with auto-merge, the synthetic status ensures the CLA check passes and auto-merge proceeds.

Removing synthetic statuses is deferred to Phase 2 after the bypass is verified to work with the actual bot workflow merge pattern.

### Why This Phased Approach

1. **No breaking changes:** Bot workflows continue to work exactly as before
2. **Security improvement:** `integration_id` prevents non-GitHub-Actions spoofing immediately
3. **Defense-in-depth:** Bypass provides an additional path for bot PRs, independent of synthetic statuses
4. **Testable:** Phase 2 can be tested without risk to production workflows

## Technical Considerations

### GitHub API Call -- Complete PUT Payload

The `PUT /repos/{owner}/{repo}/rulesets/{id}` endpoint **replaces the entire ruleset**. All existing fields must be included in the payload, or they will be removed. Here is the complete payload:

```json
{
  "name": "CLA Required",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "exclude": [],
      "include": ["~DEFAULT_BRANCH"]
    }
  },
  "rules": [
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "do_not_enforce_on_create": false,
        "required_status_checks": [
          {
            "context": "cla-check",
            "integration_id": 15368
          }
        ]
      }
    }
  ],
  "bypass_actors": [
    { "actor_id": null, "actor_type": "OrganizationAdmin", "bypass_mode": "always" },
    { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" },
    { "actor_id": 262318, "actor_type": "Integration", "bypass_mode": "always" },
    { "actor_id": 1236702, "actor_type": "Integration", "bypass_mode": "always" },
    { "actor_id": 15368, "actor_type": "Integration", "bypass_mode": "always" }
  ]
}
```

### Research Insight: API Execution

```bash
# Write the JSON payload to a temp file, then pass via --input
# This avoids shell escaping issues with nested JSON
cat > /tmp/ruleset-update.json << 'PAYLOAD'
{...the JSON above...}
PAYLOAD

gh api repos/jikig-ai/soleur/rulesets/13304872 \
  --method PUT \
  --input /tmp/ruleset-update.json
```

Verify after update:
```bash
gh api repos/jikig-ai/soleur/rulesets/13304872 | python3 -m json.tool
```

### Workflow Changes (Phase 2 Only -- NOT in this PR)

Two workflows have synthetic `cla-check` status blocks that would be removed in Phase 2:

1. `.github/workflows/scheduled-weekly-analytics.yml` (lines 101-108):
   ```yaml
   # Set CLA check status to success -- bot PRs have no human
   # contributor to sign a CLA, and the CLA Required ruleset
   # blocks auto-merge without this status.
   SHA=$(git rev-parse HEAD)
   gh api "repos/${{ github.repository }}/statuses/$SHA" \
     -f state=success \
     -f context=cla-check \
     -f description="CLA not required for automated PRs"
   ```

2. `.github/workflows/scheduled-content-publisher.yml` (lines 85-92): same pattern.

### Research Insight: security_reminder_hook

Per learning `2026-03-18-security-reminder-hook-blocks-workflow-edits.md`, editing `.github/workflows/*.yml` files triggers the `PreToolUse:Edit` hook which outputs an error-formatted warning about GitHub Actions injection patterns. This is advisory only and does not block the edit, but the agent should expect the warning and re-attempt if the edit appears to not apply. Verify edits by re-reading the file.

### Issue #772 Interaction

Issue #772 tracks 7 other Claude Code agent workflows that still use `git push origin main` and will eventually need the PR-based commit pattern. When those workflows are migrated (per #772), they will benefit from the bypass actor added in this PR. If bypass works with auto-merge (verified in Phase 2), those workflows will not need synthetic `cla-check` statuses at all. If bypass does not work with auto-merge, those workflows will need the same synthetic status pattern.

### Research Insight: GITHUB_TOKEN Cascade Limitation

Per learning `2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md`, PRs created by `GITHUB_TOKEN` do NOT trigger `pull_request` or `pull_request_target` events. This means the CLA workflow (`cla.yml`) will NOT run on bot PRs. The `cla-check` check run simply never appears -- which is different from appearing and failing. The bypass actor ensures the bot PR can merge despite the missing check.

### Rollback

If the bypass or integration_id causes issues, revert by:
1. Run `gh api repos/jikig-ai/soleur/rulesets/13304872 --method PUT --input` with the original payload (remove `integration_id` from `cla-check`, remove 15368 from `bypass_actors`)
2. No workflow changes needed since synthetic statuses are retained in Phase 1

All steps are reversible via the GitHub API without code changes.

## Implementation Phases

### Phase 1: Update Ruleset via GitHub API (This PR)

Update the CLA Required ruleset (ID 13304872) via the GitHub Rulesets API:

1. Construct the complete PUT payload (see Technical Considerations above)
2. Add `integration_id: 15368` to the `cla-check` required status check
3. Add `{ "actor_id": 15368, "actor_type": "Integration", "bypass_mode": "always" }` to `bypass_actors`
4. Execute the API call and verify the response
5. Verify with a separate GET request to confirm both changes applied

**Files changed:** None -- this is a GitHub API call only. The PR will contain only the plan/tasks artifacts.

### Phase 2: Verify Bypass Works (Post-Merge)

1. Trigger `scheduled-weekly-analytics.yml` manually (`gh workflow run`)
2. Observe whether the bot PR auto-merges. Two outcomes:
   - **Auto-merge succeeds:** The `cla-check` check run is missing (CLA workflow doesn't trigger on GITHUB_TOKEN PRs), but bypass allows merge. Proceed to Phase 3.
   - **Auto-merge stalls:** The fallback `gh pr merge --squash` (without `--auto`) should attempt immediate merge. If this succeeds, the bypass works for immediate merges but not auto-merge. File a note in #773.
   - **Both fail:** Bypass does not work as expected. The synthetic status still satisfies the check, so no breakage. Investigate and update the plan.
3. Open a test human PR and verify the CLA check still runs and blocks merge without a signature

### Phase 3: Remove Synthetic Statuses (Follow-up PR, if bypass verified)

**Only proceed if Phase 2 confirms bypass works with bot auto-merge.**

**Modify:** `.github/workflows/scheduled-weekly-analytics.yml`
- Remove the synthetic `cla-check` status block (lines 101-108)
- Remove `statuses: write` from permissions

**Modify:** `.github/workflows/scheduled-content-publisher.yml`
- Remove the synthetic `cla-check` status block (lines 85-92)
- Remove `statuses: write` from permissions

## Acceptance Criteria

### Phase 1 (This PR)
- [ ] CLA Required ruleset `cla-check` has `integration_id: 15368`
- [ ] CLA Required ruleset `bypass_actors` includes `github-actions` (ID 15368) with `bypass_mode: "always"`
- [ ] Existing bypass actors preserved (OrganizationAdmin, RepositoryRole 5, Integration 262318, Integration 1236702)
- [ ] Human PR still requires CLA signature via the CLA Assistant workflow
- [ ] Bot workflows continue to work (synthetic statuses still in place)

### Phase 2 (Post-Merge Verification)
- [ ] Bot PR from `scheduled-weekly-analytics.yml` auto-merges (with or without synthetic status)
- [ ] Bypass behavior documented (works with auto-merge, or only with immediate merge)

### Phase 3 (Follow-up PR, conditional)
- [ ] `scheduled-weekly-analytics.yml` no longer posts synthetic `cla-check` status
- [ ] `scheduled-content-publisher.yml` no longer posts synthetic `cla-check` status
- [ ] `statuses: write` permission removed from both bot workflows
- [ ] Bot PRs continue to auto-merge via bypass

## Test Scenarios

- Given the CLA Required ruleset, when inspected via API (`gh api repos/jikig-ai/soleur/rulesets/13304872`), then `integration_id: 15368` is present on `cla-check` and `github-actions` (15368) is in `bypass_actors`
- Given a human PR from an unsigned contributor, when the CLA check runs, then the PR is blocked until the CLA is signed
- Given a human PR from a signed contributor, when the CLA check runs, then it passes immediately
- Given a bot PR from `scheduled-weekly-analytics.yml` (with synthetic status), when the PR is created, then it auto-merges normally (no regression)
- Given a bot PR from a workflow WITHOUT synthetic status, when the PR is created, then the bypass actor allows merge (Phase 2 test)
- Given an external actor with `statuses: write` but no GitHub Actions access, when they try to post a synthetic `cla-check` status, then the ruleset rejects it because `integration_id` does not match

## Dependencies & Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Auto-merge does not respect bypass actors (known GitHub limitation) | Medium | Low (synthetic statuses retained as safety net) | Phase 1 keeps synthetic statuses. Phase 3 only removes them after verification. |
| `integration_id: 15368` blocks legitimate CLA check | Very Low | High | The CLA workflow runs as github-actions (15368), so integration_id: 15368 matches correctly. Verified via API inspection of PR #769. |
| PUT payload missing a field drops existing config | Low | High | Complete payload documented in Technical Considerations with all existing fields preserved. Verify with GET after PUT. |
| `bypass_mode: "always"` is too permissive | Very Low | Low | github-actions[bot] direct pushes are separately blocked by Force Push Prevention ruleset (ID 13044280). `"always"` only applies to the CLA Required ruleset. |
| Unknown bypass actor 262318 may be stale | N/A | None | Out of scope for this issue. File a separate cleanup issue if needed. |
| security_reminder_hook blocks workflow edits | Certain | None (advisory only) | Expect the warning, re-attempt edit, verify by re-reading file. Only relevant in Phase 3. |

## References & Research

### Internal References

- Issue: #773 (this fix)
- Issue: #772 (related: 7 agent workflows needing PR-based commit pattern)
- PR: #771 (content publisher fix that surfaced this issue)
- Learning: `knowledge-base/learnings/2026-03-19-content-publisher-cla-ruleset-push-rejection.md`
- Learning: `knowledge-base/project/learnings/2026-02-26-cla-system-implementation-and-gdpr-compliance.md`
- Learning: `knowledge-base/project/learnings/2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md`
- Learning: `knowledge-base/learnings/2026-03-18-security-reminder-hook-blocks-workflow-edits.md`
- Plan: `knowledge-base/project/plans/2026-02-26-feat-cla-contributor-agreements-plan.md`
- CLA workflow: `.github/workflows/cla.yml`
- Bot workflows: `.github/workflows/scheduled-weekly-analytics.yml`, `.github/workflows/scheduled-content-publisher.yml`

### External References

- [GitHub Rulesets API](https://docs.github.com/en/rest/repos/rules)
- [GitHub Available Rules for Rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
- [GitHub Apps reference](https://docs.github.com/en/rest/apps) (github-actions app ID 15368, verified via `gh api /apps/github-actions`)
- [CLA Assistant Action](https://github.com/contributor-assistant/github-action)
- [Discussion #86534: Bypass list not applying to status checks](https://github.com/orgs/community/discussions/86534)
- [Discussion #162623: Auto-merge doesn't work with rulesets](https://github.com/orgs/community/discussions/162623)
- [Discussion #144508: Bypass required status checks in rulesets](https://github.com/orgs/community/discussions/144508)
- [Discussion #43460: Allow specified actors to bypass required status checks](https://github.com/orgs/community/discussions/43460)
- [Terraform provider issue #2317: integration_id inconsistency](https://github.com/integrations/terraform-provider-github/issues/2317)

### Related Work

- Issue: #773
- Issue: #772
- PR: #771
