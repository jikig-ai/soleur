#!/usr/bin/env bash
set -euo pipefail

# Required env vars (fail-fast with :? syntax)
IMAGE="${DEPLOY_IMAGE:?Set DEPLOY_IMAGE env var}"
HOST="${DEPLOY_HOST:?Set DEPLOY_HOST env var}"
CONTAINER="${DEPLOY_CONTAINER:-$(basename "$IMAGE")}"
DOCKERFILE="${DEPLOY_DOCKERFILE:-./Dockerfile}"
TAG=$(git rev-parse --short HEAD)

echo "=== Deploying $IMAGE:$TAG to $HOST ==="

# Build and push
echo "Building $IMAGE:$TAG ..."
docker build -f "$DOCKERFILE" -t "$IMAGE:$TAG" -t "$IMAGE:latest" .
echo "Pushing to GHCR ..."
docker push "$IMAGE:$TAG"
docker push "$IMAGE:latest"

# Deploy via SSH: pull new image, stop old container, start new one
echo "Deploying to $HOST ..."
ssh "$HOST" "docker pull $IMAGE:$TAG \
  && { docker stop $CONTAINER 2>/dev/null || true; } \
  && { docker rm $CONTAINER 2>/dev/null || true; } \
  && docker run -d --name $CONTAINER --restart unless-stopped $IMAGE:$TAG"

# Health check (if URL provided)
if [[ -n "${DEPLOY_HEALTH_URL:-}" ]]; then
  echo "Checking health at $DEPLOY_HEALTH_URL ..."
  for i in 1 2 3 4 5; do
    curl -sf --max-time 5 "$DEPLOY_HEALTH_URL" > /dev/null 2>&1 && { echo "Health check passed"; break; }
    [[ $i -eq 5 ]] && { echo "ERROR: Health check failed after 5 attempts" >&2; exit 1; }
    sleep 3
  done
fi

echo "Deployed $TAG to $HOST"
