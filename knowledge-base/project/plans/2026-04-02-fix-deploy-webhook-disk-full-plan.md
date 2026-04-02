---
title: "fix(infra): deploy webhook fails due to disk full from Docker image accumulation"
type: fix
date: 2026-04-02
---

# fix(infra): Deploy webhook fails due to disk full from Docker image accumulation

## Overview

The web-platform deploy webhook accepts requests (HTTP 202) but the server-side `ci-deploy.sh` fails because the root disk is 100% full. Docker image accumulation has consumed all 75GB. The existing cleanup mechanisms (`docker system prune -f --filter "until=48h"` in ci-deploy.sh and a weekly cron with `docker image prune -af --filter "until=168h"`) are insufficient because:

1. `docker system prune` without `-a` only removes dangling images, not unused tagged images
2. The `--filter "until=48h"` threshold is too short during rapid release cycles (7 releases in 4 hours)
3. Docker layer sharing means "reclaimable" space is only 4% of total image size
4. The weekly cron runs too infrequently and its 168h threshold still allows massive accumulation

## Problem Statement

**Root cause confirmed via SSH:**

```text
Filesystem  Size  Used  Avail  Use%  Mounted on
/dev/sda1    75G   75G      0  100%  /

Docker images: 32 total, 2 active, 76.56GB total, 3.075GB (4%) reclaimable
```

The `ci-deploy.sh` ERR trap captured the exact failure:

```text
failed to extract layer ... write /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/.../app/.next/cache/webpack/server-production/0.pack: no space left on device
DEPLOY_ERROR: ci-deploy.sh failed at line 100 (exit 1)
```

The deploy webhook returns 202 immediately (async fire-and-forget pattern per #968), so CI gets a success on the webhook call but fails at the health verification poll step. Production stays on v0.13.7 while v0.13.8 image is built and pushed to GHCR but never pulled to the server.

**Failed run:** [actions/runs/23917271973](https://github.com/jikig-ai/soleur/actions/runs/23917271973)

## Proposed Solution

### Phase 1: Immediate recovery (unblock deploys)

SSH to the server and run aggressive Docker cleanup to free disk space, then manually trigger a deploy of v0.13.8.

**Tasks:**

1. **Clean Docker images** -- Remove all unused images (not just dangling):

   ```bash
   ssh root@135.181.45.178 "docker image prune -af"
   ```

   This removes all images not referenced by running containers. With 2 active containers and 32 images, this should free ~70GB.

2. **Verify disk space recovered:**

   ```bash
   ssh root@135.181.45.178 "df -h /"
   ```

3. **Re-run the release workflow** to deploy v0.13.8:

   ```bash
   gh workflow run web-platform-release.yml -f bump_type=patch -f skip_deploy=false
   ```

   Alternatively, re-run the failed deploy job from the existing run.

4. **Verify production health:**

   ```bash
   curl -sf "https://app.soleur.ai/health" | jq .
   ```

   Expected: `version: "0.13.8"`, low uptime.

### Phase 2: Fix ci-deploy.sh cleanup logic

Replace the ineffective `docker system prune -f --filter "until=48h"` with aggressive image cleanup that keeps only images used by running containers.

**Current (broken):**

```bash
# Line 104-105 in ci-deploy.sh
echo "Pruning old Docker images (>48h)..."
docker system prune -f --filter "until=48h"
```

**Proposed:**

```bash
echo "Pruning unused Docker images..."
docker image prune -af --filter "until=24h"
```

Key changes:

- `docker image prune` instead of `docker system prune` -- targets images specifically, not containers/networks
- `-a` flag -- removes all unused images, not just dangling ones
- `--filter "until=24h"` -- keeps the currently running image (just deployed) plus any images younger than 24h as a safety margin for rollback

This runs at the START of every deploy, before the `docker pull`. Combined with the weekly cron, this prevents accumulation.

### Phase 3: Fix weekly cron job

The weekly cron in `cloud-init.yml` uses `--filter "until=168h"` which keeps a week of images. On a 75GB disk with 3GB images, that's only 25 images before the disk is full -- a single busy week exceeds this.

**Current:**

```bash
docker image prune -af --filter "until=168h"
```

**Proposed:**

```bash
docker image prune -af --filter "until=72h"
```

Reduce from 168h (7 days) to 72h (3 days). This is a safety net -- the per-deploy cleanup in Phase 2 is the primary mechanism. The cron catches images from failed deploys or manual pulls.

### Phase 4: Add disk space check to ci-deploy.sh

Add a pre-flight disk space check that fails fast with a clear error instead of waiting for the Docker layer extraction to fail:

```bash
# Check available disk space (minimum 5GB required for image pull)
AVAIL_KB=$(df --output=avail / | tail -1 | tr -d ' ')
if [[ "$AVAIL_KB" -lt 5242880 ]]; then
  logger -t "$LOG_TAG" "REJECTED: insufficient disk space (${AVAIL_KB}KB available, 5GB required)"
  echo "Error: insufficient disk space for deploy" >&2
  exit 1
fi
```

This provides an immediate, actionable error message instead of a cryptic overlayfs extraction failure.

### Phase 5: Update ci-deploy.test.sh

Add test cases for:

- Disk space check rejection path
- Verify the new prune command ordering (prune before pull)

## Acceptance Criteria

- [ ] Production is running v0.13.8 (or latest version at time of fix)
- [ ] Root disk on soleur-web-platform has >50% free space after cleanup
- [ ] `ci-deploy.sh` uses `docker image prune -af --filter "until=24h"` before each deploy
- [ ] Weekly cron uses `docker image prune -af --filter "until=72h"`
- [ ] `ci-deploy.sh` includes a disk space pre-flight check (5GB minimum)
- [ ] All existing ci-deploy.test.sh tests pass
- [ ] New test covers disk space rejection path
- [ ] Subsequent deploys succeed without manual intervention

## Test Scenarios

- Given a server with <5GB free disk space, when ci-deploy.sh runs, then it exits with "insufficient disk space" error before attempting docker pull
- Given 30+ unused Docker images on disk, when ci-deploy.sh runs a deploy, then unused images >24h old are pruned before the pull
- Given a successful deploy, when checking disk space, then the root filesystem has >10GB free
- Given the weekly cron runs, when there are images older than 72h, then they are removed

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling fix.

## Files Changed

| File | Change |
|------|--------|
| `apps/web-platform/infra/ci-deploy.sh` | Replace `docker system prune` with `docker image prune -af`, add disk space pre-flight check |
| `apps/web-platform/infra/ci-deploy.test.sh` | Add test for disk space check rejection |
| `apps/web-platform/infra/cloud-init.yml` | Update weekly cron from 168h to 72h filter |

## References

- Issue: [#1405](https://github.com/jikig-ai/soleur/issues/1405)
- Failed run: [actions/runs/23917271973](https://github.com/jikig-ai/soleur/actions/runs/23917271973)
- Learning: [Async webhook deploy pattern](../../learnings/2026-03-21-async-webhook-deploy-cloudflare-timeout.md)
- Learning: [Canary rollback pattern](../../learnings/implementation-patterns/2026-03-28-canary-rollback-docker-deploy.md)
- Learning: [Deploy gate on docker_pushed output](../../learnings/integration-issues/deploy-gate-docker-pushed-output-ci-20260330.md)
