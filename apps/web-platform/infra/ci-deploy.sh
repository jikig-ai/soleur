#!/usr/bin/env bash
set -euo pipefail

# Deploy script invoked by the webhook listener (adnanh/webhook).
# The webhook sets SSH_ORIGINAL_COMMAND from the JSON payload's "command" field.
# Parses it for structured "deploy <component> <image> <tag>" format.

readonly LOG_TAG="ci-deploy"

# Structured error output: on failure, emit the failing line number and exit code.
# In async mode (include-command-output-in-response: false), stderr goes to syslog
# via journalctl -u webhook, not the HTTP response.
trap 'echo "DEPLOY_ERROR: ci-deploy.sh failed at line $LINENO (exit $?)" >&2' ERR

# Resolve env file: download secrets from Doppler to a temp file (chmod 600).
# Caller must clean up via cleanup_env_file. Exits on any failure -- no fallback.
resolve_env_file() {
  if ! command -v doppler >/dev/null 2>&1; then
    logger -t "$LOG_TAG" "FATAL: Doppler CLI not installed"
    echo "Error: Doppler CLI not installed on this server" >&2
    exit 1
  fi

  if [[ -z "${DOPPLER_TOKEN:-}" ]]; then
    logger -t "$LOG_TAG" "FATAL: DOPPLER_TOKEN not set"
    echo "Error: DOPPLER_TOKEN environment variable not set" >&2
    exit 1
  fi

  local tmpenv
  tmpenv=$(mktemp /tmp/doppler-env.XXXXXX)
  chmod 600 "$tmpenv"
  if doppler secrets download --no-file --format docker --project soleur --config prd > "$tmpenv" 2>/dev/null; then
    echo "$tmpenv"
    return 0
  fi

  rm -f "$tmpenv"
  logger -t "$LOG_TAG" "FATAL: Doppler secrets download failed"
  echo "Error: Failed to download secrets from Doppler" >&2
  exit 1
}

# Clean up temp env file after container starts (secrets are in container memory).
cleanup_env_file() {
  rm -f "$1"
}

# Exact allowlist of valid images per component (not prefix match -- prevents suffix injection).
declare -A ALLOWED_IMAGES=(
  [web-platform]="ghcr.io/jikig-ai/soleur-web-platform"
  [telegram-bridge]="ghcr.io/jikig-ai/soleur-telegram-bridge"
)

# Log truncated command to avoid persisting attacker payloads to syslog
logger -t "$LOG_TAG" "SSH_ORIGINAL_COMMAND: ${SSH_ORIGINAL_COMMAND:0:200}"

if [[ -z "${SSH_ORIGINAL_COMMAND:-}" ]]; then
  logger -t "$LOG_TAG" "REJECTED: no command provided"
  echo "Error: no command provided" >&2
  exit 1
fi

# Validate field count (exactly 4 fields expected: deploy <component> <image> <tag>)
field_count=$(printf '%s\n' "$SSH_ORIGINAL_COMMAND" | wc -w)
if [[ "$field_count" -ne 4 ]]; then
  logger -t "$LOG_TAG" "REJECTED: expected 4 fields, got $field_count"
  echo "Error: malformed command (expected 4 fields, got $field_count)" >&2
  exit 1
fi

# Parse command -- read -r prevents backslash interpretation in untrusted input
read -r ACTION COMPONENT IMAGE TAG <<< "$SSH_ORIGINAL_COMMAND"

# Validate action
if [[ "$ACTION" != "deploy" ]]; then
  logger -t "$LOG_TAG" "REJECTED: unknown action '$ACTION'"
  echo "Error: unknown action '$ACTION'" >&2
  exit 1
fi

# Validate component exists in allowlist
if [[ -z "${ALLOWED_IMAGES[$COMPONENT]+x}" ]]; then
  logger -t "$LOG_TAG" "REJECTED: unknown component '$COMPONENT'"
  echo "Error: unknown component '$COMPONENT'" >&2
  exit 1
fi

# Validate image matches exact expected value for this component
if [[ "$IMAGE" != "${ALLOWED_IMAGES[$COMPONENT]}" ]]; then
  logger -t "$LOG_TAG" "REJECTED: invalid image '$IMAGE' for component '$COMPONENT'"
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

# Serialize concurrent deploys (webhook may invoke ci-deploy.sh simultaneously).
# CI_DEPLOY_LOCK is overridable for testing; production uses /var/lock/ci-deploy.lock.
LOCK_FILE="${CI_DEPLOY_LOCK:-/var/lock/ci-deploy.lock}"
exec 200>"$LOCK_FILE"
flock -n 200 || { logger -t "$LOG_TAG" "REJECTED: another deploy in progress"; echo "Error: another deploy in progress" >&2; exit 1; }

# Check available disk space (minimum 5GB required for image pull + extraction)
AVAIL_KB=$(df --output=avail / | tail -1 | tr -d ' ')
if [[ "$AVAIL_KB" -lt 5242880 ]]; then
  logger -t "$LOG_TAG" "REJECTED: insufficient disk space (${AVAIL_KB}KB available, 5GB required)"
  echo "Error: insufficient disk space for deploy" >&2
  exit 1
fi

