#!/usr/bin/env bash
set -euo pipefail

IMAGE="ghcr.io/Jikigai/soleur-telegram-bridge"
TAG=$(git rev-parse --short HEAD)
HOST="${BRIDGE_HOST:?Set BRIDGE_HOST env var}"

echo "Building $IMAGE:$TAG ..."
docker build -t "$IMAGE:$TAG" -t "$IMAGE:latest" .

echo "Pushing to GHCR ..."
docker push "$IMAGE:$TAG"
docker push "$IMAGE:latest"

echo "Deploying to $HOST ..."
ssh "root@$HOST" "docker pull $IMAGE:latest && docker restart soleur-bridge"

echo "Deployed $TAG to $HOST"
