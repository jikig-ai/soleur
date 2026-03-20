---
title: "fix: sanitize version interpolation in deploy scripts"
type: fix
date: 2026-03-20
semver: patch
---

# fix: sanitize version interpolation in deploy scripts

## Overview

Both app deploy workflows (`web-platform-release.yml` and `telegram-bridge-release.yml`) interpolate `needs.release.outputs.version` directly into shell commands without format validation. While the version originates from `reusable-release.yml` which validates components are integers (line 201-204), defense-in-depth requires the consumers to independently validate before use -- a malformed string reaching the deploy step could inject shell commands on the production server via `appleboy/ssh-action`.

Closes #833

## Problem Statement

In both deploy workflows, the version output is interpolated into a `TAG` variable and then used in `docker pull` and `docker run` commands executed over SSH on the production server:

```yaml
# .github/workflows/web-platform-release.yml:54
TAG="v${{ needs.release.outputs.version }}"
docker pull "$IMAGE:$TAG"
```

```yaml
# .github/workflows/telegram-bridge-release.yml:68
TAG="v${{ needs.release.outputs.version }}"
docker pull "$IMAGE:$TAG"
```

The `${{ }}` expression is string-interpolated by GitHub Actions before the shell sees it. If the value contained shell metacharacters (`;`, `$()`, backticks), they would execute in the SSH session on the production server. The risk is low because the version comes from an internal reusable workflow that already validates integer components, but defense-in-depth is standard practice for shell commands running on production infrastructure.

## Proposed Solution

Add a semver format validation guard immediately after the `TAG` assignment in both deploy scripts. The guard validates the format and aborts with a clear error message if the version is malformed:

```bash
TAG="v${{ needs.release.outputs.version }}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "::error::Invalid version format: $TAG"; exit 1; }
```

This is the exact pattern suggested in the issue, with the addition of GitHub Actions `::error::` annotation for visibility in the workflow UI.

### Files to Modify

1. `.github/workflows/web-platform-release.yml` -- line 54, add validation after `TAG=` assignment
2. `.github/workflows/telegram-bridge-release.yml` -- line 68, add validation after `TAG=` assignment

## Non-goals

- Modifying `reusable-release.yml` -- it already validates version components are integers at computation time (lines 201-204)
- Adding validation to the Docker build step in `reusable-release.yml` -- the `${{ steps.version.outputs.next }}` value is computed locally within the same job, not received from an external source
- Quoting changes beyond the version interpolation -- other `${{ }}` expressions in these files reference secrets (handled by the ssh-action) or boolean outputs (not injectable)

## Acceptance Criteria

- [ ] `web-platform-release.yml` validates version format matches `^v[0-9]+\.[0-9]+\.[0-9]+$` before any `docker` command in `.github/workflows/web-platform-release.yml`
- [ ] `telegram-bridge-release.yml` validates version format matches `^v[0-9]+\.[0-9]+\.[0-9]+$` before any `docker` command in `.github/workflows/telegram-bridge-release.yml`
- [ ] Both validations use `::error::` annotation for GitHub Actions UI visibility
- [ ] Both validations abort with `exit 1` on mismatch
- [ ] No functional change to the deploy flow when version format is valid (existing tests/deploys unaffected)

## Test Scenarios

- Given a valid version output like `1.2.3`, when the deploy step runs, then `TAG` is set to `v1.2.3` and deployment proceeds normally
- Given a malformed version output like `1.2.3; rm -rf /`, when the deploy step runs, then the regex guard fails and the step exits with error before any docker command executes
- Given an empty version output, when the deploy step runs, then the regex guard fails (TAG=`v` does not match the pattern) and exits with error
- Given a version with extra segments like `1.2.3.4`, when the deploy step runs, then the regex guard fails (anchored regex rejects non-semver formats)
- Given a version with pre-release suffix like `1.2.3-beta`, when the deploy step runs, then the regex guard fails (only strict `X.Y.Z` is accepted, matching the project's versioning scheme)

## Context

- Flagged during review of #748 / PR #824
- Pre-existing issue, not introduced by that PR
- Risk is low (version comes from internal workflow output, not external input)
- Constitution mandates: "All `workflow_dispatch` inputs must be validated against a strict regex before use in shell commands" and SpecFlow analysis is recommended for CI/workflow changes

## MVP

### .github/workflows/web-platform-release.yml (deploy step, lines 53-55)

```yaml
          script: |
            IMAGE="ghcr.io/jikig-ai/soleur-web-platform"
            TAG="v${{ needs.release.outputs.version }}"
            [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "::error::Invalid version format: $TAG"; exit 1; }
            docker pull "$IMAGE:$TAG"
```

### .github/workflows/telegram-bridge-release.yml (deploy step, lines 67-69)

```yaml
          script: |
            IMAGE="ghcr.io/jikig-ai/soleur-telegram-bridge"
            TAG="v${{ needs.release.outputs.version }}"
            [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "::error::Invalid version format: $TAG"; exit 1; }
            docker pull "$IMAGE:$TAG"
```

## References

- Issue: #833
- PR #824 (where this was flagged)
- `.github/workflows/reusable-release.yml:201-204` -- existing version validation at source
- Constitution: "All `workflow_dispatch` inputs must be validated against a strict regex before use in shell commands" (line 119)
