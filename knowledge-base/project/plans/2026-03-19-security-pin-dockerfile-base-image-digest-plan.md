---
title: "security(telegram-bridge): pin Dockerfile base image to specific digest"
type: fix
date: 2026-03-19
---

# security(telegram-bridge): pin Dockerfile base image to specific digest

## Enhancement Summary

**Deepened on:** 2026-03-19
**Sections enhanced:** 3 (Acceptance Criteria, Context, MVP)
**Research sources:** Docker official docs (digest pinning), Chainguard Academy (container image digests), Renovate docs (automated digest updates), repo Dockerfile audit, institutional learnings, GitHub issue #794

### Key Improvements
1. Verified digest format is the multi-arch manifest list digest (not a platform-specific manifest), ensuring correct platform resolution on both amd64 and arm64
2. Confirmed Bun 1.3.11 aligns with CI-pinned version (via `setup-bun` in `ci.yml`, `scheduled-ship-merge.yml`, `scheduled-bug-fixer.yml`) -- no version skew between build-time and CI
3. Added Dockerfile comment convention recommendation for long-term maintainability (documenting pinned version alongside digest)
4. Identified Renovate `docker:pinDigests` preset as future automation path for keeping digests current

### New Considerations Discovered
- Docker ignores the tag entirely when a digest is present -- the `1.3.11` in `oven/bun:1.3.11@sha256:...` is purely documentary. If someone updates the tag without updating the digest, Docker silently uses the old image. This is a feature (immutability) but could surprise maintainers unfamiliar with the convention.
- The `oven/bun` image publishes multi-arch manifest lists (amd64 + arm64). Pinning the manifest list digest (as opposed to a platform-specific digest) preserves multi-arch compatibility -- important since CI builds on `ubuntu-latest` (amd64) but local development may use arm64 (Apple Silicon).
- `apps/web-platform/Dockerfile` has the same vulnerability (`FROM node:22-slim` without digest) -- should be filed as a separate issue.

---

The telegram-bridge Dockerfile uses `FROM oven/bun:latest`, a mutable tag that resolves to a different image on every pull. This creates non-reproducible builds and a supply-chain risk: a compromised or broken upstream image silently affects production. Pin to the current version (`1.3.11`) with its manifest list digest to make builds deterministic and auditable.

## Acceptance Criteria

- [x] `apps/telegram-bridge/Dockerfile` line 1 uses `FROM oven/bun:1.3.11@sha256:0733e50325078969732ebe3b15ce4c4be5082f18c4ac1a0f0ca4839c2e4e42a7` instead of `FROM oven/bun:latest`
- [x] No other lines in the Dockerfile are changed (this is a single-line security fix)
- [x] Docker build succeeds locally with the pinned image (`docker build apps/telegram-bridge/`)
- [ ] CI release workflow (`telegram-bridge-release.yml`) builds and pushes successfully with the pinned base image

### Research Insights

