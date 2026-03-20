---
title: "fix: replace curl-based HEALTHCHECK with Node.js fetch in web-platform Dockerfile"
type: fix
date: 2026-03-20
---

# fix: Replace curl-based HEALTHCHECK with Node.js fetch in web-platform Dockerfile

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
  CMD node -e "fetch('http://localhost:3000/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
```

**Why not install curl?** Option 2 from the issue (Node-based check) is preferred because:

1. It avoids adding a binary that serves no other purpose in the image
2. It reduces image size (curl + libcurl + dependencies add ~5-10 MB to slim images)
3. The web-platform container already has Node.js available -- use what is there
4. It aligns with the principle of minimal attack surface for production images

**Why not option 1 (install curl)?** While simpler and consistent with telegram-bridge, the telegram-bridge has other reasons to install curl (it installs a broader set of system utilities). The web-platform only needs git. Adding curl solely for a health check is unnecessary when Node.js can do the same thing.

## Acceptance Criteria

- [ ] `HEALTHCHECK` in `apps/web-platform/Dockerfile` uses `node -e "fetch(...)"` instead of `curl -f`
- [ ] No `curl` added to the `apt-get install` line
- [ ] Health check correctly returns exit 0 when `/health` responds 200
- [ ] Health check correctly returns exit 1 when `/health` responds non-200 or is unreachable

## Test Scenarios

- Given a running web-platform container, when the `/health` endpoint returns 200, then `docker inspect --format='{{.State.Health.Status}}'` reports `healthy`
- Given a running web-platform container, when the server is not yet started, then the health check fails gracefully (exit 1) without crashing
- Given the Dockerfile is built, when inspecting installed packages, then `curl` is NOT present in the image

## Context

- Found during code review of PR #814 (pre-existing issue)
- The `/health` endpoint exists at `apps/web-platform/server/index.ts:16-19` and returns `{"status": "ok"}` with HTTP 200
- The CI deploy script (`.github/workflows/web-platform-release.yml:68`) uses `curl` on the host to check health -- this is unaffected since it runs outside the container
- Related learning: `knowledge-base/learnings/2026-03-19-docker-healthcheck-start-period-for-slow-init.md` -- the current `--start-period=10s` is adequate for Next.js startup (unlike telegram-bridge which needs 120s for Claude CLI init)

## MVP

### apps/web-platform/Dockerfile (lines 31-32)

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
```

## References

- Issue: #815
- File: `apps/web-platform/Dockerfile:31-32`
- Comparison: `apps/telegram-bridge/Dockerfile:4-5,28-29` (correctly installs curl)
- Health endpoint: `apps/web-platform/server/index.ts:16-19`
- CI deploy health check: `.github/workflows/web-platform-release.yml:68`
