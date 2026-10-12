---
title: "Deploy Reliability: Canary Rollback"
type: feat
date: 2026-03-28
---

# Deploy Reliability: Canary Rollback

## Overview

Add health-gated canary deployment with automatic rollback to `ci-deploy.sh`, preventing downtime from bad deploys. The current script kills the old container before verifying the new one works. This restructures the deploy to: start canary → verify → swap on success or rollback on failure.

The deploy watchdog workflow (automated issue creation on failure) was evaluated and deferred. GitHub already emails on failed workflow runs, and after this fix, failed deploys = old version keeps running (not downtime). If deploy failures continue at high rates after this ships, a watchdog using Sentry logs for investigation will be built as a follow-up.

## Problem Statement

The current `ci-deploy.sh` kills the old container before verifying the new one works (hard-stop gap). 8 of the last 20 deploy runs failed (40%), with the #1235 failure going unnoticed until the founder manually checked. After this fix, failed deploys cause zero downtime — the old container keeps serving.

## Proposed Solution

Restructure the web-platform deploy block (`ci-deploy.sh` lines 97-126) to:

1. Clean stale canary from previous failed deploys
2. Pull new image
3. Start canary on port 3001
4. Health-check canary
5. On success: stop old → start new production on 80/3000 → remove canary
6. On failure: remove canary, keep old container running, exit 1

Plus critical hardening: `flock` serialization to prevent concurrent deploys, `{ ...; } || true` safety on all cleanup operations.

## Technical Approach

### Architecture

```
ci-deploy.sh (server-side, async via webhook)
├── flock -n /var/lock/ci-deploy.lock (serialize concurrent deploys)
├── Clean stale canary: { docker stop canary || true; } && { docker rm canary || true; }
├── docker system prune -f --filter "until=48h"
├── docker pull $IMAGE:$TAG
├── docker run --name soleur-web-platform-canary -p 3001:3000 ...
├── Health check: curl -sf http://localhost:3001/health (10 attempts, 3s)
├── SUCCESS PATH:
│   ├── { docker stop soleur-web-platform || true; }
│   ├── { docker rm soleur-web-platform || true; }
│   ├── docker run --name soleur-web-platform -p 80:3000 -p 3000:3000 ...
│   ├── { docker stop soleur-web-platform-canary || true; }
│   ├── { docker rm soleur-web-platform-canary || true; }
│   └── exit 0
└── FAILURE PATH:
    ├── { docker logs soleur-web-platform-canary 2>&1 | tail -30 || true; } | logger
    ├── { docker stop soleur-web-platform-canary || true; }
    ├── { docker rm soleur-web-platform-canary || true; }
    ├── log DEPLOY_ROLLBACK event to syslog
    └── exit 1 (old container untouched, serves traffic)
```

**Port swap gap:** ~1-2s window where port 80 is unbound during the swap. Acceptable: Cloudflare Tunnel retries, GHA polls at 10s intervals, vastly better than the current 30s+ gap during failed deploys.

**Async model:** ci-deploy.sh runs via fire-and-forget webhook (HTTP 202). Its exit code goes to `journalctl -u webhook`, not GHA. GHA detects failure through health poll timeout/version mismatch. GitHub's built-in email notifications alert the founder.

**Third path — production start fails after canary success:** If the canary passes but the new production `docker run` fails (port bind error, Docker daemon issue), the old container is already removed. The site is down. The implementation must handle this: if production start fails, log the error clearly and exit 1. The canary already proved the image works, so this is an infrastructure issue, not an app issue. Sentry will capture the canary's startup if any errors occurred.

**Shared volume note:** Both canary and production mount `/mnt/data/workspaces` read-write. During the ~30s health check, two containers share this volume. The app does not write to workspaces during health check (it only reads config). Plugins volume is `:ro`. This is safe but documented as an invariant — if future app changes write during startup, this must be revisited.

### Implementation

**Files modified:**

- `apps/web-platform/infra/ci-deploy.sh` — canary rollback logic
- `apps/web-platform/infra/ci-deploy.test.sh` — new test cases

**Steps:**

1. **Add `flock` serialization** at the top of ci-deploy.sh:

   ```bash
   exec 200>/var/lock/ci-deploy.lock
   flock -n 200 || { logger -t "$LOG_TAG" "REJECTED: another deploy in progress"; exit 1; }
   ```

2. **Add stale canary cleanup** before the deploy block:

   ```bash
   { docker stop soleur-web-platform-canary 2>/dev/null || true; }
   { docker rm soleur-web-platform-canary 2>/dev/null || true; }
   ```