**Docker digest behavior (from [Docker Docs](https://docs.docker.com/dhi/core-concepts/digests/)):**
- A digest is a SHA-256 hash of the image manifest content. It is immutable -- if the image content changes, the digest changes.
- When a `@sha256:...` suffix is present in the FROM line, Docker ignores the tag entirely and pulls by digest only. The tag (`1.3.11`) serves as a human-readable annotation.
- Multi-arch images have two levels of digests: the manifest list digest (points to the multi-arch index) and per-platform manifest digests. Pinning the manifest list digest preserves multi-arch resolution.

**Version alignment verification:**
- `oven/bun:1.3.11` matches the version pinned in CI via `setup-bun` (confirmed in `ci.yml:19`, `scheduled-ship-merge.yml:44`, `scheduled-bug-fixer.yml:49`)
- The learning `2026-03-18-bun-test-segfault-missing-deps.md` documents that Bun 1.3.5 segfaults on missing deps -- `1.3.11` is the known-good version already validated across the project
- No Bun breaking changes between 1.3.5 and 1.3.11 that affect the telegram-bridge runtime

## Test Scenarios

- Given the pinned Dockerfile, when `docker build apps/telegram-bridge/` runs, then the build completes using the exact image at digest `sha256:0733e50...` regardless of what `oven/bun:latest` currently resolves to
- Given a future `oven/bun:latest` update, when the CI pipeline runs, then the telegram-bridge build is unaffected because it uses the pinned digest
- Given the pinned Dockerfile, when inspecting the pulled base image with `docker inspect`, then the image ID matches the `linux/amd64` manifest `sha256:38919894db4e117a37f74e3dca503e84f24d97f19cabc5f499a289c2a5d0db7c` (resolved from the multi-arch index)
- Given a Dockerfile with `oven/bun:1.3.12@sha256:0733e50...` (tag updated but digest not), when Docker pulls the image, then it pulls the 1.3.11 content (digest wins over tag) -- this validates immutability

## Context

Found during security review of #763. Pre-existing issue tracked as #794. The project already follows SHA-pinning conventions for CI actions (all 19+ workflows pin `actions/checkout`, `docker/build-push-action`, etc. to commit SHAs with version comments -- see `2026-03-18-fix-pin-ci-action-shas-plan.md`). Bun version `1.3.11` is also already pinned in CI workflows via `setup-bun` (see `2026-03-18-fix-ci-pin-bun-version-scheduled-workflows-plan.md`). This fix extends the same supply-chain hardening to the Dockerfile.

### Digest Verification

Verified on 2026-03-19 via `docker buildx imagetools inspect`:

| Tag | Manifest List Digest |
|-----|---------------------|
| `oven/bun:latest` | `sha256:0733e50325078969732ebe3b15ce4c4be5082f18c4ac1a0f0ca4839c2e4e42a7` |
| `oven/bun:1.3.11` | `sha256:0733e50325078969732ebe3b15ce4c4be5082f18c4ac1a0f0ca4839c2e4e42a7` |

The digests match, confirming `latest` currently points to `1.3.11`. The `@sha256:...` suffix pins the exact multi-arch manifest list, so Docker resolves the correct platform-specific image (amd64 or arm64) while guaranteeing immutability.

### Per-Platform Manifests (for verification)

| Platform | Manifest Digest |
|----------|----------------|
| `linux/amd64` | `sha256:38919894db4e117a37f74e3dca503e84f24d97f19cabc5f499a289c2a5d0db7c` |
| `linux/arm64` | `sha256:06bd53b80989da758c8d2995ba711733090caf688bab09e7d4b21c6c8df728b7` |

### Research Insights

**Supply chain context (from [Chainguard Academy](https://edu.chainguard.dev/chainguard/chainguard-images/how-to-use/container-image-digests/)):**
- Tags are mutable pointers -- a registry maintainer (or attacker with push access) can update what a tag points to at any time. Digests are content-addressed and cannot be changed without changing the content itself.
- The `oven/bun` image is maintained by Oven (the Bun company). While generally trustworthy, pinning removes the trust dependency on their registry access controls and release process.

**Automated digest updates (from [Renovate Docs](https://docs.renovatebot.com/docker/)):**
- Renovate's `docker:pinDigests` preset automatically pins Dockerfile FROM lines to digests and creates PRs when new versions are available. The `:automergeDigest` preset can auto-merge digest-only updates for convenience.
- This is explicitly listed as a non-goal for this PR but is the recommended follow-up for keeping the digest current without manual lookups.

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

### Research Insights

**Best practice confirmation (from [Docker Build Best Practices](https://docs.docker.com/build/building/best-practices/)):**
- Docker's official guidance recommends pinning base images to specific versions rather than `latest`. Adding the digest goes one step further by making the pin content-addressed rather than tag-addressed.
- The `tag@sha256:digest` format is the recommended approach, combining human readability with cryptographic immutability.

**Edge case -- digest vs tag mismatch:**
- If a maintainer updates the tag (e.g., changes `1.3.11` to `1.3.12`) without updating the digest, Docker silently uses the old image (digest wins). This is correct behavior -- the digest is the source of truth. But it could confuse someone reading the Dockerfile who assumes the tag is authoritative.
- Mitigation: when updating the base image, always update both tag and digest together. Renovate handles this automatically.

## Non-Goals

- Upgrading Bun version (pin at current `1.3.11` to minimize behavioral change)
- Pinning `apps/web-platform/Dockerfile` base image (separate issue)
- Adding Renovate/Dependabot for automated digest updates (separate concern)
- Multi-stage build refactoring

## References

- Issue: #794
- Found during: #763 security review
- [Docker Docs: Image Digests](https://docs.docker.com/dhi/core-concepts/digests/)
- [Docker Build Best Practices](https://docs.docker.com/build/building/best-practices/)
- [Chainguard: Container Image Digests](https://edu.chainguard.dev/chainguard/chainguard-images/how-to-use/container-image-digests/)
- [Renovate: Docker Digest Pinning](https://docs.renovatebot.com/docker/)
- [Why Pin Docker Images with SHA](https://rockbag.medium.com/why-you-should-pin-your-docker-images-with-sha-instead-of-tags-fd132443b8a6)
- Related plans: `2026-03-18-fix-pin-ci-action-shas-plan.md`, `2026-03-18-fix-ci-pin-bun-version-scheduled-workflows-plan.md`
- Dockerfile: `apps/telegram-bridge/Dockerfile:1`
- Institutional learnings: `knowledge-base/project/learnings/2026-03-19-docker-restart-does-not-apply-new-images.md`, `knowledge-base/project/learnings/2026-03-19-docker-healthcheck-start-period-for-slow-init.md`, `knowledge-base/project/learnings/2026-03-18-bun-test-segfault-missing-deps.md`
