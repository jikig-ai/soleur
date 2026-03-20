---
title: "chore: standardize soleur UID across all Dockerfiles"
type: fix
date: 2026-03-20
---

# chore: standardize soleur UID across all Dockerfiles

## Overview

The `soleur` user has inconsistent UID handling across the two application Dockerfiles, and `apps/web-platform/Dockerfile` has a UID mismatch between the container user and the host volume ownership.

## Problem Statement

### Current state

| App | Dockerfile user creation | Runtime UID | Host volume ownership |
|-----|-------------------------|-------------|----------------------|
| telegram-bridge | `useradd -m soleur` (auto-assigned, gets UID 1001 because `bun:1000` exists) | 1001 (non-deterministic) | N/A (deploy script mounts as-is) |
| web-platform | `USER node` (built-in `node` user from `node:22-slim`) | 1000 | `chown 1001:1001 /mnt/data/workspaces` in `ci-deploy.sh:76` and `cloud-init.yml:118,213` |

### Problems

1. **telegram-bridge UID is non-deterministic.** `useradd -m soleur` auto-assigns the next available UID. On `oven/bun:1.3.11` this happens to be 1001 (because the `bun` user occupies 1000), but a base image update could change this silently.

2. **web-platform has a UID mismatch.** The container runs as `node` (UID 1000) but the host volume `/mnt/data/workspaces` is owned by UID 1001. This means the container process cannot write to the volume mount unless Docker's user namespace mapping compensates -- which it does not by default. This was likely introduced when the non-root user plan (`knowledge-base/plans/2026-03-20-security-web-platform-nonroot-user-plan.md`) specified `useradd --uid 1001 -m soleur` but the actual implementation used `USER node` instead.

3. **No `--no-log-init` flag.** The telegram-bridge `useradd` lacks `--no-log-init`, which can create a large sparse `/var/log/lastlog` file on some base images.

## Proposed Solution

Standardize both Dockerfiles on an explicit `soleur` user with UID 1001 and `--no-log-init`:

```dockerfile
RUN useradd --no-log-init --uid 1001 -m soleur
USER soleur
```

### File changes

#### 1. `apps/telegram-bridge/Dockerfile` (line 21)

**Before:**
```dockerfile
RUN useradd -m soleur
```

**After:**
```dockerfile
RUN useradd --no-log-init --uid 1001 -m soleur
```

No other changes needed -- `USER soleur` and `VOLUME /home/soleur/data` are already correct.

#### 2. `apps/web-platform/Dockerfile` (lines 47-49)

**Before:**
```dockerfile
# Non-root user (node:22-slim includes a 'node' user at uid 1000)
USER node
RUN git config --global user.name "Soleur" && git config --global user.email "soleur@localhost"
```

**After:**
```dockerfile
# Non-root user (UID 1001 avoids collision with node:22-slim's built-in node user at UID 1000)
RUN useradd --no-log-init --uid 1001 -m soleur \
    && chown -R soleur:soleur .next
USER soleur
RUN git config --global user.name "Soleur" && git config --global user.email "soleur@localhost"
```

**Why `chown -R soleur:soleur .next`:** The `.next` directory is created by the build stage and copied as root-owned. The `soleur` user needs write access at runtime. This matches the pattern documented in `knowledge-base/learnings/2026-03-20-docker-nonroot-user-with-volume-mounts.md`.

**Why NOT `chown -R soleur:soleur /app`:** `node_modules` is read-only at runtime; chown-ing 10k+ files wastes build time (per the same learning).

#### 3. No infra changes needed

The `ci-deploy.sh` and `cloud-init.yml` files already use `chown 1001:1001 /mnt/data/workspaces` -- this is correct for UID 1001 and does not need modification. The web-platform fix actually *resolves* the existing UID mismatch between the container user (was 1000) and the volume ownership (1001).

## Acceptance Criteria

- [ ] `apps/telegram-bridge/Dockerfile` uses `useradd --no-log-init --uid 1001 -m soleur` (explicit UID, no-log-init)
- [ ] `apps/web-platform/Dockerfile` creates `soleur` user with `useradd --no-log-init --uid 1001 -m soleur` instead of using the built-in `node` user
- [ ] `apps/web-platform/Dockerfile` has `chown -R soleur:soleur .next` so the non-root user can write to the Next.js build output
- [ ] `apps/web-platform/Dockerfile` uses `USER soleur` instead of `USER node`
- [ ] Both containers report `uid=1001(soleur)` when running `id`
- [ ] Web-platform container can write to `/workspaces` volume mount (UID now matches host ownership)

## Test Scenarios

- Given the telegram-bridge Dockerfile, when `docker build` completes and `docker run --rm <image> id` is executed, then the output shows `uid=1001(soleur) gid=1001(soleur)`
- Given the web-platform Dockerfile, when `docker build` completes and `docker run --rm <image> id` is executed, then the output shows `uid=1001(soleur) gid=1001(soleur)`
- Given the web-platform container with `/workspaces` mounted from a directory owned by `1001:1001`, when the process writes to `/workspaces`, then the write succeeds without permission errors
- Given the web-platform container, when `git config --global user.name` is queried, then it returns "Soleur" (git config still works for the new user)

## Edge Cases

- Given the `oven/bun` base image changes and a user with UID 1001 already exists, when `useradd --uid 1001` runs, then the build fails loudly rather than silently assigning a different UID -- this is correct behavior (explicit UID is deterministic)
- Given the `node:22-slim` base image, when `useradd --uid 1001 -m soleur` runs alongside the existing `node` user (UID 1000), then both users coexist without conflict

## Context

- Identified during code review of #813
- Related learning: `knowledge-base/learnings/2026-03-20-docker-nonroot-user-with-volume-mounts.md`
- Related plan: `knowledge-base/plans/2026-03-20-security-web-platform-nonroot-user-plan.md`
- The web-platform UID mismatch (container running as UID 1000, volume owned by UID 1001) is a pre-existing bug that this change resolves as a side effect

## References

- Issue: #817
- Prior review: #813
- Docker best practice: explicit UID assignment prevents non-deterministic builds
- `--no-log-init`: prevents large sparse `/var/log/lastlog` files (documented in learning above)
