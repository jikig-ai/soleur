---
title: "fix: resolve CI release deploy failures for web-platform and telegram-bridge"
type: fix
date: 2026-03-21
semver: patch
---

# fix: Resolve CI Release Deploy Failures for Web-Platform and Telegram-Bridge

## Overview

Both the web-platform and telegram-bridge release workflows have been failing consistently since the Cloudflare Tunnel webhook migration (#963, #967). Every push to main triggers release jobs that succeed at version computation, GitHub Release creation, and Docker image push -- but fail at the deploy step. The web-platform gets HTTP 500 (webhook command execution failure) and the telegram-bridge gets HTTP 524 (Cloudflare edge timeout) or HTTP 403 (Bot Fight Mode challenge). No code has been deployed to production since 2026-03-20 ~18:00 UTC.

Related: [#968](https://github.com/jikig-ai/soleur/issues/968)

## Problem Statement

Five distinct failure modes are interacting:

### P1: Cloudflare Bot Fight Mode blocks webhook requests (HTTP 403)

Zone-level Bot Fight Mode triggers managed challenges on ALL proxied traffic, including legitimate deploy webhook requests from GitHub Actions. The challenge is injected at the Cloudflare edge BEFORE CF Access evaluates service token headers. Documented in learning `2026-03-21-cloudflare-tunnel-server-provisioning.md` -- was supposed to be disabled during #967, but multiple 403 responses in CI logs suggest it was either not disabled or re-enabled.

**Evidence:** Runs 23365339198, 23365339193 (2026-03-20 ~22:35) return HTTP 403 with Cloudflare challenge HTML (`cZone: 'deploy.soleur.ai'`, `cType: 'managed'`).

### P2: ci-deploy.sh execution failure on the server (HTTP 500)

The webhook reaches the server but ci-deploy.sh exits non-zero. The webhook binary (`adnanh/webhook`) returns HTTP 500 with "Error occurred while executing the hook's command." Potential causes: Docker daemon issues, disk space exhaustion (documented recurrence), Doppler token expiry, or permission conflicts from systemd hardening (`ProtectSystem=strict` without adequate `ReadWritePaths`).

**Evidence:** Run 23382502736 (2026-03-21 ~15:13) returns HTTP 500.

### P3: Cloudflare 100s edge timeout exceeded (HTTP 524)

ci-deploy.sh operations (Docker prune + pull + stop + rm + run + health check) exceed Cloudflare's 100-second proxy timeout. The workflow `curl --max-time 150` is higher than Cloudflare's edge limit, so Cloudflare terminates the connection before the webhook response arrives. A Docker pull of a large Next.js image plus a 30-second health check loop can easily exceed 100s.

**Evidence:** Run 23382502779 (2026-03-21 ~15:13) returns HTTP 524 ("error code: 524").

### P4: Telegram-bridge deploying through the wrong server

The telegram-bridge release workflow sends deploy webhooks to `deploy.soleur.ai`, which routes through the Cloudflare Tunnel to the **web-platform** server's `localhost:9000`. But telegram-bridge runs on a separate Hetzner server (`soleur-bridge`). The shared `ci-deploy.sh` on the web-platform server has handlers for both components, so it attempts to deploy telegram-bridge containers on the web-platform server -- the wrong target.

**Evidence:** `apps/telegram-bridge/infra/server.tf` defines a separate `hcloud_server.bridge` resource. `apps/web-platform/infra/tunnel.tf` routes `deploy.soleur.ai` to `http://localhost:9000` on the web-platform server only.

### P5: Missing webhook infrastructure on telegram-bridge server

The telegram-bridge `cloud-init.yml` still uses SSH-based deploy (`ssh_authorized_keys` with `restrict,command=`). It lacks: cloudflared, the webhook binary, the systemd webhook service, and the hooks.json configuration. The #963 PR updated the CI workflow to use webhooks but did not provision the telegram-bridge server with webhook infrastructure.

**Evidence:** `apps/telegram-bridge/infra/cloud-init.yml` lines 16-17 still contain SSH key configuration. No `cloudflared`, `webhook`, or `webhook.service` entries exist in this file.

## Proposed Solution

### Fix 1: Verify Bot Fight Mode is disabled (P1)

Check via Cloudflare API (`GET /zones/{zone_id}/bot_management`) whether Bot Fight Mode is currently active. If active, disable it. If already disabled, the 403s were transient (pre-#967 runs) and this fix is a no-op verification.

**Files:** None (Cloudflare dashboard/API configuration)

### Fix 2: Add server-side error logging to webhook (P2)

The current `include-command-output-in-response: true` in `hooks.json` sends ci-deploy.sh stdout/stderr back in the HTTP response, but the CI workflow only prints the response body on failure -- it doesn't capture it in a structured way. Add explicit logging:
- Before the deploy: log the incoming command to syslog
- After failure: dump the last 30 lines of journal logs for the webhook service

The immediate fix is to SSH into the server and check `journalctl -u webhook --since "2026-03-21"` to identify the specific error. The structural fix is to make ci-deploy.sh failures self-diagnosing.

**Files:**
- `apps/web-platform/infra/ci-deploy.sh` -- add error context to stderr output
- `.github/workflows/web-platform-release.yml` -- log response body on failure for diagnostics

### Fix 3: Handle Cloudflare timeout with async deploy pattern (P3)

Two options:

**Option A (recommended): Increase Cloudflare proxy timeout.** Cloudflare Enterprise plans support `proxy_read_timeout` up to 600s. For Free/Pro plans, the 100s limit is fixed. Check the current plan tier. If the limit is fixed, proceed to Option B.

**Option B: Async webhook with status polling.** Change the webhook to return 202 Accepted immediately, run ci-deploy.sh in the background, and write the result to a status file. The CI workflow then polls a `/hooks/deploy-status` endpoint until completion or timeout. This requires:
- A wrapper script that backgrounds ci-deploy.sh and writes exit status
- A second webhook endpoint for status queries
- Polling logic in the CI workflow

**Option C (simplest): Accept synchronous with longer timeout.** If the server-side issue (P2) is resolved and deploys complete in <100s normally, the timeout is only hit during edge cases (large image pulls, slow registry). Add a retry with backoff in the CI workflow to handle transient timeouts.

**Files:**
- `.github/workflows/web-platform-release.yml` -- retry logic or polling
- `.github/workflows/telegram-bridge-release.yml` -- same
- `apps/web-platform/infra/cloud-init.yml` -- async wrapper if Option B

### Fix 4: Provision webhook infrastructure on telegram-bridge server (P4 + P5)

Two architectural options:

**Option A (recommended): Separate tunnel per server.** Provision cloudflared, webhook binary, and systemd services on the telegram-bridge server. Create a second Cloudflare Tunnel (e.g., `soleur-telegram-bridge`) with route `deploy-bridge.soleur.ai -> localhost:9000`. Update `telegram-bridge-release.yml` to hit the bridge-specific endpoint. This maintains server isolation and aligns with the existing architecture (separate servers, separate Terraform roots).

**Option B: Single tunnel, routing by path.** Keep a single `deploy.soleur.ai` endpoint on the web-platform server. The webhook listener dispatches to the correct server via SSH from the web-platform server to the bridge server. This adds SSH as a dependency again (defeating the purpose of the tunnel migration) and creates a single point of failure.

**Files (Option A):**
- `apps/telegram-bridge/infra/cloud-init.yml` -- add cloudflared, webhook binary, hooks.json, webhook.service (mirror web-platform pattern)
- `apps/telegram-bridge/infra/tunnel.tf` -- new Cloudflare Tunnel + Access application + service token
- `apps/telegram-bridge/infra/variables.tf` -- add `webhook_deploy_secret`, `cf_account_id`, `cf_zone_id`, `app_domain_base`
- `apps/telegram-bridge/infra/server.tf` -- add `tunnel_token` and `webhook_deploy_secret` to `templatefile()` vars
- `.github/workflows/telegram-bridge-release.yml` -- change webhook URL to `deploy-bridge.soleur.ai`

### Fix 5: Add deploy concurrency per server (structural)

Both workflows currently use `concurrency: { group: deploy-production }`. Since they deploy to different servers, they should use separate concurrency groups (`deploy-web-platform`, `deploy-telegram-bridge`) to allow parallel deploys to different servers while still serializing deploys to the same server.

**Files:**
- `.github/workflows/web-platform-release.yml` -- change concurrency group
- `.github/workflows/telegram-bridge-release.yml` -- change concurrency group

## Non-Goals

- Migrating to container orchestration (K8s, Nomad)
- Splitting ci-deploy.sh into separate per-component scripts
- Changing the Docker build/push pipeline (GHCR)
- Adding deploy failure Discord notifications (noted as open question in brainstorm, deferred)
- Modifying the reusable-release.yml version computation logic

## Acceptance Criteria

- [ ] Web-platform release workflow deploys successfully via webhook (push trigger)
- [ ] Telegram-bridge release workflow deploys successfully via webhook (push trigger)
- [ ] `workflow_dispatch` manual deploys work for both apps
- [ ] Deploy retries work (re-running a failed workflow succeeds when the release already exists)
- [ ] Deploys to different servers can run in parallel
- [ ] Deploys to the same server are serialized (concurrency group)
- [ ] Cloudflare Access rejects unauthenticated requests to both deploy endpoints
- [ ] ci-deploy.sh failures produce actionable error messages in CI logs
- [ ] Existing ci-deploy.test.sh passes unchanged

## Test Scenarios

- Given a push to main that changes `apps/web-platform/`, when the web-platform-release workflow runs, then the deploy step returns HTTP 2xx and the container is running
- Given a push to main that changes `apps/telegram-bridge/`, when the telegram-bridge-release workflow runs, then the deploy step returns HTTP 2xx and the container is running
- Given a prior release already exists for the computed version, when the workflow is re-run, then version output is still set and deploy proceeds (retry capability)
- Given both workflows trigger simultaneously, when deploys run, then web-platform and telegram-bridge deploy in parallel (different concurrency groups)
- Given an unauthenticated request to `deploy.soleur.ai`, then Cloudflare Access returns 403 (not a managed challenge page)
- Given ci-deploy.sh fails during Docker operations, when the webhook returns HTTP 500, then the response body contains the specific error message from ci-deploy.sh
- Given a deploy exceeds 90 seconds, when Cloudflare's 100s timeout approaches, then either the deploy completes within the window or the retry mechanism recovers

## Implementation Phases

### Phase 1: Diagnose (30 min)

1. SSH into the web-platform server and check: `journalctl -u webhook --since "2026-03-20"`, `systemctl status webhook`, `systemctl status cloudflared`, `df -h`, `docker ps`
2. Verify Bot Fight Mode status via Cloudflare API
3. Test webhook locally: `curl -X POST -H "Content-Type: application/json" ... http://localhost:9000/hooks/deploy` from the server itself
4. Document the specific error causing HTTP 500

### Phase 2: Fix web-platform deploy (1 hr)

1. Fix the root cause identified in Phase 1 (likely server-side: disk, permissions, Docker)
2. If Bot Fight Mode is still active, disable it
3. Add error context to ci-deploy.sh stderr output
4. Add response body logging to the CI workflow deploy step
5. Trigger `workflow_dispatch` to verify fix

### Phase 3: Provision telegram-bridge webhook (1.5 hr)

1. Add Cloudflare Tunnel + Access resources to `apps/telegram-bridge/infra/tunnel.tf`
2. Update `cloud-init.yml` to install cloudflared, webhook binary, hooks.json, webhook.service
3. Update `server.tf` templatefile vars
4. Update `telegram-bridge-release.yml` webhook URL
5. Add CF Access secrets to GitHub Actions
6. `terraform plan` and `terraform apply`
7. Verify end-to-end with `workflow_dispatch`

### Phase 4: Structural improvements (30 min)

1. Update concurrency groups to per-server
2. Add deploy timeout handling (retry or async pattern)
3. Run both workflows via `workflow_dispatch` to verify

## Dependencies and Risks

- **Server access required:** Diagnosis requires SSH access to both Hetzner servers
- **Terraform state:** Changes to telegram-bridge infra require Terraform credentials (Hetzner + Cloudflare + R2 backend)
- **GitHub Secrets:** New secrets needed for telegram-bridge: `CF_ACCESS_CLIENT_ID_BRIDGE`, `CF_ACCESS_CLIENT_SECRET_BRIDGE`
- **Cloudflare plan tier:** If on Free/Pro plan, the 100s proxy timeout is immutable -- must use async pattern or optimize deploy speed
- **Risk: cloud-init changes don't apply to running servers.** cloud-init only runs at server creation. Changes to `cloud-init.yml` require either manual provisioning or server rebuild. The Terraform `lifecycle { ignore_changes = [user_data] }` block prevents automatic reprovisioning.

## References

- Brainstorm: [2026-03-20-ci-release-reliability-brainstorm.md](../brainstorms/2026-03-20-ci-release-reliability-brainstorm.md)
- Learning: [2026-03-21-cloudflare-tunnel-server-provisioning.md](../learnings/2026-03-21-cloudflare-tunnel-server-provisioning.md)
- Learning: [2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md](../learnings/2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md)
- Issue: [#968 - deploy webhook unreachable from GitHub Actions](https://github.com/jikig-ai/soleur/issues/968)
- PR #963: Replace SSH CI deploy with Cloudflare Tunnel webhook
- PR #967: Complete Cloudflare Tunnel server-side provisioning
- Spec: [feat-webhook-deploy/spec.md](../project/specs/feat-webhook-deploy/spec.md)
- `.github/workflows/web-platform-release.yml`
- `.github/workflows/telegram-bridge-release.yml`
- `.github/workflows/reusable-release.yml`
- `apps/web-platform/infra/ci-deploy.sh`
- `apps/web-platform/infra/cloud-init.yml`
- `apps/telegram-bridge/infra/cloud-init.yml`
- `apps/web-platform/infra/tunnel.tf`
- `apps/telegram-bridge/infra/server.tf`
