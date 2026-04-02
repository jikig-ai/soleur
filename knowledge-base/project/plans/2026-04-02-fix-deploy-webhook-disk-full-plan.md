---
title: "fix(infra): deploy webhook fails due to disk full from Docker image accumulation"
type: fix
date: 2026-04-02
deepened: 2026-04-02
---

# fix(infra): Deploy webhook fails due to disk full from Docker image accumulation

## Enhancement Summary

**Deepened on:** 2026-04-02
**Sections enhanced:** 5
**Research sources:** Docker official docs (Context7), project learnings (5 files), ci-deploy.sh + test suite analysis

### Key Improvements

1. Added implementation details with exact line numbers and insertion points for each code change
2. Identified that the prune fix must be applied to BOTH component cases in ci-deploy.sh (web-platform AND telegram-bridge)
3. Clarified that the disk space check placement must be after lock acquisition but before the case statement
4. Added edge case: `df --output=avail` is GNU coreutils-specific (safe on Ubuntu but not portable to Alpine/BusyBox)
5. Added note that telegram-bridge has no cloud-init.yml (no cron to fix), only ci-deploy.sh needs updating for that component

### New Considerations Discovered

- The `base64encode(file())` Terraform pattern means ci-deploy.sh changes propagate to new servers automatically but NOT to the live server -- Phase 1 must SCP the updated script
- The telegram-bridge server shares ci-deploy.sh via cross-module reference in Terraform, so the fix automatically applies to both components in the source file
- Docker docs confirm: `docker image prune -a` is safe for running containers -- "removes all images which aren't used by existing containers"

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

3. **Copy updated ci-deploy.sh to the live server** -- cloud-init only runs at provisioning time, so the live server still has the old script:

   ```bash
   scp apps/web-platform/infra/ci-deploy.sh root@135.181.45.178:/usr/local/bin/ci-deploy.sh
   ```

4. **Re-run the release workflow** to deploy v0.13.8:

   ```bash
   gh workflow run web-platform-release.yml -f bump_type=patch -f skip_deploy=false
   ```

   Alternatively, re-run the failed deploy job from the existing run.

5. **Verify production health:**

   ```bash
   curl -sf "https://app.soleur.ai/health" | jq .
   ```

   Expected: `version: "0.13.8"`, low uptime.

6. **Check telegram-bridge server disk** -- The telegram-bridge server has its own cloud-init with the same weekly cron pattern. Verify it isn't also accumulating images:

   ```bash
   ssh root@<bridge-ip> "df -h / && docker system df"
   ```

   If it has the same problem, apply the same cleanup.

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
docker image prune -af
```

Key changes:

- `docker image prune` instead of `docker system prune` -- targets images specifically, not containers/networks
- `-a` flag -- removes all unused images, not just dangling ones
- No `--filter` -- Docker protects images referenced by running containers, so in-use images are safe. During rapid release cycles (7 releases in 4 hours), a time-based filter like `"until=24h"` would prune nothing because all images are recent, defeating the purpose.

This runs at the START of every deploy, before the `docker pull`. Combined with the weekly cron, this prevents accumulation.

### Research Insights

**Docker docs confirm safety:** Per the official Docker documentation: "`docker image prune -a` removes all images which aren't used by existing containers." Images referenced by running (or stopped) containers are protected. The `-a` flag without `--filter` is the correct approach for aggressive cleanup.

**Two locations to change in ci-deploy.sh:** The same broken prune command appears in BOTH the `web-platform)` case (line 104-105) and the `telegram-bridge)` case (line 178-179). Both must be updated.

**Terraform propagation:** The updated `ci-deploy.sh` is injected into `cloud-init.yml` via Terraform's `base64encode(file())` pattern (see [learning: Terraform base64encode cloud-init deduplication](../../learnings/2026-03-20-terraform-base64encode-cloud-init-deduplication.md)). The telegram-bridge Terraform references this same file via cross-module path. This means the source file change propagates to both apps' cloud-init automatically for new servers. However, the live server's `/usr/local/bin/ci-deploy.sh` was written at provisioning time and is NOT updated by deploys -- Phase 1 must SCP the fixed script to the server before re-deploying.

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

**Note:** The telegram-bridge infra directory (`apps/telegram-bridge/infra/`) has no `cloud-init.yml` -- its server provisioning is handled differently. Only the web-platform cloud-init.yml contains the weekly Docker cleanup cron. The ci-deploy.sh fix in Phase 2 covers both components since both cases are in the same file.

### Phase 4: Add disk space check to ci-deploy.sh

Add a pre-flight disk space check that fails fast with a clear error instead of waiting for the Docker layer extraction to fail.

**Insertion point:** After lock acquisition (line 99) but BEFORE the `case "$COMPONENT"` statement (line 101). This ensures the check is serialized by flock and runs before any Docker operations regardless of component.

```bash
# Check available disk space (minimum 5GB required for image pull + extraction)
AVAIL_KB=$(df --output=avail / | tail -1 | tr -d ' ')
if [[ "$AVAIL_KB" -lt 5242880 ]]; then
  logger -t "$LOG_TAG" "REJECTED: insufficient disk space (${AVAIL_KB}KB available, 5GB required)"
  echo "Error: insufficient disk space for deploy" >&2
  exit 1
