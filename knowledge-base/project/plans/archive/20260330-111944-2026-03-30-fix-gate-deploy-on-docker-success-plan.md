---
title: "fix(ci): gate deploy job on Docker build success"
type: fix
date: 2026-03-30
---

# fix(ci): gate deploy job on Docker build success

## Enhancement Summary

**Deepened on:** 2026-03-30
**Sections enhanced:** 4 (Proposed Solution, Technical Considerations, Test Scenarios, Acceptance Criteria)
**Research sources:** GitHub Actions docs, project learnings (5 relevant), workflow file analysis

### Key Improvements

1. Added edge case analysis for retry path with `check_changed` gate interaction
2. Identified that `docker/build-push-action` (composite action) supports `outcome` the same as `run:` steps
3. Added concrete step-by-step execution traces for all three paths (first-run, retry, failure)
4. Strengthened test scenarios with specific output value assertions

## Overview

The deploy job in `web-platform-release.yml` uses `always()` combined with `needs.release.outputs.version != ''` to decide whether to deploy. Because `version` is computed before the Docker build step, the condition is true even when Docker build fails. This causes spurious deploy webhooks to fire against non-existent images, triggering unnecessary canary rollback cycles on the production server.

This plan implements Task 2 from the parent plan (`2026-03-30-fix-deploy-verification-docker-build-plan.md`), addressing issue #1317.

## Problem Statement

### The `always()` + `version` gate is insufficient

The current deploy condition in `web-platform-release.yml`:

```yaml
deploy:
  needs: [release, migrate]
  if: >-
    always() &&
    needs.release.outputs.version != '' &&
    (needs.migrate.result == 'success' || needs.migrate.result == 'skipped') &&
    (github.event_name != 'workflow_dispatch' || !inputs.skip_deploy)
```

The `always()` is intentional -- it allows deploy to run even when the release job is marked "failed" (which happens on idempotency skip). However, `version` is set in an early step (before Docker build), so it is available regardless of whether Docker build+push succeeded. The deploy fires, the server attempts `docker pull` on a non-existent image, and the canary pattern rolls back.

### Docker build step is skipped on retry

The Docker build and login steps in `reusable-release.yml` (lines 266-274) are conditioned on:

```yaml
if: steps.create_release.outputs.released == 'true' && inputs.docker_image != ''
```

On retry (when the release already exists), `released` is `'false'` because the `create_release` step is skipped by its own condition (`idempotency.outputs.exists == 'false'`). This means the Docker build is skipped entirely on retry, even when the Docker image was never successfully pushed.

### telegram-bridge has the same latent bug

The `telegram-bridge-release.yml` deploy condition is:

```yaml
if: needs.release.outputs.version != '' && (github.event_name != 'workflow_dispatch' || !inputs.skip_deploy)
```

It does not use `always()`, so the bug is less severe (if the release job fails, GitHub Actions skips the deploy by default). However, it still gates on `version` rather than Docker push success, so a partial release job failure (Docker build fails but version was computed) could allow deploy to fire.

## Proposed Solution

### 1. Add `docker_pushed` output to `reusable-release.yml`

Add a new step after "Build and push Docker image" that sets a `docker_pushed` output to `'true'` only when the build+push succeeds. Expose this as a workflow-level output.

**File:** `.github/workflows/reusable-release.yml`

**Changes:**

- Add `docker_pushed` to the `outputs:` section at both job and workflow level
- Add a new step after "Build and push Docker image":

```yaml
- name: Set docker_pushed output
  id: docker_pushed
  if: steps.docker_build.outcome == 'success'
  run: printf 'pushed=%s\n' "true" >> "$GITHUB_OUTPUT"
```

- Add `id: docker_build` to the existing "Build and push Docker image" step
- Add `id: docker_login` to the existing "Docker login" step

**Output wiring:**

