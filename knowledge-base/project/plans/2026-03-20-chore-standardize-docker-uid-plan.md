---
title: "chore: standardize soleur UID across all Dockerfiles"
type: fix
date: 2026-03-20
deepened: 2026-03-20
---

# chore: standardize soleur UID across all Dockerfiles

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5 (Problem Statement, Proposed Solution, Edge Cases, Test Scenarios, References)
**Research sources:** Docker official docs, institutional learnings (6 relevant), web research on UID/GID best practices

### Key Improvements

1. Identified a pre-existing UID mismatch bug in web-platform (container runs as UID 1000, volume owned by UID 1001) -- this plan fixes it as a side effect
2. Added `--no-log-init` rationale with upstream bug references (Go sparse file handling, shadow-utils fix timeline)
3. Added GID consistency analysis -- `useradd` auto-creates a matching group, so explicit `groupadd` is unnecessary for this case
4. Expanded edge cases with Renovate digest-pin interaction and telegram-bridge volume ownership considerations
5. Incorporated three institutional learnings: cloud-init chown ordering, Docker nonroot user three-file sync rule, and base image digest pinning interaction

### New Considerations Discovered

- The telegram-bridge deploy script mounts `/mnt/data:/home/soleur/data` -- the host directory `/mnt/data` is owned by `deploy:deploy`, but Docker volume mounts bypass host permissions when the container user has the UID that owns the files inside the mount. Since the container writes to `/home/soleur/data` (mapped to `/mnt/data`), the `deploy` user owns the host directory but the container's `soleur` user (UID 1001) creates files inside it. This works because Docker bind mounts use the container UID for file creation, and the `deploy` user has Docker group access to manage containers. No change needed, but documented for clarity.
- Renovate is configured for Docker digest pinning (`knowledge-base/project/learnings/2026-03-20-renovate-enabled-managers-scoping.md`). If Renovate updates the `oven/bun` base image and the new image includes a user at UID 1001, the build will fail loudly (correct behavior -- the explicit `--uid 1001` acts as a contract).

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

2. **web-platform has a UID mismatch.** The container runs as `node` (UID 1000) but the host volume `/mnt/data/workspaces` is owned by UID 1001. This means the container process cannot write to the volume mount unless Docker's user namespace mapping compensates -- which it does not by default. This was likely introduced when the non-root user plan (`knowledge-base/project/plans/2026-03-20-security-web-platform-nonroot-user-plan.md`) specified `useradd --uid 1001 -m soleur` but the actual implementation used `USER node` instead.

3. **No `--no-log-init` flag.** The telegram-bridge `useradd` lacks `--no-log-init`, which can create a large sparse `/var/log/lastlog` file on some base images. The `lastlog` and `faillog` databases store per-user records indexed by UID offset. Without `--no-log-init`, `useradd` initializes these entries, and Go's archive/tar (used by Docker image layers) does not handle sparse files correctly -- it materializes the sparse regions, potentially inflating the image layer. For UID 1001 the file is small (~12 KB), but the flag is a defensive best practice that prevents surprises if UIDs ever change. See [shadow-utils upstream fix](https://github.com/shadow-maint/shadow/pull/558) and [Docker docs issue #4754](https://github.com/docker/docker.github.io/issues/4754).

4. **GID consistency.** Both base images (`oven/bun`, `node:22-slim`) have their built-in users at GID 1000. When `useradd --uid 1001 -m soleur` runs, it auto-creates group `soleur` with GID 1001 (matching the UID). Explicit `groupadd` is unnecessary because there are no shared group memberships across containers.

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

No other changes needed -- `USER soleur` and `VOLUME /home/soleur/data` are already correct. The `oven/bun:1.3.11` base image has a `bun` user at UID 1000, so UID 1001 is the next available slot and does not conflict.

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

**Why `chown -R soleur:soleur .next`:** The `.next` directory is created by the build stage and copied as root-owned. The `soleur` user needs write access at runtime. This matches the pattern documented in `knowledge-base/project/learnings/2026-03-20-docker-nonroot-user-with-volume-mounts.md`.

