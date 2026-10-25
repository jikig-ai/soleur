---
title: "ADR-299: The release build cache is an inline registry cache, not the Actions cache"
status: Accepted
date: 2026-10-25
supersedes: []
amends: []
tags: [ci, github-actions, buildkit, release, cache]
---

# ADR-299: The release build cache is an inline registry cache, not the Actions cache

## Status

Accepted — 2026-10-25. The decision is accepted; its delivery is verified after merge by the first
release (build, signed digest, zot copy, offline verify) and by the follow-through on #10917 (Actions
cache usage under 8 GB once unused entries age out). If either fails, this ADR is amended.

## Context

`.github/workflows/reusable-release.yml` exported its BuildKit cache with
`cache-to: type=gha,mode=min,scope=web-platform-release`. The gha backend stores each changed layer blob
as its own entry in the repository's shared 10 GB Actions cache. Measured 2026-10-23 (#10917):
`active_caches_size_in_bytes=10231817250` across 178 entries, 9.6 GB of it release `buildkit-blob-*`
entries at about 1.17 GB per release, dominated by two layers whose hash changes every release (the
layers below `ENV BUILD_SHA` in `apps/web-platform/Dockerfile`), so they are never reused. Over the cap,
GitHub evicts least-recently-accessed first, so the churn evicted every other workflow's caches that
were older than about a day (npm, CodeQL, and the rehearsal skip monitor's streak, which moved to an
artifact in ADR-296 for that reason).

## Decision

The release docker build uses an inline registry cache: `cache-to: type=inline` and
`cache-from: type=registry,ref=<image>:latest`, with `provenance: false` set explicitly. The cache
metadata lives in the pushed GHCR image, so it writes nothing to the Actions cache. There is no
`type=gha` fallback, because a second backend would keep exporting.

Inline cache carries final-image layers only, which is the property `mode=min` gave the gha export: the
builder-stage `SENTRY_AUTH_TOKEN` layer stays out of it, and the rule that no non-public secret ARG may
reach the runner stage stays in the workflow comment. `provenance: false` stops build-args being
recorded in the default attestation (the repository is public, so the default would be `mode=max`);
nothing in the repository consumes release-image attestations. The cosign, zot-copy and verify steps
read the post-push digest, so the changed manifest (a single OCI image manifest instead of an index with
attestations) does not affect them.

Ruled by CTO agent (2026-10-25): `:latest` is the cache source, and only a run on `refs/heads/main` may
push it (the `:latest` tag line in the build step is gated on `github.ref`). A dedicated `:buildcache` tag
would add an ungated push with the same trust profile, since BuildKit cache keys are content-addressed and
poisoning needs GHCR write access that already allows pushing the image. The gate exists because the old
gha cache was ref-scoped and a global tag is not: `web-platform-release.yml` has a `workflow_dispatch` with
no branch guard, so a branch-built image's layers could otherwise be imported by the next main release and
signed as main (`ci-deploy.sh` pins the cosign identity to `reusable-release.yml@refs/heads/main`). A main
run that fails the zot gate has already advanced `:latest`; that image is main-built, so the trust is the
same, and the check that would flip this is a published release whose layers trace to a gate-failed build.
The test in `plugins/soleur/test/reusable-release-caller-permissions.test.sh` (section 4) pins the gate.

## Consequences

- The first release after merge builds cold once (the existing `:latest` carries no cache metadata). The
  drift monitor's sustained threshold is 225 minutes, far above the worst measured cold build (~22 minutes).
- Old `gha` entries are not deleted; unused entries are evicted by GitHub after 7 days.
- Dockerfile layers below `ENV BUILD_SHA` still rebuild on every release. Moving them is #5055 and is not
  needed for the cap.
- Layers above `ENV BUILD_VERSION` (apt, the gh apt repo, global npm tools, Playwright system packages) are
  reused for as long as the lines above them do not change. The gha cache evicted them after 7 days idle, so
  OS and security updates refreshed more often than a registry cache will; a base-image digest bump or an
  edit above those lines refreshes them.
- `provenance: false` ends new build-arg-bearing attestations (#7389: `SENTRY_AUTH_TOKEN` is a build-arg and
  the default on a public repository is `mode=max`). It does not retract attestations already published, and
  whether the token needs rotating is a decision outside this ADR. Nothing in the repository consumes
  release-image attestations. The durable fix for the build-arg itself (a BuildKit secret mount, PR #7390)
  is separate and, if it lands, must drop the `.SLSA` requirement of its verify step.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Scheduled cache-prune workflow | Mutates production state and treats the symptom; the writer is the problem. |
| `mode=max` or a scope split on the gha backend | `mode=max` exports the secret-bearing builder layer; a scope split still exports about the same bytes. |
| Reorder `ENV BUILD_SHA` below `npm ci --omit=dev` (#5055) | A build-speed win, not a cap fix: the gha export would still write the changed layers. |
| Dedicated `:buildcache` tag | Ungated extra push with the same trust profile as `:latest` (see Decision). |
| `provenance: mode=min` plus a BuildKit secret mount (#7389 / PR #7390) | The better long-term fix for the build-arg, but it keeps attestations that nothing reads and is an unmerged, separate change; `provenance: false` closes the forward leak now and does not preclude it. |

## Evidence

A local two-stage build against a throwaway registry (2026-10-25): with `provenance: false` and
`--cache-to type=inline`, the pushed tag is a single `application/vnd.oci.image.manifest.v1+json`, and a
rebuild with `--cache-from type=registry,ref=<tag>` reports the stable layer `CACHED` while the
per-release layer rebuilds.
