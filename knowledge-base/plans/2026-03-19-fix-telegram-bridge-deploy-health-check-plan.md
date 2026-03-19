---
title: "fix: telegram-bridge deploy health check times out during CLI spawn"
type: fix
date: 2026-03-19
semver: patch
---

# fix: telegram-bridge deploy health check times out during CLI spawn

## Overview

The telegram-bridge CI deploy health check fails because the Claude CLI subprocess takes longer than 100s to reach "ready" state on initial spawn. The health endpoint returns HTTP 503 ("degraded") while `cliState !== "ready"`, which is the entire duration of the CLI spawn. The container starts correctly (`--restart unless-stopped`) and the bot functions after the CLI initializes, but the deploy step reports failure -- a false negative.

## Problem Statement

The deploy step in `telegram-bridge-release.yml` uses `curl -sf` which fails on non-2xx responses. The health endpoint (`apps/telegram-bridge/src/health.ts`) only returns HTTP 200 when both `cliProcess !== null` AND `cliState === "ready"`. During CLI spawn (which takes 60-100+ seconds), the state is "connecting" and the endpoint returns 503.

The current health check loop (20 retries * 5s = 100s) was already bumped from 30s in #761 but still isn't enough. The issue has been escalating through #759, #760, and #761 with increasingly long timeouts, which is the wrong approach -- the fundamental problem is that the health check conflates "container is alive and accepting traffic" with "CLI subprocess is fully initialized."

## Proposed Solution

**Option 1 from the issue: Accept degraded health during deploy.** This is the simplest fix that addresses the root cause rather than papering over it with longer timeouts.

### Two changes

1. **Modify the CI health check** in `telegram-bridge-release.yml` to accept HTTP 503 with `status: degraded` as a passing condition (the bot is starting, not broken). The check verifies the container is up and the health endpoint is responsive -- it does not need to wait for full CLI readiness.

2. **Optionally add a `/readyz` endpoint** (Kubernetes convention) that returns 200 only when CLI is fully ready, keeping `/health` for liveness. This separates concerns cleanly but is not strictly required for the CI fix.

### Why not the other options

- **Option 2 (increase timeout to 180s):** This is the same escalation pattern from #759 -> #760 -> #761. The CLI startup time is variable and will eventually exceed any fixed timeout. Wasteful CI minutes.
- **Option 3 (two-phase health check in CI):** Adds complexity to the bash script for something the health endpoint should express directly.
- **Option 4 (skip health check on first deploy):** Removes the safety net entirely. The health check should pass, not be skipped.

## Technical Approach

### Change 1: CI health check accepts degraded state

In `.github/workflows/telegram-bridge-release.yml`, replace the `curl -sf` check with a check that accepts both 200 and 503-with-degraded-status:

**File:** `.github/workflows/telegram-bridge-release.yml` (lines 79-88)

Current:
```bash
for i in $(seq 1 20); do
  if curl -sf http://localhost:8080/health; then
    echo " OK"
    exit 0
  fi
  sleep 5
done
echo "Health check failed"
docker logs soleur-bridge --tail 30
exit 1
```

Proposed:
```bash
for i in $(seq 1 12); do
  STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health || echo "000")
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "503" ]; then
    BODY=$(curl -s http://localhost:8080/health)
    echo "Health endpoint responded: HTTP $STATUS - $BODY"
    exit 0
  fi
  echo "Attempt $i: HTTP $STATUS (waiting for health endpoint...)"
  sleep 5
done
echo "Health check failed - endpoint not responding"
docker logs soleur-bridge --tail 30
exit 1
```

This reduces retries to 12 (60s) since we only need the health endpoint to respond at all, not wait for CLI readiness. HTTP 000 means curl couldn't connect (container not up yet). Any response from the health endpoint (200 or 503) means the container is running and the Bun server is listening.

### Change 2: Add `/readyz` endpoint (optional, for future use)

**File:** `apps/telegram-bridge/src/health.ts`

Add a `/readyz` path that returns 200 only when CLI is fully ready. The existing `/health` endpoint remains unchanged (still returns 503 during spawn). This follows the Kubernetes liveness/readiness probe convention and provides a clean separation for future orchestration.

```typescript
if (url.pathname === "/readyz" && req.method === "GET") {
  const ready = state.cliProcess !== null && state.cliState === "ready";
  return Response.json(
    { ready, cli: state.cliState },
    { status: ready ? 200 : 503 },
  );
}
```

### Change 3: Update Dockerfile HEALTHCHECK (align with liveness semantics)

**File:** `apps/telegram-bridge/Dockerfile` (lines 28-29)

