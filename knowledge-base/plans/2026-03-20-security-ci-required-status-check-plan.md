---
title: "security: add CI as required status check for auto-merge safety"
type: feat
date: 2026-03-20
issue: "#826"
---

# security: add CI as required status check for auto-merge safety

## Overview

The `test` job from `.github/workflows/ci.yml` is not a required status check on `main`. The only required checks are `cla-check` (ruleset ID 13304872) and force-push/deletion prevention (ruleset ID 13044280). This means auto-merge -- used by Renovate and `gh pr merge --auto` -- can proceed even if CI fails or is skipped.

## Problem Statement

Found during code review of PR #820 (Renovate config). Renovate's `default:automergeDigest` preset uses GitHub's native auto-merge, which only waits for *required* status checks. Without CI as a required check, a broken dependency update could merge to `main` without passing tests.

The existing rulesets on `main`:

| Ruleset | ID | Rules |
|---------|-----|-------|
| CLA Required | 13304872 | `required_status_checks` (`cla-check` with `integration_id: 15368`) |
| Force Push Prevention | 13044280 | `deletion`, `non_fast_forward` |

Neither ruleset requires the `test` status check.

## Proposed Solution

Create a new GitHub repository ruleset named **"CI Required"** targeting `~DEFAULT_BRANCH` (main) that requires the `test` status check. Use the GitHub API via `gh api` -- consistent with how the existing rulesets were created. A new, dedicated ruleset keeps concerns separated (CI vs CLA vs force-push prevention).

### API Call

```bash
gh api repos/jikig-ai/soleur/rulesets -X POST --input /tmp/ci-required-ruleset.json
```

### Ruleset Payload

```json
{
  "name": "CI Required",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
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
            "context": "test",
            "integration_id": 15368
          }
        ]
      }
    }
  ],
  "bypass_actors": [
    {
      "actor_id": 5,
      "actor_type": "RepositoryRole",
      "bypass_mode": "always"
    }
  ]
}
```

### Design Decisions

1. **`integration_id: 15368`** -- restricts which app can satisfy the `test` check to `github-actions` (the app behind `GITHUB_TOKEN`). This prevents third-party actors from spoofing the status, consistent with the hardening applied to `cla-check` per issue #773.

2. **`strict_required_status_checks_policy: false`** -- "loose" mode means the branch doesn't need to be up-to-date with `main` before merging. Consistent with the CLA Required ruleset. Strict mode would require rebasing on every `main` update, creating unnecessary friction.

3. **Separate ruleset (not extending CLA Required)** -- keeps concerns separated. Each ruleset has a clear, single purpose. Easier to audit and modify independently.

4. **RepositoryRole bypass (actor_id 5 = Admin)** -- allows repository admins to bypass in emergencies, matching the CLA Required ruleset pattern.

## Technical Considerations

### Bot Workflow Impact (Critical Edge Case)

9 scheduled bot workflows use `[skip ci]` in commit messages and create PRs via the PR-based commit pattern. Currently they only post synthetic `cla-check` statuses. If `test` becomes required:

- The `[skip ci]` commit message causes CI to be skipped
- The `test` status check is never posted
- Auto-merge blocks indefinitely

**Affected workflows:**
- `scheduled-content-publisher.yml`
- `scheduled-content-generator.yml`
- `scheduled-weekly-analytics.yml`
- `scheduled-competitive-analysis.yml`
- `scheduled-growth-audit.yml`
- `scheduled-seo-aeo-audit.yml`
- `scheduled-community-monitor.yml`
- `scheduled-campaign-calendar.yml`
- `scheduled-growth-execution.yml`

**Mitigation:** Each bot workflow must also post a synthetic `test` status alongside the existing synthetic `cla-check` status. The pattern is already established -- add a second `gh api` call:

```yaml
# Existing: synthetic cla-check
gh api "repos/${{ github.repository }}/statuses/$SHA" \
  -f state=success \
  -f context=cla-check \
  -f description="Bot commit - CLA not required"

# New: synthetic test status
gh api "repos/${{ github.repository }}/statuses/$SHA" \
  -f state=success \
  -f context=test \
  -f description="Bot commit - CI not required"
```

This is safe because bot PRs contain only automated metadata updates (analytics snapshots, content status changes, campaign calendar updates) -- they do not modify code that would benefit from CI testing.

### Renovate PR Impact

