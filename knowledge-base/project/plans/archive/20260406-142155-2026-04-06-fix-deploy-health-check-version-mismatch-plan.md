---
title: "fix(infra): deploy health check fails with version mismatch"
type: fix
date: 2026-04-06
deepened: 2026-04-06
---

# fix(infra): Deploy health check fails with version mismatch

## Enhancement Summary

**Deepened on:** 2026-04-06
**Sections enhanced:** 3 (Problem Statement, Phase 1, Acceptance Criteria)
**Research sources:** 6 institutional learnings, server.tf analysis, PR #1575 post-merge verification

### Key Improvements

1. **Root cause identified:** Doppler ProtectHome fix (PR #1575) was merged but `terraform apply` was never run -- the fix never reached the server. Every deploy since v0.13.41 fails because Doppler cannot create `~/.doppler` under systemd's ProtectHome=read-only.
2. **Phase 1 rewritten:** Investigation is now targeted at confirming and applying the Doppler fix, not open-ended diagnosis.
3. **Added GHCR authentication verification** as a secondary investigation item.

### New Considerations Discovered

- PR #1575's post-merge checklist has two unchecked items: `terraform apply` and deploy verification
- The server may have accumulated 4+ failed deploy versions (v0.13.41 through v0.13.45) that never applied
- The 120s -> 300s polling window increase remains valuable even after the root cause is fixed (defense-in-depth against legitimate slow deploys)

## Overview

The web-platform release workflow's deploy verification step consistently fails with a version mismatch. The Docker image builds and pushes to GHCR successfully, the deploy webhook fires and is accepted (HTTP 202), but the health endpoint continues reporting the old version for the entire 120s polling window.

Evidence from PR #1578 merge (commit f14469e3, run 24026573965):

- Expected: `0.13.45`
- Got: `0.13.44` (12 attempts over 120s)
- Re-run also failed with the same mismatch

## Problem Statement

**[Updated 2026-04-06 via deepen-plan, corrected via SSH diagnosis]**

The root cause is **NOT the ProtectHome issue** (that fix was already applied via terraform). The actual root cause is a **Doppler CLI stderr warning contaminating the env file**.

### Actual Root Cause: Doppler stderr leak in ci-deploy.sh

1. **`DOPPLER_CONFIG_DIR=/tmp/.doppler`** was correctly set in `/etc/default/webhook-deploy` (terraform was already applied).
2. **But** in `ci-deploy.sh:35`, `doppler secrets download ... 2>&1` merged stderr into stdout. When `DOPPLER_CONFIG_DIR` is set in the environment, Doppler CLI outputs a warning to stderr: `"Using DOPPLER_CONFIG_DIR from the environment. To disable this, use --no-read-env."`
3. This warning got captured into `$doppler_output` and written to the env file.
4. Docker rejected the env file: `docker: invalid env file: variable 'Using DOPPLER_CONFIG_DIR from the environment...' contains whitespaces`
5. **Deploy failure cascade:** Docker `run` exits 125, ERR trap fires, old container stays running, health endpoint reports old version.

### Fix Applied

Changed `2>&1` to `2>"$doppler_stderr_file"` to separate stderr from stdout. Error messages are still captured on failure (read from the stderr file), but warnings no longer contaminate the env file.

### Secondary issue: 120s polling window

Even after fixing the root cause, the polling window should be increased from 120s to 300s. The documented pattern (learning: `2026-03-21-async-webhook-deploy-cloudflare-timeout.md`) prescribes 300s, but the implementation only uses 120s. Worst-case deploy time (prune + pull + canary check + swap) can exceed 120s.

## Proposed Solution

### Phase 1: Apply Doppler ProtectHome fix via Terraform

**[Updated 2026-04-06 via deepen-plan -- root cause identified]**

The most likely root cause is that PR #1575's Doppler fix was merged but `terraform apply` was never run. The fix must be pushed to the server.

**Step 1.1: Confirm the hypothesis (read-only SSH diagnosis)**

```bash
# Verify Doppler config dir env var is NOT set in webhook service
ssh root@<server> "grep DOPPLER_CONFIG_DIR /etc/default/webhook-deploy"

# Confirm deploys are failing at Doppler download
ssh root@<server> "journalctl -u webhook -t ci-deploy --since '24 hours ago' --no-pager | grep -i 'doppler\|FATAL\|DEPLOY_ERROR' | tail -20"

# Check which version is actually running
ssh root@<server> "docker ps --filter name=soleur-web-platform --format '{{.Image}}'"
```

**Step 1.2: Run `terraform apply` to push the fix**

Per AGENTS.md, all server configuration goes through Terraform. The `terraform_data.deploy_pipeline_fix` resource will:

1. Push the current `ci-deploy.sh` (with Doppler error capture instead of `2>/dev/null`)
2. Push the current `webhook.service` (with EnvironmentFile + ReadWritePaths)
3. Append `DOPPLER_CONFIG_DIR=/tmp/.doppler` and `DOPPLER_ENABLE_VERSION_CHECK=false` to `/etc/default/webhook-deploy`
4. Restart the webhook service
5. Delete stale `/mnt/data/.env`

```bash
cd apps/web-platform/infra
doppler run -c prd_terraform -- terraform apply
```

**Step 1.3: Verify the fix by triggering a deploy**

After terraform apply, re-run the failed release workflow to verify the deploy succeeds:

```bash
gh workflow run web-platform-release.yml
# Or re-run the specific failed run:
gh run rerun 24026573965
```

**Step 1.4: Secondary investigation (if Doppler is NOT the cause)**

If Step 1.1 shows that `DOPPLER_CONFIG_DIR` IS set and deploys are failing for a different reason, investigate:

1. **GHCR authentication** -- `docker pull ghcr.io/jikig-ai/soleur-web-platform:vX.Y.Z` requires credentials if the package is private
2. **Canary health check timeout** -- Port conflict, env var issue
3. **bwrap sandbox check failure** -- New image incompatibility
4. **Disk space** -- `df -h /`
5. **flock contention** -- Another deploy holding the lock

### Research Insights (Phase 1)

**Deploy failure chain pattern:** This project has experienced a pattern of deploy pipeline fixes that are merged but not applied to the existing server due to `lifecycle { ignore_changes = [user_data] }` on the Hetzner server resource. Every ci-deploy.sh or cloud-init change requires a `terraform_data` provisioner AND a subsequent `terraform apply`. The following learnings document this pattern:

- `2026-04-03-doppler-not-installed-env-fallback-outage.md` -- Doppler CLI not installed on server despite cloud-init
- `stale-env-deploy-pipeline-terraform-bridge-20260405.md` -- ci-deploy.sh using stale .env instead of Doppler
- `2026-04-06-doppler-protecthome-readonly-config-dir-fix.md` -- Doppler failing under ProtectHome=read-only

**Prevention recommendation:** Add `terraform apply` to the release workflow or create a post-merge hook that detects changes to `apps/web-platform/infra/` and triggers `terraform apply` automatically. The current manual `terraform apply` step is consistently missed.

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

- [x] Doppler ProtectHome fix confirmed applied to server (`grep DOPPLER_CONFIG_DIR /etc/default/webhook-deploy` returns a match)
- [x] `terraform apply` completed successfully for `apps/web-platform/infra/`
- [x] A deploy triggered after `terraform apply` successfully updates the running version (health endpoint reports new version)
- [x] Health check polling window increased from 120s to 300s in `web-platform-release.yml`
- [x] Status check uses jq (`'.status'`) instead of `grep -q "ok"`
- [x] Version mismatch log messages include uptime (to distinguish "old container still running" from "new container started with wrong version")
- [ ] No regressions to existing deploy functionality (webhook still returns 202, canary pattern still works)

## Test Scenarios

- Given the Doppler fix has been applied via `terraform apply`, when a deploy webhook fires, then ci-deploy.sh should successfully download secrets from Doppler and complete the canary/swap deploy
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

- Does `/etc/default/webhook-deploy` on the server contain `DOPPLER_CONFIG_DIR=/tmp/.doppler`? (If no, confirms `terraform apply` was not run)
- What does `journalctl -u webhook -t ci-deploy` show? Expect `FATAL: Doppler secrets download failed` with ProtectHome mkdir error
- Is the canary container (`soleur-web-platform-canary`) still running or was it cleaned up?
- Is the GHCR package public or private? If private, does the server have `docker login ghcr.io` credentials?

### Related Issues

- #1602 -- This issue
- #1574 -- Doppler ProtectHome deploy failure (fixed by PR #1575, terraform apply pending)
- #1548 -- Terraform infrastructure fix (stale env, ProtectSystem)
- #968 -- Original deploy webhook unreachable issue

### Related PRs

- PR #1575 -- Doppler ProtectHome fix (merged 2026-04-06T08:50, terraform apply NOT confirmed)
- PR #1578 -- The PR whose merge exposed this issue (merged 2026-04-06T09:27)