fi
```

This provides an immediate, actionable error message instead of a cryptic overlayfs extraction failure.

### Research Insights

**Edge case:** `df --output=avail` is a GNU coreutils extension. The production server runs Ubuntu (confirmed via cloud-init), so this is safe. If the server were ever migrated to Alpine/BusyBox, the command would fail. Not a concern for this fix but worth noting.

**Threshold rationale:** 5GB provides margin for image pull (~3.2GB compressed) plus layer extraction overhead. The current image size is 3.19GB. If the image grows significantly, the threshold may need adjustment -- but the prune-before-pull in Phase 2 is the primary defense, not this check.

### Phase 5: Update ci-deploy.test.sh

Add test cases following the existing mock pattern in `ci-deploy.test.sh`:

**Disk space check rejection test:** Mock `df` to return a low value and verify the script exits with the expected error message.

```bash
# Mock df to report low disk space
cat > "$MOCK_DIR/df" << 'MOCK'
#!/bin/bash
echo "Avail"
echo "1000000"
MOCK
chmod +x "$MOCK_DIR/df"
```

Use `assert_exit_contains` with expected exit 1 and text "insufficient disk space".

**Prune command verification:** The existing `assert_prune_before_pull` test uses `DOCKER_TRACE:system` to detect `docker system prune`. Update the expected trace marker to match the new `docker image prune` command. The traced mock outputs `DOCKER_TRACE:$1`, so `docker image prune` will produce `DOCKER_TRACE:image` instead of `DOCKER_TRACE:system`. Update the assertion in `assert_prune_before_pull` accordingly.

**Existing tests that must still pass:** All 22+ existing tests (happy path, field validation, adversarial input, canary trace order, flock rejection) must continue to pass. The only change to existing test output is the prune trace marker (`image` vs `system`) in the canary trace order tests.

## Acceptance Criteria

- [ ] Production is running v0.13.8 (or latest version at time of fix)
- [ ] Root disk on soleur-web-platform has >50% free space after cleanup
- [ ] `ci-deploy.sh` uses `docker image prune -af` (no filter) before each deploy
- [ ] Weekly cron uses `docker image prune -af --filter "until=72h"`
- [ ] `ci-deploy.sh` includes a disk space pre-flight check (5GB minimum)
- [ ] All existing ci-deploy.test.sh tests pass
- [ ] New test covers disk space rejection path
- [ ] Subsequent deploys succeed without manual intervention

## Test Scenarios

- Given a server with <5GB free disk space, when ci-deploy.sh runs, then it exits 1 with "insufficient disk space" error before any Docker operations
- Given sufficient disk space and 30+ unused Docker images, when ci-deploy.sh runs a deploy, then `docker image prune -af` runs before `docker pull` (verified via DOCKER_TRACE markers)
- Given a valid web-platform deploy command, when tracing Docker operations, then trace shows `image|pull|stop|rm|run|...` (not `system|pull|...`)
- Given a valid telegram-bridge deploy command, when tracing Docker operations, then trace shows `image|pull|...` (same prune change applied)
- Given existing ci-deploy.test.sh tests, when all tests run after the fix, then all pass (including updated trace expectations)

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
