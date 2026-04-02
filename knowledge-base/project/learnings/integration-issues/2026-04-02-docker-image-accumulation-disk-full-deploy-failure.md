---
module: System
date: 2026-04-02
problem_type: integration_issue
component: tooling
symptoms:
  - "Deploy webhook returns HTTP 202 but container does not restart"
  - "Health endpoint reports old version with high uptime (container never restarted)"
  - "Root disk 100% full: /dev/sda1 75G 75G 0 100%"
  - "Docker layer extraction fails: no space left on device"
root_cause: config_error
resolution_type: code_fix
severity: critical
tags: [docker, disk-space, deploy, webhook, prune, ci-deploy]
---

# Troubleshooting: Deploy Webhook Fails Due to Docker Image Accumulation Filling Disk

## Problem

The web-platform deploy webhook accepted requests (HTTP 202) but the server-side ci-deploy.sh failed silently because the root disk was 100% full from Docker image accumulation. Production stayed on the old version while CI reported a deploy verification failure.

## Environment

- Module: System (web-platform infra)
- Affected Component: ci-deploy.sh, cloud-init.yml
- Server: Hetzner 75GB root disk
- Date: 2026-04-02

## Symptoms

- Deploy webhook returns HTTP 202 (accepted) but container does not restart
- Health endpoint consistently reports old version with high uptime
- Root disk at 100%: 32 Docker images totaling 76.56GB, only 2 active
- Docker layer extraction fails with "no space left on device"
- Re-running the failed deploy step produces the same result

## What Didn't Work

**`docker system prune -f --filter "until=48h"`** (existing cleanup):

- Only removes dangling images (untagged), not unused tagged images
- The `--filter "until=48h"` threshold keeps all recent images during rapid release cycles
- Docker layer sharing means "reclaimable" space was only 4% of total image size

**Weekly cron with `docker image prune -af --filter "until=168h"`**:

- Runs too infrequently (weekly)
- 168h threshold still allows massive accumulation during busy weeks

## Session Errors

**setup-ralph-loop.sh path wrong**

- **Recovery:** Corrected from `./plugins/soleur/skills/one-shot/scripts/` to `./plugins/soleur/scripts/`
- **Prevention:** Verify script paths exist before invoking in skill instructions

**set -eo pipefail crashes test suite on grep no-match**

- **Recovery:** Wrapped grep in `{ grep ... || true; }` pattern
- **Prevention:** In bash scripts with `set -eo pipefail`, always use `{ grep ... || true; }` when grep results feed into variable assignment and no-match is a valid state

**df mock not updated in run_deploy (only in run_deploy_traced)**

- **Recovery:** Updated both mock functions to include the MOCK_DF_LOW env var check
- **Prevention:** When test files have parallel mock functions (run_deploy and run_deploy_traced), update ALL instances when adding new mocks

**MOCK_DF_LOW=1 func syntax didn't propagate env var through subshell chain**

- **Recovery:** Used `$(export MOCK_DF_LOW=1; run_deploy ...)` pattern matching existing MOCK_DOCKER_PULL_FAIL usage
- **Prevention:** In bash, use explicit `export` inside `$(...)` for env vars that must propagate through nested subshells to mock scripts. The `VAR=value func` syntax does not reliably export to grandchild processes

## Solution

Three changes to prevent Docker image accumulation:

**1. Replace prune command (ci-deploy.sh, both component cases):**

```bash
# Before (broken):
echo "Pruning old Docker images (>48h)..."
docker system prune -f --filter "until=48h"

# After (fixed):
echo "Pruning unused Docker images..."
docker image prune -af
```

**2. Add disk space pre-flight check (ci-deploy.sh, after flock):**

```bash
AVAIL_KB=$(df --output=avail / | tail -1 | tr -d ' ')
if [[ "$AVAIL_KB" -lt 5242880 ]]; then
  logger -t "$LOG_TAG" "REJECTED: insufficient disk space (${AVAIL_KB}KB available, 5GB required)"
  echo "Error: insufficient disk space for deploy" >&2
  exit 1
fi
```

**3. Reduce weekly cron filter (cloud-init.yml):**

```bash
# Before: docker image prune -af --filter "until=168h"
# After:  docker image prune -af --filter "until=72h"
```

## Why This Works

1. **`docker image prune -af`** removes ALL images not referenced by running containers. The `-a` flag targets unused tagged images (not just dangling). Docker protects images used by running/stopped containers, so in-use images are safe.
2. **Pre-flight check** provides an immediate, actionable error ("insufficient disk space") instead of a cryptic overlayfs extraction failure deep in the Docker pull process.
3. **Reduced cron filter** catches images from failed deploys or manual pulls that the per-deploy prune misses.

The per-deploy prune is the primary defense. The cron is a safety net. The pre-flight check is a fail-fast guard.

## Prevention

- Use `docker image prune -af` (not `docker system prune`) for Docker cleanup in deploy scripts
- Add disk space pre-flight checks before operations that require significant disk I/O
- Monitor server disk usage proactively (see #1409 for monitoring gap)
- During rapid release cycles, time-based filters are ineffective because all images are recent

## Related Issues

- See also: [ci-deploy-reliability-and-mock-trace-testing](../../learnings/2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md)
- See also: [deploy-gate-docker-pushed-output-ci](./deploy-gate-docker-pushed-output-ci-20260330.md)
- Tracking: #1409 (disk space monitoring and alerting)
