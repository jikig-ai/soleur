---
title: "fix: CI release reliability overhaul"
type: fix
date: 2026-03-20
---

# fix: CI release reliability overhaul

## Overview

The Telegram Bridge and Web Platform release workflows have a ~20% deploy failure rate. The primary cause is disk exhaustion on the shared production server (no Docker image cleanup). Three structural issues amplify failures: no deploy concurrency groups, excessive workflow triggers, and an inability to retry failed deploys.

## Problem Statement / Motivation

Recent failures (runs 23354847942, 23354725743, 23354660846, 23354660863) all fail with `no space left on device` during `docker pull` on the Hetzner production server. Both apps deploy to the same cx22 server. With ~20 releases/day and no `docker system prune` anywhere in the pipeline, disk exhaustion is inevitable.

Beyond the immediate disk issue:
- No deploy concurrency groups allow parallel SSH sessions to race on the same server
- Every push to main triggers all 3 release workflows regardless of changed paths (wasting Actions minutes)
- Failed deploys cannot be retried because the deploy job gates on `released == 'true'`, which is `'false'` when the release already exists

## Proposed Solution

Four targeted changes to existing files:

### 1. Docker image cleanup in `ci-deploy.sh`

Add `docker system prune -f --filter "until=48h"` before `docker pull` in both the `web-platform` and `telegram-bridge` case blocks.

**Safety notes:**
- `docker system prune` never removes images referenced by running containers
- `--filter "until=48h"` only removes images older than 48 hours (retains rollback capability)
- Prune runs in the same SSH session as pull/deploy, so no partial-state risk

**File:** `apps/web-platform/infra/ci-deploy.sh:72` (web-platform block) and `:98` (telegram-bridge block)

### 2. Shared deploy concurrency group

Add a **single shared** concurrency group to both caller workflows' deploy jobs. Both apps deploy to the same Hetzner server, so they must not race:

```yaml
deploy:
  concurrency:
    group: deploy-production
    cancel-in-progress: false
```

Using a shared `deploy-production` group (not per-app) because:
- Same physical server (2 vCPU, 4GB RAM cx22) — concurrent `docker pull` + container restarts would saturate resources
- `cancel-in-progress: false` queues deploys instead of cancelling, so no deploys are dropped

**Files:** `.github/workflows/web-platform-release.yml:40` and `.github/workflows/telegram-bridge-release.yml:35`

### 3. Path filters on push triggers

Add `paths:` filters to the `on.push` trigger in each caller workflow so they only fire when their own app files change:

```yaml
# web-platform-release.yml
on:
  push:
    branches: [main]
    paths: ['apps/web-platform/**']

# telegram-bridge-release.yml
on:
  push:
    branches: [main]
    paths: ['apps/telegram-bridge/**']

# version-bump-and-release.yml
on:
  push:
    branches: [main]
    paths: ['plugins/soleur/**', 'plugin.json']
```

**Design decisions:**
- Using broad `apps/<component>/**` rather than narrowing to `src/` + `Dockerfile` — simpler to maintain, and unnecessary deploys from infra changes are rare and harmless
- `workflow_dispatch` trigger is unaffected by `paths:` (GitHub ignores path filters for dispatch events)
- Path filters and `check_changed` are complementary: path filters prevent workflow startup (saves Actions minutes), `check_changed` handles `workflow_dispatch` where path filters don't apply

**Interaction with synthetic status checks:** The `post-bot-statuses.sh` script posts synthetic success statuses for release workflows when they don't run. With path filters, workflows that previously ran-and-skipped will now not run at all. Verify that the synthetic status script handles the "never started" case, not just the "started and skipped" case. Read `scripts/post-bot-statuses.sh` to confirm.

**Files:** `.github/workflows/web-platform-release.yml:1-6`, `.github/workflows/telegram-bridge-release.yml:1-4`, `.github/workflows/version-bump-and-release.yml` (check existing triggers)

### 4. Deploy retry via version output

Change the deploy job's `if` condition from:
```yaml
if: needs.release.outputs.released == 'true'
```
to:
```yaml
if: needs.release.outputs.version != ''
```

**Why this works without changing `reusable-release.yml`:**
- The `version` step (reusable-release.yml:181-215) runs when `check_changed.outputs.changed == 'true'`
- The `idempotency` step (reusable-release.yml:217-229) runs after the `version` step
- So `version` output is already populated even when `idempotency.exists == 'true'` (release already exists)
- The `released` output (line 62) only becomes `'true'` when `create_release` actually runs
- Docker build (line 273-285) is gated on `released == 'true'` — this is correct because we don't want to rebuild an existing image on retry

**Retry scenario:** Release created + Docker pushed + deploy failed. Re-run the workflow: `check_changed` passes (same diff), `version` computed (same), `idempotency` finds existing release, `create_release` skipped, Docker build skipped, but deploy runs because `version != ''`. Deploy pulls the existing image and restarts the container.

**Edge case — Docker build failed:** If the release was created but Docker build failed, re-running still won't rebuild. This is acceptable because: (a) Docker build failures are rare (2 out of 50 runs, both caused by code bugs), and (b) the correct fix is to merge a code fix, which triggers a new release.

