---
title: "fix(deploy): resolve Docker build ERESOLVE failure and prevent deploy-on-build-failure"
type: fix
date: 2026-03-30
---

# fix(deploy): resolve Docker build ERESOLVE failure and prevent deploy-on-build-failure

## Overview

The Web Platform production server is stuck on v0.9.7 because every release since PR #1306 fails at the Docker build step with an `npm ERESOLVE` peer dependency conflict. The deploy job fires anyway (due to a workflow condition bug) and the verification step correctly reports a version mismatch. Two distinct bugs compound into one symptom.

## Problem Statement

### Primary bug: Docker build fails with ERESOLVE

PR #1306 (`aeec24e1`) added `@vitejs/plugin-react@^6.0.1` to `devDependencies` but did not regenerate `package-lock.json`. The lockfile resolves `vite@5.4.21` (from `vitest@^3.1.0`), but `@vitejs/plugin-react@6.0.1` requires `vite@^6.0.0` as a peer dependency. `npm ci` enforces strict peer resolution and fails:

```text
npm error code ERESOLVE
npm error ERESOLVE could not resolve
npm error While resolving: @vitejs/plugin-react@6.0.1
npm error Found: vite@5.4.21
```

This is the exact pattern documented in learning `2026-03-29-post-merge-release-workflow-verification.md` (PR #1275 broke builds the same way with Playwright). The systemic fix from that learning (post-merge release verification in `/ship` Phase 7) was implemented, but the preventive fix (enforcing lockfile sync in CI) was not.

### Secondary bug: deploy fires when Docker build fails

The deploy job in `web-platform-release.yml` uses:

```yaml
if: >-
  always() &&
  needs.release.outputs.version != '' &&
  ...
```

The `always()` function causes the deploy job to run regardless of the release job's conclusion. Since `version` is computed in an early step (before Docker build), the output is available even when the build fails. The deploy webhook fires, the server attempts `docker pull` on a non-existent image, the canary pattern rolls back correctly, and verification reports a version mismatch.

### Impact

- 5 consecutive release runs failed (web-v0.9.8 through web-v0.10.0 all had Docker build failures)
- Production is running v0.9.7 (last successful deploy from 2026-03-30T06:07)
- New features from PRs #1282, #1283, #1284, #1275, #1289, #1299, #1300, #1306 are not live
- Each failed deploy sends a spurious webhook to the production server, triggering an unnecessary canary cycle

### Timeline of failures

| Run | PR | Version | Build Step | Deploy Step |
|-----|-----|---------|-----------|-------------|
| 23714097067 | manual | 0.8.6 | success | success (last good deploy) |
| 23714561544 | #1275 | 0.8.7 | FAIL (EUSAGE: missing Playwright in lockfile) | FAIL (version mismatch) |
| 23715833492 | #1282 | 0.8.8 | FAIL (ERESOLVE) | FAIL (version mismatch) |
| 23715935176 | #1284 | 0.8.9 | FAIL | FAIL |
| 23716133528 | #1283 | 0.9.0 | FAIL | FAIL |
| 23716451087 | #1285 | 0.9.1 | FAIL | FAIL |
| 23716582437 | #1293 | 0.9.2 | success (lockfile fix) | success |
| ... | ... | ... | success | success |
| 23730476844 | #1296 | 0.9.7 | success | success (current prod) |
| 23731850092 | #1306 | 0.10.0 | FAIL (ERESOLVE: plugin-react vs vite) | FAIL (version mismatch) |

Note: PR #1293 fixed the Playwright lockfile issue, but PR #1306 re-introduced a new lockfile desync with `@vitejs/plugin-react`.

## Proposed Solution

### Shipping strategy: two PRs

Per review feedback, split into an urgent fix and a hardening follow-up:

- **PR 1 (this branch):** Task 1 only -- regenerate lockfiles, unblock production deploy
- **PR 2 (follow-up issue):** Tasks 2 + 3 -- deploy gating and CI lockfile check

### Task 1: Fix the package-lock.json desync (urgent -- this PR)

Regenerate `package-lock.json` to resolve the `@vitejs/plugin-react@6.0.1` peer dependency on `vite@^6`. This requires either:

- ~~**Option A**: Upgrade `vite` to v6~~ — Not viable. `@vitejs/plugin-react@6.0.1` requires `vite@^8.0.0`, not `^6.0.0` as initially assumed. Upgrading to vite@8 would be a major change.
- **Option B (chosen)**: Pin `@vitejs/plugin-react` to `^4.7.0` which supports `vite@^4 || ^5 || ^6 || ^7`. This is compatible with the project's existing `vite@5.4.21` resolved via `vitest@^3.1.0`.

**Files:**

- `apps/web-platform/package.json` (possibly adjust version range)
- `apps/web-platform/package-lock.json` (regenerate)
- `apps/web-platform/bun.lock` (regenerate for consistency, per constitution rule)

After merge, verify deploy via ship Phase 7 (automated). If the path filter skips auto-trigger, run `gh workflow run web-platform-release.yml -f bump_type=patch`.

### Task 2: Gate deploy on Docker build success (follow-up PR)

Change the deploy job condition to prevent firing when the Docker image was never pushed.

**Current:**

```yaml
deploy:
  needs: [release, migrate]
  if: >-
    always() &&
    needs.release.outputs.version != '' &&
    ...
```

**Better approach**: Add a new output `docker_pushed` from the reusable release workflow that is only set when the Docker build+push step succeeds. Gate the deploy on this output instead:

```yaml
deploy:
  needs: [release, migrate]
  if: >-
    always() &&
    needs.release.outputs.docker_pushed == 'true' &&
    (needs.migrate.result == 'success' || needs.migrate.result == 'skipped') &&
    ...
```

**Timing gap (from review):** The Docker build step is currently gated on `steps.create_release.outputs.released == 'true'`. On retry (release already exists), `released` is `'false'`, so the Docker build is skipped and `docker_pushed` would never be set. Fix: change the Docker build step condition from `released == 'true'` to `version != '' && docker_image != ''` so it runs on retry too. This also requires skipping the push if the image already exists in GHCR (idempotency for Docker).

**Files:**

- `.github/workflows/reusable-release.yml` (add `docker_pushed` output, fix Docker build step condition)
- `.github/workflows/web-platform-release.yml` (gate deploy on `docker_pushed`)
- `.github/workflows/telegram-bridge-release.yml` (apply same fix for consistency)

### Task 3: Add CI lockfile sync check (follow-up PR)

Add a step to the PR CI workflow that verifies `package-lock.json` is in sync with `package.json` when dependency files change.

**Approach**: Add a job that runs `npm install --package-lock-only` in `apps/web-platform/` and checks for uncommitted changes to `package-lock.json`. Fail with a clear error message if changes are detected. Scope to trigger only when `apps/web-platform/package.json` changes.

**Note (from review):** This is a band-aid over the dual-lockfile problem (bun for local dev, npm for Docker). The deeper fix is to pick one package manager. File a separate issue to evaluate removing the dual-lockfile setup.

**Files:**

- `.github/workflows/ci.yml` or equivalent PR CI workflow (add lockfile sync check)

## Technical Considerations

### Peer dependency resolution

`@vitejs/plugin-react@6.x` requires `vite@^6`. The project uses `vitest@^3.1.0` which pulls in `vite` as a peer dependency. Need to verify:

1. Does `vitest@3.x` support `vite@6`? (check vitest's peerDependencies)
2. If not, is there a `@vitejs/plugin-react@5.x` that supports `vite@5`?

The `vitest@3.2.4` lockfile entry shows `peerOptional vite@"^5.0.0 || ^6.0.0 || ^7.0.0-0"` -- so vitest supports both vite 5 and 6. Running `npm install` should resolve to vite@6 since `@vitejs/plugin-react@6.0.1` requires it.

### Dockerfile build stages

The Dockerfile has two `npm ci` calls:

1. Stage 1 (`deps`): `npm ci` -- installs ALL dependencies (including devDependencies like vite, vitest, plugin-react)
2. Stage 3 (`runner`): `npm ci --omit=dev` -- installs only production dependencies

The ERESOLVE failure occurs in Stage 1. The production image (Stage 3) does not include vite or plugin-react at all, so the fix has no production impact beyond unblocking the build.

### Deploy retry semantics

The `always()` in the deploy condition was intentional -- it allows deploy to run even when the release job is marked as "failed" due to an idempotency skip. The fix must preserve this retry behavior while adding a check that the Docker image actually exists.

### Existing learnings that apply

- `2026-03-29-post-merge-release-workflow-verification.md`: Exact same pattern (lockfile desync breaking Docker builds)
- `2026-03-19-docker-restart-does-not-apply-new-images.md`: Server-side deploy mechanics
- `2026-03-21-async-webhook-deploy-cloudflare-timeout.md`: Webhook deploy architecture
- `2026-03-28-canary-rollback-docker-deploy.md`: Canary pattern handles the failed pull gracefully
- `2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md`: Deploy retry gating

## Acceptance Criteria

- [x] `npm ci` succeeds in `apps/web-platform/` with the updated `package-lock.json`
- [ ] Docker build for web-platform completes successfully in CI
- [ ] Deploy job does NOT fire when Docker build fails (test by checking workflow condition logic)
- [ ] Deploy job DOES fire when Docker build succeeds (preserves normal flow)
- [ ] Deploy job DOES fire on retry when release already exists but Docker build succeeds (preserves retry)
- [ ] Production server reports the new version on `/health` endpoint after merge
- [ ] PR CI fails when `package-lock.json` is out of sync with `package.json` (preventive check)

## Test Scenarios

- Given a PR that changes `package.json` devDependencies, when `package-lock.json` is not regenerated, then PR CI fails with a clear error about lockfile desync
- Given a release run where Docker build fails, when the deploy job evaluates its condition, then it is skipped (not run)
- Given a release run where Docker build succeeds, when the deploy job evaluates its condition, then it fires the webhook and verifies deployment
- Given a retry of an existing release (idempotency skip), when Docker build succeeds on retry, then the deploy job fires normally
- **API verify:** `curl -sf "https://app.soleur.ai/health" | jq '.version'` expects the new version string after deploy

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| `vite@6` upgrade may break existing vitest config | Verify tests pass locally before committing |
| Changing deploy condition may break retry workflow | Add `docker_pushed` output instead of removing `always()` |
| CI lockfile check may have false positives on unrelated PRs | Scope check to only run when `apps/web-platform/package.json` changes |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/CI fix with no user-facing, legal, marketing, or financial impact.

## References

- Issue: [#1307](https://github.com/jikig-ai/soleur/issues/1307)
- Failed run: [23731850092](https://github.com/jikig-ai/soleur/actions/runs/23731850092)
- PR that introduced the desync: [#1306](https://github.com/jikig-ai/soleur/pull/1306)
- Previous lockfile fix: [#1293](https://github.com/jikig-ai/soleur/pull/1293)
- Learning: `knowledge-base/project/learnings/2026-03-29-post-merge-release-workflow-verification.md`
- Learning: `knowledge-base/project/learnings/2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md`
- Learning: `knowledge-base/project/learnings/2026-03-21-async-webhook-deploy-cloudflare-timeout.md`
- Learning: `knowledge-base/project/learnings/implementation-patterns/2026-03-28-canary-rollback-docker-deploy.md`
