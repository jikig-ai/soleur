---
title: "feat: Deploy skill (/soleur:deploy) for container deployment"
type: feat
date: 2026-02-13
issue: "#40"
version-bump: MINOR
---

# Deploy Skill (/soleur:deploy)

Promote the existing `deploy.sh` from `apps/telegram-bridge/scripts/` to a first-class Soleur skill at `plugins/soleur/skills/deploy/`.

## Enhancement Summary

**Deepened on:** 2026-02-13
**Sections enhanced:** 4 (SKILL.md structure, deploy.sh patterns, hetzner-setup, test scenarios)
**Research agents used:** skill-structure-patterns, learnings-researcher, docker-deploy-best-practices

### Key Improvements
1. Concrete SKILL.md template with exact YAML frontmatter and phase structure from existing skill patterns
2. Deploy script enhanced with preflight SSH check, stop+pull+start pattern (not restart), and exponential backoff health checks
3. Security hardening: env var validation with `:?` syntax, secrets via stdin not arguments
4. Added Dockerfile requirement and `DEPLOY_DOCKERFILE` optional env var

### Learnings Applied
- Use markdown links for file references, not backticks (backtick-references learning)
- Skills are agent-discoverable; commands are not (command-vs-skill learning)
- Always update versioning triad together (plugin-versioning learning)
- Separate infrastructure setup from runtime scripts (cloud-deploy learning)

## Problem Statement

The deploy script works but is buried in an app-specific directory. Promoting it to a skill makes it agent-discoverable and reusable across projects.

## Non-Goals

- Terraform integration (v2+)
- Rolling updates or rollback automation (v2+)
- Multi-environment support (staging/production) (v2+)
- CI/CD pipeline deployment (belongs in GitHub Actions per constitution)
- Docker Compose or orchestration frameworks

## Proposed Solution

Create a skill with three files that wraps the existing script with validation, confirmation, and health checking.

## Files to Create

### 1. `plugins/soleur/skills/deploy/SKILL.md`

```yaml
---
name: deploy
description: "This skill should be used when deploying containerized applications to remote servers. It builds Docker images, pushes to GHCR, and deploys via SSH with health verification. Triggers on \"deploy\", \"deploy to production\", \"push to server\", \"ship to remote\"."
---
```

Four-phase workflow following existing skill patterns (Phase N format from ship skill):

**Phase 0 - Validate:**
- Check required env vars with `:?` fail-fast syntax: `DEPLOY_HOST`, `DEPLOY_IMAGE`
- Check Docker daemon: `docker info > /dev/null 2>&1`
- Test SSH connectivity: `ssh -o ConnectTimeout=5 -o BatchMode=yes "$DEPLOY_HOST" "echo OK"`
- Check git state: warn on uncommitted changes (`git status --porcelain`)
- Check Dockerfile exists (default: `./Dockerfile`, override with `DEPLOY_DOCKERFILE`)

**Phase 1 - Plan:**
- Show deployment summary using AskUserQuestion:
  - Image: `$DEPLOY_IMAGE:$(git rev-parse --short HEAD)`
  - Target: `$DEPLOY_HOST`
  - Container: `$DEPLOY_CONTAINER`
  - Health URL: `$DEPLOY_HEALTH_URL` (if set)
- Ask for confirmation before proceeding

**Phase 2 - Execute:**
- Run [deploy.sh](./scripts/deploy.sh) via `bash ${CLAUDE_PLUGIN_ROOT}/skills/deploy/scripts/deploy.sh`
- Script handles: build, tag, push, SSH deploy

**Phase 3 - Verify:**
- If `DEPLOY_HEALTH_URL` is set: curl with exponential backoff (1s, 2s, 4s, 8s, cap 10s), max 10 attempts
- If not set: report success without health check
- On failure: show SSH command to check remote container logs

Environment variables documented in SKILL.md:

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `DEPLOY_HOST` | Yes | SSH target (user@host) | `root@203.0.113.10` |
| `DEPLOY_IMAGE` | Yes | GHCR image path | `ghcr.io/org/app` |
| `DEPLOY_HEALTH_URL` | No | Health check endpoint | `http://203.0.113.10:3000/health` |
| `DEPLOY_CONTAINER` | No | Container name (default: image basename) | `myapp` |
| `DEPLOY_DOCKERFILE` | No | Dockerfile path (default: `./Dockerfile`) | `./docker/Dockerfile.prod` |

Link to first-time setup: [hetzner-setup.md](./references/hetzner-setup.md)

### 2. `plugins/soleur/skills/deploy/scripts/deploy.sh`

Adapted from `apps/telegram-bridge/scripts/deploy.sh`. Key changes from research:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Required env vars (fail-fast with :? syntax)
IMAGE="${DEPLOY_IMAGE:?Set DEPLOY_IMAGE env var}"
HOST="${DEPLOY_HOST:?Set DEPLOY_HOST env var}"
CONTAINER="${DEPLOY_CONTAINER:-$(basename "$IMAGE")}"
DOCKERFILE="${DEPLOY_DOCKERFILE:-./Dockerfile}"
TAG=$(git rev-parse --short HEAD)

# Preflight
docker info > /dev/null 2>&1 || { echo "ERROR: Docker daemon not running" >&2; exit 1; }
ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST" "echo OK" > /dev/null 2>&1 \
  || { echo "ERROR: SSH to $HOST failed" >&2; exit 1; }

echo "=== Deploying $IMAGE:$TAG to $HOST ==="

# Build and push
echo "Building $IMAGE:$TAG ..."
docker build -f "$DOCKERFILE" -t "$IMAGE:$TAG" -t "$IMAGE:latest" .
echo "Pushing to GHCR ..."
docker push "$IMAGE:$TAG"
docker push "$IMAGE:latest"

