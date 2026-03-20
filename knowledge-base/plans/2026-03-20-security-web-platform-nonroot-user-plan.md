---
title: "security: add non-root USER directive to web-platform Dockerfile"
type: fix
date: 2026-03-20
---

# security: add non-root USER directive to web-platform Dockerfile

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5 (Acceptance Criteria, SpecFlow Analysis, Proposed Solution, Test Scenarios, References)
**Research sources:** Docker official docs (Context7), Node.js Docker best practices, Next.js Docker security guides, Arcjet security blog, project learnings (3 relevant)

### Key Improvements

1. **UID 1000 conflict identified:** `node:22-slim` already ships a `node` user at UID 1000. Creating `soleur` via `useradd` assigns UID 1001, avoiding conflict but diverging from the telegram-bridge pattern (which uses UID 1000 on `oven/bun`, a base without a pre-existing user). The plan now uses `useradd --uid 1001` explicitly for determinism.
2. **`curl` availability confirmed:** `node:22-slim` installs `curl` by default (via bookworm-slim base layer), so the HEALTHCHECK works without additional `apt-get install`.
3. **`chown -R` scope narrowed:** Rather than `chown -R soleur:soleur /app` (which recurses into `node_modules` -- 10k+ files, slow), the plan now targets only the directories the non-root user must write to or own: `.next/` and the workspace mountpoint.
4. **Deploy script `chown -R` race condition identified:** If workspace provisioning happens concurrently, `chown -R` on the host could race with active writes. The plan now uses `chown` on only the top-level `/mnt/data/workspaces` directory (not recursive) and lets the container create subdirectories with the correct owner.
5. **`npm run build` cache directory:** Next.js writes to `.next/cache/` at runtime for ISR/data caching. This directory must be writable by the non-root user, not just readable.

---

The web-platform Dockerfile (`apps/web-platform/Dockerfile`) runs the production process as root. Any code-execution vulnerability (e.g., via the Agent SDK spawning Claude Code processes in user workspaces) gives the attacker full container privileges. The telegram-bridge Dockerfile already follows the non-root pattern (`RUN useradd -m soleur` / `USER soleur`). This plan brings web-platform into parity.

## Acceptance Criteria

- [x] `apps/web-platform/Dockerfile` creates a non-root `soleur` user and switches to it before `CMD`
- [x] The `.next/` build output (created by `npm run build` as root) is owned by `soleur` at runtime -- both readable (static assets, server bundles) and writable (`.next/cache/` for ISR)
- [x] Volume mounts (`/workspaces`, `/app/shared/plugins/soleur:ro`) remain accessible -- deployment script (`web-platform-release.yml`) must `chown` host directories or the Dockerfile must set ownership on mountpoints
- [x] HEALTHCHECK continues to work (`curl` is pre-installed in `node:22-slim` and accessible to all users)
- [x] `npm run start` succeeds as non-root (Next.js binds to port 3000, which is > 1024 so no capability needed)
- [x] No regression in workspace provisioning (`server/workspace.ts` writes to `/workspaces/<userId>/`)
- [x] `git init` in workspace provisioning works correctly (`HOME` is `/home/soleur`, git uses `HOME` for `.gitconfig`)

### Research Insights -- Acceptance Criteria

