---
title: "security(telegram-bridge): pin npm install @anthropic-ai/claude-code to specific version"
type: fix
date: 2026-03-19
---

# security: pin @anthropic-ai/claude-code npm version in Dockerfiles

## Enhancement Summary

**Deepened on:** 2026-03-19
**Sections enhanced:** 4 (Proposed Fix, SpecFlow Edge Cases, Test Scenarios, Follow-up)
**Research sources:** npm security best practices (OpenSSF, Endor Labs), Docker build best practices, npm registry immutability guarantees, institutional learnings from docker-base-image-digest-pinning

### Key Improvements

1. Added research-backed rationale for why version pinning (not integrity hashing) is the correct approach for global npm installs
2. Added Dockerfile inline comment convention matching existing codebase pattern from #801
3. Identified additional follow-up issue: `node:22-slim` base image in web-platform also unpinned
4. Confirmed npm registry immutability guarantee makes version pinning equivalent to digest pinning for npm packages

### New Considerations Discovered

- Global `npm install -g` has no lockfile mechanism -- version pinning is the only available control
- npm registry guarantees published package versions are immutable (content-addressed storage) -- unlike Docker tags, an npm version string cannot be re-published with different content
- The `npm unpublish` window is 72 hours for new packages; after that, versions are permanently immutable

---

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

### Research Insights

**Why this matters (supply-chain risk):**

- The npm ecosystem has experienced multiple supply-chain attacks via package takeover and typosquatting (event-stream, ua-parser-js, colors.js)
- `npm install -g` with no version pin is equivalent to Docker's `FROM image:latest` -- it resolves to whatever is current at build time
- Unlike local project dependencies (which have `package-lock.json` for integrity verification), global installs have no lockfile mechanism -- version pinning is the only available control
- OpenSSF npm best practices explicitly recommend pinning all dependency versions in CI/CD environments

**Why version pinning is sufficient (no digest equivalent needed):**

- The npm registry guarantees that once a package version is published, its contents are immutable (content-addressed storage via SHA-512)
- `npm unpublish` is restricted to a 72-hour window for packages with fewer than 300 weekly downloads; established packages like `@anthropic-ai/claude-code` cannot be unpublished and re-published with different content
- This makes npm version strings functionally equivalent to Docker image digests for immutability purposes

## Proposed Fix

Pin to the current latest version (`2.1.79`) in both Dockerfiles:

```dockerfile
# apps/telegram-bridge/Dockerfile:9
RUN npm install -g @anthropic-ai/claude-code@2.1.79

# apps/web-platform/Dockerfile:4
RUN npm install -g @anthropic-ai/claude-code@2.1.79
```

### Implementation Notes

- **Comment convention:** Match the existing inline comment style from line 8 of telegram-bridge Dockerfile (`# Install Claude Code CLI via npm (avoids curl-pipe-shell antipattern)`). No comment change needed -- the existing comment already explains the "why".
- **Version choice:** `2.1.79` is the latest release as of 2026-03-19. The integrity hash is `sha512-oYBzNpOaqCJGhOvbAR+aiLVVyoLEDOCpKntnIjwzEvDAXmKfKzN+X6EKmvtzYQFSaVUlV42jAHqDZ3WVvoZpqw==`.
- **No code changes beyond the version suffix:** This is a pure string append (`@2.1.79`) on two lines. No functional behavior changes.

## Scope Decision: web-platform Dockerfile

Issue #802 only mentions telegram-bridge. However, `apps/web-platform/Dockerfile` has the identical problem on line 4 and uses `FROM node:22-slim` (also no digest pin, but that's a separate issue). Fixing both in this PR is consistent with #801's pattern of fixing the same class of issue across the codebase when discovered.

**Out of scope:** The `node:22-slim` base image in web-platform is unpinned (no digest). That's a separate issue -- file it if not already tracked.

## Acceptance Criteria

