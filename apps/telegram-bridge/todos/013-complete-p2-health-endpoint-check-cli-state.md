---
status: complete
priority: p2
issue_id: "013"
tags: [code-review, reliability, operations]
dependencies: []
---

# Health endpoint should reflect CLI state

## Problem Statement

The health endpoint always returns 200 OK with `{ status: "ok" }` regardless of whether the CLI process is alive, errored, or stuck. External monitoring tools (Docker health checks, load balancers) cannot detect when the bridge is in a degraded state.

## Findings

- **architecture-strategist**: "health always 200 -- useless for monitoring"
- **performance-oracle**: "health endpoint provides no operational insight"

## Proposed Solutions

### Option A: Return CLI state in health response (Recommended)
```typescript
Bun.serve({
  port: 8080,
  hostname: "127.0.0.1",
  fetch() {
    const healthy = cliProcess !== null && cliState === "ready";
    const status = healthy ? 200 : 503;
    return new Response(
      JSON.stringify({ status: healthy ? "ok" : "degraded", cliState, queueLength: messageQueue.length }),
      { status, headers: { "Content-Type": "application/json" } }
    );
  },
});
```
- **Effort**: Small
- **Risk**: Low -- may cause container restarts if orchestrator acts on 503

### Option B: Separate liveness and readiness endpoints
- `/health` always 200 (process alive)
- `/ready` returns 503 when CLI not ready
- **Effort**: Medium
- **Risk**: Low

## Acceptance Criteria
- [ ] Health endpoint returns 503 when CLI is not running or in error state
- [ ] Response body includes cliState and queue length
- [ ] Docker health check can detect degraded bridge

## Work Log
- 2026-02-11: Identified during /soleur:review round 2