```yaml
# Job-level outputs
outputs:
  version: ${{ steps.version.outputs.next }}
  tag: ${{ steps.version.outputs.tag }}
  released: ${{ steps.create_release.outputs.released || 'false' }}
  docker_pushed: ${{ steps.docker_pushed.outputs.pushed || 'false' }}

# Workflow-level outputs
outputs:
  version:
    value: ${{ jobs.release.outputs.version }}
  tag:
    value: ${{ jobs.release.outputs.tag }}
  released:
    value: ${{ jobs.release.outputs.released }}
  docker_pushed:
    description: "Whether Docker image was built and pushed (true/false)"
    value: ${{ jobs.release.outputs.docker_pushed }}
```

### 2. Fix Docker build step condition for retry

Change the Docker login and build step conditions from `steps.create_release.outputs.released == 'true'` to a condition that fires whenever a version is available and docker is configured:

**Current (lines 266-274):**

```yaml
- name: Docker login
  if: steps.create_release.outputs.released == 'true' && inputs.docker_image != ''

- name: Build and push Docker image
  if: steps.create_release.outputs.released == 'true' && inputs.docker_image != ''
```

**Proposed:**

```yaml
- name: Docker login
  if: steps.version.outputs.next != '' && inputs.docker_image != ''

- name: Build and push Docker image
  id: docker_build
  if: steps.version.outputs.next != '' && inputs.docker_image != ''
```

This ensures Docker build runs on retry when the release already exists but the image was never pushed.

**Idempotency concern:** If the image already exists in GHCR, re-pushing with the same tag is idempotent (GHCR accepts duplicate pushes of the same digest). No additional skip logic is needed for Docker push -- unlike GitHub Release creation, Docker push does not fail on duplicates.

**`check_changed` gate interaction:** All steps in the release job are gated on `steps.check_changed.outputs.changed == 'true'`. When `changed` is `'false'` (no component files changed), the `version` step never runs, so `version.outputs.next` is empty. The proposed condition `steps.version.outputs.next != ''` correctly evaluates to false in this case, keeping Docker build skipped. No behavioral change for the no-change path.

### 3. Gate deploy on `docker_pushed` in `web-platform-release.yml`

**File:** `.github/workflows/web-platform-release.yml`

**Current (lines 60-64):**

```yaml
deploy:
  needs: [release, migrate]
  if: >-
    always() &&
    needs.release.outputs.version != '' &&
    (needs.migrate.result == 'success' || needs.migrate.result == 'skipped') &&
    (github.event_name != 'workflow_dispatch' || !inputs.skip_deploy)
```

**Proposed:**

```yaml
deploy:
  needs: [release, migrate]
  if: >-
    always() &&
    needs.release.outputs.docker_pushed == 'true' &&
    (needs.migrate.result == 'success' || needs.migrate.result == 'skipped') &&
    (github.event_name != 'workflow_dispatch' || !inputs.skip_deploy)
```

The only change is replacing `needs.release.outputs.version != ''` with `needs.release.outputs.docker_pushed == 'true'`. The `always()` is preserved (needed for retry semantics when the release job is marked failed due to idempotency skip). The `docker_pushed` output is only set when Docker build+push actually succeeds, so the deploy only fires when the image exists in GHCR.

### 4. Apply same fix to `telegram-bridge-release.yml`

**File:** `.github/workflows/telegram-bridge-release.yml`

**Current (line 43):**

```yaml
deploy:
  needs: release
  if: needs.release.outputs.version != '' && (github.event_name != 'workflow_dispatch' || !inputs.skip_deploy)
```

**Proposed:**

```yaml
deploy:
  needs: release
  if: >-
    always() &&
    needs.release.outputs.docker_pushed == 'true' &&
    (github.event_name != 'workflow_dispatch' || !inputs.skip_deploy)
```

Changes: (1) replace `version != ''` with `docker_pushed == 'true'`, (2) add `always()` to match web-platform semantics and enable retry. Without `always()`, a failed release job (including idempotency skip that sets the job to failed) would cause GitHub Actions to skip the deploy by default.

