# Learning: Adding a non-root user to a Node.js Dockerfile with volume mounts

## Problem

The web-platform container ran as root. Switching to a non-root user required coordinated changes across three files: the Dockerfile, the deploy workflow, and the cloud-init provisioning script. The plan identified the Dockerfile change but missed two of the three files and a runtime dependency on git config.

## Solution

### 1. Dockerfile: create user, scope ownership, set git config

- `useradd --no-log-init --uid 1001 -m soleur` -- UID 1001 avoids collision with the base image's `node` user (UID 1000). `--no-log-init` prevents large `/var/log/lastlog` sparse files.
- `chown -R soleur:soleur .next` -- scope to the only directory the process writes to at runtime. Do NOT chown `/app` (10k+ node_modules files slow the build and are read-only at runtime).
- `USER soleur` -- placed after all root-requiring instructions (package install, build).
- `git config --global user.name/email` -- workspace provisioning calls `git commit`, which fails without identity config. Root had implicit config; the new user does not.

### 2. Deploy workflow and cloud-init: non-recursive chown on mount point

- `chown 1001:1001 /mnt/data/workspaces` (no `-R`) -- the process creates child directories with correct ownership automatically. `-R` is a scaling trap as workspace count grows.
- This chown must appear in BOTH the deploy workflow (deploy-time) and cloud-init.yml (first-boot provisioning).

## Key Insight

**Three-file sync rule:** Any Docker USER change requires updating three files in lockstep:

| File | Responsibility |
|---|---|
| Dockerfile | Create user, set UID, chown writable dirs, switch USER |
| Deploy workflow | chown host volume mount points before `docker run` |
| cloud-init.yml | chown host volume mount points at first-boot provisioning |

**Checklist for future non-root migrations:**
- Identify the base image's existing user and UID
- Pick a non-colliding UID
- Audit which directories the process writes to at runtime -- chown only those
- Audit which host volumes are mounted -- add non-recursive chown to deploy AND provisioning scripts
- Audit whether the process calls git, ssh, or other tools that require per-user config

## Session Errors

1. Plan contradicted itself: research section said non-recursive chown, proposed solution used `-R`
2. Plan missed cloud-init.yml needing the same chown as the deploy workflow
3. Plan missed git config requirement for the non-root user's `git commit` calls

## Tags

category: infrastructure
module: web-platform
related: 2026-03-19-docker-base-image-digest-pinning, 2026-03-19-docker-restart-does-not-apply-new-images
