---
title: "security(telegram-bridge): pin Dockerfile base image to specific digest"
type: fix
date: 2026-03-19
---

# security(telegram-bridge): pin Dockerfile base image to specific digest

## Enhancement Summary

**Deepened on:** not yet
**Research sources:** Docker Hub manifest inspection, repo Dockerfile audit, institutional learnings, GitHub issue #794

---

The telegram-bridge Dockerfile uses `FROM oven/bun:latest`, a mutable tag that resolves to a different image on every pull. This creates non-reproducible builds and a supply-chain risk: a compromised or broken upstream image silently affects production. Pin to the current version (`1.3.11`) with its manifest list digest to make builds deterministic and auditable.

## Acceptance Criteria

- [ ] `apps/telegram-bridge/Dockerfile` line 1 uses `FROM oven/bun:1.3.11@sha256:0733e50325078969732ebe3b15ce4c4be5082f18c4ac1a0f0ca4839c2e4e42a7` instead of `FROM oven/bun:latest`
- [ ] No other lines in the Dockerfile are changed (this is a single-line security fix)
- [ ] Docker build succeeds locally with the pinned image (`docker build apps/telegram-bridge/`)
- [ ] CI release workflow (`telegram-bridge-release.yml`) builds and pushes successfully with the pinned base image

## Test Scenarios

- Given the pinned Dockerfile, when `docker build apps/telegram-bridge/` runs, then the build completes using the exact image at digest `sha256:0733e50...` regardless of what `oven/bun:latest` currently resolves to
- Given a future `oven/bun:latest` update, when the CI pipeline runs, then the telegram-bridge build is unaffected because it uses the pinned digest
- Given the pinned Dockerfile, when inspecting the pulled base image with `docker inspect`, then the image ID matches the `linux/amd64` manifest `sha256:38919894db4e117a37f74e3dca503e84f24d97f19cabc5f499a289c2a5d0db7c` (resolved from the multi-arch index)

## Context

Found during security review of #763. Pre-existing issue tracked as #794. The project already follows SHA-pinning conventions for CI actions (all 19+ workflows pin `actions/checkout`, `docker/build-push-action`, etc. to commit SHAs with version comments -- see `2026-03-18-fix-pin-ci-action-shas-plan.md`). Bun version `1.3.11` is also already pinned in CI workflows via `setup-bun` (see `2026-03-18-fix-ci-pin-bun-version-scheduled-workflows-plan.md`). This fix extends the same supply-chain hardening to the Dockerfile.

### Digest Verification

Verified on 2026-03-19 via `docker buildx imagetools inspect`:

| Tag | Manifest List Digest |
|-----|---------------------|
| `oven/bun:latest` | `sha256:0733e50325078969732ebe3b15ce4c4be5082f18c4ac1a0f0ca4839c2e4e42a7` |
| `oven/bun:1.3.11` | `sha256:0733e50325078969732ebe3b15ce4c4be5082f18c4ac1a0f0ca4839c2e4e42a7` |

The digests match, confirming `latest` currently points to `1.3.11`. The `@sha256:...` suffix pins the exact multi-arch manifest list, so Docker resolves the correct platform-specific image (amd64 or arm64) while guaranteeing immutability.

### Related Pre-Existing Issue

`apps/web-platform/Dockerfile` uses `FROM node:22-slim` without a digest pin -- the same class of vulnerability. Out of scope for this issue; should be tracked separately.

## MVP

### `apps/telegram-bridge/Dockerfile` (line 1)

**Before:**
```dockerfile
FROM oven/bun:latest
```

**After:**
```dockerfile
FROM oven/bun:1.3.11@sha256:0733e50325078969732ebe3b15ce4c4be5082f18c4ac1a0f0ca4839c2e4e42a7
```

### Why version + digest (not digest alone)

The `version@sha256:...` format serves two purposes:
1. **Human readability** -- developers can see at a glance which Bun version the image is based on
2. **Immutability** -- Docker ignores the tag when a digest is present and pulls by content hash only

This mirrors the `@<sha> # vX.Y.Z` convention used for CI action pinning throughout the repository.

## Non-Goals

- Upgrading Bun version (pin at current `1.3.11` to minimize behavioral change)
- Pinning `apps/web-platform/Dockerfile` base image (separate issue)
- Adding Renovate/Dependabot for automated digest updates (separate concern)
- Multi-stage build refactoring

## References

- Issue: #794
- Found during: #763 security review
- OWASP Docker Security: pin base images
- Related plans: `2026-03-18-fix-pin-ci-action-shas-plan.md`, `2026-03-18-fix-ci-pin-bun-version-scheduled-workflows-plan.md`
- Dockerfile: `apps/telegram-bridge/Dockerfile:1`
- Institutional learnings: `knowledge-base/learnings/2026-03-19-docker-restart-does-not-apply-new-images.md`, `knowledge-base/learnings/2026-03-19-docker-healthcheck-start-period-for-slow-init.md`
