---
title: "security: add non-root USER directive to web-platform Dockerfile"
type: fix
date: 2026-03-20
---

# security: add non-root USER directive to web-platform Dockerfile

The web-platform Dockerfile (`apps/web-platform/Dockerfile`) runs the production process as root. Any code-execution vulnerability (e.g., via the Agent SDK spawning Claude Code processes in user workspaces) gives the attacker full container privileges. The telegram-bridge Dockerfile already follows the non-root pattern (`RUN useradd -m soleur` / `USER soleur`). This plan brings web-platform into parity.

## Acceptance Criteria

- [ ] `apps/web-platform/Dockerfile` creates a non-root `soleur` user and switches to it before `CMD`
- [ ] The `.next/` build output (created by `npm run build` as root) is readable by the `soleur` user at runtime
- [ ] Volume mounts (`/workspaces`, `/app/shared/plugins/soleur:ro`) remain accessible -- deployment script (`web-platform-release.yml`) must `chown` host directories or the Dockerfile must set ownership on mountpoints
- [ ] HEALTHCHECK continues to work (curl must be available to the non-root user)
- [ ] `npm run start` succeeds as non-root (Next.js binds to port 3000, which is > 1024 so no capability needed)
- [ ] No regression in workspace provisioning (`server/workspace.ts` writes to `/workspaces/<userId>/`)

## SpecFlow Analysis

### Critical Path

1. `npm run build` runs as root (build stage) -- produces `.next/` owned by root
2. `USER soleur` switches to non-root
3. `npm run start` reads `.next/` -- needs read access
4. Runtime writes to `/workspaces/<userId>/` via `workspace.ts` -- needs write access to the mounted volume
5. Runtime reads `/app/shared/plugins/soleur` (read-only mount) -- needs read access

### Edge Cases

| Scenario | Risk | Mitigation |
|----------|------|------------|
| `.next/` owned by root after build | `EACCES` on `npm run start` | `chown -R soleur:soleur /app` after build, before `USER soleur` |
| `/workspaces` volume mounted as root-owned | `EACCES` on `mkdirSync` in `workspace.ts` | Deploy script creates dir with correct ownership, or Dockerfile creates mountpoint with `soleur` ownership and Docker preserves it |
| `npm ci` writes `node_modules/` as root | Read-only at runtime, no issue | No action needed -- `node_modules` is read at runtime, not written |
| `curl` not available to non-root user | HEALTHCHECK fails | `curl` is installed via `apt-get` as root -- binary remains accessible to all users via PATH |
| `git init` in workspace provisioning | `git` config may reference root home | `HOME` env defaults to `/home/soleur` after `USER soleur`; git uses `HOME` for `.gitconfig` |
| Port 3000 binding | Privileged port restriction | Port 3000 > 1024, no issue |

### Deploy Script Impact

The deploy step in `.github/workflows/web-platform-release.yml` (line 57-65) runs:

```bash
docker run -d \
  -v /mnt/data/workspaces:/workspaces \
  -v /mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro \
  ...
```

Host directories are owned by `root` (created by prior root-based containers). After switching to `USER soleur` (UID 1000 typically), the container process cannot write to `/workspaces` unless:
1. The host directory ownership is changed to match `soleur`'s UID, OR
2. The `docker run` command adds `--user root` (defeats the purpose), OR
3. The Dockerfile creates `/workspaces` with `soleur` ownership before `USER`, and Docker preserves the ownership on bind-mount only if the host dir is empty (it is not -- existing workspaces exist).

**Recommended approach:** Add a lightweight entrypoint script that runs as root, `chown`s the volume mountpoints, then `exec`s the app as `soleur` via `gosu` or `su-exec`. However, this adds complexity. The simpler alternative used by many production Node.js images is to ensure the host volume directories have the correct UID before deployment -- i.e., a one-time `chown` on the host via the deploy script.

**Simplest approach for this PR:** Update the deploy script to `chown -R 1000:1000 /mnt/data/workspaces` before `docker run`. This is a one-line change in the CI workflow and avoids introducing `gosu` dependencies.

## Proposed Solution

### `apps/web-platform/Dockerfile`

```dockerfile
FROM node:22-slim AS base

# Install Claude Code CLI (needed by Agent SDK)
RUN npm install -g @anthropic-ai/claude-code@2.1.79

# Install git (needed for workspace provisioning)
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install dependencies
COPY package.json package-lock.json ./
RUN npm ci --production=false

# Copy source
COPY . .

# NEXT_PUBLIC_ vars must be present at build time for client-side inlining
ARG NEXT_PUBLIC_SUPABASE_URL
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY

# Build Next.js
RUN npm run build

# Non-root user (matches telegram-bridge pattern)
RUN useradd -m soleur
RUN chown -R soleur:soleur /app
USER soleur

# Production
ENV NODE_ENV=production
ENV PORT=3000
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

CMD ["npm", "run", "start"]
```

### `.github/workflows/web-platform-release.yml` (deploy step)

Add `chown` before `docker run` to ensure volume mountpoint ownership:

```bash
# Ensure workspace volume is owned by soleur (UID 1000)
chown -R 1000:1000 /mnt/data/workspaces
```

## Test Scenarios

- Given a fresh `docker build`, when `docker run` starts, then the process runs as `soleur` (verify with `docker exec <id> whoami`)
- Given the built image, when the container starts with volume mounts, then `/workspaces` is writable by the `soleur` user
- Given the running container, when a workspace is provisioned via the API, then `workspace.ts` creates directories and files without `EACCES`
- Given the running container, when HEALTHCHECK fires, then `curl` succeeds (exit 0)
- Given the running container, when Next.js starts, then it reads `.next/` without permission errors

## Context

- Closes #806
- Pattern source: `apps/telegram-bridge/Dockerfile` (lines 21-22)
- Related parallel PRs: #810 (multi-stage Dockerfile), #812 (dockerignore), #814 (base image pinning)
- Deployment workflow: `.github/workflows/web-platform-release.yml`
- Runtime filesystem operations: `apps/web-platform/server/workspace.ts`, `apps/web-platform/server/agent-runner.ts`

## References

- `apps/web-platform/Dockerfile` -- target file
- `apps/telegram-bridge/Dockerfile:21-22` -- reference pattern
- `.github/workflows/web-platform-release.yml:51-65` -- deploy script with volume mounts
- `apps/web-platform/server/workspace.ts` -- runtime writes to `/workspaces`
- `apps/web-platform/server/agent-runner.ts:17` -- reads from `/app/shared/plugins/soleur`
- `knowledge-base/learnings/2026-03-19-docker-base-image-digest-pinning.md` -- related Docker learning
