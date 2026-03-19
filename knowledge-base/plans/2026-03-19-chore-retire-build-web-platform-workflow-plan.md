---
title: "chore: retire build-web-platform.yml"
type: fix
date: 2026-03-19
---

# Retire build-web-platform.yml

## Overview

Delete the orphaned `build-web-platform.yml` GitHub Actions workflow. It was superseded by `web-platform-release.yml` (shipped in #739/#742) and its trigger branch (`feat/web-platform-ux`) no longer exists on the remote.

**Issue:** #752
**Related:** #739 (closed -- independent app release pipelines)

## Problem Statement

`.github/workflows/build-web-platform.yml` triggers on pushes to `feat/web-platform-ux` (a specific feature branch, not a pattern). That branch has been merged and deleted. The workflow also supports `workflow_dispatch`, but this is redundant with `web-platform-release.yml` which handles main-branch builds, versioned Docker tags, deploy, and Discord notifications via the reusable release pipeline.

Keeping the orphaned workflow creates confusion about which workflow builds the web platform and risks accidental `:latest` tag pushes that conflict with the versioned release pipeline.

## Proposed Solution

**Option 1: Delete it** (recommended). The simplest option. `web-platform-release.yml` fully covers the build/deploy lifecycle with proper versioning.

Repurposing for PR preview builds (option 2 from the issue) would require a complete rewrite and is better done as a new workflow when needed.

## Technical Approach

### Phase 1: Delete the Workflow

- [ ] **1.1** Delete `.github/workflows/build-web-platform.yml`
- [ ] **1.2** Verify no other workflows reference it: `grep -r "build-web-platform" .github/` (confirmed: only self-reference at line 18)

### Phase 2: Verify No Regressions

- [ ] **2.1** Confirm `web-platform-release.yml` is the active workflow handling web-platform builds (confirmed: runs on every push to main, 5 recent successful runs)
- [ ] **2.2** Confirm the `feat/web-platform-ux` branch does not exist on remote (`git ls-remote --heads origin feat/web-platform-ux` returns empty)

## Acceptance Criteria

- [ ] `build-web-platform.yml` is deleted from `.github/workflows/`
- [ ] No duplicate `:latest` tag pushes from two workflows
- [ ] `web-platform-release.yml` continues to function as the sole web-platform CI/CD pipeline

## Test Scenarios

- Given `build-web-platform.yml` is deleted, when a PR touching `apps/web-platform/` merges to main, then only `web-platform-release.yml` runs and produces a versioned release
- Given `build-web-platform.yml` is deleted, when checking GitHub Actions workflow list, then `build-web-platform.yml` no longer appears
- Given `build-web-platform.yml` is deleted, when running `web-platform-release.yml` via `workflow_dispatch`, then it still builds and optionally deploys correctly

## Dependencies & Prerequisites

| Dependency | Status | Blocker? |
|-----------|--------|----------|
| `web-platform-release.yml` active | Confirmed (5 recent runs) | No |
| `feat/web-platform-ux` branch deleted | Confirmed (no remote ref) | No |
| No workflows depend on `build-web-platform.yml` | Confirmed (grep) | No |

## Risk Analysis

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Lose `workflow_dispatch` build capability | None | None | `web-platform-release.yml` has `workflow_dispatch` with `bump_type` and `skip_deploy` inputs |
| Need PR preview builds later | Low | Low | Create a new purpose-built workflow when the need arises (separate issue) |

## Semver

`semver:patch` -- removing an orphaned workflow file, no functional change.

## References

### Internal

- `.github/workflows/build-web-platform.yml` -- the file to delete
- `.github/workflows/web-platform-release.yml` -- its replacement
- `.github/workflows/reusable-release.yml` -- the reusable workflow called by the replacement
- `knowledge-base/plans/2026-03-19-feat-per-app-release-pipelines-plan.md` -- the plan that created the replacement (line 105: "Keep for now; file separate issue to retire/repurpose")

### Learnings Applied

- **Audit existing workflows before adding new ones** (constitution.md): `build-web-platform.yml` was explicitly flagged for retirement in #739's plan.
