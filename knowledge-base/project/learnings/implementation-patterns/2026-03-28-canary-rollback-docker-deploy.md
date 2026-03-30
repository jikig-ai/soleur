---
module: web-platform/infra
date: 2026-03-28
problem_type: deployment_issue
component: ci_deploy
symptoms:
  - "Failed deploys cause downtime because old container is killed before new one is verified"
  - "40% deploy failure rate (8/20 runs)"
root_cause: hard_stop_gap
severity: high
tags: [canary, rollback, docker, deploy, zero-downtime]
---

# Learning: Canary Rollback for Docker Deploys Without Kubernetes

## Problem

The `ci-deploy.sh` deploy script killed the old container (`docker stop` + `docker rm`) before starting and verifying the new one. When the new container failed to start or health-check, the site was down with no running container. 8 of 20 recent deploys failed, each causing downtime.

## Solution

Restructured the deploy to a canary pattern:

1. Pull new image
2. Start canary container on a different port (3001 vs production's 80/3000)
3. Health-check the canary
4. On success: stop old → start new production on correct ports → remove canary
5. On failure: remove canary, keep old container running (zero downtime)

Three critical hardening additions:

- `flock -n` at the top to serialize concurrent deploys (webhook can fire twice)
- Stale canary cleanup (`docker stop/rm` the canary name) before each deploy to prevent "name already in use" from previous failures
- Third-path handling: if canary passes but production `docker run` fails, log the error clearly

## Key Insight

Docker cannot rebind ports on a running container (`docker rename` does not change port mappings). The "swap" requires stopping the old container and starting a brand-new container with production port bindings. This creates a brief (~1-2 second) gap where port 80 is unbound. Cloudflare Tunnel retry and the GHA 10-second poll interval absorb this gap. The canary's only purpose is verifying the image works — it is always discarded after verification.

## Session Errors

**Markdown lint failure on plan file** — Missing blank lines around fenced code blocks inside numbered lists. Recovery: fixed immediately. **Prevention:** Always add blank lines before and after fenced code blocks in markdown, especially inside list items.

**Test mock trace markers consumed by pipe** — `{ docker logs ... || true; } | logger` pipes docker mock's `DOCKER_TRACE:logs` marker to the logger mock, so it doesn't appear in test output. Recovery: removed `logs` from expected trace. **Prevention:** When piping a mocked command's output to another mocked command, the first mock's trace markers are consumed by the pipe. Either trace to stderr or accept the marker won't be visible.

**Flock rejection message invisible in test** — The flock rejection logged to `logger` (mocked to swallow output) but didn't echo to stderr. Test couldn't find the expected text. Recovery: added `echo ... >&2` alongside the logger call, matching the pattern of other rejection paths. **Prevention:** When adding new rejection paths in scripts with mocked logger, always echo to stderr as well.

## Tags

category: implementation-patterns
module: web-platform/infra