## Technical Considerations

### GitHub Actions `always()` semantics

`always()` makes a job evaluate its `if:` condition regardless of upstream job status. Without it, GitHub Actions skips the job when any `needs:` dependency has a non-success conclusion. We need `always()` to allow deploy to fire on retry (where the release job may be marked "failed" due to idempotency skip).

### Output availability with `always()`

When a job uses `always()`, it can access outputs from its `needs:` dependencies even if those dependencies failed. The `docker_pushed` output defaults to `'false'` (via the `|| 'false'` fallback in the job outputs), so a failed Docker step produces a falsy gate.

### `steps.X.outcome` vs `steps.X.conclusion`

`outcome` reflects the step's actual result before `continue-on-error` processing. `conclusion` reflects the final result after `continue-on-error`. Since the Docker build step does not use `continue-on-error`, both are identical. Using `outcome` is the safer choice because it always reflects the true result.

### No migration needed for telegram-bridge deploy condition change

The telegram-bridge deploy does not have a `migrate` job, so the condition is simpler. Adding `always()` there is safe because the only `needs:` dependency is `release`, and the `docker_pushed` gate prevents deploy from firing when Docker build failed.

### Non-Docker components are unaffected

The `docker_pushed` output defaults to `'false'` when `docker_image` is empty (the Docker steps are all skipped). Caller workflows that do not use Docker do not reference `docker_pushed` in their deploy conditions, so they are unaffected.

### Research Insights: GitHub Actions step outcome for `uses:` actions

The "Build and push Docker image" step uses `docker/build-push-action` (a `uses:` step, not a `run:` step). Per GitHub Actions documentation, both `uses:` and `run:` steps populate `steps.<id>.outcome` and `steps.<id>.conclusion`. The `outcome` property reflects the step's actual result before `continue-on-error` processing. Since `docker/build-push-action` does not set `continue-on-error`, `outcome` and `conclusion` are identical. The proposed `steps.docker_build.outcome == 'success'` condition works correctly for composite actions.

### Execution trace: three paths

**Path 1 -- Normal first run (Docker build succeeds):**

1. `check_changed` -> `changed=true`
2. `version` -> `next=0.10.1`, `tag=web-v0.10.1`
3. `idempotency` -> `exists=false`
4. `create_release` -> `released=true`
5. Docker login -> runs (`version.outputs.next != ''` is true)
6. Docker build -> runs, succeeds
7. `docker_pushed` -> `pushed=true`
8. Job outputs: `version=0.10.1`, `released=true`, `docker_pushed=true`
9. Deploy job: `always()` evaluates condition -> `docker_pushed == 'true'` is true -> deploys

**Path 2 -- Retry (release exists, Docker build succeeds):**

1. `check_changed` -> `changed=true`
2. `version` -> `next=0.10.1`, `tag=web-v0.10.1`
3. `idempotency` -> `exists=true`
4. `create_release` -> SKIPPED (condition `exists == 'false'` is false)
5. Docker login -> runs (`version.outputs.next != ''` is true, regardless of `released`)
6. Docker build -> runs, succeeds
7. `docker_pushed` -> `pushed=true`
8. Job outputs: `version=0.10.1`, `released=false`, `docker_pushed=true`
9. Job conclusion: may be `failure` due to skipped release step
10. Deploy job: `always()` forces condition evaluation -> `docker_pushed == 'true'` is true -> deploys

**Path 3 -- Docker build fails:**

1. `check_changed` -> `changed=true`
2. `version` -> `next=0.10.1`
3. `create_release` -> `released=true`
4. Docker login -> runs
5. Docker build -> runs, FAILS (ERESOLVE, OOM, etc.)
6. `docker_pushed` -> SKIPPED (`steps.docker_build.outcome == 'success'` is false)
7. Job outputs: `version=0.10.1`, `released=true`, `docker_pushed=false` (fallback)
8. Deploy job: `always()` evaluates condition -> `docker_pushed == 'true'` is false -> SKIPPED

