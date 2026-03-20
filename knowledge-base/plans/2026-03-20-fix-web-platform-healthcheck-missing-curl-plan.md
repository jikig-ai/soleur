---
title: "fix: replace curl-based HEALTHCHECK with Node.js fetch in web-platform Dockerfile"
type: fix
date: 2026-03-20
---

# fix: Replace curl-based HEALTHCHECK with Node.js fetch in web-platform Dockerfile

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 4 (Proposed Solution, Acceptance Criteria, Test Scenarios, Context)
**Research sources:** Docker healthcheck best practices, Node.js fetch timeout behavior, distroless container patterns, project learnings

### Key Improvements
1. Added explicit `AbortSignal.timeout()` to the fetch call for deterministic timeout behavior independent of Docker's `--timeout`
2. Identified and documented Node.js unhandled promise rejection edge case (Node 15+ terminates on unhandled rejections -- our `.catch()` handles this correctly)
3. Added test scenario for timeout behavior and shell quoting validation

### New Considerations Discovered
- The `node -e` approach uses Docker's shell form (`CMD command`), which runs under `/bin/sh -c` -- this is fine for `node:22-slim` which includes a shell, but would not work for distroless images (not applicable here, but worth noting for future reference)
- Native `fetch()` has no default timeout -- without `AbortSignal.timeout()`, the fetch could hang indefinitely if the server accepts the connection but never responds, though Docker's `--timeout=5s` would kill the process at the container level

## Overview

The web-platform Dockerfile defines a `HEALTHCHECK` using `curl`, but the `node:22-slim` base image does not include `curl`. The health check silently fails on every probe, causing Docker to mark the container as permanently unhealthy.

## Problem Statement

`apps/web-platform/Dockerfile` lines 31-32:

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1
```

The base image `node:22-slim` ships without `curl`. The `apt-get install` on line 7 only installs `git`. The health check command fails with "command not found" on every invocation, so Docker never sees a healthy probe and the container stays in `unhealthy` state indefinitely.

The telegram-bridge Dockerfile (`apps/telegram-bridge/Dockerfile`) correctly installs `curl` alongside its other system dependencies (line 5), which is why its identical `HEALTHCHECK` pattern works.

## Proposed Solution

Replace the `curl`-based health check with a Node.js `fetch()` one-liner. Node.js 22 includes native `fetch()` (stable since Node 18), so no additional binaries are needed.

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health',{signal:AbortSignal.timeout(4_000)}).then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
```

**Why not install curl?** Option 2 from the issue (Node-based check) is preferred because:

1. It avoids adding a binary that serves no other purpose in the image
2. It reduces image size (curl + libcurl + dependencies add ~5-10 MB to slim images)
3. The web-platform container already has Node.js available -- use what is there
4. It aligns with the principle of minimal attack surface for production images

**Why not option 1 (install curl)?** While simpler and consistent with telegram-bridge, the telegram-bridge has other reasons to install curl (it installs a broader set of system utilities). The web-platform only needs git. Adding curl solely for a health check is unnecessary when Node.js can do the same thing.

### Research Insights

