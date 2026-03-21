# Learning: docker restart does NOT apply newly pulled images

## Problem

The telegram-bridge deploy script (`apps/telegram-bridge/scripts/deploy.sh:16`) used:

```bash
docker pull $IMAGE:latest && docker restart soleur-bridge
```

After `docker pull` downloads a new `:latest` image, `docker restart` restarts the **existing container** with its **existing image**. The newly pulled image is never used. The deploy appears to succeed (restart returns 0) but the container silently runs the old code.

## Solution

Replace `docker restart` with the stop/rm/run pattern:

```bash
docker pull "$IMAGE:$TAG"
{ docker stop soleur-bridge || true; }
{ docker rm soleur-bridge || true; }
docker run -d --name soleur-bridge \
  --restart unless-stopped \
  --env-file /mnt/data/.env \
  -v /mnt/data:/home/soleur/data \
  -p 127.0.0.1:8080:8080 \
  "$IMAGE:$TAG"
```

Note the `{ ...; }` grouping around `|| true` — without it, bash operator precedence causes `|| true` to absorb failures from earlier commands in the chain (see: `2026-02-13-bash-operator-precedence-ssh-deploy-fallback.md`).

## Key Insight

`docker restart` ≠ "restart with latest image." It restarts the same container with the same image it was created from. To apply a new image, you must destroy the container (`stop` + `rm`) and create a new one (`run`). This is a semantic distinction that is easy to miss — the command name suggests it does more than it does.

## Tags

category: runtime-errors
module: deploy, docker
severity: critical
