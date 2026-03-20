#!/usr/bin/env bash
set -euo pipefail

# Forced command script for the CI deploy SSH key.
# Runs automatically when the CI key authenticates (via command= in authorized_keys).
# Parses SSH_ORIGINAL_COMMAND for structured "deploy <component> <image> <tag>" format.
#
# IMPORTANT: Do not add 'envs' input to appleboy/ssh-action steps that use this key.
# drone-ssh prepends 'export VAR=value' lines to SSH_ORIGINAL_COMMAND which would
# break the 'read -r' parsing below.

readonly LOG_TAG="ci-deploy"

# Exact allowlist of valid images per component (not prefix match -- prevents suffix injection).
declare -A ALLOWED_IMAGES=(
  [web-platform]="ghcr.io/jikig-ai/soleur-web-platform"
  [telegram-bridge]="ghcr.io/jikig-ai/soleur-telegram-bridge"
)

logger -t "$LOG_TAG" "SSH_ORIGINAL_COMMAND: ${SSH_ORIGINAL_COMMAND:-<none>}"

if [[ -z "${SSH_ORIGINAL_COMMAND:-}" ]]; then
  logger -t "$LOG_TAG" "REJECTED: no command provided"
  echo "Error: no command provided" >&2
  exit 1
fi

# Validate field count (exactly 4 fields expected: deploy <component> <image> <tag>)
field_count=$(echo "$SSH_ORIGINAL_COMMAND" | wc -w)
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
