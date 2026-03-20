---
title: "chore: remove stale bypass actor 262318 from CLA Required ruleset"
type: chore
date: 2026-03-19
semver: patch
---

# chore: remove stale bypass actor 262318 from CLA Required ruleset

## Enhancement Summary

**Deepened on:** 2026-03-19
**Sections enhanced:** 4 (Proposed Solution, Technical Considerations, Acceptance Criteria, Test Scenarios)
**Research sources:** GitHub REST API docs (Context7), Terraform provider issues #2269/#2952/#2179, prior PR #775 execution log

### Key Improvements

1. Corrected API semantics: PUT endpoint fields are all Optional (partial update possible), but full payload is safer and matches the proven pattern from PR #775
2. Added known-bug context: Terraform provider had bypass_actors deletion bugs (go-github client issue, fixed in v63.0.0) -- not applicable to direct REST API calls via `gh api`
3. Added concrete execution script with temp-file pattern and response verification
4. Added GITHUB_TOKEN cascade limitation as a verification consideration

### New Considerations Discovered

- The PUT endpoint supports partial updates (all fields Optional per GitHub docs), but array fields like `bypass_actors` are replaced wholesale when included -- sending the field with 3 entries replaces the previous 4 entries
- Terraform provider issues #2269, #2952, and #2179 document bypass_actors deletion bugs, but these are in the `go-github` Go client library (empty array serialization), not in the REST API itself
- The `gh api --method PUT --input /tmp/file.json` pattern was successfully used in PR #775 to modify this exact ruleset -- proven path

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

Remove the stale bypass actor entry via the GitHub Rulesets API. This is a single `PUT` call with the `bypass_actors` array set to the desired state (3 entries instead of 4).

### API Call

Use `gh api --method PUT --input /tmp/ruleset-update.json repos/jikig-ai/soleur/rulesets/13304872` with the complete ruleset payload, identical to the current state except with the `262318` entry removed from `bypass_actors`. This is the same pattern successfully used in PR #775 to modify this exact ruleset.

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

