---
title: "node:22-slim missing ca-certificates breaks git HTTPS clone"
date: 2026-04-06
category: runtime-errors
tags: [docker, git, ssl, ca-certificates, node-slim, workspace-provisioning]
severity: high
module: web-platform
symptoms: ["Git clone failed: server certificate verification failed", "CAfile: none CRLfile: none"]
root_cause: "node:22-slim Docker image does not include ca-certificates package"
---

# node:22-slim Missing ca-certificates Breaks Git HTTPS Clone

## Problem

Project setup (`provisionWorkspaceWithRepo` in `apps/web-platform/server/workspace.ts`) fails in the Docker container with:

```text
Git clone failed: server certificate verification failed. CAfile: none CRLfile: none
```

All HTTPS git operations inside the container are broken. Users cannot connect repositories.

## Root Cause Analysis

The `node:22-slim` Docker base image does NOT include the `ca-certificates` package. Git's HTTPS transport uses GnuTLS which looks for the CA bundle at `/etc/ssl/certs/ca-certificates.crt`. Without this file, all HTTPS git operations fail.

**Why Node.js itself was unaffected:** Node.js bundles its own Mozilla CA certificates in the binary. Node's `fetch()`, `https`, and npm operations use this internal bundle -- they do not depend on the system CA store.

**AppArmor ruled out:** The AppArmor profile allows broad `file` access and does not restrict reading from `/etc/ssl/`.

## Solution

Add `ca-certificates` to the existing `apt-get install` line in `apps/web-platform/Dockerfile` runner stage (~400KB addition):

```diff
 # Install git (workspace provisioning) + bubblewrap/socat (Agent SDK sandbox)
+# ca-certificates: required for git HTTPS clone -- node:22-slim omits it (#1645)
 RUN apt-get update && apt-get install -y --no-install-recommends \
-    git bubblewrap socat \
+    ca-certificates git bubblewrap socat \
     && rm -rf /var/lib/apt/lists/*
```

No code changes needed in `workspace.ts` -- git just needs its CA bundle on the filesystem.

## Key Insight

`-slim` Docker images strip packages you might assume are always present. When adding system binaries to a slim image (like `git`), audit their runtime dependencies -- not just whether the binary installs. `git` installed fine but its HTTPS transport silently depended on `ca-certificates`. The failure only appeared at clone time, not at install time.

General pattern: any tool making outbound TLS connections via the system TLS library needs `ca-certificates` on Debian-slim images (`git`, `curl`, `wget`, `openssl s_client`).

## Session Errors

1. **Subagent rate limit during plan+deepen phase** -- Planning subagent hit API rate limits, so planning was completed inline. No impact on the fix itself.
   - **Prevention:** No workflow change possible -- rate limits are external. The inline fallback worked correctly.

## Cross-References

- `knowledge-base/project/learnings/2026-03-20-node-slim-missing-curl-healthcheck.md` -- Same root cause pattern (slim image missing packages)
- `knowledge-base/project/learnings/2026-03-20-multistage-docker-build-esbuild-server-compilation.md` -- Multi-stage Dockerfile rewrite where runner `apt-get install` was first added
- `knowledge-base/project/learnings/2026-03-20-docker-nonroot-user-with-volume-mounts.md` -- Git config for the non-root user that runs the clone

## Tags

category: runtime-errors
module: web-platform