- [x] `apps/telegram-bridge/Dockerfile` pins `@anthropic-ai/claude-code` to version `2.1.79`
- [x] `apps/web-platform/Dockerfile` pins `@anthropic-ai/claude-code` to version `2.1.79`
- [x] Docker build succeeds for both images with pinned version
- [x] All existing tests pass
- [ ] PR body includes `Closes #802`

## Test Scenarios

- Given the telegram-bridge Dockerfile, when `docker build` runs, then it installs exactly `@anthropic-ai/claude-code@2.1.79` (not latest)
- Given the web-platform Dockerfile, when `docker build` runs, then it installs exactly `@anthropic-ai/claude-code@2.1.79` (not latest)
- Given a fresh build environment, when the Dockerfile is built twice at different times, then both builds produce the same claude-code version

### Verification Command

After building, verify the installed version inside the container:

```bash
docker run --rm <image> npx claude --version
# Expected output should include 2.1.79
```

## SpecFlow Edge Cases

1. **Version availability**: Version `2.1.79` is currently the latest on npm. If it gets unpublished (rare but possible with npm), the Docker build would fail loudly -- which is the correct behavior (fail-closed rather than silently installing a different version). Note: npm's unpublish policy makes this extremely unlikely for established packages (>300 weekly downloads cannot be unpublished after 72 hours).

2. **Future updates**: Updating claude-code requires a deliberate Dockerfile edit and PR. This is intentional friction -- the same pattern used for the base image pin in #801. Consider a Dependabot or Renovate rule to auto-create PRs for version bumps (out of scope for this PR).

3. **CI cache invalidation**: Pinning a specific version means Docker layer caching works correctly. Without a pin, `npm install -g @anthropic-ai/claude-code` could serve a stale cached layer even when a new version is available, creating inconsistency between cached and uncached builds. With pinning, the layer is deterministic -- it only invalidates when the Dockerfile line changes.

4. **Transitive dependency drift**: Even with the top-level package pinned, `npm install -g` resolves transitive dependencies at install time (no lockfile for global installs). This means transitive deps could differ between builds. This is an inherent limitation of global npm installs. For this use case (CLI tool), the risk is low -- `@anthropic-ai/claude-code` bundles its dependencies. If stricter control is needed in the future, consider vendoring the package or using a multi-stage build with a lockfile.

## Files to Modify

| File | Line | Change |
|------|------|--------|
| `apps/telegram-bridge/Dockerfile` | 9 | Add `@2.1.79` version suffix |
| `apps/web-platform/Dockerfile` | 4 | Add `@2.1.79` version suffix |

## Follow-up Issues

1. **`security(web-platform): pin Dockerfile base image node:22-slim to specific digest`** -- same pattern as #794 but for the web-platform image. The `FROM node:22-slim AS base` line has no digest pin.
2. **Consider automated dependency update tooling** (Dependabot/Renovate) to create PRs when new `@anthropic-ai/claude-code` versions are released, preventing version drift while maintaining the security of explicit pinning.

## References

- Issue: #802
- Related PR: #801 (base image digest pinning)
- Related issue: #794 (base image pinning)
- Learning: `knowledge-base/project/learnings/2026-03-19-docker-base-image-digest-pinning.md`
- npm registry: <https://www.npmjs.com/package/@anthropic-ai/claude-code>
- [OpenSSF npm Best Practices for the Supply Chain](https://openssf.org/blog/2022/09/01/npm-best-practices-for-the-supply-chain/)
- [How to Defend Against NPM Supply Chain Attacks (Endor Labs)](https://www.endorlabs.com/learn/how-to-defend-against-npm-software-supply-chain-attacks)
- [How to Pin Package Versions in Dockerfiles (OneUptime)](https://oneuptime.com/blog/post/2026-02-08-how-to-pin-package-versions-in-dockerfiles-for-reproducible-builds/view)
- [Docker Build Best Practices](https://docs.docker.com/build/building/best-practices/)
- [GitHub's Plan for a More Secure npm Supply Chain](https://github.blog/security/supply-chain-security/our-plan-for-a-more-secure-npm-supply-chain/)
