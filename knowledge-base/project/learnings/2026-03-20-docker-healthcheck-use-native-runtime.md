# Learning: Use native runtime for Docker HEALTHCHECK instead of installing external binaries

## Problem

The web-platform Dockerfile defined a HEALTHCHECK using `curl`, but the `node:22-slim` base image doesn't include curl. The health check silently failed on every probe, causing Docker to mark the container as permanently unhealthy.

## Solution

Replace curl with Node.js native `fetch()` (stable since Node 18):

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health',{signal:AbortSignal.timeout(4_000)}).then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
```

Key details:

- `AbortSignal.timeout(4_000)` provides a 4-second application-level timeout, giving 1 second of headroom before Docker's 5-second `--timeout` SIGKILL
- `.catch(() => process.exit(1))` handles connection refused, DNS failures, and timeouts
- `.then(r => { if(!r.ok) process.exit(1) })` catches non-200 HTTP responses
- Shell form `CMD` works in node:22-slim (has /bin/sh); exec form needed only for distroless

## Key Insight

Always use the application's native runtime for Docker health checks. Installing curl/wget solely for health probes adds 5-10 MB, expands CVE attack surface, and creates a dependency mismatch between the health check tool and the application runtime. If the container has Node.js, use `node -e "fetch(...)"`. If it has Python, use `python -c "import urllib..."`.

## Tags

category: infrastructure
module: docker
