# CI Release Reliability Brainstorm

**Date:** 2026-03-20
**Status:** Approved
**Participants:** Jean (founder), Claude (engineering)

## What We're Building

A reliability overhaul for the Telegram Bridge and Web Platform release workflows. The current release pipeline breaks regularly due to disk exhaustion, deploy races, excessive workflow triggers, and an inability to retry failed deploys.

## Why This Approach

The release pipeline has a ~20% failure rate for web-platform deploys today (3 failures out of 15 recent runs), with the primary cause being `no space left on device` on the production server. Both apps deploy to the same Hetzner server, and Docker images are never cleaned up. With ~20 releases/day, disk exhaustion is inevitable.

Beyond the immediate fix, three structural issues amplify failures:
1. No deploy concurrency groups allow parallel SSH sessions to race
2. Every push to main triggers all 3 release workflows regardless of changed paths
3. Failed deploys cannot be retried because the idempotency check gates on release creation, not version resolution

## Key Decisions

### 1. Docker Image Cleanup: Pre-deploy prune in ci-deploy.sh
- Add `docker system prune -f --filter "until=48h"` before `docker pull` in each component block
- Keeps current image + ~48h of rollback capability
- Rejected alternative: server cron job (separate moving part, doesn't guarantee cleanup before deploy)

### 2. Deploy Concurrency: Workflow-level concurrency groups
- Add `concurrency: { group: deploy-<workflow>, cancel-in-progress: false }` to each caller's deploy job
- Queues deploys instead of racing; in-flight deploy finishes before next starts
- Applies to: `web-platform-release.yml`, `telegram-bridge-release.yml`

### 3. Path Filtering: Trigger only on relevant changes
- `web-platform-release.yml`: `paths: ['apps/web-platform/**']`
- `telegram-bridge-release.yml`: `paths: ['apps/telegram-bridge/**']`
- `version-bump-and-release.yml`: `paths: ['plugins/**', 'plugin.json']`
- Eliminates ~60% of no-op workflow runs
- `workflow_dispatch` trigger unaffected

### 4. Deploy Retry: Gate on version resolution, not release creation
- Change deploy `if` from `released == 'true'` to `version != ''`
- Reusable workflow outputs version even when release already exists
- Allows re-running a workflow to retry a failed deploy without creating a duplicate release

## Open Questions

- Should we add deploy failure Discord notifications? Currently only release success is notified.
- Is 48h the right retention window for old Docker images, or should we keep more/fewer?

## Files Affected

- `apps/web-platform/infra/ci-deploy.sh` — add docker prune
- `.github/workflows/web-platform-release.yml` — concurrency group, path filter
- `.github/workflows/telegram-bridge-release.yml` — concurrency group, path filter
- `.github/workflows/version-bump-and-release.yml` — path filter
- `.github/workflows/reusable-release.yml` — add version output for existing releases
- `apps/web-platform/infra/ci-deploy.test.sh` — test the prune behavior