**Files:** `.github/workflows/web-platform-release.yml:42`, `.github/workflows/telegram-bridge-release.yml:37`

## Technical Considerations

### Learned patterns to apply (from knowledge-base/learnings/)

- **Bash operator precedence** (`2026-02-13-bash-operator-precedence-ssh-deploy-fallback.md`): The existing `ci-deploy.sh` already uses `{ ...; }` grouping correctly for `docker stop || true` and `docker rm || true`. Maintain this pattern when adding the prune command.
- **Concurrency groups** (`2026-03-03-serialize-version-bumps-to-merge-time.md`): Use `cancel-in-progress: false` to queue, not race. This is the established repo pattern.
- **Path filters + squash merges** (`github-actions-auto-release-permissions.md`): Path filters work correctly with squash merges — the squash commit includes all file changes from the PR.
- **Output sanitization** (`2026-03-05-github-output-newline-injection-sanitization.md`): No new outputs are being written, so no new sanitization needed. Existing `printf` + `tr -d '\n\r'` patterns are already in place.
- **SHA pinning** (`2026-02-27-github-actions-sha-pinning-workflow.md`): No new actions are being added. Existing SHA pins are maintained.

### SpecFlow edge cases addressed

- **Prune + concurrent deploy race:** Impossible with shared concurrency group — only one deploy runs at a time
- **Prune removing running container's image:** Docker protects images referenced by running containers; `--filter "until=48h"` adds extra safety
- **Shared deps not triggering deploys:** Accepted limitation. Manual `workflow_dispatch` is available. Documented in brainstorm open questions.

## Acceptance Criteria

- [ ] Deploy to production server succeeds without `no space left on device` errors
- [ ] `docker system prune -f --filter "until=48h"` runs before `docker pull` in both component blocks of `ci-deploy.sh`
- [ ] `ci-deploy.test.sh` includes a test verifying prune runs before pull for each component
- [ ] Both caller workflows have `concurrency: { group: deploy-production, cancel-in-progress: false }` on their deploy jobs
- [ ] `web-platform-release.yml` only triggers on `apps/web-platform/**` changes (+ `workflow_dispatch`)
- [ ] `telegram-bridge-release.yml` only triggers on `apps/telegram-bridge/**` changes (+ `workflow_dispatch`)
- [ ] `version-bump-and-release.yml` only triggers on `plugins/soleur/**` or `plugin.json` changes (+ `workflow_dispatch`)
- [ ] Re-running a workflow after a failed deploy successfully retries the deploy
- [ ] Synthetic status checks still work correctly with path-filtered workflows (verify `post-bot-statuses.sh`)

## Test Scenarios

- Given a deploy with >48h-old Docker images on disk, when the deploy runs, then old images are pruned before pull and the deploy succeeds
- Given two PRs merged in quick succession touching both apps, when both release workflows fire, then deploys are serialized (one waits for the other)
- Given a PR that only changes `knowledge-base/` files, when pushed to main, then no release workflows trigger
- Given a previous deploy that failed (release + Docker image exist), when the workflow is re-run, then the deploy job runs and pulls the existing image
- Given a `workflow_dispatch` trigger, when no files changed, then path filters are bypassed and the workflow runs normally

## Success Metrics

- Deploy failure rate drops from ~20% to <5% (eliminating disk exhaustion failures)
- No-op workflow runs (triggered but immediately skipped) drop by ~60%
- Failed deploys can be retried without manual intervention beyond re-running the workflow

## Dependencies & Risks

- **Risk:** Adding path filters changes which workflows run on push events. The `post-bot-statuses.sh` synthetic status script may need updating if it expects workflows to always run. **Mitigation:** Read the script before implementation and adjust if needed.
- **Risk:** Shared concurrency group means a slow web-platform deploy blocks a telegram-bridge deploy. **Mitigation:** Acceptable tradeoff — deploys complete in <2 minutes, and serialization prevents resource contention on the cx22.
- **Risk:** `docker system prune` on the production server removes more than intended. **Mitigation:** `--filter "until=48h"` limits scope; running containers' images are always protected.

## References & Research

### Internal References

- Brainstorm: `knowledge-base/brainstorms/2026-03-20-ci-release-reliability-brainstorm.md`
- Reusable release workflow: `.github/workflows/reusable-release.yml`
- Deploy script: `apps/web-platform/infra/ci-deploy.sh`
- Deploy tests: `apps/web-platform/infra/ci-deploy.test.sh`
- Synthetic statuses: `scripts/post-bot-statuses.sh`
- Bash operator precedence learning: `knowledge-base/learnings/runtime-errors/2026-02-13-bash-operator-precedence-ssh-deploy-fallback.md`
- Serialize version bumps learning: `knowledge-base/learnings/2026-03-03-serialize-version-bumps-to-merge-time.md`

### Related Work

- PR #923: Extract synthetic status posting to shared script
- PR #922: Add timeout and abort handling to review gate promise