# Deploy via SSH: pull new image, stop old container, start new one
echo "Deploying to $HOST ..."
ssh "$HOST" "docker pull $IMAGE:$TAG && docker stop $CONTAINER 2>/dev/null || true && docker rm $CONTAINER 2>/dev/null || true && docker run -d --name $CONTAINER --restart unless-stopped $IMAGE:$TAG"

# Health check (if URL provided)
if [[ -n "${DEPLOY_HEALTH_URL:-}" ]]; then
  echo "Running health check at $DEPLOY_HEALTH_URL ..."
  WAIT=1
  for i in $(seq 1 10); do
    if curl -sf --max-time 5 "$DEPLOY_HEALTH_URL" > /dev/null 2>&1; then
      echo "Health check passed (attempt $i)"
      break
    fi
    echo "  Attempt $i/10: waiting ${WAIT}s..."
    sleep "$WAIT"
    WAIT=$((WAIT < 10 ? WAIT * 2 : 10))
    if [[ $i -eq 10 ]]; then
      echo "ERROR: Health check failed after 10 attempts" >&2
      exit 1
    fi
  done
fi

echo "Deployed $TAG to $HOST"
```

Key improvements over original:
- **Preflight checks**: Docker daemon and SSH connectivity validated before building
- **Configurable Dockerfile path**: Supports non-standard Dockerfile locations
- **Stop+pull+start pattern**: Instead of `docker restart` which doesn't pull new images
- **Health check with exponential backoff**: Avoids log spam, handles slow startups
- **Container name configurable**: Not hardcoded to `soleur-bridge`
- Under 45 lines -- stays within the 50-line target

### 3. `plugins/soleur/skills/deploy/references/hetzner-setup.md`

First-time setup guide covering:

1. **Hetzner VM provisioning** -- minimal instance type recommendation, OS (Ubuntu 22.04+)
2. **Docker installation** -- `apt install docker.io` or official Docker repo
3. **GHCR authentication on VM** -- `echo $GHCR_TOKEN | docker login ghcr.io -u USERNAME --password-stdin` (pipe to stdin, not argument)
4. **SSH key setup** -- `ssh-keygen` + `ssh-copy-id`, `chmod 600` on key files, test with `ssh -o BatchMode=yes`
5. **Firewall rules** -- `ufw allow 22/tcp && ufw allow <app-port>/tcp && ufw enable`
6. **Volume mounting** -- Use `mount || true` (idempotent), not `mkfs.ext4 -F` (destructive) per cloud-deploy learning
7. **Health endpoint** -- Recommend adding `/health` endpoint to application for monitoring

## Files to Modify

### 4. `plugins/soleur/.claude-plugin/plugin.json`

Bump version: `2.3.1` -> `2.4.0` (MINOR -- new skill)

### 5. `plugins/soleur/CHANGELOG.md`

Add entry for v2.4.0:
- `feat: add deploy skill (/soleur:deploy) for container deployment (closes #40)`

### 6. `plugins/soleur/README.md`

- Update skill count (36 -> 37)
- Add `deploy` to skills table with description

### 7. Root `README.md`

Update version badge from 2.3.1 to 2.4.0

### 8. `.github/ISSUE_TEMPLATE/bug_report.yml`

Update version placeholder from 2.3.1 to 2.4.0

## Acceptance Criteria

- [ ] `/soleur:deploy` is discoverable by agents (appears in skill list)
- [ ] Running the skill validates required env vars before building
- [ ] Running the skill shows a confirmation prompt before deploying
- [ ] `deploy.sh` builds, tags (SHA + latest), pushes, and SSH-deploys using stop+pull+start
- [ ] Health check runs after deploy when `DEPLOY_HEALTH_URL` is set (exponential backoff)
- [ ] Versioning triad updated (plugin.json, CHANGELOG.md, README.md)
- [ ] References in SKILL.md use markdown links, not backticks
- [ ] `deploy.sh` is executable (`chmod +x`)

## Test Scenarios

- Given DEPLOY_HOST is not set, when /soleur:deploy runs, then it fails immediately with "Set DEPLOY_HOST env var"
- Given DEPLOY_IMAGE is not set, when /soleur:deploy runs, then it fails immediately with "Set DEPLOY_IMAGE env var"
- Given Docker daemon is not running, when /soleur:deploy runs, then it fails with "Docker daemon not running"
- Given SSH connection to DEPLOY_HOST fails, when /soleur:deploy runs, then it fails with "SSH to $HOST failed"
- Given valid env vars and Docker running, when /soleur:deploy runs, then it shows deployment plan and asks for confirmation
- Given user confirms deployment, when deploy.sh executes, then Docker image is built, tagged, pushed to GHCR, old container stopped, new container started
- Given DEPLOY_HEALTH_URL is set, when deploy completes, then health check runs with exponential backoff and reports result
- Given DEPLOY_HEALTH_URL is not set, when deploy completes, then skill reports success without health check
- Given uncommitted git changes exist, when /soleur:deploy runs, then it warns but allows proceeding
- Given DEPLOY_CONTAINER is not set, when deploy runs, then container name defaults to image basename

## References

- Source script: `apps/telegram-bridge/scripts/deploy.sh`
- Issue: #40
- Parent issue: #28 (Cloud Deploy)
- Learning: `knowledge-base/learnings/integration-issues/2026-02-10-cloud-deploy-infra-and-sdk-integration.md`
- Learning: `knowledge-base/learnings/2026-02-12-command-vs-skill-selection-criteria.md`
- Learning: `knowledge-base/learnings/technical-debt/2026-02-12-backtick-references-in-skills.md`
- Learning: `knowledge-base/learnings/plugin-versioning-requirements.md`
