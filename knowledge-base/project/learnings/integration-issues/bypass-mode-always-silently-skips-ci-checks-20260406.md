---
module: github-rulesets
date: 2026-04-06
problem_type: integration_issue
component: tooling
symptoms:
  - "PRs merged with failing CI checks without any warning"
  - "Admin bypass_mode 'always' silently skips required status checks"
  - "No audit trail when admin merges PR with failing checks"
root_cause: config_error
resolution_type: config_change
severity: high
tags: [github-rulesets, bypass-mode, ci-checks, auto-merge, branch-protection]
---

# Troubleshooting: GitHub CI Required ruleset bypass_mode "always" silently skips checks

## Problem

The CI Required ruleset (ID 14145388) had `bypass_mode: "always"` for both OrganizationAdmin and RepositoryRole (Admin) actors. This allowed the admin to merge PRs with failing CI checks without any warning or audit trail. Direct pushes to main also bypassed all ruleset rules.

## Environment

- Module: github-rulesets
- Affected Component: CI Required ruleset, `scripts/create-ci-required-ruleset.sh`
- Date: 2026-04-06

## Symptoms

- PRs merged with failing test checks without any warning
- No audit trail for admin bypass merges
- Direct pushes to main bypassed all ruleset enforcement
- The creation script was out of sync with the live ruleset (missing `dependency-review` and `e2e` checks)

## What Didn't Work

**Direct solution:** The problem was identified and fixed on the first attempt after researching the GitHub Rulesets API bypass_mode semantics.

## Session Errors

**Ralph loop setup script path error**

- **Recovery:** Corrected path from `./plugins/soleur/skills/one-shot/scripts/` to `./plugins/soleur/scripts/`
- **Prevention:** The one-shot skill references `setup-ralph-loop.sh` — verify the script path exists before calling it

**QA direct push test used wrong auth method**

- **Recovery:** Fell back to API verification (`current_user_can_bypass` field) instead of attempting actual push
- **Prevention:** Use `gh api` to verify ruleset enforcement state rather than attempting destructive push tests

**Code-simplicity-reviewer agent stalled**

- **Recovery:** Proceeded with findings from the two completed agents (security-sentinel, architecture-strategist)
- **Prevention:** Set agent timeouts and proceed with partial results when some agents stall

## Solution

Changed `bypass_mode` from `"always"` to `"pull_request"` for both bypass actors on the CI Required ruleset.

**API update:**

```bash
gh api "repos/jikig-ai/soleur/rulesets/14145388" \
  -X PUT --input payload.json
```

With payload containing `"bypass_mode": "pull_request"` for both actors.

**Script update (`scripts/create-ci-required-ruleset.sh`):**

```json
// Before (broken):
"bypass_mode": "always"

// After (fixed):
"bypass_mode": "pull_request"
```

Also synced the script's `required_status_checks` with the live ruleset (added `dependency-review` and `e2e`).

## Why This Works

1. **Root cause:** `bypass_mode: "always"` grants the actor full bypass of ALL ruleset rules — including direct pushes to protected branches with zero audit trail.

2. **How the fix helps:** `bypass_mode: "pull_request"` restricts the actor to the PR workflow. The actor can still merge PRs with failing checks (escape hatch for broken CI), but a bypass badge appears in the PR timeline (audit trail). Direct pushes to main are blocked entirely.

3. **Critical finding — auto-merge is already protected:** `gh pr merge --squash --auto` (used by the `/ship` workflow) always waits for requirements to be met regardless of the caller's bypass_mode. The `--auto` flag does NOT exercise bypass privileges. This means the actual gap was narrower than initially assessed — only direct merges (GitHub UI "Merge" button or `gh pr merge` without `--auto`) were affected. The `/ship` pipeline was already safe.

## Prevention

- When creating GitHub rulesets, default to `bypass_mode: "pull_request"` rather than `"always"` — `"always"` should only be used during initial setup/bootstrapping and then tightened
- Periodically audit bypass_actors on all rulesets (see `2026-03-19-github-ruleset-stale-bypass-actors.md`)
- The protection stack should be layered: ruleset enforcement + auto-merge behavior + bypass audit trail
- Keep creation scripts in sync with live rulesets — when updating a live ruleset via API, update the script in the same PR

## Related Issues

- See also: [github-ruleset-stale-bypass-actors](../2026-03-19-github-ruleset-stale-bypass-actors.md) — Stale bypass actors with `bypass_mode: "always"` on security rulesets
- See also: [github-ruleset-put-replaces-entire-payload](../2026-04-03-github-ruleset-put-replaces-entire-payload.md) — PUT endpoint replaces array fields wholesale
- See also: [ci-quality-gates-and-test-failure-visibility](../2026-04-01-ci-quality-gates-and-test-failure-visibility.md) — Related CI quality gates work
- See also: [skip-ci-blocks-auto-merge](../2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs.md) — Required checks and auto-merge interaction