The Docker HEALTHCHECK should also tolerate degraded state since it runs continuously. During CLI restart (crash recovery), the container is still alive:

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -sf http://localhost:8080/health || curl -s http://localhost:8080/health | grep -q '"bot":"running"' || exit 1
```

This passes if either the health endpoint returns 200 OR the response body contains `"bot":"running"` (which it does even during degraded state).

## Non-goals

- Speeding up CLI initialization (separate concern, depends on Claude Code CLI internals)
- Changing the health endpoint response codes (503 for degraded is semantically correct)
- Adding Kubernetes-style probes to the web-platform (it doesn't have this problem)

## Acceptance Criteria

- [ ] CI deploy health check passes when the health endpoint returns HTTP 503 with `status: degraded` (`telegram-bridge-release.yml`)
- [ ] CI deploy health check still fails when the health endpoint is unreachable (container not started)
- [ ] `/readyz` endpoint returns 200 only when CLI is fully ready (`health.ts`)
- [ ] `/readyz` endpoint returns 503 when CLI is connecting or in error state (`health.ts`)
- [ ] Dockerfile HEALTHCHECK tolerates degraded state during CLI spawn (`Dockerfile`)
- [ ] Existing health endpoint behavior unchanged -- 200 when ready, 503 when degraded (`health.ts`)
- [ ] All existing health tests continue to pass (`test/health.test.ts`)
- [ ] New tests cover `/readyz` endpoint behavior (`test/health.test.ts`)

## Test Scenarios

### Acceptance Tests

- Given the CLI is spawning (cliState="connecting"), when the deploy health check runs, then it should pass because HTTP 503 with degraded status is accepted
- Given the container has not started yet, when the deploy health check runs, then it should fail after exhausting retries (HTTP 000)
- Given the CLI is fully ready (cliState="ready"), when `/readyz` is called, then it returns HTTP 200 with `{ready: true}`
- Given the CLI is connecting (cliState="connecting"), when `/readyz` is called, then it returns HTTP 503 with `{ready: false}`
- Given the CLI is in error state (cliState="error"), when `/readyz` is called, then it returns HTTP 503 with `{ready: false}`

### Regression Tests

- Given the existing health tests, when run after changes, then all 8 existing tests pass unchanged (P2-013 regression coverage preserved)

### Edge Cases

- Given the health endpoint is responding with 503 but `bot` field is missing, when Docker HEALTHCHECK runs, then it should fail (container is broken, not just spawning)
- Given a POST request to `/readyz`, when the endpoint receives it, then it returns 404

## MVP

### `apps/telegram-bridge/src/health.ts`

```typescript
export function createHealthServer(port: number, state: HealthState) {
  return Bun.serve({
    port,
    hostname: "127.0.0.1",
    fetch(req) {
      const url = new URL(req.url);

      // Liveness: is the process alive and serving?
      if (url.pathname === "/health" && req.method === "GET") {
        const healthy = state.cliProcess !== null && state.cliState === "ready";
        return Response.json(
          {
            status: healthy ? "ok" : "degraded",
            cli: state.cliState,
            bot: "running",
            queue: state.messageQueue.length,
            uptime: Math.floor((Date.now() - state.startTime) / 1000),
            messagesProcessed: state.messagesProcessed,
          },
          { status: healthy ? 200 : 503 },
        );
      }

      // Readiness: is the CLI subprocess fully initialized?
      if (url.pathname === "/readyz" && req.method === "GET") {
        const ready = state.cliProcess !== null && state.cliState === "ready";
        return Response.json(
          { ready, cli: state.cliState },
          { status: ready ? 200 : 503 },
        );
      }

      return new Response("Not found", { status: 404 });
    },
  });
}
```

### `.github/workflows/telegram-bridge-release.yml` (deploy health check)

```bash
echo "Waiting for health endpoint (container liveness)..."
for i in $(seq 1 12); do
  STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health || echo "000")
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "503" ]; then
    BODY=$(curl -s http://localhost:8080/health)
    echo "Health endpoint responded: HTTP $STATUS - $BODY"
    exit 0
  fi
  echo "Attempt $i: HTTP $STATUS (waiting for health endpoint...)"
  sleep 5
done
echo "Health check failed - endpoint not responding"
docker logs soleur-bridge --tail 30
exit 1
```

## References

- Issue: #763
- Related PRs: #759 (Dockerfile npm fix), #760 (env var injection), #761 (timeout increase to 100s)
- Related issue: #739 (app versioning)
- Health endpoint: `apps/telegram-bridge/src/health.ts`
- Deploy workflow: `.github/workflows/telegram-bridge-release.yml`
- Health tests: `apps/telegram-bridge/test/health.test.ts`
- Learning: `knowledge-base/learnings/2026-03-19-docker-restart-does-not-apply-new-images.md`
