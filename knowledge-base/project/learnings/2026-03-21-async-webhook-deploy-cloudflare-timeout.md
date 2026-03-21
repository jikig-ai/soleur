# Learning: Async webhook deploy pattern to eliminate Cloudflare edge timeouts

## Problem

CI release deploy jobs for both web-platform and telegram-bridge failed consistently after the Cloudflare Tunnel webhook migration (#963, #967). Five distinct failure modes compounded into a single symptom (deploys never reaching production):

1. **Cloudflare Bot Fight Mode (HTTP 403)** -- Zone-level bot protection intercepted legitimate deploy webhook calls from GitHub Actions runners. Bot Fight Mode injects managed challenges at the Cloudflare edge BEFORE Cloudflare Access evaluates service token headers. A correctly authenticated request gets a 403/challenge response and never reaches the webhook endpoint. This was identified and fixed in #967 but continued to affect new infrastructure.

2. **ci-deploy.sh execution failure (HTTP 500)** -- When the webhook binary ran ci-deploy.sh synchronously (`include-command-output-in-response: true`), any script failure produced an HTTP 500. The webhook binary's default behavior is to wait for the command to complete and return its exit code as the HTTP status. Script errors (Docker pull failures, health check timeouts) surfaced as opaque 500s to the CI caller with no structured error output.

3. **Cloudflare 120s edge timeout (HTTP 524)** -- Cloudflare enforces a hard 120-second timeout on proxied HTTP connections. A Docker image pull + container restart routinely takes 60-180 seconds. With synchronous webhook execution, the deploy script's runtime exceeded Cloudflare's edge timeout, producing HTTP 524 (A Timeout Occurred) responses even when the deploy was succeeding on the server. The CI job saw a 524 and marked the deploy as failed, even though the container was running correctly moments later.

4. **telegram-bridge deploying through the wrong server** -- Both web-platform and telegram-bridge workflows used the same `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET` GitHub secrets. The telegram-bridge deploy routed through the web-platform Cloudflare Access application and tunnel, hitting the web-platform server's webhook binary instead of the bridge server. The webhook accepted the request (valid HMAC) but the deploy script ran on the wrong host.

5. **Missing webhook infrastructure on telegram-bridge server** -- The telegram-bridge server had no cloudflared, no webhook binary, no hooks.json, and no webhook.service. Only the web-platform server had been provisioned with tunnel infrastructure in #967. The bridge server still expected SSH-based deploys that no longer existed.

## Solution

### 1. Switch webhook from synchronous to async (fire-and-forget)

The root cause of the 524 timeout was synchronous command execution. Two `hooks.json` settings control this:

```json
{
  "include-command-output-in-response": false,
  "success-http-response-code": 202
}
```

With `include-command-output-in-response: false`, the webhook binary forks ci-deploy.sh and returns immediately without waiting for completion. The `success-http-response-code: 202` signals to the CI caller that the deploy was accepted but not yet complete (HTTP 202 Accepted semantics). This eliminates the Cloudflare timeout entirely -- the HTTP response completes in milliseconds regardless of deploy duration.

### 2. CI workflow: fire-and-forget with health poll verification

The deploy job was restructured into two steps:

- **Step 1: Fire webhook** -- POST the deploy payload, assert HTTP 202, exit. Uses `--max-time 30` (only needs enough time for HMAC validation and fork, not the full deploy).
- **Step 2: Poll health endpoint** -- Loop up to 30 attempts (10s apart, 300s total) hitting the app's `/health` endpoint. Success means the new container is running. Timeout means the deploy failed on the server side, and `journalctl -u webhook -t ci-deploy` on the server has the details.

This decouples "was the deploy accepted?" from "did the deploy succeed?" -- the correct separation for async operations.

### 3. Full Cloudflare Tunnel infrastructure for telegram-bridge

Created `apps/telegram-bridge/infra/tunnel.tf` mirroring the web-platform pattern:

- `cloudflare_zero_trust_tunnel_cloudflared.bridge` -- Separate tunnel (not shared with web-platform)
- `cloudflare_record.deploy_bridge` -- DNS CNAME `deploy-bridge.soleur.ai` routing through the bridge tunnel
- `cloudflare_zero_trust_access_application.deploy_bridge` -- Separate CF Access application
- `cloudflare_zero_trust_access_service_token.deploy_bridge` -- Separate service token to avoid credential collision

### 4. telegram-bridge cloud-init provisioning

Rewrote `apps/telegram-bridge/infra/cloud-init.yml` to include the full webhook stack: cloudflared installation from apt, webhook binary with checksum verification, hooks.json with async execution, and a hardened systemd webhook.service unit. This mirrors the web-platform cloud-init with bridge-specific adaptations (no workspace volumes, localhost-only port binding).

### 5. Error trap in ci-deploy.sh

Added `trap 'echo "DEPLOY_ERROR: ci-deploy.sh failed at line $LINENO (exit $?)" >&2' ERR` to produce structured error output. In async mode, stderr goes to syslog via `journalctl -u webhook -t ci-deploy`, not the HTTP response. This provides a debugging breadcrumb when deploys fail without being connected to the CI job's output.

### 6. Separate concurrency groups per server

Changed from a shared `deploy-production` concurrency group to per-server groups (`deploy-web-platform`, `deploy-telegram-bridge`). The shared group was serializing unrelated deploys -- a telegram-bridge deploy would block waiting for a web-platform deploy to complete, even though they target different servers.

### 7. Separate CF Access credentials per server

Created `_BRIDGE` suffixed GitHub secret names: `CF_ACCESS_CLIENT_ID_BRIDGE`, `CF_ACCESS_CLIENT_SECRET_BRIDGE`, `WEBHOOK_DEPLOY_SECRET_BRIDGE`. The telegram-bridge workflow references these instead of the web-platform credentials. This prevents the credential collision that caused bridge deploys to route through the web-platform tunnel.

## Key Insight

**Never run long-running operations synchronously through a reverse proxy with a connection timeout.** Cloudflare's 120s edge timeout is not configurable on non-Enterprise plans. Any webhook that triggers a Docker pull + restart will intermittently exceed this limit. The correct pattern for deploy webhooks behind Cloudflare (or any CDN/proxy with connection timeouts) is:

1. **Accept** -- Validate credentials and payload, fork the work, return 202 immediately.
2. **Execute** -- Run the deploy asynchronously. Log to syslog/journald.
3. **Verify** -- Have the CI caller poll a health endpoint to confirm success.

This is the standard async job pattern (submit, poll, verify) applied to infrastructure. It is more resilient than synchronous execution even without proxy timeouts, because it separates the "was the request valid?" question from the "did the work succeed?" question. A synchronous webhook conflates these into a single HTTP response, making it impossible to distinguish "bad request" from "slow deploy" from "proxy timeout."

A secondary insight: when multiple servers share a Cloudflare Access domain, each server needs its own tunnel, Access application, service token, and GitHub secret set. Sharing credentials across servers is a routing bug, not a cost optimization. The Cloudflare free tier has no per-tunnel or per-application limits, so there is zero cost to separating them.

## Session Errors

1. **setup-ralph-loop.sh path error** -- A script reference used the wrong relative path initially. The path was taken from a plan document without tracing the `../` steps to verify the final target. This reinforces the AGENTS.md rule: "When a plan specifies relative paths, trace each `../` step to verify the final target before implementing."

2. **Work skill parallelization gate violation** -- Started executing tasks sequentially before completing the independence analysis required by the work skill. The correct protocol is to analyze all tasks for dependencies first, identify which can run in parallel, then execute. Jumping to execution skips the dependency analysis that prevents wasted work on tasks that block each other.

3. **CWD confusion after cd into terraform dir** -- After `cd`-ing into a Terraform directory for `terraform init/plan`, subsequent file operations used relative paths that resolved incorrectly. The fix is to use absolute paths exclusively (per AGENTS.md) or run Terraform commands with `-chdir` instead of `cd`.

## Prevention

- **New webhook endpoints behind Cloudflare**: Always use `include-command-output-in-response: false` + `success-http-response-code: 202` unless the command completes in under 10 seconds. The 120s Cloudflare timeout is not a safe margin for any operation involving network I/O (Docker pulls, API calls, package installs).
- **Multi-server deploy infrastructure**: Create per-server tunnel, Access application, service token, and GitHub secrets from the start. Use a naming convention (`_BRIDGE`, `_PLATFORM`) that makes the separation obvious in both Terraform resource names and GitHub secret names.
- **Concurrency groups**: Name them after the deployment target, not the action. `deploy-web-platform` is correct; `deploy-production` is ambiguous when production has multiple servers.
- **Relative path verification**: When implementing from a plan, trace every relative path to its absolute target before writing code. Plans regularly prescribe paths that look plausible but resolve to the wrong directory.
- **Parallelization analysis before execution**: When a work skill or plan lists multiple tasks, spend 60 seconds mapping dependencies before starting any work. The time invested in analysis is always less than the time wasted by discovering mid-task that task 3 depends on task 2's output.

## Cross-References

- [Cloudflare Tunnel server-side provisioning](2026-03-21-cloudflare-tunnel-server-provisioning.md) -- The predecessor session that built the initial tunnel infrastructure for web-platform (#967). This session extended it to telegram-bridge and fixed the timeout failure mode.
- [CI deploy reliability and mock trace testing](2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md) -- Previous CI deploy fixes (Docker prune, retry gating, concurrency groups). The concurrency group separation in this session evolved from the shared group introduced there.
- [Cloudflare Terraform v4/v5 resource names](2026-03-20-cloudflare-terraform-v4-v5-resource-names.md) -- Naming conventions for Cloudflare Tunnel Terraform resources. The telegram-bridge tunnel.tf follows the v4 naming pattern documented here.
- [Terraform state R2 migration](2026-03-21-terraform-state-r2-migration.md) -- R2 backend setup required before Terraform operations in this session could work.
- [Checksum verification for binary downloads](2026-03-20-checksum-verification-binary-downloads.md) -- The telegram-bridge cloud-init includes webhook binary checksum verification following this pattern.
- [Static binary install replaces sudo apt](2026-03-20-static-binary-install-replaces-sudo-apt.md) -- Session error #1 (setup-ralph-loop.sh wrong path) mirrors the path error documented here.
- Issue #968 -- The deploy webhook unreachable issue that triggered this investigation.
- Issue #963 -- Original SSH-to-tunnel migration PR.
- Issue #967 -- Server-side tunnel provisioning PR.

## Tags
category: ci-cd
module: .github/workflows, web-platform, telegram-bridge, infrastructure
