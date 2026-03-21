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

# Resolve env file: prefer Doppler secrets download, fall back to /mnt/data/.env.
# Writes secrets to a temp file (chmod 600) that the caller must clean up via cleanup_env_file.
resolve_env_file() {
  if command -v doppler >/dev/null 2>&1 && [[ -n "${DOPPLER_TOKEN:-}" ]]; then
    local tmpenv
    tmpenv=$(mktemp /tmp/doppler-env.XXXXXX)
    chmod 600 "$tmpenv"
    if doppler secrets download --no-file --format docker --project soleur --config prd > "$tmpenv" 2>/dev/null; then
      echo "$tmpenv"
      return 0
    fi
    rm -f "$tmpenv"
    logger -t "$LOG_TAG" "WARNING: Doppler download failed, falling back to /mnt/data/.env"
  fi
  echo "/mnt/data/.env"
}

# Clean up temp env file after container starts (secrets are in container memory).
cleanup_env_file() {
  if [[ "$1" != "/mnt/data/.env" ]]; then
    rm -f "$1"
  fi
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

# Component-specific deploy logic
case "$COMPONENT" in
  web-platform)
    echo "Pruning old Docker images (>48h)..."
    docker system prune -f --filter "until=48h"
    docker pull "$IMAGE:$TAG"
    { docker stop soleur-web-platform || true; }
    { docker rm soleur-web-platform || true; }
    sudo chown 1001:1001 /mnt/data/workspaces
    ENV_FILE=$(resolve_env_file)
    docker run -d \
      --name soleur-web-platform \
      --restart unless-stopped \
      --env-file "$ENV_FILE" \
      -v /mnt/data/workspaces:/workspaces \
      -v /mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro \
      -p 0.0.0.0:80:3000 \
      -p 0.0.0.0:3000:3000 \
      "$IMAGE:$TAG"
    cleanup_env_file "$ENV_FILE"
    echo "Waiting for health check..."
    for i in $(seq 1 10); do
      if curl -sf http://localhost:3000/health; then
        echo " OK"
        exit 0
      fi
      sleep 3
    done
    echo "Health check failed"
    docker logs soleur-web-platform --tail 30 2>&1 | logger -t ci-deploy
    exit 1
    ;;
  telegram-bridge)
    echo "Pruning old Docker images (>48h)..."
    docker system prune -f --filter "until=48h"
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