Renovate PRs trigger the CI workflow normally (no `[skip ci]`). The `test` job runs and posts the `test` status. No changes needed for Renovate -- this is the primary scenario the ruleset is designed to protect.

### Terraform Consideration

AGENTS.md mandates Terraform for infrastructure provisioning. However:
- No GitHub Terraform provider is configured in this repo
- Both existing rulesets (CLA Required, Force Push Prevention) were created via `gh api`
- Adding a GitHub Terraform provider for a single ruleset would be out of pattern
- The Terraform `github_repository_ruleset` resource had known bugs in the go-github client (issues #2269, #2952) per the stale bypass actors learning

**Decision:** Use `gh api` for consistency with existing rulesets. Terraform migration of all rulesets can be a separate initiative if desired.

## Acceptance Criteria

- [ ] New "CI Required" ruleset exists on `main` requiring the `test` status check with `integration_id: 15368`
- [ ] All 9 bot workflows post synthetic `test` status alongside existing synthetic `cla-check` status
- [ ] Human PRs with passing CI can still merge via auto-merge
- [ ] Human PRs with failing CI are blocked from auto-merge
- [ ] Bot PRs with synthetic statuses can still merge via auto-merge
- [ ] Renovate PRs trigger real CI and are blocked if tests fail
- [ ] Ruleset verification: `gh api repos/jikig-ai/soleur/rulesets` shows the new ruleset

## Test Scenarios

- Given a PR where CI `test` job passes, when auto-merge is enabled, then the PR merges successfully
- Given a PR where CI `test` job fails, when auto-merge is enabled, then the PR is blocked from merging
- Given a bot PR with `[skip ci]` and synthetic `test` + `cla-check` statuses, when auto-merge is enabled, then the PR merges successfully
- Given a bot PR with `[skip ci]` and only synthetic `cla-check` (missing `test`), when auto-merge is enabled, then the PR is blocked (validates the check works)
- Given a Renovate digest-update PR, when CI runs and passes, then auto-merge proceeds
- Given a Renovate digest-update PR, when CI runs and fails, then auto-merge is blocked

## MVP

### 1. Create the ruleset (`gh api` one-liner)

```bash
# /tmp/ci-required-ruleset.json
gh api repos/jikig-ai/soleur/rulesets -X POST --input /tmp/ci-required-ruleset.json
```

### 2. Update bot workflows (9 files)

For each of the 9 `scheduled-*.yml` files listed above, add a synthetic `test` status POST immediately after the existing `cla-check` POST:

```yaml
# .github/workflows/scheduled-weekly-analytics.yml (and 8 others)
# Add after the existing cla-check synthetic status:
gh api "repos/${{ github.repository }}/statuses/$SHA" \
  -f state=success \
  -f context=test \
  -f description="Bot commit - CI not required"
```

### 3. Verify

```bash
# Verify ruleset exists
gh api repos/jikig-ai/soleur/rulesets --jq '.[] | select(.name == "CI Required") | {id, name, enforcement}'

# Verify test check is required
gh api repos/jikig-ai/soleur/rulesets --jq '.[] | select(.name == "CI Required") | .rules[].parameters.required_status_checks[].context'
```

## Dependencies & Risks

- **Risk:** If `[skip ci]` behavior changes in GitHub Actions, bot workflows could break. Mitigated by the synthetic status pattern being resilient -- it posts statuses regardless of CI behavior.
- **Risk:** If a bot workflow is added in the future without the synthetic `test` status, its PRs will be blocked. Mitigated by documenting the pattern in a learning.
- **Dependency:** Repository admin permissions needed to create rulesets via the API.

## References

- Issue: #826
- PR #820 (Renovate config with auto-merge -- the discovery context)
- Existing CLA Required ruleset: ID 13304872
- Existing Force Push Prevention ruleset: ID 13044280
- Learning: `knowledge-base/learnings/2026-03-19-github-ruleset-stale-bypass-actors.md`
- Learning: `knowledge-base/learnings/2026-03-19-github-actions-bypass-actor-not-feasible.md`
- Learning: `knowledge-base/learnings/2026-03-19-content-publisher-cla-ruleset-push-rejection.md`
- Learning: `knowledge-base/learnings/2026-03-19-ci-squash-fallback-bypasses-merge-gates.md`
- CI workflow: `.github/workflows/ci.yml`