**Why NOT `chown -R soleur:soleur /app`:** `node_modules` is read-only at runtime; chown-ing 10k+ files wastes build time (per the same learning).

#### 3. No infra changes needed (three-file sync verification)

Per the three-file sync rule from `knowledge-base/project/learnings/2026-03-20-docker-nonroot-user-with-volume-mounts.md`, any Docker USER change requires verifying three files in lockstep:

| File | UID reference | Status |
|------|--------------|--------|
| `apps/web-platform/Dockerfile` | `useradd --uid 1001` | **CHANGING** (this PR) |
| `apps/web-platform/infra/ci-deploy.sh:76` | `chown 1001:1001 /mnt/data/workspaces` | Already correct |
| `apps/web-platform/infra/cloud-init.yml:118,213` | `sudo chown 1001:1001 /mnt/data/workspaces` | Already correct |
| `apps/web-platform/infra/cloud-init.yml:35` | sudoers rule `1001\:1001` | Already correct |

For telegram-bridge, the same check:

| File | UID reference | Status |
|------|--------------|--------|
| `apps/telegram-bridge/Dockerfile` | `useradd --uid 1001` | **CHANGING** (this PR) |
| `apps/telegram-bridge/infra/ci-deploy.sh:107` | `-v /mnt/data:/home/soleur/data` | No UID-specific reference (mounts as-is) |
| `apps/telegram-bridge/infra/cloud-init.yml:62` | `chown -R deploy:deploy /mnt/data` | Host dir owned by deploy, container writes as UID 1001 -- works because Docker bind mounts use container UID for file creation |

The web-platform fix actually *resolves* the existing UID mismatch between the container user (was UID 1000 via `USER node`) and the volume ownership (UID 1001 in infra scripts).

## Acceptance Criteria

- [x] `apps/telegram-bridge/Dockerfile` uses `useradd --no-log-init --uid 1001 -m soleur` (explicit UID, no-log-init)
- [x] `apps/web-platform/Dockerfile` creates `soleur` user with `useradd --no-log-init --uid 1001 -m soleur` instead of using the built-in `node` user
- [x] `apps/web-platform/Dockerfile` has `chown -R soleur:soleur .next` so the non-root user can write to the Next.js build output
- [x] `apps/web-platform/Dockerfile` uses `USER soleur` instead of `USER node`
- [x] Both containers report `uid=1001(soleur)` when running `id`
- [x] Web-platform container can write to `/workspaces` volume mount (UID now matches host ownership)

## Test Scenarios

### UID verification

- Given the telegram-bridge Dockerfile, when `docker build` completes and `docker run --rm <image> id` is executed, then the output shows `uid=1001(soleur) gid=1001(soleur) groups=1001(soleur)`
- Given the web-platform Dockerfile, when `docker build` completes and `docker run --rm <image> id` is executed, then the output shows `uid=1001(soleur) gid=1001(soleur) groups=1001(soleur)`

### Volume mount permissions

- Given the web-platform container with `/workspaces` mounted from a directory owned by `1001:1001`, when the process writes to `/workspaces`, then the write succeeds without permission errors
- Given the web-platform container, when `docker run --rm -v /tmp/test-workspaces:/workspaces <image> touch /workspaces/test-file` is executed (after `chown 1001:1001 /tmp/test-workspaces`), then the file is created successfully

### Application functionality

- Given the web-platform container, when `git config --global user.name` is queried, then it returns "Soleur" (git config still works for the new user -- the home directory moved from `/home/node` to `/home/soleur`)
- Given the web-platform container, when `git config --global user.email` is queried, then it returns "soleur@localhost"

### Regression: no lastlog sparse file

- Given either Dockerfile, when `docker build` completes and the image layers are inspected, then `/var/log/lastlog` is either absent or zero-size (the `--no-log-init` flag prevents sparse file creation)

### Regression: .next directory writable

