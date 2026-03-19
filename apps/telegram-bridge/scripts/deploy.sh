#!/usr/bin/env bash
set -euo pipefail

IMAGE="ghcr.io/jikig-ai/soleur-telegram-bridge"
TAG=$(git rev-parse --short HEAD)
HOST="${BRIDGE_HOST:?Set BRIDGE_HOST env var}"

echo "Building $IMAGE:$TAG ..."
docker build -t "$IMAGE:$TAG" -t "$IMAGE:latest" .

echo "Pushing to GHCR ..."
docker push "$IMAGE:$TAG"
docker push "$IMAGE:latest"

echo "Deploying to $HOST ..."
ssh "root@$HOST" "docker pull $IMAGE:latest && { docker stop soleur-bridge || true; } && { docker rm soleur-bridge || true; } && docker run -d --name soleur-bridge --restart unless-stopped --env-file /mnt/data/.env -v /mnt/data:/home/soleur/data -p 127.0.0.1:8080:8080 $IMAGE:latest"

echo "Deployed $TAG to $HOST"