# Component-specific deploy logic
case "$COMPONENT" in
  web-platform)
    echo "Pruning unused Docker images..."
    docker image prune -af
    docker pull "$IMAGE:$TAG"

    # Clean stale canary from previous failed deploy
    { docker stop soleur-web-platform-canary 2>/dev/null || true; }
    { docker rm soleur-web-platform-canary 2>/dev/null || true; }

    # Prepare environment (shared between canary and production)
    sudo chown 1001:1001 /mnt/data/workspaces
    ENV_FILE=$(resolve_env_file)

    # Start canary on port 3001 (old container still serving on 80/3000)
    # AppArmor unconfined: Ubuntu 24.04 docker-default profile blocks mount()
    # inside user namespaces, which bwrap needs for OS-level sandbox (#1557).
    docker run -d \
      --name soleur-web-platform-canary \
      --restart no \
      --security-opt apparmor=unconfined \
      --env-file "$ENV_FILE" \
      -v /mnt/data/workspaces:/workspaces \
      -v /mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro \
      -p 0.0.0.0:3001:3000 \
      "$IMAGE:$TAG"

    # Health-check canary
    echo "Waiting for canary health check..."
    CANARY_HEALTHY=false
    for i in $(seq 1 10); do
      if curl -sf http://localhost:3001/health; then
        CANARY_HEALTHY=true
        echo " Canary OK"
        break
      fi
      sleep 3
    done

    # Verify bwrap sandbox works inside canary (#1557).
    # If bwrap fails, the OS-level sandbox (Layer 1) is non-functional.
    if [[ "$CANARY_HEALTHY" == "true" ]]; then
      echo "Verifying bwrap sandbox..."
      if ! docker exec soleur-web-platform-canary bwrap --new-session --die-with-parent --dev /dev --unshare-pid --bind / / -- true 2>&1; then
        echo "Canary sandbox check failed, rolling back..."
        logger -t "$LOG_TAG" "DEPLOY_ROLLBACK: bwrap sandbox non-functional in $IMAGE:$TAG"
        { docker stop soleur-web-platform-canary 2>/dev/null || true; }
        { docker rm soleur-web-platform-canary 2>/dev/null || true; }
        cleanup_env_file "$ENV_FILE"
        exit 1
      fi
      echo "Sandbox OK"
    fi

    if [[ "$CANARY_HEALTHY" == "true" ]]; then
      # SUCCESS: swap canary to production
      echo "Canary passed, swapping to production..."
      { docker stop soleur-web-platform 2>/dev/null || true; }
      { docker rm soleur-web-platform 2>/dev/null || true; }

      if docker run -d \
        --name soleur-web-platform \
        --restart unless-stopped \
        --security-opt apparmor=unconfined \
        --env-file "$ENV_FILE" \
        -v /mnt/data/workspaces:/workspaces \
        -v /mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro \
        -p 0.0.0.0:80:3000 \
        -p 0.0.0.0:3000:3000 \
        "$IMAGE:$TAG"; then
        { docker stop soleur-web-platform-canary 2>/dev/null || true; }
        { docker rm soleur-web-platform-canary 2>/dev/null || true; }
        cleanup_env_file "$ENV_FILE"
        echo "Deploy succeeded"
        exit 0
      else
        # Production start failed after canary success (infra issue, not app)
        logger -t "$LOG_TAG" "DEPLOY_ERROR: production container failed to start after canary passed"
        { docker stop soleur-web-platform-canary 2>/dev/null || true; }
        { docker rm soleur-web-platform-canary 2>/dev/null || true; }
        cleanup_env_file "$ENV_FILE"
        exit 1
      fi
    else
      # ROLLBACK: canary failed, keep old container running
      echo "Canary health check failed, rolling back..."
      { docker logs soleur-web-platform-canary --tail 30 2>&1 || true; } | logger -t "$LOG_TAG"
      { docker stop soleur-web-platform-canary 2>/dev/null || true; }
      { docker rm soleur-web-platform-canary 2>/dev/null || true; }
      cleanup_env_file "$ENV_FILE"
      logger -t "$LOG_TAG" "DEPLOY_ROLLBACK: canary failed for $IMAGE:$TAG, keeping previous version"
      exit 1
    fi
    ;;
  telegram-bridge)
    echo "Pruning unused Docker images..."
    docker image prune -af
    docker pull "$IMAGE:$TAG"
    { docker stop soleur-bridge || true; }
    { docker rm soleur-bridge || true; }
    ENV_FILE=$(resolve_env_file)
    docker run -d \
      --name soleur-bridge \
      --restart unless-stopped \
      --env-file "$ENV_FILE" \
      -v /mnt/data:/home/soleur/data \
      -v /mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro \
      -p 127.0.0.1:8080:8080 \
      "$IMAGE:$TAG"
    cleanup_env_file "$ENV_FILE"
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
    docker logs soleur-bridge --tail 30 2>&1 | logger -t ci-deploy
    exit 1
    ;;
  *)
    logger -t "$LOG_TAG" "ERROR: no deploy handler for '$COMPONENT'"
    echo "Error: no deploy handler for '$COMPONENT'" >&2
    exit 1
    ;;
esac
