---
feature: cd-deploy-ci-gate-and-build-cache
date: 2026-06-08
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
branch: feat-cd-deploy-ci-gate-and-build-cache
pr: 5051
issue: 5052
brainstorm: knowledge-base/project/brainstorms/2026-06-08-cd-deploy-ci-gate-and-build-cache-brainstorm.md
---

# Spec: Gate prod deploy on CI + speed up the CD critical path

## Problem Statement

The web-platform prod deploy chain (`web-platform-release.yml`, triggered on `push:[main]`)
runs **independently of and in parallel with `ci.yml`** — the deploy is gated only on build +
migrate + Doppler-secret presence + a post-deploy health/version poll. The test suite gates
nothing. A PR that is green in isolation but broken by a semantic conflict on `main` (builds,
boots, health 200s) therefore **ships to prod undetected**, caught only after the fact by
post-merge CI or — for non-`[bot-fix]` commits — the 6-hour `main-health-monitor` cron.

Separately, the Docker image build has **no layer cache** (`docker/build-push-action` with no
`setup-buildx`, no `cache-from`/`cache-to`). Every release re-executes all pinned runner-stage
installs (claude-code, likec4, apt packages, gh, **playwright+chromium**) plus two `npm ci`
runs. Measured baseline: release chain ~13 min median vs. CI ~5 min median.

## Goals

- **G1.** A semantically broken `main` cannot reach prod: the `deploy` job waits for `ci.yml`'s
  `test` aggregator to succeed for the same commit SHA.
- **G2.** The gate adds ~zero wall-clock: the Docker image continues to build **in parallel**
  with CI (gate the cutover, not the build). Time-to-prod = `max(build_chain, CI)`.
- **G3.** Materially cut the ~13-min build via Docker layer caching, so most releases skip the
  pinned heavy layers and rebuild only source-dependent layers.
- **G4.** No existing deploy gate (migrate, verify-migrations, verify-doppler-secrets, health
  poll, flock, SHA assertion) is weakened or removed.

## Non-Goals

- **NG1.** Removing or reducing post-merge CI (`ci.yml` on `push:[main]`) — it remains the only
  per-push main-health signal and the `workflow_run` trigger for `post-merge-monitor.yml`.
- **NG2.** Rewriting the release trigger model to `workflow_run`-on-CI (rejected: cold-start +
  default-branch-context quirks; gating the `deploy` job is far smaller).
- **NG3.** A fast-smoke CI subset — unnecessary; CI (~5 min) is already faster than the build.
- **NG4.** Touching the plugin release path (`version-bump-and-release.yml`) — it ships no prod
  service; scope is web-platform only.

## Functional Requirements

- **FR1.** Add a wait-for-CI job to `web-platform-release.yml` that blocks until the `ci.yml`
  `test` required-context check-run for **this push's `${{ github.sha }}`** reaches a terminal
  conclusion.
- **FR2.** The `deploy` job gains this job as a `needs:` dependency; `deploy` proceeds only when
  CI's `test` concluded `success` (in addition to all existing `needs:` conditions).
- **FR3.** Fail-closed: if CI for the SHA concludes `failure`/`cancelled`/`timed_out`, or the
  wait exceeds a bounded ceiling without a terminal CI conclusion, the `deploy` job does **not**
  run (no prod cutover on unknown/red CI state).
- **FR4.** The `release` (build + Docker push), `migrate`, `verify-migrations`, and
  `verify-doppler-secrets` jobs are **unchanged in their trigger ordering** — the image builds
  in parallel with CI; only the final `deploy` cutover waits.
- **FR5.** Add `docker/setup-buildx-action` and configure `cache-from`/`cache-to` (default
  `type=gha`, `mode=max`) on the `docker/build-push-action` step in `reusable-release.yml`.
- **FR6.** Audit the Dockerfile layer order so the rarely-changing heavy runner-stage installs
  are cacheable independent of source-busting `COPY` layers (maximize FR5 hit rate). Make only
  order-preserving moves that do not change the final image contents.

## Technical Requirements

- **TR1.** Same-SHA correctness: the wait-for-CI job must key on `${{ github.sha }}`, not the
  latest/any CI run — `main`'s `concurrency` group lets prior runs finish, so a stale run must
  not satisfy the gate.
- **TR2.** Wait mechanism: prefer a small inline `gh api` poll of the check-runs for the SHA
  (no new third-party dependency). If a third-party action is used instead, it MUST be
  SHA-pinned per the repo's vendor-pin discipline (`vendor-pin-verify.yml`).
- **TR3.** The `test` context name is load-bearing (branch-protection ruleset 14145388). The
  wait job MUST reference it by the exact same name; do not rename.
- **TR4.** Bounded wait ceiling for FR3, sized above the p100 CI duration (≥15 min suggested,
  given ~8 min observed max) with explicit fail-closed on timeout.
- **TR5.** `type=gha` cache: verify the Playwright/Chromium layer fits within the 10 GB repo
  cache budget and is not evicted by sibling-workflow caches; document the cache key strategy.
- **TR6.** No secret exposure regression: build-args and `cache-to` must not write secret
  material into a cache scope readable outside the workflow.

## Secondary / Optional Scope (implement only if low-risk)

- **OS1 (lever 2).** Parallelize `migrate` with the Docker build by splitting version-compute
  into its own lightweight job that both the build and `migrate` depend on, removing the slow
  image build from the `migrate → deploy` serial path. Gated behind staying small and not
  disturbing the `release.outputs.version` / `docker_pushed` contracts the `deploy` job reads.

## Acceptance Criteria

- **AC1.** A PR that lands a deliberately test-breaking change on `main` (in a fixture/dry-run
  context) does NOT trigger a prod cutover; the `deploy` job is blocked by the wait-for-CI job.
- **AC2.** A normal green merge deploys with no measurable added wall-clock vs. baseline (CI
  concludes before the build chain reaches `deploy`).
- **AC3.** A second consecutive release with unchanged dependencies shows Docker cache hits for
  the runner-stage install layers (claude-code, likec4, apt, gh, playwright) in build logs.
- **AC4.** All pre-existing deploy gates and post-deploy health/SHA assertions still fire.
- **AC5.** `vendor-pin-verify.yml`, `infra-validation.yml`, and the `test` required-context
  remain green; no ruleset context renamed or orphaned.
