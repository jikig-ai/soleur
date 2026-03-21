# Learning: node:22-slim does not include curl -- use Node.js fetch for HEALTHCHECK

## Problem

The web-platform Dockerfile HEALTHCHECK used `curl -f http://localhost:3000/health` with a comment claiming "curl is pre-installed in node:22-slim." Every health probe failed with "command not found," causing Docker to permanently mark the container as unhealthy.

## Solution

Replace `curl -f` with `node -e "fetch(...)"` using the Node.js runtime already present in the image. Node 22 includes stable native `fetch()` (via undici) and `AbortSignal.timeout()`.

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health',{signal:AbortSignal.timeout(4_000)}).then(r=>{if(!r.ok)process.exit(1)}).catch(e=>{console.error(e.message);process.exit(1)})"
```

Key design choices:

- `AbortSignal.timeout(4_000)` provides 1s headroom before Docker's 5s SIGKILL, allowing `.catch()` to exit cleanly
- `console.error(e.message)` populates Docker health logs for debuggability
- No need for exec form (`CMD ["node", "-e", "..."]`) — shell form works correctly under `/bin/sh -c`

## Key Insight

Slim Docker base images (debian:bookworm-slim variants like node:22-slim) strip many common utilities including curl. When a Node.js runtime is already available, use `node -e fetch(...)` instead of installing curl — it avoids adding unnecessary binaries and reduces attack surface.

## Tags

category: runtime-errors
module: docker
