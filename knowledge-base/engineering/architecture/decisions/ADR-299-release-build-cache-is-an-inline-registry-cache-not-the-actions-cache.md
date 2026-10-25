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

Ruled by CTO agent (2026-10-25): `:latest` is the cache source. A dedicated `:buildcache` tag would add
an ungated push with the same trust profile, since BuildKit cache keys are content-addressed and
poisoning needs GHCR write access that already allows pushing the image. `:latest` is moved by the build
step before the zot gate runs; the old gha scope had the same profile. This flips if a build that failed
the zot gate is shown to have fed a later published build.

## Consequences

- The first release after merge builds cold once (the existing `:latest` carries no cache metadata).
- Old `gha` entries are not deleted; unused entries are evicted by GitHub after 7 days.
- Dockerfile layers below `ENV BUILD_SHA` still rebuild on every release. Moving them is #5055 and is not
  needed for the cap.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Scheduled cache-prune workflow | Mutates production state and treats the symptom; the writer is the problem. |
| `mode=max` or a scope split on the gha backend | `mode=max` exports the secret-bearing builder layer; a scope split still exports about the same bytes. |
| Reorder `ENV BUILD_SHA` below `npm ci --omit=dev` (#5055) | A build-speed win, not a cap fix: the gha export would still write the changed layers. |
| Dedicated `:buildcache` tag | Ungated extra push with the same trust profile as `:latest` (see Decision). |

## Evidence

A local two-stage build against a throwaway registry (2026-10-25): with `provenance: false` and
`--cache-to type=inline`, the pushed tag is a single `application/vnd.oci.image.manifest.v1+json`, and a
rebuild with `--cache-from type=registry,ref=<tag>` reports the stable layer `CACHED` while the
per-release layer rebuilds.
