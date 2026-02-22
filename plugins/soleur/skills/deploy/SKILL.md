---
name: deploy
description: "This skill should be used when deploying containerized applications to remote servers. It builds Docker images, pushes to GHCR, and deploys via SSH with health verification. Triggers on \"deploy\", \"deploy to production\", \"push to server\", \"ship to remote\"."
---

# Deploy Skill

Deploy a containerized application to a remote server via Docker and SSH.

## Environment Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `DEPLOY_HOST` | Yes | SSH target (user@host) | `root@203.0.113.10` |
| `DEPLOY_IMAGE` | Yes | GHCR image path | `ghcr.io/org/app` |
| `DEPLOY_HEALTH_URL` | No | Health check endpoint | `http://203.0.113.10:3000/health` |
| `DEPLOY_CONTAINER` | No | Container name (default: image basename) | `myapp` |
| `DEPLOY_DOCKERFILE` | No | Dockerfile path (default: `./Dockerfile`) | `./docker/Dockerfile.prod` |

For first-time server setup, see [hetzner-setup.md](./references/hetzner-setup.md).

## Phase 0: Validate

Check prerequisites before starting the build.

Run these checks as separate Bash commands:

1. Verify `DEPLOY_HOST` is set: `printenv DEPLOY_HOST` (must produce output)
2. Verify `DEPLOY_IMAGE` is set: `printenv DEPLOY_IMAGE` (must produce output)
3. Verify Docker daemon: `docker info > /dev/null 2>&1`
4. Verify SSH connectivity: `ssh -o ConnectTimeout=5 -o BatchMode=yes <deploy-host> "echo OK"` (replace `<deploy-host>` with the actual DEPLOY_HOST value)
5. Verify Dockerfile exists: `test -f ./Dockerfile` (or the DEPLOY_DOCKERFILE path if set)

If any check fails, stop and report the error. Do not proceed to Phase 1.

## Phase 1: Plan

Show the deployment summary and ask for confirmation.

Use the **AskUserQuestion tool** to present:

**Question:** "Deploy this configuration?"

**Options:**
1. **Deploy** -- Proceed with build and deployment
2. **Cancel** -- Abort deployment

Display before asking:

```text
Deployment Plan
  Image:      <DEPLOY_IMAGE>:<git-short-sha>
  Target:     <DEPLOY_HOST>
  Container:  <DEPLOY_CONTAINER or image basename>
  Dockerfile: <DEPLOY_DOCKERFILE or ./Dockerfile>
  Health URL: <DEPLOY_HEALTH_URL or none>
```

Resolve `<git-short-sha>` by running `git rev-parse --short HEAD`.

If the user selects Cancel, stop execution.

## Phase 2: Execute

Run [deploy.sh](./scripts/deploy.sh) to build, push, and deploy:

```bash
bash ./plugins/soleur/skills/deploy/scripts/deploy.sh
```

The script handles:
1. Build Docker image tagged with git SHA and `:latest`
2. Push both tags to GHCR
3. SSH to remote host: pull image, stop old container, start new container

## Phase 3: Verify

After deployment completes, verify the service is running.

**If `DEPLOY_HEALTH_URL` is set:**

The deploy script runs a health check (5 attempts, 3s apart).

If the health check fails:

```text
Health check failed. Debug with:
  ssh <DEPLOY_HOST> "docker logs <container-name> --tail 50"
```

**If `DEPLOY_HEALTH_URL` is not set:**

Report deployment as complete without health verification:

```text
Deployed <git-short-sha> to <DEPLOY_HOST>
No health URL configured -- skipping verification.
```

## Important Rules

- Never hardcode secrets in the deploy script. Use environment variables.
- Never deploy without user confirmation (Phase 1 gate).
- The script uses `set -euo pipefail` -- any command failure aborts the deployment.
- Container restart uses stop+pull+start, not `docker restart`, to ensure the new image is used.
