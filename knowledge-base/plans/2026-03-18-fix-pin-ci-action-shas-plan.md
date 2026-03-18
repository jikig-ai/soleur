---
title: "fix: pin action tags to SHA in build-web-platform.yml"
type: fix
date: 2026-03-18
---

# fix(ci): pin action tags to SHA in build-web-platform.yml

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

| Action | Current Tag | Pin To | SHA |
|--------|------------|--------|-----|
| `actions/checkout` | `@v4` | `v4.3.1` | `34e114876b0b11c390a56381ad16ebd13914f8d5` |
| `docker/login-action` | `@v3` | `v3.7.0` | `c94ce9fb468520275223c153574b00df6fe4bcc9` |
| `docker/build-push-action` | `@v6` | `v6.19.2` | `10e90e3645eae34f1e60eeb005ba3a3d33f178e8` |
| `appleboy/ssh-action` | `@v1` | `v1.2.5` | `0ff4204d59e8e51228ff73bce53f80d53301dee2` |

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

## Test Scenarios

- Given `build-web-platform.yml` with SHA-pinned actions, when a push event triggers the workflow on `feat/web-platform-ux`, then the `build-and-push` job should succeed with identical behavior to the tag-based version.
- Given the pinned `appleboy/ssh-action` SHA, when a `workflow_dispatch` with `deploy: true` triggers the deploy job, then SSH commands execute on the production server using the pinned action version.
- Given the workflow file, when inspecting all `uses:` lines with `grep 'uses:' .github/workflows/build-web-platform.yml`, then every line contains a 40-character hex SHA followed by a `# vX.Y.Z` comment.

## Context

- **Issue:** #716
- **Priority:** HIGH -- production SSH key exposure risk
- **Semver:** `semver:patch` -- no behavioral change, security hardening only
- **Pattern precedent:** `ci.yml` line 14 (`actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`)

## References

- GitHub security advisory on tag mutability: https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#using-third-party-actions
- Related issue: #716
- Found during review of: #715
- Existing SHA-pinned workflows: `.github/workflows/ci.yml`, `.github/workflows/deploy-docs.yml`, `.github/workflows/cla.yml`
