---
title: "chore: remove stale bypass actor 262318 from CLA Required ruleset"
type: fix
date: 2026-03-19
semver: patch
---

# chore: remove stale bypass actor 262318 from CLA Required ruleset

## Overview

The CLA Required ruleset (ID `13304872`) in `jikig-ai/soleur` contains four bypass actors. One of them -- `{ "actor_id": 262318, "actor_type": "Integration", "bypass_mode": "always" }` -- cannot be identified via any GitHub API endpoint and is not present in the organization's installation list. This actor should be removed to eliminate an unauditable bypass path on a security-critical ruleset.

## Problem Statement

An unidentifiable integration with `bypass_mode: "always"` on the CLA enforcement ruleset is a security hygiene concern. The actor:

- Returns 404 from `GET /apps/262318` (the canonical GitHub App lookup endpoint)
- Does not appear in `GET /orgs/jikig-ai/installations` (only `linear` ID 42984725 and `claude` ID 107541094 are installed)
- Was present when the ruleset was created on 2026-02-27 -- it was not introduced by any recent PR
- Was flagged during the security review of PR #775, which hardened the `cla-check` status with `integration_id: 15368`
- The older autonomous bugfix plan (2026-03-05) incorrectly assumed 262318 was a Claude App ID; the March 19 investigation confirmed Claude is ID 1236702

The most likely explanation is that 262318 was a GitHub App that was once installed on the org/repo (e.g., a CLA-related app, CI tool, or similar), was later uninstalled or deleted, and its ghost entry persisted in the ruleset's bypass_actors array. GitHub does not automatically prune bypass actors when apps are uninstalled.

## Proposed Solution

Remove the stale bypass actor entry via the GitHub Rulesets API. This is a single `PUT` call that replaces the entire ruleset, preserving all other fields.

### API Call

Use `gh api PUT /repos/jikig-ai/soleur/rulesets/13304872` with the complete ruleset payload, identical to the current state except with the `262318` entry removed from `bypass_actors`.

**Current bypass_actors:**

```json
[
  { "actor_id": null, "actor_type": "OrganizationAdmin", "bypass_mode": "always" },
  { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" },
  { "actor_id": 262318, "actor_type": "Integration", "bypass_mode": "always" },
  { "actor_id": 1236702, "actor_type": "Integration", "bypass_mode": "always" }
]
```

**Proposed bypass_actors:**

```json
[
  { "actor_id": null, "actor_type": "OrganizationAdmin", "bypass_mode": "always" },
  { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" },
  { "actor_id": 1236702, "actor_type": "Integration", "bypass_mode": "always" }
]
```

### Complete PUT Payload

The `PUT` endpoint replaces the entire ruleset. All fields must be included:

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
    { "actor_id": 1236702, "actor_type": "Integration", "bypass_mode": "always" }
  ]
}
```

## Technical Considerations

### Risk: Breaking bot workflows

The Claude app (ID 1236702) is the only Integration bypass actor that matters for bot workflows. Bot workflows authenticate as `github-actions[bot]` (app ID 15368), which satisfies the `integration_id: 15368` constraint on the `cla-check` status check -- they do not rely on bypass actors at all. The Claude app bypass is for `claude-code-action` workflows. Removing the ghost entry 262318 removes no active functionality.

### Risk: PUT replaces the entire ruleset

The GitHub Rulesets API `PUT` endpoint is a full replacement, not a patch. Omitting any field causes it to be removed. The payload above was constructed by reading the current ruleset state and removing only the target entry.

### Rollback plan

If removal causes unexpected issues, re-add the entry:

```bash
gh api --method PUT /repos/jikig-ai/soleur/rulesets/13304872 \
  --input <payload-with-262318-restored.json>
```

### SpecFlow edge cases

- **What if 262318 is still active via a path not visible in the installations API?** GitHub does not offer an endpoint to look up arbitrary app IDs by number. `GET /apps/{id}` returns 404, which means the app is either deleted or private. If private but still active, removal would cause that app's PRs to no longer bypass CLA. However, no PRs in the repository's history show any activity from an app matching this ID.
- **What if GitHub re-uses app IDs?** GitHub app IDs are globally unique and monotonically increasing. They are not recycled. A deleted app's ID remains permanently retired.

## Acceptance Criteria

- [ ] Actor 262318 removed from CLA Required ruleset bypass_actors
- [ ] All other ruleset fields unchanged (verified via `gh api GET /repos/jikig-ai/soleur/rulesets/13304872`)
- [ ] Remaining bypass actors verified: OrganizationAdmin (null), RepositoryRole (5), Claude Integration (1236702)
- [ ] Bot workflow verified: trigger a bot workflow (e.g., analytics) and confirm auto-merge still works
- [ ] Human PR verified: open a test PR and confirm CLA check still triggers

## Test Scenarios

- Given the CLA Required ruleset has actor 262318 removed, when a human opens a PR, then the `cla-check` status check is still required and triggers normally
- Given the CLA Required ruleset has actor 262318 removed, when a bot workflow creates a PR with synthetic `cla-check` status, then auto-merge succeeds
- Given the CLA Required ruleset has actor 262318 removed, when `claude-code-action` creates a PR, then CLA is bypassed via the remaining Claude bypass actor (1236702)
- Given the ruleset was updated via PUT, when the ruleset is read back via GET, then all fields match the intended state (name, enforcement, conditions, rules, bypass_actors)

## Investigation Summary

| Investigation Step | Result |
|---|---|
| `GET /apps/262318` | 404 Not Found |
| `GET /orgs/jikig-ai/installations` | Only linear (42984725) and claude (107541094) |
| Cross-reference with known app IDs | Not CLA Assistant (128106), not Dependabot (29110), not Renovate (2740), not Codecov (254) |
| Git history search for "262318" | Only appears in plans and todos referencing this investigation |
| Ruleset creation date | 2026-02-27 -- actor was present from creation |
| Claude app confirmed | ID 1236702 (via `GET /apps/claude`), installation 107541094 |

## Non-goals

- Contacting GitHub support to identify the app (the 404 response is sufficient evidence; support inquiry would delay a simple cleanup)
- Auditing other rulesets for stale actors (Force Push Prevention has no bypass actors)
- Modifying any ruleset fields other than bypass_actors

## References

- Issue: [#779](https://github.com/jikig-ai/soleur/issues/779)
- Related PR: [#775](https://github.com/jikig-ai/soleur/pulls/775) (added `integration_id` to CLA check)
- Related issue: [#773](https://github.com/jikig-ai/soleur/issues/773) (CLA check security gap)
- Learning: `knowledge-base/learnings/2026-03-19-github-actions-bypass-actor-not-feasible.md`
- Learning: `knowledge-base/learnings/2026-03-19-content-publisher-cla-ruleset-push-rejection.md`
- Prior plan: `knowledge-base/plans/2026-03-19-chore-cla-ruleset-integration-id-plan.md`
- GitHub Rulesets API: [PUT /repos/{owner}/{repo}/rulesets/{id}](https://docs.github.com/en/rest/repos/rules#update-a-repository-ruleset)