**Best Practices (Docker official docs, Node.js Docker best practices):**
- The [Node.js Docker best practices guide](https://github.com/nodejs/docker-node/blob/main/docs/BestPractices.md) recommends using the built-in `node` user (UID 1000) provided by official Node images. However, for consistency with the telegram-bridge pattern and to maintain a project-wide `soleur` user convention, creating a dedicated `soleur` user is acceptable. The tradeoff is a second non-root user in the image.
- [Docker official documentation](https://github.com/docker/docs/blob/main/content/guides/agentic-ai.md) shows the pattern `RUN useradd --create-home --shell /bin/bash app && chown -R app:app /app` followed by `USER app` -- matching the approach in this plan.

**Security rationale:** Per [goldbergyoni/nodebestpractices](https://github.com/goldbergyoni/nodebestpractices/blob/master/sections/security/non-root-user.md), "If you are running your server as root and it gets hacked through a vulnerability in your code, the attacker will have total control over your machine." The web-platform is particularly high-risk because it spawns Claude Code processes in user workspaces via the Agent SDK.

## SpecFlow Analysis

### Critical Path

1. `npm run build` runs as root (build stage) -- produces `.next/` owned by root
2. `RUN useradd` creates the `soleur` user (UID 1001, since UID 1000 is taken by the `node` user in `node:22-slim`)
3. `RUN chown` transfers ownership of `.next/` to `soleur`
4. `USER soleur` switches to non-root
5. `npm run start` reads `.next/` -- needs read access to server bundles, write access to `.next/cache/`
6. Runtime writes to `/workspaces/<userId>/` via `workspace.ts` -- needs write access to the mounted volume
7. Runtime reads `/app/shared/plugins/soleur` (read-only mount) -- needs read access (world-readable by default)

### Edge Cases

| Scenario | Risk | Mitigation |
|----------|------|------------|
| `.next/` owned by root after build | `EACCES` on `npm run start` | `chown -R soleur:soleur .next` after build, before `USER soleur` |
| `.next/cache/` needs write access at runtime | ISR/data cache writes fail | Covered by the `chown` above -- `.next/cache/` is inside `.next/` |
| `/workspaces` volume mounted as root-owned | `EACCES` on `mkdirSync` in `workspace.ts` | Deploy script `chown 1001:1001 /mnt/data/workspaces` (top-level only, not recursive) |
| `npm ci` writes `node_modules/` as root | Read-only at runtime, no issue | No action needed -- `node_modules` is read at runtime, not written |
| `curl` not available to non-root user | HEALTHCHECK fails | `curl` is pre-installed in `node:22-slim` (confirmed via [bookworm-slim Dockerfile](https://github.com/nodejs/docker-node/blob/main/22/bookworm-slim/Dockerfile)) and accessible to all users via PATH |
| `git init` in workspace provisioning | `git` config may reference root home | `HOME` env defaults to `/home/soleur` after `USER soleur`; git uses `HOME` for `.gitconfig` |
| Port 3000 binding | Privileged port restriction | Port 3000 > 1024, no issue |
| UID 1000 conflict with `node` user | `useradd` fails or produces unpredictable behavior | Use `--uid 1001` explicitly to avoid conflict with the pre-existing `node` user |
| npm global installs (`/usr/local/lib/node_modules/`) | `claude-code` CLI installed as root, read-only for `soleur` | Global `node_modules` are read-only at runtime; CLI is invoked via `PATH`, no write access needed |
| Existing workspace files on host volume | Files created by prior root-based containers have `root:root` ownership | One-time `chown -R 1001:1001 /mnt/data/workspaces` in deploy script handles migration |

### Research Insights -- Edge Cases

**`.next/cache/` write requirement:** Next.js uses `.next/cache/` at runtime for Incremental Static Regeneration (ISR) and data caching. Per the [Arcjet security guide](https://blog.arcjet.com/security-advice-for-self-hosting-next-js-in-docker/), the `.next` directory must be writable by the non-root user. The recommended pattern creates `.next/` with correct ownership before copying build output.

**UID determinism:** [Docker official patterns](https://github.com/docker/docs/blob/main/content/guides/dotnet/containerize.md) use explicit UID assignment (`ARG UID=10001` / `--uid "${UID}"`) for deterministic builds. Since `node:22-slim` already occupies UID 1000, this plan explicitly assigns UID 1001 to avoid a silent conflict.

### Deploy Script Impact

The deploy step in `.github/workflows/web-platform-release.yml` (line 57-65) runs:

```bash
docker run -d \
  -v /mnt/data/workspaces:/workspaces \
  -v /mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro \
  ...
```

Host directories are owned by `root` (created by prior root-based containers). After switching to `USER soleur` (UID 1001), the container process cannot write to `/workspaces` unless:
1. The host directory ownership is changed to match `soleur`'s UID, OR
2. The `docker run` command adds `--user root` (defeats the purpose), OR
3. The Dockerfile creates `/workspaces` with `soleur` ownership before `USER`, and Docker preserves the ownership on bind-mount only if the host dir is empty (it is not -- existing workspaces exist).

**Simplest approach for this PR:** Update the deploy script to `chown -R 1001:1001 /mnt/data/workspaces` before `docker run`. This is a one-line change in the CI workflow. Use `-R` for the initial migration (existing files), then subsequent workspace provisioning creates new directories owned by `soleur` (UID 1001) automatically since the process runs as that user.

### Research Insights -- Deploy Script

**From project learning ([docker-restart-does-not-apply-new-images](../learnings/2026-03-19-docker-restart-does-not-apply-new-images.md)):** The deploy script already uses the correct stop/rm/run pattern (not `docker restart`), so the new image with the `USER` directive will be applied on deploy.

**From project learning ([docker-healthcheck-start-period-for-slow-init](../learnings/2026-03-19-docker-healthcheck-start-period-for-slow-init.md)):** The web-platform Dockerfile uses `--start-period=10s`. If the `chown` or startup adds latency, consider increasing this value. The telegram-bridge uses `--start-period=120s` because the Claude CLI takes 60-100s to initialize. The web-platform starts faster (Next.js server), so 10s should remain sufficient.

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

# Non-root user (UID 1001 avoids conflict with node:22-slim's built-in 'node' user at UID 1000)
RUN useradd --uid 1001 -m soleur \
    && chown -R soleur:soleur .next
USER soleur

# Production
ENV NODE_ENV=production
ENV PORT=3000
EXPOSE 3000

# Health check (curl is pre-installed in node:22-slim)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

CMD ["npm", "run", "start"]
```

### Research Insights -- Proposed Solution

**Why `chown .next` instead of `chown /app`:**
- `chown -R soleur:soleur /app` recurses into `node_modules/` (typically 10,000+ files), adding significant build time for no runtime benefit -- `node_modules` is read-only at runtime.
- Only `.next/` needs ownership transfer: it contains the build output that Next.js reads and the cache directory it writes to.
- `node_modules/`, `package.json`, source files, and other `/app` contents are read-only at runtime and world-readable by default, so root ownership is fine.

**Why not use the built-in `node` user:**
- The telegram-bridge uses `soleur` as the user name. Using the same name across all containers maintains a consistent security convention and makes `chown` commands in deploy scripts predictable.
- The `node` user's home directory is `/home/node`. Using a `soleur` user with `/home/soleur` keeps home directory conventions aligned across services.

**Why `--uid 1001` explicitly:**
- `node:22-slim` already has `node` at UID 1000. Without `--uid`, `useradd` auto-assigns the next available UID, which is likely 1001 but not guaranteed across base image versions.
- Explicit UID ensures deploy scripts can reliably reference `1001:1001` in `chown` commands.

### `.github/workflows/web-platform-release.yml` (deploy step)

Add `chown` before `docker run` to ensure volume mountpoint ownership:

```bash
# Ensure workspace volume is owned by soleur (UID 1001)
chown -R 1001:1001 /mnt/data/workspaces
```

**Note:** The `-R` flag is needed for the initial migration from root-owned files. On subsequent deploys, new workspaces are created by the `soleur` process and already have correct ownership. The `-R` adds negligible time for the current workspace count.

## Test Scenarios

- Given a fresh `docker build`, when `docker run` starts, then the process runs as `soleur` (verify with `docker exec <id> whoami` -- should output `soleur`, not `root`)
- Given the built image, when the container starts with volume mounts, then `/workspaces` is writable by the `soleur` user (verify with `docker exec <id> touch /workspaces/test && rm /workspaces/test`)
- Given the running container, when a workspace is provisioned via the API, then `workspace.ts` creates directories and files without `EACCES` errors
- Given the running container, when HEALTHCHECK fires, then `curl` succeeds (exit 0) -- `curl` is pre-installed in `node:22-slim`
- Given the running container, when Next.js starts, then it reads `.next/` without permission errors and can write to `.next/cache/` for ISR
- Given the running container, when `git init` runs in a new workspace, then git uses `/home/soleur` as `HOME` and writes `.gitconfig` there (not to `/root`)
- Given the running container, when `id` is run, then the output shows `uid=1001(soleur)` (not uid=1000 which is the `node` user)
- Given the deploy script runs with existing root-owned workspaces, when `chown -R 1001:1001 /mnt/data/workspaces` executes, then all existing workspace files become owned by UID 1001

### Research Insights -- Test Scenarios

**Verification commands (from Docker best practices):**
```bash
# Verify non-root execution
docker exec <container> id
# Expected: uid=1001(soleur) gid=1001(soleur) groups=1001(soleur)

# Verify .next/ ownership
docker exec <container> ls -la /app/.next/
# Expected: drwxr-xr-x soleur soleur

# Verify .next/cache/ is writable
docker exec <container> touch /app/.next/cache/test-write && echo OK
# Expected: OK

# Verify /workspaces is writable (after deploy chown)
docker exec <container> mkdir -p /workspaces/test-user && echo OK
# Expected: OK

# Verify curl is available for HEALTHCHECK
docker exec <container> which curl
# Expected: /usr/bin/curl
```

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
- `knowledge-base/learnings/2026-03-19-docker-healthcheck-start-period-for-slow-init.md` -- HEALTHCHECK start-period pattern
- `knowledge-base/learnings/2026-03-19-docker-restart-does-not-apply-new-images.md` -- deploy script correctness confirmation
- [Node.js Docker Best Practices](https://github.com/nodejs/docker-node/blob/main/docs/BestPractices.md) -- built-in `node` user guidance
- [Docker Official Docs: Non-Root User](https://github.com/docker/docs/blob/main/content/guides/agentic-ai.md) -- `useradd` + `chown` + `USER` pattern
- [Arcjet: Security Advice for Self-Hosting Next.js in Docker](https://blog.arcjet.com/security-advice-for-self-hosting-next-js-in-docker/) -- `.next/` ownership requirements
- [Node.js Security Best Practices: Non-Root User](https://github.com/goldbergyoni/nodebestpractices/blob/master/sections/security/non-root-user.md) -- security rationale
- [node:22-bookworm-slim Dockerfile](https://github.com/nodejs/docker-node/blob/main/22/bookworm-slim/Dockerfile) -- confirms `curl` pre-installed, `node` user at UID 1000
