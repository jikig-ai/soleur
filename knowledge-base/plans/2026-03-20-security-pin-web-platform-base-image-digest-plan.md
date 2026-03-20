---
title: "security(web-platform): pin Dockerfile base image node:22-slim to specific digest"
type: fix
date: 2026-03-20
---

# security(web-platform): pin Dockerfile base image node:22-slim to specific digest

The web-platform Dockerfile uses `FROM node:22-slim AS base` without a digest pin on line 1. This is the same class of mutable-tag supply-chain risk that #794/#801 fixed for the telegram-bridge base image (`oven/bun`). A compromised or broken upstream `node:22-slim` image silently affects production builds. Pin to the current manifest list digest to make builds deterministic and auditable.

## Acceptance Criteria

- [ ] `apps/web-platform/Dockerfile` line 1 uses `FROM node:22-slim@sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d AS base` instead of `FROM node:22-slim AS base`
- [ ] No other lines in the Dockerfile are changed (single-line security fix)
- [ ] Docker build succeeds locally with the pinned image (`docker build apps/web-platform/`)
- [ ] CI release workflow (`web-platform-release.yml` via `reusable-release.yml`) builds and pushes successfully with the pinned base image

## Test Scenarios

- Given the pinned Dockerfile, when `docker build apps/web-platform/` runs, then the build completes using the exact image at digest `sha256:4f77a690...` regardless of what `node:22-slim` currently resolves to
- Given a future `node:22-slim` tag update (e.g., Node 22.x.y patch), when the CI pipeline runs, then the web-platform build is unaffected because it uses the pinned digest
- Given the pinned Dockerfile, when building on arm64 (Apple Silicon local dev), then Docker resolves the correct `linux/arm64/v8` platform manifest from the multi-arch index
- Given a Dockerfile with `node:22.15@sha256:4f77a690...` (tag updated but digest not), when Docker pulls the image, then it pulls the original `22-slim` content (digest wins over tag) -- validates immutability behavior

## Context

Filed as issue #805 during planning for #802. Pre-existing vulnerability identified in `apps/web-platform/Dockerfile:1`. The telegram-bridge Dockerfile (#801) already follows this exact pattern with `oven/bun:1.3.11@sha256:...`.

### Digest Verification

Verified on 2026-03-20 via `docker buildx imagetools inspect`:

| Tag | Manifest List Digest |
|-----|---------------------|
| `node:22-slim` | `sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d` |

The `@sha256:...` suffix pins the exact multi-arch manifest list, so Docker resolves the correct platform-specific image (amd64 for CI on `ubuntu-latest`, arm64 for local dev on Apple Silicon) while guaranteeing immutability.

### Per-Platform Manifests (for verification)

| Platform | Manifest Digest |
|----------|----------------|
| `linux/amd64` | `sha256:af5818e10f6294a719b4314f34ec03d8e8ad8f571a8d23742418790e6ebb5c90` |
| `linux/arm64/v8` | `sha256:fc7d5ecebef0bbf60003ed8ad5175ffed43f2952e5a6e553973c04461f57b6c9` |

### Institutional Learnings Applied

- **`2026-03-19-docker-base-image-digest-pinning.md`**: Docker ignores the tag entirely when a digest is present -- `22-slim` is purely documentary. Always update tag and digest together. Pin the manifest list digest (not platform-specific) to preserve multi-arch resolution.
- **`2026-03-19-docker-restart-does-not-apply-new-images.md`**: On the deployment server, `docker stop` + `docker rm` + `docker run` (already used in `web-platform-release.yml`) is required for new images to take effect -- `docker restart` reuses the old container image.

### SpecFlow Edge Cases

1. **Digest staleness**: The pinned digest will become stale as Node.js releases security patches. This is the intended trade-off (reproducibility over freshness). Future mitigation: Renovate `docker:pinDigests` preset.
2. **CI caching**: GitHub Actions Docker layer cache uses the FROM line as a cache key. Changing from `node:22-slim` to `node:22-slim@sha256:...` invalidates the cache once, then subsequent builds benefit from the same stable cache key (digest never changes until manually updated).
3. **Build args unaffected**: The `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` build args on lines 19-20 are unrelated to the base image pin -- no interaction.

## MVP

### `apps/web-platform/Dockerfile` (line 1)

**Before:**

```dockerfile
FROM node:22-slim AS base
```

**After:**

```dockerfile
FROM node:22-slim@sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d AS base
```

### Why `tag@sha256:digest` format

The `tag@sha256:...` format serves two purposes:

1. **Human readability** -- developers see at a glance which Node version the image is based on
2. **Immutability** -- Docker ignores the tag when a digest is present and pulls by content hash only

This mirrors the `@sha256:...` convention already used for:
- Telegram-bridge base image (`oven/bun:1.3.11@sha256:...` in `apps/telegram-bridge/Dockerfile`)
- CI action pinning (`actions/checkout@sha256:...` across all 19+ workflows)

## Non-Goals

- Upgrading Node.js version (pin at current `22-slim` to minimize behavioral change)
- Adding Renovate/Dependabot for automated digest updates (separate concern)
- Multi-stage build refactoring
- Non-root user setup (tracked separately in other worktrees)
- `.dockerignore` optimization (tracked separately)

## References

- Issue: #805
- Related PR: #801 (telegram-bridge base image digest pinning)
- Related issue: #794 (original base image pinning issue for telegram-bridge)
- Found during: #802 planning
- Dockerfile: `apps/web-platform/Dockerfile:1`
- Reference implementation: `apps/telegram-bridge/Dockerfile:1`
- Learning: `knowledge-base/learnings/2026-03-19-docker-base-image-digest-pinning.md`
- CI workflow: `.github/workflows/web-platform-release.yml` (uses `reusable-release.yml`)
- [Docker Docs: Image Digests](https://docs.docker.com/dhi/core-concepts/digests/)
- [Docker Build Best Practices](https://docs.docker.com/build/building/best-practices/)
