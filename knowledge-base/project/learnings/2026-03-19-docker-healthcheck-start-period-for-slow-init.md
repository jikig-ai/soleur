# Learning: Docker --start-period for slow-initializing containers

## Problem

The telegram-bridge deploy health check kept failing because the Claude CLI subprocess takes 60-100+ seconds to initialize. The health endpoint correctly returns HTTP 503 ("degraded") during this window, but `curl -sf` treats any non-2xx as failure. The team kept increasing the retry timeout (#759, #760, #761) — an escalating pattern that never converges because CLI startup time is variable.

## Solution

Three-pronged fix that addresses the root cause (liveness/readiness conflation) instead of papering over it with longer timeouts:

1. **Docker `--start-period=120s`** — purpose-built for slow-starting containers. Health check failures during this window are ignored; the container stays "starting" rather than going "unhealthy". This is the key infrastructure-level fix.

2. **CI deploy check accepts HTTP 503** — the deploy only needs to verify the container is alive (HTTP server responding), not that the CLI subprocess is fully initialized. Any HTTP response (200 or 503) from the health endpoint means the container is running.

3. **`/readyz` endpoint** — separates liveness (`/health` — "is the process alive?") from readiness (`/readyz` — "is the CLI fully initialized?") following Kubernetes probe conventions. Provides clean semantics for future orchestration.

## Key Insight

When a health check conflates "process is alive" with "service is fully ready," the fix is to separate the concerns — not to increase timeouts. Docker's `--start-period` and the Kubernetes liveness/readiness probe model are established patterns for this exact problem. Look for `--start-period` before reaching for timeout increases.

## Tags
category: integration-issues
module: telegram-bridge