3. **Restructure web-platform deploy block** (lines 97-126):
   - Move `resolve_env_file()` and `sudo chown` before canary start
   - Start canary: `docker run -d --name soleur-web-platform-canary --restart no --env-file "$ENV_FILE" -v ... -p 0.0.0.0:3001:3000 "$IMAGE:$TAG"`
   - Health-check canary: poll `localhost:3001/health` (10 attempts, 3s sleep)
   - Success path: stop old → rm old → start production (80:3000, 3000:3000, `--restart unless-stopped`) → stop canary → rm canary
   - Failure path: dump canary logs (protected with `{ ... || true; }`) → stop canary → rm canary → log `DEPLOY_ROLLBACK` → exit 1
   - Both paths: cleanup env file

4. **Add test cases** in ci-deploy.test.sh:
   - Canary success path — verify docker trace ordering
   - Canary failure / rollback path — verify old container preserved
   - Docker pull failure — no canary started, old untouched
   - Canary crash on start — no health check, old untouched
   - Production start failure after canary success — error logged, exit 1

5. **Enhance curl mock** for port-based routing (3001 for canary, configurable failure)

**Gotchas from learnings:**

- Wrap every `docker stop/rm ... || true` in `{ ...; }` (bash operator precedence)
- Protect `docker logs` with `{ ... || true; }` under `set -euo pipefail`
- Use `rm -f` for TOCTOU safety
- Health check: `curl -sf` (existing pattern), canary on port 3001
- Env file cleanup on both paths — explicit in each branch
- `--restart no` for canary (temporary), `--restart unless-stopped` for production

## Acceptance Criteria

- [ ] Stale canary cleaned up before each deploy
- [ ] `flock` prevents concurrent ci-deploy.sh execution
- [ ] Canary starts on port 3001 with identical config (volumes, env) before old container is touched
- [ ] On canary health-check pass: old container stopped, new production started on ports 80/3000
- [ ] On canary health-check fail: canary removed, old container untouched, exit 1
- [ ] On production start failure after canary success: error logged, exit 1
- [ ] `DEPLOY_ROLLBACK` event logged to syslog on rollback with image tags
- [ ] All existing ci-deploy.test.sh tests pass (no regressions)
- [ ] New tests cover: canary success, rollback, pull failure, canary crash, production start failure

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Recommended canary rollback over Kamal migration. SSH re-introduction is a dealbreaker. The rollback logic replicates Kamal's core value in ~30 lines of bash. Port swap has ~1-2s gap, acceptable given Cloudflare retry and GHA poll interval. No capability gaps.

### Operations (COO)

**Status:** reviewed
**Assessment:** 40% failure rate clusters on 2026-03-27 (6 failures), suggesting specific incident. Pipeline hardened over 7+ sessions. Kamal evaluated and rejected ($0 cost but reverses SSH→webhook migration). No capability gaps.

## Test Scenarios

- Given a valid deploy command, when canary health check passes, then old container is stopped and new production container runs on ports 80:3000 and 3000:3000
- Given a valid deploy command, when canary health check fails, then canary is removed and old container continues serving traffic
- Given a valid deploy command, when docker pull fails, then no canary is started and old container is untouched
- Given a valid deploy command, when canary docker run fails (crash on start), then no health check runs and old container is untouched
- Given a valid deploy command, when canary succeeds but production docker run fails, then error is logged and script exits 1
- Given a valid deploy command, when a stale canary exists from previous failure, then it is cleaned up before new canary starts
- Given a deploy already in progress (flock held), when a second deploy fires, then it exits 1 with "another deploy in progress"

## Dependencies & Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Port swap gap (~1-2s) | Brief 502/503 during swap | Cloudflare Tunnel retry, GHA 10s poll interval absorbs it |
| Shared volume dual-write during canary | Potential workspace corruption | App does not write during health check (documented invariant) |
| Production start fails after canary success | Site down (old already removed) | Image already verified by canary — this is infra, not app issue |
| Disk space during canary (two containers) | Docker pull or run fails | `docker system prune` runs before pull (existing) |

## Deferred Work

- **Deploy watchdog workflow** — Automated GitHub issue creation on deploy failure. Deferred per DHH review: GitHub already emails on failed workflows. After this fix, failed deploys = old version keeps running. If failures continue at high rates, build watchdog using Sentry logs (not Better Stack/Docker logs) for investigation.
- **Better Stack log drain** — Not configured. Sentry is the preferred log source for future investigation.

## References

- `apps/web-platform/infra/ci-deploy.sh:97-126` — current deploy block to restructure
- `apps/web-platform/infra/ci-deploy.test.sh:14-82` — mock infrastructure for testing
- `.github/workflows/web-platform-release.yml:49-93` — deploy job (webhook + health poll)
- `knowledge-base/project/learnings/runtime-errors/2026-02-13-bash-operator-precedence-ssh-deploy-fallback.md` — `{ ...; } || true` pattern
- `knowledge-base/project/learnings/2026-03-19-docker-restart-does-not-apply-new-images.md` — stop/rm/run, never restart
- #1238 — parent issue
- #1235 — production observability (triggered this work)
- #1237 — health endpoint fix
