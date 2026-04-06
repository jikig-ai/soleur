---
title: "fix(infra): deploy health check fails with version mismatch"
type: fix
date: 2026-04-06
---

# fix(infra): Deploy health check fails with version mismatch

## Overview

The web-platform release workflow's deploy verification step consistently fails with a version mismatch. The Docker image builds and pushes to GHCR successfully, the deploy webhook fires and is accepted (HTTP 202), but the health endpoint continues reporting the old version for the entire 120s polling window.

Evidence from PR #1578 merge (commit f14469e3, run 24026573965):

- Expected: `0.13.45`
- Got: `0.13.44` (12 attempts over 120s)
- Re-run also failed with the same mismatch

## Problem Statement

The deploy pipeline has a fundamental timing problem. The async webhook deploy pattern (learning: `2026-03-21-async-webhook-deploy-cloudflare-timeout.md`) intentionally decouples "was the deploy accepted?" from "did the deploy succeed?" The webhook returns HTTP 202 immediately, and CI polls the health endpoint to verify the new version is running.

However, the total time for a full deploy on the server can exceed the 120s polling window:

1. **Webhook receives request** (~instant)
2. **ci-deploy.sh starts** (~instant)
3. **`docker image prune -af`** (variable, can be slow with many layers)
4. **`docker pull`** (30-90s depending on layer cache and network)
5. **Start canary container on port 3001** (~2-5s)
6. **Canary health check** (up to 10 attempts x 3s = 30s max)
7. **bwrap sandbox verification** (~1-2s)
8. **Stop old container, start new production container** (~5-10s)
9. **New container startup** (Next.js cold start, 5-15s)

Total worst case: ~150s+. The CI poll window is only 120s (12 attempts x 10s).

Additionally, there may be concurrent deploy issues if the `deploy-web-platform` concurrency group allows a second webhook while ci-deploy.sh still holds the flock, or if CI fires multiple deploy webhooks for rapid merges.

## Proposed Solution

### Phase 1: Investigate server-side deploy failure

The re-run also failed with the same mismatch. If the issue were purely timing, a re-run (which skips Docker build/push since the image already exists in GHCR) should complete faster. The persistent failure suggests ci-deploy.sh is failing silently on the server. Diagnose first.

Potential server-side failure causes (ordered by likelihood):

1. **GHCR authentication failure** -- `docker pull ghcr.io/jikig-ai/soleur-web-platform:vX.Y.Z` requires credentials if the package is private. Verify whether the server has `docker login ghcr.io` configured.
2. **Canary health check timeout** -- The canary may fail to start (port conflict, missing env var, Doppler download failure)
3. **bwrap sandbox check failure** -- The bwrap verification may reject the new image
4. **Disk space** -- Even with `docker image prune -af`, disk may be full from non-Docker data
5. **flock contention** -- Another deploy may hold the lock

Diagnostic approach (read-only SSH per AGENTS.md):

```bash
# Check journald for ci-deploy.sh output (most important -- shows exact failure)
ssh root@<server> "journalctl -u webhook -t ci-deploy --since '1 hour ago' --no-pager | tail -100"

# Check if the expected image exists on the server
ssh root@<server> "docker images | grep soleur-web-platform | head -10"

# Check running containers
ssh root@<server> "docker ps -a --filter name=soleur-web-platform"

# Check disk space
ssh root@<server> "df -h /"

# Check GHCR auth
ssh root@<server> "cat ~/.docker/config.json 2>/dev/null | jq '.auths | keys'"
```

### Phase 2: Fix polling window and improve diagnostics

Regardless of the root cause found in Phase 1, the polling window should be increased to match the documented pattern. The existing learning (`2026-03-21-async-webhook-deploy-cloudflare-timeout.md`) prescribes "30 attempts (10s apart, 300s total)" but the implementation only uses 12 attempts (120s).

**File: `.github/workflows/web-platform-release.yml`**

Changes to the "Verify deploy health and version" step:

- Increase from 12 attempts x 10s (120s) to 30 attempts x 10s (300s)
- Use jq for status check instead of fragile `grep -q "ok"` (matches "ok" anywhere in response)
- Add uptime to version mismatch messages (distinguishes "old container still running" from "new container with wrong version")

