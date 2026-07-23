---
title: A plan's "live-confirmed anonymous" registry/auth probe is a cached-creds false-confirm that 401s in CI
date: 2026-07-05
category: integration-issues
module: .github/workflows, apps/web-platform/infra
tags: [ghcr, docker, github-actions, permissions, auth, plan-probe, ci-vs-local, false-confirm]
severity: medium
related:
  - "[[2026-06-16-external-api-shape-ac-must-land-captured-fixture-not-probed-claim]]"
  - "[[2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns]]"
---

# "Live-confirmed anonymous" registry access is a cached-creds false-confirm in CI

## Problem

PR #6030's `web_2_recreate` CI job resolves web-1's running image tag → immutable
`@sha256` digest via `docker buildx imagetools inspect ghcr.io/…/soleur-web-platform:<tag>`.
The plan recorded (`session-state.md`): *"resolve @sha256 via docker buildx imagetools
inspect (live-confirmed no-auth on public repo)."* The job had no `permissions:` block
(inheriting workflow-level `contents: read` only) and never ran `docker login`.

The first real dispatch failed in ~1 minute:
```
ERROR: failed to authorize: failed to fetch anonymous token: … 401 Unauthorized
##[error]tag->digest resolution returned '' … Aborting BEFORE -replace.
```
GHCR is a **private** package. The plan's "live-confirmed no-auth" was almost certainly
run on a machine whose Docker had cached `ghcr.io` credentials (`~/.docker/`
from a prior `docker login`), so the local `imagetools inspect` succeeded *authenticated*
while appearing anonymous. In CI (ephemeral runner, no login), the same command is
genuinely anonymous → 401.

## Solution

Authenticate before the pull, mirroring the repo's own release workflow
(`reusable-release.yml:425-432`):
- Add job-level `permissions: { contents: read, packages: read }` (GHA job permissions
  are a **full replacement** of the workflow default, not additive — so re-state
  `contents: read`; `packages: read` is the minimal scope for an `imagetools inspect` pull).
- `printf '%s' "$GH_TOKEN" | docker login ghcr.io -u "$GH_ACTOR" --password-stdin` (token
  via stdin, never argv), with `GH_TOKEN=${{ secrets.GITHUB_TOKEN }}` / `GH_ACTOR=${{ github.actor }}`.
- `GITHUB_TOKEN` + `packages: read` has pull access because the package is pushed by the
  same repo's release workflow (auto-linked to the repo).

## Key insight

An anonymous-access claim about a registry, API, or endpoint that was "verified locally"
is only trustworthy if verified in a **credential-free context**. `docker`/`gh`/`aws`/`gcloud`
all silently fall back to cached creds, so a local probe proves "I can reach it," NOT
"it is anonymously reachable." Generalizes the captured-evidence rule
([[2026-06-16-external-api-shape-ac-must-land-captured-fixture-not-probed-claim]]): for an
anonymous-access AC, the evidence must be a probe run with creds explicitly scrubbed
(`docker logout` / `env -i` / a fresh container / the CI runner itself), not a claim.

**The safety architecture worked perfectly:** the 401 aborted at the FIRST step, before any
`terraform -replace` — zero destruction, web-1 untouched, prod 200 throughout. The
fail-closed "abort BEFORE -replace on any resolution failure" design turned a plan-probe
error into a safe no-op instead of a bad recreate.

## Prevention

- When a plan/AC asserts anonymous/unauthenticated access to a registry or API, require the
  confirming probe to be run credential-scrubbed (or in CI), and prefer wiring auth anyway
  (least-privilege token) since it is free when the resource turns out to be private.
- For any CI step that pulls from GHCR, default to `packages: read` + `docker login` with
  `GITHUB_TOKEN` — do not assume public.