The `PUT` endpoint accepts all fields as Optional (per [GitHub REST API docs](https://docs.github.com/en/rest/repos/rules#update-a-repository-ruleset)). However, when an array field like `bypass_actors` is included, the entire array is replaced -- sending 3 entries replaces the previous 4. Include all fields for safety and to match the proven pattern from PR #775:

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

### Execution Script

Write the payload to a temp file and execute via `gh api`. This avoids shell escaping issues with nested JSON (learned from PR #775):

```bash
cat > /tmp/ruleset-update.json << 'PAYLOAD'
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
PAYLOAD

gh api repos/jikig-ai/soleur/rulesets/13304872 \
  --method PUT \
  --input /tmp/ruleset-update.json
```

Verify after update:

```bash
gh api repos/jikig-ai/soleur/rulesets/13304872 2>/dev/null | \
  python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(json.dumps(d['bypass_actors'], indent=2))"
```

## Technical Considerations

### Risk: Breaking bot workflows

The Claude app (ID 1236702) is the only Integration bypass actor that matters for bot workflows. Bot workflows authenticate as `github-actions[bot]` (app ID 15368), which satisfies the `integration_id: 15368` constraint on the `cla-check` status check -- they do not rely on bypass actors at all. The Claude app bypass is for `claude-code-action` workflows. Removing the ghost entry 262318 removes no active functionality.

### Research Insight: GITHUB_TOKEN cascade limitation

Per the learning from PR #771 migration, PRs created by `GITHUB_TOKEN` do NOT trigger `pull_request` or `pull_request_target` events. This means the CLA workflow (`cla.yml`) will NOT run on bot PRs -- the `cla-check` check run simply never appears. Bot workflows work around this by posting synthetic `cla-check` statuses via the Statuses API. The Claude app bypass (ID 1236702) allows `claude-code-action` PRs to merge despite the missing check. Neither mechanism depends on actor 262318.

### Risk: PUT array replacement semantics

The GitHub Rulesets API `PUT` endpoint marks all fields as Optional ([docs](https://docs.github.com/en/rest/repos/rules#update-a-repository-ruleset)). When an array field like `bypass_actors` is included in the payload, the entire array is replaced with the provided value. The full payload approach (including all fields) is used here for safety and to match the proven pattern from PR #775.

### Research Insight: Terraform bypass_actors deletion bugs (not applicable)

Multiple Terraform provider issues ([#2269](https://github.com/integrations/terraform-provider-github/issues/2269), [#2952](https://github.com/integrations/terraform-provider-github/issues/2952), [#2179](https://github.com/integrations/terraform-provider-github/issues/2179)) document bugs where removing bypass_actors via Terraform appears to succeed but the actors persist. The root cause was in the `go-github` client library (empty array serialization issue), fixed in `go-github` v63.0.0. This bug does **not** affect direct REST API calls via `gh api` -- PR #775 successfully modified this exact ruleset's bypass_actors using `gh api --method PUT --input`.

### Rollback plan

If removal causes unexpected issues, re-add the entry immediately. **Note:** If other ruleset fields have been modified since this plan was written, regenerate the payload from the current live state (`gh api repos/jikig-ai/soleur/rulesets/13304872`) and only change the `bypass_actors` array — do not blindly use the hardcoded payload below:

```bash
cat > /tmp/ruleset-rollback.json << 'PAYLOAD'
{
  "name": "CLA Required",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "exclude": [], "include": ["~DEFAULT_BRANCH"] } },
  "rules": [{ "type": "required_status_checks", "parameters": { "strict_required_status_checks_policy": false, "do_not_enforce_on_create": false, "required_status_checks": [{ "context": "cla-check", "integration_id": 15368 }] } }],
  "bypass_actors": [
    { "actor_id": null, "actor_type": "OrganizationAdmin", "bypass_mode": "always" },
    { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" },
    { "actor_id": 262318, "actor_type": "Integration", "bypass_mode": "always" },
    { "actor_id": 1236702, "actor_type": "Integration", "bypass_mode": "always" }
  ]
}
PAYLOAD

gh api repos/jikig-ai/soleur/rulesets/13304872 --method PUT --input /tmp/ruleset-rollback.json
```

No code changes or workflow modifications are needed -- this is a pure API-level change, reversible in seconds.

### SpecFlow edge cases

- **What if 262318 is still active via a path not visible in the installations API?** GitHub does not offer an endpoint to look up arbitrary app IDs by number. `GET /apps/{id}` returns 404, which means the app is either deleted or private. If private but still active, removal would cause that app's PRs to no longer bypass CLA. However, no PRs in the repository's history show any activity from an app matching this ID.
- **What if GitHub re-uses app IDs?** GitHub app IDs are globally unique and monotonically increasing. They are not recycled. A deleted app's ID remains permanently retired.
- **What if the PUT call succeeds but bypass_actors are not updated?** Verify by checking the response body of the PUT call (it returns the updated ruleset). If bypass_actors in the response still contains 4 entries, the API ignored the change -- fall back to the GitHub UI (Settings > Rules > CLA Required > Bypass list).

## Acceptance Criteria

- [x] Actor 262318 removed from CLA Required ruleset bypass_actors (verified in PUT response body)
- [x] All other ruleset fields unchanged (verified via separate `GET /repos/jikig-ai/soleur/rulesets/13304872`)
- [x] Remaining bypass actors verified: OrganizationAdmin (null), RepositoryRole (5), Claude Integration (1236702)
- [ ] Bot workflow verified: this feature branch PR itself will test CLA check behavior -- the PR must pass CLA check before merge
- [x] Stale references to 262318 in autonomous bugfix plan noted as incorrect (the plan incorrectly claims 262318 is a Claude App ID)

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

### Internal

- Issue: [#779](https://github.com/jikig-ai/soleur/issues/779)
- Related PR: [#775](https://github.com/jikig-ai/soleur/pull/775) (added `integration_id` to CLA check)
- Related issue: [#773](https://github.com/jikig-ai/soleur/issues/773) (CLA check security gap)
- Learning: `knowledge-base/learnings/2026-03-19-github-actions-bypass-actor-not-feasible.md`
- Learning: `knowledge-base/learnings/2026-03-19-content-publisher-cla-ruleset-push-rejection.md`
- Prior plan: `knowledge-base/plans/2026-03-19-chore-cla-ruleset-integration-id-plan.md`

### External

- [GitHub Rulesets API: Update a repository ruleset](https://docs.github.com/en/rest/repos/rules#update-a-repository-ruleset) -- PUT endpoint, all fields Optional
- [Terraform provider #2269: bypass_actors cannot be deleted](https://github.com/integrations/terraform-provider-github/issues/2269) -- go-github client bug, fixed in v63.0.0
- [Terraform provider #2952: removing bypass actors has no effect](https://github.com/integrations/terraform-provider-github/issues/2952) -- fixed in provider v6.10.0
- [Terraform provider #2179: bypass_actors not deleted on GitHub](https://github.com/integrations/terraform-provider-github/issues/2179) -- original bug report
