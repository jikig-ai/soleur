---
title: "fix: replace curl-based HEALTHCHECK with Node.js fetch in web-platform Dockerfile"
type: fix
date: 2026-03-20
---

# fix: Replace curl-based HEALTHCHECK with Node.js fetch in web-platform Dockerfile

## Overview

The web-platform Dockerfile HEALTHCHECK uses `curl -f http://localhost:3000/health`, but `node:22-slim` (Debian bookworm-slim) does not include `curl`. Every health probe fails with "command not found," causing Docker to permanently mark the container as unhealthy.

**Empirically verified:** `docker run --rm node:22-slim@sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d bash -c "curl --version"` returns `bash: curl: command not found`. The existing Dockerfile comment on line 36 ("curl is pre-installed in node:22-slim") is incorrect.

## Problem Statement

`apps/web-platform/Dockerfile` lines 36-38:

```dockerfile
# Health check (curl is pre-installed in node:22-slim)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1
```

The `apt-get install` on line 7 only installs `git`. The `curl` binary is absent, so every HEALTHCHECK invocation fails silently. Docker marks the container as permanently `unhealthy`.

The telegram-bridge Dockerfile (`apps/telegram-bridge/Dockerfile:5`) correctly installs `curl` alongside other system dependencies, which is why its identical HEALTHCHECK pattern works.

## Proposed Solution

Replace the `curl`-based health check with a Node.js `fetch()` one-liner. Node.js 22 includes native `fetch()` (stable since Node 18), so no additional binaries are needed.

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health',{signal:AbortSignal.timeout(4_000)}).then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
```

### Why not install curl?

1. It avoids adding a binary that serves no other purpose in the image
2. It reduces image size (curl + libcurl + dependencies add ~5-10 MB to slim images)
3. The container already has Node.js available -- use what is already there
4. It aligns with minimal attack surface for production images
5. The telegram-bridge installs curl because it has other reasons for a broader set of system utilities; the web-platform only needs `git`

### Why AbortSignal.timeout(4_000)?

- Node.js native `fetch()` has no default timeout -- without `AbortSignal.timeout()`, the fetch hangs indefinitely if the server accepts the connection but never responds
- 4 seconds provides 1 second of headroom before Docker's 5-second `--timeout` kills the process
- Docker's `--timeout` is a hard kill (SIGKILL) with no cleanup; `AbortSignal.timeout()` allows `.catch()` to run and exit cleanly with code 1
- `AbortSignal.timeout()` is available in Node.js 17.3+ (well within the Node 22 baseline)

### Error handling

- `.catch(() => process.exit(1))` handles: connection refused, DNS failure, and timeout (via AbortSignal)
- `.then(r => { if(!r.ok) process.exit(1) })` catches HTTP error responses (4xx, 5xx) that would not trigger a network error
- In Node.js 15+, unhandled promise rejections terminate with a non-zero exit code -- the explicit `.catch()` guarantees exit code 1 specifically

## Acceptance Criteria

- [ ] `HEALTHCHECK` in `apps/web-platform/Dockerfile` uses `node -e "fetch(...)"` instead of `curl -f`
- [ ] `fetch()` call includes `AbortSignal.timeout(4_000)` for deterministic timeout behavior
- [ ] Incorrect comment ("curl is pre-installed in node:22-slim") is removed or corrected
- [ ] No `curl` added to the `apt-get install` line
- [ ] Health check returns exit 0 when `/health` responds 200
- [ ] Health check returns exit 1 when `/health` responds non-200 or is unreachable
- [ ] CI deploy health check in `.github/workflows/web-platform-release.yml:70` is unaffected (runs on the host, not inside the container)

## Test Scenarios

- Given the Dockerfile is built, when running `docker build`, then no syntax errors from shell quoting in the `node -e` command
- Given a running web-platform container, when the `/health` endpoint returns 200, then `docker inspect --format='{{.State.Health.Status}}'` reports `healthy`
- Given a running web-platform container, when the server is not yet started, then the health check fails gracefully (exit 1) without crashing
- Given the Dockerfile is built, when inspecting installed packages, then `curl` is NOT present in the image
- Given a running web-platform container, when the `/health` endpoint hangs without responding, then the fetch times out after 4 seconds via `AbortSignal.timeout` and exits with code 1

## Context

- Issue: #818 (pre-existing bug identified during code review of PR #813)
- Related prior work: worktree `feat-healthcheck-curl-815` has an identical plan -- issue #818 was filed as a replacement after #815 was discovered to be a duplicate tracking effort
- The `/health` endpoint at `apps/web-platform/server/index.ts:16-19` returns `{"status": "ok"}` with HTTP 200
- The CI deploy script `.github/workflows/web-platform-release.yml:70` uses `curl` on the host to check health -- this is unaffected since it runs outside the container
- Related learnings: `knowledge-base/learnings/2026-03-19-docker-healthcheck-start-period-for-slow-init.md`, `knowledge-base/learnings/2026-03-19-docker-base-image-digest-pinning.md`
- Semver: `semver:patch` -- bug fix, no new features

## MVP

### apps/web-platform/Dockerfile (lines 36-38)

```dockerfile
# Health check (uses Node.js fetch -- curl is not available in node:22-slim)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health',{signal:AbortSignal.timeout(4_000)}).then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
```

## Non-goals

- Installing `curl` in the image (adds unnecessary binary and attack surface)
- Changing the `/health` endpoint implementation
- Modifying the CI deploy health check (runs on host, uses host curl)
- Changing the telegram-bridge HEALTHCHECK (correctly installs curl for other reasons)

## References

- Issue: #818
- File: `apps/web-platform/Dockerfile:36-38`
- Comparison: `apps/telegram-bridge/Dockerfile:5,28-29` (correctly installs curl)
- Health endpoint: `apps/web-platform/server/index.ts:16-19`
- CI deploy health check: `.github/workflows/web-platform-release.yml:70`
- [Docker Healthchecks: Why Not To Use curl or iwr](https://blog.sixeyed.com/docker-healthchecks-why-not-to-use-curl-or-iwr/)
