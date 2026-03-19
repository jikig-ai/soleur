---
title: "security(telegram-bridge): pin npm install @anthropic-ai/claude-code to specific version"
type: fix
date: 2026-03-19
---

# security: pin @anthropic-ai/claude-code npm version in Dockerfiles

## Overview

The telegram-bridge and web-platform Dockerfiles install `@anthropic-ai/claude-code` via `npm install -g` without a version pin. This is the same class of mutable-tag supply-chain risk that #794/#801 fixed for the Docker base image: builds at different times silently pull different package versions, creating non-reproducible builds and a vector for supply-chain attacks.

Issue #802 identifies `apps/telegram-bridge/Dockerfile` line 9. During research, the same unpinned install was found in `apps/web-platform/Dockerfile` line 4.

## Problem

```dockerfile
# apps/telegram-bridge/Dockerfile:9
RUN npm install -g @anthropic-ai/claude-code

# apps/web-platform/Dockerfile:4
RUN npm install -g @anthropic-ai/claude-code
```

Without a version pin, `npm install -g` resolves to `@latest` at build time. A compromised or breaking upstream publish silently enters production on the next Docker build.

## Proposed Fix

Pin to the current latest version (`2.1.79`) in both Dockerfiles:

```dockerfile
# apps/telegram-bridge/Dockerfile:9
RUN npm install -g @anthropic-ai/claude-code@2.1.79

# apps/web-platform/Dockerfile:4
RUN npm install -g @anthropic-ai/claude-code@2.1.79
```

Unlike Docker base images, npm packages don't have digest pinning -- the version string is the immutable identifier (npm registry guarantees published versions are immutable once published).

## Scope Decision: web-platform Dockerfile

Issue #802 only mentions telegram-bridge. However, `apps/web-platform/Dockerfile` has the identical problem on line 4 and uses `FROM node:22-slim` (also no digest pin, but that's a separate issue). Fixing both in this PR is consistent with #801's pattern of fixing the same class of issue across the codebase when discovered.

**Out of scope:** The `node:22-slim` base image in web-platform is unpinned (no digest). That's a separate issue -- file it if not already tracked.

## Acceptance Criteria

- [ ] `apps/telegram-bridge/Dockerfile` pins `@anthropic-ai/claude-code` to version `2.1.79`
- [ ] `apps/web-platform/Dockerfile` pins `@anthropic-ai/claude-code` to version `2.1.79`
- [ ] Docker build succeeds for both images with pinned version
- [ ] All existing tests pass
- [ ] PR body includes `Closes #802`

## Test Scenarios

- Given the telegram-bridge Dockerfile, when `docker build` runs, then it installs exactly `@anthropic-ai/claude-code@2.1.79` (not latest)
- Given the web-platform Dockerfile, when `docker build` runs, then it installs exactly `@anthropic-ai/claude-code@2.1.79` (not latest)
- Given a fresh build environment, when the Dockerfile is built twice at different times, then both builds produce the same claude-code version

## SpecFlow Edge Cases

1. **Version availability**: Version `2.1.79` is currently the latest on npm. If it gets unpublished (rare but possible with npm), the Docker build would fail loudly -- which is the correct behavior (fail-closed rather than silently installing a different version).
2. **Future updates**: Updating claude-code requires a deliberate Dockerfile edit and PR. This is intentional friction -- the same pattern used for the base image pin in #801.
3. **CI cache invalidation**: Pinning a specific version means Docker layer caching works correctly. Without a pin, `npm install -g @anthropic-ai/claude-code` could serve a stale cached layer even when a new version is available, creating inconsistency between cached and uncached builds.

## Files to Modify

| File | Line | Change |
|------|------|--------|
| `apps/telegram-bridge/Dockerfile` | 9 | Add `@2.1.79` version suffix |
| `apps/web-platform/Dockerfile` | 4 | Add `@2.1.79` version suffix |

## Follow-up Issue

File a new issue for: `security(web-platform): pin Dockerfile base image node:22-slim to specific digest` -- same pattern as #794 but for the web-platform image.

## References

- Issue: #802
- Related PR: #801 (base image digest pinning)
- Related issue: #794 (base image pinning)
- Learning: `knowledge-base/learnings/2026-03-19-docker-base-image-digest-pinning.md`
- npm registry: https://www.npmjs.com/package/@anthropic-ai/claude-code