### Discord notification on retry

The "Post to Discord" step is gated on `steps.create_release.outputs.released == 'true'`. On retry, `released` is `'false'` (release creation was skipped), so Discord notification is also skipped. This is correct behavior -- a retry should not send a duplicate release announcement. No changes needed to the Discord step.

## Acceptance Criteria

- [x] `reusable-release.yml` exposes a `docker_pushed` output set to `'true'` only on Docker build+push success
- [x] Docker login and build steps fire when version is available (not just when release was newly created), enabling retry
- [x] `web-platform-release.yml` deploy job gates on `docker_pushed == 'true'` instead of `version != ''`
- [x] `telegram-bridge-release.yml` deploy job gates on `docker_pushed == 'true'` with `always()`
- [x] Deploy does NOT fire when Docker build fails (verified by condition logic)
- [x] Deploy DOES fire on normal first-run when Docker build succeeds
- [x] Deploy DOES fire on retry when release exists but Docker build succeeds

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- CI/CD workflow fix with no user-facing, legal, marketing, or financial impact.

## Test Scenarios

### Core scenarios

- Given a release run where Docker build fails, when the deploy job evaluates its condition, then `docker_pushed` is `'false'` and deploy is skipped
- Given a release run where Docker build succeeds, when the deploy job evaluates its condition, then `docker_pushed` is `'true'` and deploy fires normally
- Given a retry of an existing release (idempotency skip), when the Docker build step evaluates its condition, then it runs (because `version != ''`) instead of being skipped
- Given a retry where Docker build succeeds, when the deploy job evaluates its condition, then `docker_pushed` is `'true'` and deploy fires
- Given a component with no Docker image configured (`docker_image` is empty), when the release runs, then `docker_pushed` is `'false'` and no deploy-related steps are affected

### Edge cases

- Given a release run where `check_changed.outputs.changed` is `'false'`, when Docker build evaluates `version.outputs.next != ''`, then it is false (version step was skipped) and Docker build is skipped
- Given a retry where Docker login fails (GHCR auth error), when Docker build evaluates its condition, then Docker build is skipped (its `if:` condition passes but the `docker/login-action` step fails first, so `docker_build.outcome` is never set, `docker_pushed` remains `'false'`)
- Given a release run on telegram-bridge where Docker build succeeds, when the deploy job evaluates `always() && docker_pushed == 'true'`, then deploy fires even if the release job's overall conclusion is `failure`

### Verification approach

Since these are CI workflow changes that cannot be unit-tested locally, verification relies on:

1. **Static analysis:** Trace the condition logic through all three execution paths (see Execution Traces above)
2. **Manual trigger after merge:** Run `gh workflow run web-platform-release.yml -f bump_type=patch` and verify the deploy job fires and succeeds
3. **Regression check:** Confirm the next organic push to main triggers the release workflow and deploys correctly via `/health` endpoint

## Files Changed

| File | Change |
|------|--------|
| `.github/workflows/reusable-release.yml` | Add `docker_pushed` output, add `id` to Docker steps, fix Docker build condition, add docker_pushed setter step |
| `.github/workflows/web-platform-release.yml` | Replace `version != ''` with `docker_pushed == 'true'` in deploy condition |
| `.github/workflows/telegram-bridge-release.yml` | Replace `version != ''` with `docker_pushed == 'true'`, add `always()` in deploy condition |

## References

- Issue: [#1317](https://github.com/jikig-ai/soleur/issues/1317)
- Parent issue: [#1307](https://github.com/jikig-ai/soleur/issues/1307)
- Parent plan: `knowledge-base/project/plans/2026-03-30-fix-deploy-verification-docker-build-plan.md`
- Learning: `knowledge-base/project/learnings/2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md`
- Learning: `knowledge-base/project/learnings/2026-03-29-post-merge-release-workflow-verification.md`