**Best Practices (from Docker healthcheck literature):**
- Use the application's native runtime for health checks instead of adding external binaries -- this is the consensus recommendation from both [Elton Stoneman's analysis](https://blog.sixeyed.com/docker-healthchecks-why-not-to-use-curl-or-iwr/) and [Matt Knight's distroless guide](https://www.mattknight.io/blog/docker-healthchecks-in-distroless-node-js)
- curl adds ~2.5 MB on Alpine and ~5-10 MB on Debian slim, plus expands the attack surface with libcurl dependencies
- Health checks should validate that the application can serve requests, not just that a process is alive

**Timeout Handling:**
- Node.js native `fetch()` has no default timeout -- if the server accepts the TCP connection but hangs, fetch waits indefinitely
- `AbortSignal.timeout(4_000)` provides a 4-second application-level timeout, giving 1 second of headroom before Docker's 5-second `--timeout` kills the process
- Docker's `--timeout` is a hard kill (SIGKILL) with no cleanup -- the `AbortSignal.timeout()` allows the `.catch()` handler to run and exit cleanly with code 1
- `AbortSignal.timeout()` is available in Node.js 17.3+ (well within our Node 22 baseline)

**Error Handling:**
- The `.catch(() => process.exit(1))` handles three failure modes: connection refused (server not started), DNS resolution failure, and timeout (via AbortSignal)
- In Node.js 15+, unhandled promise rejections terminate the process with a non-zero exit code -- our explicit `.catch()` is the safer pattern since it guarantees exit code 1 specifically (not an arbitrary non-zero code)
- The `.then(r => { if(!r.ok) process.exit(1) })` catches HTTP error responses (4xx, 5xx) that would not trigger a network error

**Shell Form vs Exec Form:**
- The `CMD` in shell form (`CMD node -e "..."`) runs under `/bin/sh -c`, which is available in `node:22-slim`
- For distroless images, the exec form (`CMD ["/usr/local/bin/node", "-e", "..."]`) would be required -- not applicable here but noted for future reference

## Acceptance Criteria

- [ ] `HEALTHCHECK` in `apps/web-platform/Dockerfile` uses `node -e "fetch(...)"` instead of `curl -f`
- [ ] `fetch()` call includes `AbortSignal.timeout(4_000)` for deterministic timeout behavior
- [ ] No `curl` added to the `apt-get install` line
- [ ] Health check correctly returns exit 0 when `/health` responds 200
- [ ] Health check correctly returns exit 1 when `/health` responds non-200 or is unreachable

## Test Scenarios

- Given a running web-platform container, when the `/health` endpoint returns 200, then `docker inspect --format='{{.State.Health.Status}}'` reports `healthy`
- Given a running web-platform container, when the server is not yet started, then the health check fails gracefully (exit 1) without crashing
- Given the Dockerfile is built, when inspecting installed packages, then `curl` is NOT present in the image
- Given the Dockerfile is built, when running `docker build`, then no syntax errors occur from shell quoting in the `node -e` command
- Given a running web-platform container, when the `/health` endpoint hangs without responding, then the fetch times out after 4 seconds via `AbortSignal.timeout` and exits with code 1

## Context

- Found during code review of PR #814 (pre-existing issue)
- The `/health` endpoint exists at `apps/web-platform/server/index.ts:16-19` and returns `{"status": "ok"}` with HTTP 200
- The CI deploy script (`.github/workflows/web-platform-release.yml:68`) uses `curl` on the host to check health -- this is unaffected since it runs outside the container
- Related learning: `knowledge-base/learnings/2026-03-19-docker-healthcheck-start-period-for-slow-init.md` -- the current `--start-period=10s` is adequate for Next.js startup (unlike telegram-bridge which needs 120s for Claude CLI init)
- Related learning: `knowledge-base/learnings/2026-03-19-npm-global-install-version-pinning.md` -- the existing `npm install -g @anthropic-ai/claude-code@2.1.79` in the Dockerfile already follows version pinning best practices (no changes needed)
- Related learning: `knowledge-base/learnings/2026-03-19-docker-base-image-digest-pinning.md` -- the existing `FROM node:22-slim@sha256:...` already uses digest pinning (no changes needed)

## MVP

### apps/web-platform/Dockerfile (lines 31-32)

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health',{signal:AbortSignal.timeout(4_000)}).then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
```

## References

- Issue: #815
- File: `apps/web-platform/Dockerfile:31-32`
- Comparison: `apps/telegram-bridge/Dockerfile:4-5,28-29` (correctly installs curl)
- Health endpoint: `apps/web-platform/server/index.ts:16-19`
- CI deploy health check: `.github/workflows/web-platform-release.yml:68`
- [Docker Healthchecks: Why Not To Use curl or iwr](https://blog.sixeyed.com/docker-healthchecks-why-not-to-use-curl-or-iwr/)
- [Docker healthchecks in distroless Node.js](https://www.mattknight.io/blog/docker-healthchecks-in-distroless-node-js)
- [Docker Healthcheck without curl or wget](https://muratcorlu.com/docker-healthcheck-without-curl-or-wget/)