```yaml
- name: Verify deploy health and version
  env:
    VERSION: ${{ needs.release.outputs.version }}
  run: |
    for i in $(seq 1 30); do
      HEALTH=$(curl -sf "https://app.soleur.ai/health" 2>/dev/null || echo "")
      if [ -z "$HEALTH" ]; then
        echo "Attempt $i/30: health endpoint unreachable"
      else
        STATUS=$(echo "$HEALTH" | jq -r '.status // empty')
        if [ "$STATUS" = "ok" ]; then
          DEPLOYED_VERSION=$(echo "$HEALTH" | jq -r '.version // empty')
          if [ "$DEPLOYED_VERSION" = "$VERSION" ]; then
            echo "Deploy verified: version $VERSION running"
            echo "$HEALTH" | jq .
            exit 0
          fi
          UPTIME=$(echo "$HEALTH" | jq -r '.uptime // "unknown"')
          echo "Attempt $i/30: version mismatch (expected=$VERSION got=$DEPLOYED_VERSION uptime=${UPTIME}s)"
        else
          echo "Attempt $i/30: health endpoint returned non-ok status"
          echo "$HEALTH" | jq . 2>/dev/null || echo "$HEALTH"
        fi
      fi
      sleep 10
    done
    echo "::error::Deploy verification failed after 300s — expected version $VERSION"
    exit 1
```

## Acceptance Criteria

- [ ] Root cause of deploy failure identified via server-side log investigation
- [ ] Root cause fixed (if server-side issue found) or confirmed as timing-only
- [ ] Health check polling window increased from 120s to 300s in `web-platform-release.yml`
- [ ] Status check uses jq (`'.status'`) instead of `grep -q "ok"`
- [ ] Version mismatch log messages include uptime (to distinguish "old container still running" from "new container started with wrong version")
- [ ] No regressions to existing deploy functionality (webhook still returns 202, canary pattern still works)

## Test Scenarios

- Given a successful deploy that takes 150s, when the health check polls for 300s, then the version match should be detected before timeout
- Given a deploy where the webhook fires but ci-deploy.sh fails, when the health check polls for 300s, then the step should fail with a clear error showing the old version and high uptime
- Given a deploy where the health endpoint is temporarily unreachable during container swap, when the health check encounters unreachable attempts, then it should continue polling and eventually succeed

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/CI bug fix.

## Known Limitations

- **False negative on slow deploys:** If the deploy succeeds after the verification timeout, the deploy job reports failure even though the server is running the new version. The email notification will fire for a "failed" deploy that actually succeeded. Increasing to 300s makes this less likely but does not eliminate it. A deploy status endpoint (deferred) would be the complete fix.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Add a deploy status endpoint (webhook writes status to file, CI polls file) | Real-time deploy progress visibility | Requires new server-side infrastructure, complexity | Deferred -- overkill for a timing issue |
| Use synchronous webhook with longer Cloudflare timeout | Simpler CI verification | Cloudflare 120s edge timeout is not configurable on non-Enterprise; would regress #968 | Rejected |
| Reduce deploy time (faster prune, pre-pull) | Fixes root cause | Unreliable -- pull times depend on network; prune is already `-af` | Supplement to Phase 1, not replacement |

## References & Research

### Internal References

- `.github/workflows/web-platform-release.yml:94-115` -- Current health check verification step
- `apps/web-platform/infra/ci-deploy.sh` -- Server-side deploy script with canary pattern
- `apps/web-platform/server/health.ts` -- Health endpoint returning `BUILD_VERSION` env var
- `apps/web-platform/Dockerfile:45-46` -- `BUILD_VERSION` ARG/ENV injection
- `.github/workflows/reusable-release.yml:305` -- `BUILD_VERSION` build arg set to computed version

### Institutional Learnings

- `2026-03-21-async-webhook-deploy-cloudflare-timeout.md` -- Documents the fire-and-forget + poll pattern, prescribes 30 attempts (300s)
- `2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md` -- Docker prune and deploy retry patterns
- `2026-04-02-docker-image-accumulation-disk-full-deploy-failure.md` -- Disk space as silent deploy failure cause
- `2026-04-05-stale-env-deploy-pipeline-terraform-bridge.md` -- Recent deploy pipeline fix via terraform_data provisioner
- `2026-03-19-docker-restart-does-not-apply-new-images.md` -- Container restart semantics (not applicable here; ci-deploy.sh uses stop/rm/run correctly)
- `2026-03-29-post-merge-release-workflow-verification.md` -- Post-merge verification gate

### Key Investigation Questions

- Is the GHCR package public or private? If private, does the server have `docker login ghcr.io` credentials?
- What does `journalctl -u webhook -t ci-deploy` show for the failed deploy timeframe?
- Is the canary container (`soleur-web-platform-canary`) still running or was it cleaned up?

### Related Issues

- #1602 -- This issue
- #968 -- Original deploy webhook unreachable issue
- #1548 -- Terraform infrastructure fix (stale env, ProtectSystem)
