---
title: "fix: pin action tags to SHA in build-web-platform.yml"
type: fix
date: 2026-03-18
deepened: 2026-03-18
---

# fix(ci): pin action tags to SHA in build-web-platform.yml

## Enhancement Summary

**Deepened on:** 2026-03-18
**Sections enhanced:** 4 (Proposed Solution, Acceptance Criteria, Test Scenarios, References)
**Research conducted:** GitHub API SHA verification, cross-workflow consistency audit, mutable tag resolution check

### Key Improvements

1. Verified zero behavioral change: mutable tags (`v3`, `v6`, `v1`) currently resolve to the exact same SHAs as the pinned patch releases (`v3.7.0`, `v6.19.2`, `v1.2.5`) -- confirmed via GitHub API
2. Confirmed `actions/checkout` SHA consistency with all 18 other workflows that already pin this action
3. Identified that no Dependabot or Renovate config exists in the repository, validating the non-goal about automated updates

### New Considerations Discovered

- All four mutable tags currently point to the same commits as the latest patch releases, so this change is provably zero-risk from a behavioral standpoint
- The repository has 18 workflows already using the SHA-pinned `actions/checkout` -- `build-web-platform.yml` is the sole outlier across all workflows
- `docker/login-action` `v4.0.0` is available but upgrading is correctly scoped as a non-goal to keep this a pure security fix

## Overview

`build-web-platform.yml` is the only workflow in the repository that still uses mutable version tags (`@v4`, `@v3`, `@v6`, `@v1`) instead of SHA-pinned references. All other workflows (ci.yml, deploy-docs.yml, cla.yml, scheduled-*.yml, etc.) already follow the `@<sha> # vX.Y.Z` convention. This inconsistency exposes the build-and-deploy pipeline to supply-chain attacks.

The `appleboy/ssh-action@v1` reference is particularly high-risk: it receives `secrets.WEB_PLATFORM_SSH_KEY` and executes arbitrary commands on the production server. A compromised tag could exfiltrate the SSH private key.

Found during security review of #715.

## Problem Statement

Four action references in `.github/workflows/build-web-platform.yml` use mutable version tags:

| Line | Current Reference | Risk |
|------|------------------|------|
| 33 | `actions/checkout@v4` | Low -- read-only checkout |
| 36 | `docker/login-action@v3` | Medium -- receives `GITHUB_TOKEN` |
| 46 | `docker/build-push-action@v6` | Medium -- pushes container images |
| 66 | `appleboy/ssh-action@v1` | HIGH -- receives production SSH key, executes on server |

A compromised or force-pushed tag could inject malicious code into any of these actions. The `appleboy/ssh-action` case is critical because it handles the production SSH private key and runs shell commands on the deployment server.

## Proposed Solution

Pin all four actions to their current latest patch release commit SHAs, using the `@<sha> # vX.Y.Z` comment convention already established in ci.yml and other workflows.

### Pinning Map

| Action | Current Tag | Pin To | SHA | Verified |
|--------|------------|--------|-----|----------|
| `actions/checkout` | `@v4` | `v4.3.1` | `34e114876b0b11c390a56381ad16ebd13914f8d5` | Matches ci.yml and 17 other workflows |
| `docker/login-action` | `@v3` | `v3.7.0` | `c94ce9fb468520275223c153574b00df6fe4bcc9` | `v3` tag currently resolves to this SHA |
| `docker/build-push-action` | `@v6` | `v6.19.2` | `10e90e3645eae34f1e60eeb005ba3a3d33f178e8` | `v6` tag currently resolves to this SHA |
| `appleboy/ssh-action` | `@v1` | `v1.2.5` | `0ff4204d59e8e51228ff73bce53f80d53301dee2` | `v1` tag currently resolves to this SHA |

All SHAs verified via `gh api repos/<owner>/<repo>/git/ref/tags/<tag>` on 2026-03-18. All tags are lightweight (type: `commit`), pointing directly to commit objects -- no annotated tag dereferencing needed.

### Changes Required

**File:** `.github/workflows/build-web-platform.yml`

Replace each `uses:` line:

```yaml
# Line 33: actions/checkout
# Before:
uses: actions/checkout@v4
# After:
uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1

# Line 36: docker/login-action
# Before:
uses: docker/login-action@v3
# After:
uses: docker/login-action@c94ce9fb468520275223c153574b00df6fe4bcc9 # v3.7.0

# Line 46: docker/build-push-action
# Before:
uses: docker/build-push-action@v6
# After:
uses: docker/build-push-action@10e90e3645eae34f1e60eeb005ba3a3d33f178e8 # v6.19.2

# Line 66: appleboy/ssh-action
# Before:
uses: appleboy/ssh-action@v1
# After:
uses: appleboy/ssh-action@0ff4204d59e8e51228ff73bce53f80d53301dee2 # v1.2.5
```

