---
title: "security(web-platform): pin Dockerfile base image node:22-slim to specific digest"
type: fix
date: 2026-03-20
---

# security(web-platform): pin Dockerfile base image node:22-slim to specific digest

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 3 (Acceptance Criteria, Context, MVP)
**Research sources:** Docker official docs (digest pinning best practices, build policies), Context7 Docker documentation, institutional learnings (5 relevant), repo Dockerfile audit, GitHub issue #805

### Key Improvements
1. Confirmed via Docker official documentation that `tag@sha256:digest` is the canonical pinning format -- Docker ignores the tag when digest is present, making the tag purely documentary
2. Verified the digest `sha256:4f77a690...` is the multi-arch manifest list digest (not platform-specific), preserving correct resolution on both amd64 (CI) and arm64 (local dev)
3. Confirmed existing `npm install -g @anthropic-ai/claude-code@2.1.79` on Dockerfile line 4 is already version-pinned per `npm-global-install-version-pinning` learning -- no additional supply-chain fix needed in this PR
4. Validated deploy workflow (`web-platform-release.yml`) already uses stop/rm/run pattern (not `docker restart`) per `docker-restart-does-not-apply-new-images` learning -- digest change propagates correctly on deploy

### New Considerations Discovered
- Docker supports Rego-based build policies that can enforce digest pinning organization-wide (`input.image.isCanonical` check). Not in scope for this PR but a viable future enforcement mechanism.
- The `node:22-slim` tag resolves to Debian bookworm-slim base (confirmed via `org.opencontainers.image.base.name: debian:bookworm-slim` annotation). This is relevant for future hardening (distroless or Chainguard alternatives).
- After this PR, all Dockerfiles in the repository will use digest-pinned base images -- the web-platform was the last remaining unpinned image.

---

The web-platform Dockerfile uses `FROM node:22-slim AS base` without a digest pin on line 1. This is the same class of mutable-tag supply-chain risk that #794/#801 fixed for the telegram-bridge base image (`oven/bun`). A compromised or broken upstream `node:22-slim` image silently affects production builds. Pin to the current manifest list digest to make builds deterministic and auditable.

## Acceptance Criteria

- [x] `apps/web-platform/Dockerfile` line 1 uses `FROM node:22-slim@sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d AS base` instead of `FROM node:22-slim AS base`
- [x] No other lines in the Dockerfile are changed (single-line security fix)
- [x] Docker build succeeds locally with the pinned image (`docker build apps/web-platform/`)
- [ ] CI release workflow (`web-platform-release.yml` via `reusable-release.yml`) builds and pushes successfully with the pinned base image

### Research Insights

**Docker Official Documentation Confirmation ([Docker Build Best Practices](https://docs.docker.com/build/building/best-practices/)):**
- "To fully secure your supply chain integrity, you can pin the image version to a specific digest. By pinning your images to a digest, you're guaranteed to always use the same image version, even if a publisher replaces the tag with a new image."
- The `tag@sha256:digest` format is the canonical approach recommended by Docker, combining human readability with cryptographic immutability.

**Completeness check:** After this change, all Dockerfiles in the repository (`apps/telegram-bridge/Dockerfile`, `apps/web-platform/Dockerfile`) will use digest-pinned base images. No remaining unpinned FROM lines.

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
4. **Existing supply-chain pins intact**: Line 4 (`npm install -g @anthropic-ai/claude-code@2.1.79`) is already version-pinned per the `npm-global-install-version-pinning` learning. npm's immutability guarantee makes this functionally equivalent to a digest pin for packages.
5. **Deploy propagation verified**: The `web-platform-release.yml` deploy job uses `docker stop` + `docker rm` + `docker run` (lines 54-65), not `docker restart`. Per the `docker-restart-does-not-apply-new-images` learning, this correctly applies the new image on deploy. No changes needed to the deploy workflow.

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

### Research Insights

**Docker digest semantics (from [Docker Docs: Digests](https://docs.docker.com/dhi/core-concepts/digests/)):**
- A digest is a SHA-256 hash of the image manifest content. It is immutable -- if the image content changes, the digest changes.
- `docker pull node:22-slim@sha256:4f77a690...` retrieves exactly the image with that content hash, regardless of what the `22-slim` tag currently points to.
- Multi-arch images have two levels: the manifest list digest (index) and per-platform manifest digests. Pinning the manifest list digest preserves multi-arch resolution.

**Build policy enforcement (from [Docker Build Policies](https://docs.docker.com/build/policies/)):**
- Docker supports Rego-based build policies that can enforce digest pinning via `input.image.isCanonical`. This is a future enforcement option for organization-wide policy, not needed for this single-fix PR.

**Simplicity assessment:**
- This change is already minimal -- a single line modification with zero behavioral impact beyond supply-chain hardening. No abstractions, no new patterns, no code to maintain. The plan correctly scopes this as a single-line fix with no other Dockerfile changes.

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
- Learning: `knowledge-base/project/learnings/2026-03-19-docker-base-image-digest-pinning.md`
- CI workflow: `.github/workflows/web-platform-release.yml` (uses `reusable-release.yml`)
- [Docker Docs: Image Digests](https://docs.docker.com/dhi/core-concepts/digests/)
- [Docker Build Best Practices](https://docs.docker.com/build/building/best-practices/)
