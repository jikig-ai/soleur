---
title: "security: restrict CI deploy SSH key with command= in authorized_keys"
type: feat
date: 2026-03-20
---

# security: restrict CI deploy SSH key with command= in authorized_keys

## Overview

The CI deploy SSH key (`WEB_PLATFORM_SSH_KEY`) currently grants full root shell access to the web-platform Hetzner server. If the GitHub secret is compromised, an attacker gets unrestricted root SSH. This plan restricts the key using OpenSSH's `command=` forced command and `restrict` options so it can only execute a predefined deploy script.

## Problem Statement

The `WEB_PLATFORM_SSH_KEY` secret is a passwordless Ed25519 key (created in #738) used by both `web-platform-release.yml` and `telegram-bridge-release.yml` to SSH into the server as root. The firewall already exposes SSH to `0.0.0.0/0` (required because GitHub Actions runners use dynamic IPs). Combined, these create a high-risk attack surface: a compromised secret yields arbitrary root command execution on the server.

## Proposed Solution

### 1. Create a deploy wrapper script on the server

Place `/usr/local/bin/ci-deploy.sh` on the server. This script is the forced command -- it runs automatically when the CI key authenticates. The script:

- Reads `SSH_ORIGINAL_COMMAND` to determine which component to deploy and what image/tag to use
- Validates the command against an allowlist of operations (deploy web-platform, deploy telegram-bridge)
- Executes only the validated deploy logic
- Rejects all other commands with a logged error

### 2. Update `authorized_keys` with `restrict,command=`

Replace the current unrestricted key entry with:

```
restrict,command="/usr/local/bin/ci-deploy.sh" ssh-ed25519 AAAA... ci-deploy-2026@soleur-web-platform
```

The `restrict` keyword disables all forwarding (port, X11, agent), PTY allocation, and user-rc execution in one directive. This is cleaner and more future-proof than listing individual `no-*` options.

### 3. Update CI workflows to pass structured commands

Modify both `web-platform-release.yml` and `telegram-bridge-release.yml` deploy steps to pass a structured command string that `ci-deploy.sh` can parse from `SSH_ORIGINAL_COMMAND`. Replace the inline multi-line scripts with a single-line deploy command.

## Technical Approach

### How `command=` interacts with `appleboy/ssh-action`

The `appleboy/ssh-action` (via `drone-ssh`) concatenates all script lines with `\n` and sends them as a single SSH exec request. When `command=` is set in `authorized_keys`:

1. The original script is **ignored** by OpenSSH
2. The forced command (`ci-deploy.sh`) runs instead
3. The original script is available in `SSH_ORIGINAL_COMMAND`

This means the CI workflow must encode its intent (which component, what image, what tag) into the `script` field, and `ci-deploy.sh` parses it from `SSH_ORIGINAL_COMMAND`.

### Deploy script design (`ci-deploy.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail

# Parse the structured deploy command from SSH_ORIGINAL_COMMAND
# Expected format: "deploy <component> <image> <tag>"
# Example: "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.2.3"

readonly ALLOWED_COMPONENTS="web-platform telegram-bridge"
readonly LOG_TAG="ci-deploy"

logger -t "$LOG_TAG" "SSH_ORIGINAL_COMMAND: ${SSH_ORIGINAL_COMMAND:-<none>}"

if [[ -z "${SSH_ORIGINAL_COMMAND:-}" ]]; then
  logger -t "$LOG_TAG" "REJECTED: no command provided"
  echo "Error: no command provided" >&2
  exit 1
fi

# Parse command
read -r ACTION COMPONENT IMAGE TAG <<< "$SSH_ORIGINAL_COMMAND"

# Validate action
if [[ "$ACTION" != "deploy" ]]; then
  logger -t "$LOG_TAG" "REJECTED: unknown action '$ACTION'"
  echo "Error: unknown action '$ACTION'" >&2
  exit 1
fi

# Validate component
if [[ ! " $ALLOWED_COMPONENTS " =~ " $COMPONENT " ]]; then
  logger -t "$LOG_TAG" "REJECTED: unknown component '$COMPONENT'"
  echo "Error: unknown component '$COMPONENT'" >&2
  exit 1
fi

# Validate image matches expected pattern
if [[ ! "$IMAGE" =~ ^ghcr\.io/jikig-ai/soleur- ]]; then
  logger -t "$LOG_TAG" "REJECTED: invalid image '$IMAGE'"
  echo "Error: invalid image" >&2
  exit 1
fi

# Validate tag format (vX.Y.Z)
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  logger -t "$LOG_TAG" "REJECTED: invalid tag '$TAG'"
  echo "Error: invalid tag format" >&2
  exit 1
fi

logger -t "$LOG_TAG" "ACCEPTED: deploy $COMPONENT $IMAGE:$TAG"

# Component-specific deploy logic
case "$COMPONENT" in
  web-platform)
    docker pull "$IMAGE:$TAG"
    { docker stop soleur-web-platform || true; }
    { docker rm soleur-web-platform || true; }
    chown 1001:1001 /mnt/data/workspaces
    docker run -d \
      --name soleur-web-platform \
      --restart unless-stopped \
      --env-file /mnt/data/.env \
      -v /mnt/data/workspaces:/workspaces \
      -v /mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro \
      -p 0.0.0.0:80:3000 \
      -p 0.0.0.0:3000:3000 \
      "$IMAGE:$TAG"
    echo "Waiting for health check..."
    for i in $(seq 1 10); do
      if curl -sf http://localhost:3000/health; then
        echo " OK"
        exit 0
      fi
      sleep 3
    done
    echo "Health check failed"
    docker logs soleur-web-platform --tail 30
    exit 1
    ;;
  telegram-bridge)
    docker pull "$IMAGE:$TAG"
    { docker stop soleur-bridge || true; }
    { docker rm soleur-bridge || true; }
    docker run -d \
      --name soleur-bridge \
      --restart unless-stopped \
      --env-file /mnt/data/.env \
      -v /mnt/data:/home/soleur/data \
      -v /mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro \
      -p 127.0.0.1:8080:8080 \
      "$IMAGE:$TAG"
    echo "Waiting for health endpoint..."
    for i in $(seq 1 24); do
      STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health 2>/dev/null) || STATUS="000"
      if [ "$STATUS" = "200" ] || [ "$STATUS" = "503" ]; then
        BODY=$(curl -s http://localhost:8080/health)
        echo "Health endpoint responded: HTTP $STATUS - $BODY"
        exit 0
      fi
      echo "Attempt $i/24: HTTP $STATUS (waiting...)"
      sleep 5
    done
    echo "Health check failed after 120s"
    docker logs soleur-bridge --tail 30
    exit 1
    ;;
esac
```

### CI workflow changes

#### `web-platform-release.yml` deploy step

Replace the current inline script with:

```yaml
- name: Deploy to server
  uses: appleboy/ssh-action@0ff4204d59e8e51228ff73bce53f80d53301dee2 # v1.2.5
  with:
    host: ${{ secrets.WEB_PLATFORM_HOST }}
    username: root
    key: ${{ secrets.WEB_PLATFORM_SSH_KEY }}
    script: deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v${{ needs.release.outputs.version }}
```

#### `telegram-bridge-release.yml` deploy step

The telegram-bridge workflow has two SSH steps: one for env var setup and one for deploy.

The env var setup step (`Ensure telegram env vars on server`) writes to `/mnt/data/.env`. With `command=` restriction, this arbitrary file manipulation is blocked. Two options:

1. **Move env var management out of CI** -- manage `.env` via Terraform `user_data` or manual provisioning (preferred, separates config from deploy)
2. **Add an `env-setup` action** to `ci-deploy.sh` with strict validation

Option 1 is preferred: env vars are secrets that should be provisioned once, not on every deploy. The `Ensure telegram env vars on server` step uses `grep -q` to avoid duplicates, meaning it's already idempotent and only needed for initial setup. After initial provisioning, this step is a no-op.

**Decision:** Remove the env var setup SSH step from the workflow. Document that `.env` management is a one-time manual provisioning step (or future Terraform task).

The deploy step becomes:

```yaml
- name: Deploy to server
  uses: appleboy/ssh-action@0ff4204d59e8e51228ff73bce53f80d53301dee2 # v1.2.5
  with:
    host: ${{ secrets.WEB_PLATFORM_HOST }}
    username: root
    key: ${{ secrets.WEB_PLATFORM_SSH_KEY }}
    script: deploy telegram-bridge ghcr.io/jikig-ai/soleur-telegram-bridge v${{ needs.release.outputs.version }}
```

### Server-side provisioning

The deploy script and `authorized_keys` update must be applied to the running server. Since this is a one-time configuration change on an existing server (not infrastructure provisioning), it requires SSH access:

1. **Create `ci-deploy.sh`** on the server at `/usr/local/bin/ci-deploy.sh`
2. **Set permissions:** `chmod 755 /usr/local/bin/ci-deploy.sh`
3. **Update `/root/.ssh/authorized_keys`** to add `restrict,command=` prefix to the CI key
4. **Test** by running `gh workflow run web-platform-release.yml` with deploy

### Cloud-init update for future reprovisioning

Update `apps/web-platform/infra/cloud-init.yml` to include:

1. A `write_files` entry for `/usr/local/bin/ci-deploy.sh`
2. A `write_files` entry for the restricted `authorized_keys` format (or instructions in comments)

This ensures the restriction is reproduced if the server is rebuilt.

## Alternative Approaches Considered

### 1. ForceCommand in sshd_config (REJECTED)

Using `ForceCommand` in a `Match` block in `sshd_config` would apply to ALL keys, not just the CI key. Since the admin also SSHs as root, this would lock out admin access. Per-key `command=` in `authorized_keys` is the correct approach.

### 2. Separate deploy user (CONSIDERED, DEFERRED)

Creating a non-root `deploy` user with docker group membership would further reduce blast radius. However, `docker` group membership is effectively root-equivalent (container escape). This adds complexity without meaningful security gain for the current setup. Can be revisited when the server runs rootless Docker.

### 3. Watchtower / webhook-based deploy (REJECTED)

Eliminates SSH entirely by having the server pull images automatically. However, this removes CI control over deploy timing, version pinning, and health check verification. The current SSH-based deploy with `command=` restriction provides a good balance.

### 4. Validate SSH_ORIGINAL_COMMAND line-by-line (REJECTED)

Instead of a structured command protocol, validate each line of the original multi-line script against an allowlist. This is fragile -- any change to the CI script syntax breaks validation. The structured `deploy <component> <image> <tag>` protocol is simpler and more maintainable.

## Non-goals

- Restricting the admin SSH key (personal key should remain unrestricted)
- Replacing SSH with a different deploy mechanism
- Implementing rootless Docker
- Automating `.env` management via CI (separate concern)
- Restricting firewall SSH access (covered by #748 host fingerprint pinning and future IP allowlisting)

## Acceptance Criteria

- [ ] CI deploy key in `authorized_keys` has `restrict,command="/usr/local/bin/ci-deploy.sh"` prefix
- [ ] `/usr/local/bin/ci-deploy.sh` exists on server with mode 755
- [ ] `ci-deploy.sh` validates action, component, image pattern, and tag format
- [ ] `ci-deploy.sh` logs all attempts (accepted and rejected) via `logger`
- [ ] `gh workflow run web-platform-release.yml -f bump_type=patch` deploy succeeds
- [ ] `gh workflow run telegram-bridge-release.yml -f bump_type=patch` deploy succeeds
- [ ] Arbitrary commands via the CI key are rejected (tested with `ssh -i <key> root@<host> "whoami"`)
- [ ] `cloud-init.yml` updated with deploy script for future reprovisioning
- [ ] Telegram-bridge env setup step removed from workflow (env managed separately)

## Test Scenarios

- Given the CI key is restricted with `command=`, when `appleboy/ssh-action` sends `deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0`, then the web-platform container is redeployed and health check passes
- Given the CI key is restricted, when `appleboy/ssh-action` sends `deploy telegram-bridge ghcr.io/jikig-ai/soleur-telegram-bridge v1.0.0`, then the telegram-bridge container is redeployed and health check passes
- Given the CI key is restricted, when someone runs `ssh -i <ci-key> root@<host> "whoami"`, then the connection is rejected with "unknown action 'whoami'"
- Given the CI key is restricted, when someone runs `ssh -i <ci-key> root@<host> "deploy web-platform evil-image:latest v1.0.0"`, then the deploy is rejected with "invalid image"
- Given the CI key is restricted, when someone runs `ssh -i <ci-key> root@<host> "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform latest"`, then the deploy is rejected with "invalid tag format"
- Given the CI key is restricted, when an admin SSH key connects (without `command=`), then full shell access is available as before

## Dependencies & Risks

### Dependencies

- SSH access to the web-platform server for provisioning `ci-deploy.sh` and updating `authorized_keys`
- The admin SSH key must NOT have `command=` restriction (only the CI key)
- Both workflows must be updated atomically with the server-side changes to avoid a window where CI deploys fail

### Risks

- **Deployment window**: Between updating `authorized_keys` and deploying the workflow changes, CI deploys will fail because the old inline scripts won't match the forced command. Mitigation: update server-side first, merge workflow changes, verify immediately.
- **Script bugs**: A bug in `ci-deploy.sh` could break all deploys. Mitigation: test with a manual SSH command before merging workflow changes.
- **Telegram env vars**: Removing the env setup step assumes `.env` is already populated. Mitigation: verify `.env` contents on server before removing the step.

## Implementation Phases

### Phase 1: Create deploy script and update cloud-init (repo changes)

- Create `ci-deploy.sh` script content in `apps/web-platform/infra/ci-deploy.sh`
- Update `apps/web-platform/infra/cloud-init.yml` to include the deploy script via `write_files`
- Update `web-platform-release.yml` deploy step to use structured command
- Update `telegram-bridge-release.yml` deploy step to use structured command (remove env setup step)

### Phase 2: Server-side provisioning (manual)

- SSH into server and install `ci-deploy.sh` at `/usr/local/bin/ci-deploy.sh`
- Update `/root/.ssh/authorized_keys` with `restrict,command=` prefix
- Test manually: `ssh -i <ci-key> root@<host> "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"`
- Test rejection: `ssh -i <ci-key> root@<host> "whoami"`

### Phase 3: Verify CI deploy (automated)

- Merge workflow changes
- Run `gh workflow run web-platform-release.yml -f bump_type=patch`
- Verify deploy succeeds and health check passes

## Semver

This is a security hardening change that does not affect the plugin itself. The PR should use `semver:patch` label.

## References

- Issue: #747
- Related: #738 (CI deploy SSH key fix -- created the current passwordless key)
- Related: #748 (pin server host key fingerprint -- complementary hardening)
- Learning: `knowledge-base/learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`
- Learning: `knowledge-base/learnings/2026-03-19-openssh-first-match-wins-drop-in-precedence.md`
- OpenSSH `authorized_keys` man page: `restrict` keyword disables all forwarding, PTY, user-rc in one directive
- `appleboy/ssh-action` uses `drone-ssh` which concatenates script lines with `\n` into a single SSH exec request
- `apps/web-platform/infra/cloud-init.yml` -- current server provisioning
- `.github/workflows/web-platform-release.yml` -- web-platform deploy workflow
- `.github/workflows/telegram-bridge-release.yml` -- telegram-bridge deploy workflow