- Given the web-platform container, when `docker run --rm <image> ls -la .next/` is executed, then the `.next` directory is owned by `soleur:soleur` (not `root:root`)

## Edge Cases

- Given the `oven/bun` base image changes and a user with UID 1001 already exists, when `useradd --uid 1001` runs, then the build fails loudly (`useradd: UID 1001 is not unique`) rather than silently assigning a different UID -- this is correct behavior and acts as a contract that prevents silent UID drift
- Given the `node:22-slim` base image, when `useradd --uid 1001 -m soleur` runs alongside the existing `node` user (UID 1000), then both users coexist without conflict
- Given Renovate updates the `oven/bun` or `node:22-slim` digest pin (per `knowledge-base/project/learnings/2026-03-19-docker-base-image-digest-pinning.md`), when the new base image includes changes to `/etc/passwd`, then the explicit `--uid 1001` ensures the `soleur` user UID is unchanged regardless of base image user additions
- Given the telegram-bridge container mounts `/mnt/data:/home/soleur/data` where `/mnt/data` is owned by `deploy:deploy` on the host, when the `soleur` user (UID 1001) writes files inside the mount, then Docker uses the container UID (1001) for file creation -- the `deploy` user still manages the top-level directory while container-created files are owned by UID 1001 on the host
- Given both containers run on the same host and a future requirement introduces shared volume mounts between them, when both processes write to the shared volume, then both produce files owned by UID 1001 -- no permission conflicts because the UIDs match

## Context

- Identified during code review of #813
- Related learning: `knowledge-base/project/learnings/2026-03-20-docker-nonroot-user-with-volume-mounts.md`
- Related plan: `knowledge-base/project/plans/2026-03-20-security-web-platform-nonroot-user-plan.md`
- The web-platform UID mismatch (container running as UID 1000, volume owned by UID 1001) is a pre-existing bug that this change resolves as a side effect

## References

### Issue and PR context

- Issue: #817
- Prior review: #813
- Related non-root user plan: `knowledge-base/project/plans/2026-03-20-security-web-platform-nonroot-user-plan.md`

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-03-20-docker-nonroot-user-with-volume-mounts.md` -- three-file sync rule (Dockerfile, deploy workflow, cloud-init), scoped chown pattern
- `knowledge-base/project/learnings/2026-03-20-cloud-init-chown-ordering-recursive-before-specific.md` -- broadest-to-narrowest chown ordering (already correct in web-platform cloud-init)
- `knowledge-base/project/learnings/2026-03-19-docker-base-image-digest-pinning.md` -- digest pins ensure base image UID stability; Renovate manages pin updates
- `knowledge-base/project/learnings/2026-03-20-multistage-docker-build-esbuild-server-compilation.md` -- diff against origin/main to catch dropped security hardening
- `knowledge-base/project/learnings/2026-03-20-node-slim-missing-curl-healthcheck.md` -- web-platform healthcheck uses `node -e fetch()`, unaffected by user change
- `knowledge-base/project/learnings/2026-03-20-dockerignore-nextjs-vs-bun-patterns.md` -- runtime-specific differences between apps

### External references

- [Docker: Understanding the USER Instruction](https://www.docker.com/blog/understanding-the-docker-user-instruction/) -- explicit UID assignment prevents non-deterministic builds
- [shadow-utils: Do not reset non-existent data in lastlog/faillog](https://github.com/shadow-maint/shadow/pull/558) -- upstream fix for the `--no-log-init` issue
- [Docker docs issue #4754: --no-log-init best practice](https://github.com/docker/docker.github.io/issues/4754) -- community discussion on sparse file issue
- [Nick Janetakis: Running Docker Containers as a Non-root User](https://nickjanetakis.com/blog/running-docker-containers-as-a-non-root-user-with-a-custom-uid-and-gid) -- UID/GID matching pattern
- [Baeldung: Docker Shared Volumes Permissions](https://www.baeldung.com/ops/docker-shared-volumes-permissions) -- volume ownership strategies