## Non-goals

- Upgrading actions to new major versions (e.g., docker/login-action v3 to v4). This fix pins at current major versions to minimize behavioral changes.
- Adding Dependabot or Renovate for automated SHA updates. That is a separate concern.
- Auditing the `appleboy/ssh-action` source code. Pinning mitigates tag-based supply-chain attacks but does not address trust in the action itself.

## Acceptance Criteria

- [ ] All four `uses:` lines in `build-web-platform.yml` reference commit SHAs, not version tags
- [ ] Each SHA has a trailing `# vX.Y.Z` comment matching the resolved version
- [ ] The `actions/checkout` SHA matches the one already used in `ci.yml` (`34e114876b0b11c390a56381ad16ebd13914f8d5`)
- [ ] No other functional changes to the workflow (triggers, env vars, secrets, steps)
- [ ] Workflow YAML remains valid (passes `actionlint` or equivalent)
- [ ] No remaining `@v[0-9]` references in `build-web-platform.yml` (grep verification: `grep -E 'uses:.*@v[0-9]' .github/workflows/build-web-platform.yml` returns empty)

## Test Scenarios

- Given `build-web-platform.yml` with SHA-pinned actions, when a push event triggers the workflow on `feat/web-platform-ux`, then the `build-and-push` job should succeed with identical behavior to the tag-based version.
- Given the pinned `appleboy/ssh-action` SHA, when a `workflow_dispatch` with `deploy: true` triggers the deploy job, then SSH commands execute on the production server using the pinned action version.
- Given the workflow file, when inspecting all `uses:` lines with `grep 'uses:' .github/workflows/build-web-platform.yml`, then every line contains a 40-character hex SHA followed by a `# vX.Y.Z` comment.

## Context

- **Issue:** #716
- **Priority:** HIGH -- production SSH key exposure risk
- **Semver:** `semver:patch` -- no behavioral change, security hardening only
- **Pattern precedent:** `ci.yml` line 14 (`actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`)

## Research Insights

### Security Best Practices

- **GitHub's official guidance** recommends pinning to full-length commit SHAs as "the most stable option" for using third-party actions. Mutable tags (even signed ones) can be force-pushed by repository maintainers or compromised accounts.
- The `# vX.Y.Z` trailing comment convention is a widely adopted pattern that preserves human readability while enforcing immutability. Dependabot and Renovate both understand this format and can auto-update the SHA while preserving the comment.
- Third-party actions that receive secrets are the highest-priority candidates for SHA pinning. `appleboy/ssh-action` receiving `WEB_PLATFORM_SSH_KEY` is the textbook case -- a compromised tag could exfiltrate the key in a single workflow run.

### Cross-Workflow Consistency Audit

18 other workflows in this repository already pin `actions/checkout` to `34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`. After this fix, all 19 workflows will be consistent.

Workflows checked:
- `ci.yml`, `cla.yml`, `claude-code-review.yml`, `deploy-docs.yml`, `post-merge-monitor.yml`
- `review-reminder.yml`, `scheduled-bug-fixer.yml`, `scheduled-campaign-calendar.yml`
- `scheduled-community-monitor.yml`, `scheduled-competitive-analysis.yml`
- `scheduled-content-generator.yml`, `scheduled-content-publisher.yml`
- `scheduled-daily-triage.yml`, `scheduled-growth-audit.yml`, `scheduled-growth-execution.yml`
- `scheduled-seo-aeo-audit.yml`, `scheduled-ship-merge.yml`, `scheduled-weekly-analytics.yml`
- `test-pretooluse-hooks.yml`, `version-bump-and-release.yml`

### Zero-Risk Verification

The mutable major-version tags currently resolve to the exact same commit SHAs as the latest patch releases:

| Tag | Resolves to SHA | Same as patch release |
|-----|----------------|----------------------|
| `v3` (docker/login-action) | `c94ce9fb...` | `v3.7.0` |
| `v6` (docker/build-push-action) | `10e90e36...` | `v6.19.2` |
| `v1` (appleboy/ssh-action) | `0ff4204d...` | `v1.2.5` |

This means the behavioral diff of this change is exactly zero -- we are freezing the exact code that runs today.

## References

- GitHub security advisory on tag mutability: https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#using-third-party-actions
- Related issue: #716
- Found during review of: #715
- Existing SHA-pinned workflows: `.github/workflows/ci.yml`, `.github/workflows/deploy-docs.yml`, `.github/workflows/cla.yml`
- SHA verification commands: `gh api repos/<owner>/<repo>/git/ref/tags/<tag> --jq '.object.sha'`
