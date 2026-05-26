---
title: "fix(infra): replace terraform_data.deploy_pipeline_fix SSH provisioner with CF Tunnel webhook"
type: fix
date: 2026-05-26
lane: single-domain
requires_cpo_signoff: false
---

# fix(infra): replace terraform_data.deploy_pipeline_fix SSH provisioner with CF Tunnel webhook

## Overview

Replace the SSH provisioner in `terraform_data.deploy_pipeline_fix` (`apps/web-platform/infra/server.tf:216-327`) with an HTTPS call through the existing Cloudflare Tunnel + webhook pattern (#749). This eliminates the last CI workflow that requires SSH from a GitHub-hosted runner to the production host, closing the regression introduced when `deploy_pipeline_fix` was added (#2185) after #749 had already removed the CI deploy SSH firewall rule.

The existing `apply-deploy-pipeline-fix.yml` workflow currently works around the SSH gap via a `cloudflared access tcp` bridge (#4177) + iptables NAT redirect. This works but is complex infrastructure (cloudflared install, SHA pin, bridge startup, NAT redirect, known_hosts seeding, teardown) bolted onto a workflow that should simply POST an HTTPS payload. The webhook pattern already exists and is proven for the deploy path (`/hooks/deploy`); this plan extends it with a new `/hooks/infra-config` endpoint.

## Problem Statement / Motivation

1. **SSH from CI to prod is architecturally eliminated per #749.** `firewall.tf:15` documents: "CI deploy SSH rule removed -- deploys now use webhook via Cloudflare Tunnel." The `deploy_pipeline_fix` resource reintroduced SSH-from-CI for one workflow.

2. **The CF Tunnel SSH bridge workaround (#4177) is fragile.** It requires: cloudflared binary install + SHA verification, CF Access service-token credential extraction from Doppler, TCP bridge startup with timeout-poll, iptables NAT redirect to fool Go's SSH client (which does not consult `~/.ssh/config`), host-key seeding against the local forward, and a teardown step. Any of these can fail for reasons unrelated to the actual apply.

3. **Recurring drift cost.** Per `2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`, this resource drifts on every merge touching trigger files. The drift is by design, but each cycle requires `terraform apply` which includes SSH. Eliminating SSH from the apply path makes the drift-resolution cycle simpler and more reliable.

## Proposed Solution

### Approach

Add a new webhook endpoint (`/hooks/infra-config`) to the existing `adnanh/webhook` listener that:

1. Accepts an HMAC-authenticated HTTPS POST with base64-encoded file contents passed as environment variables via `pass-environment-to-command` (same pattern as the existing `/hooks/deploy` endpoint).
2. Runs a **hardcoded** handler script (`infra-config-apply.sh`) that writes the known set of files atomically (mktemp + mv) with hardcoded paths, modes, and owners -- no generic JSON schema, no arbitrary command execution.
3. Runs the fixed post-write sequence: chmod, chown, visudo-validate-then-install for sudoers, `systemctl daemon-reload`.
4. Handles self-restart of the webhook service via a delayed one-shot systemd timer (`systemd-run --on-active=3s systemctl restart webhook`) so the HTTP response completes before the restart kills the listener.
5. Returns 202 (fire-and-forget, same pattern as `/hooks/deploy`).

Then replace the `terraform_data.deploy_pipeline_fix` resource:
- Remove all `connection {}`, `provisioner "file" {}`, and `provisioner "remote-exec" {}` blocks.
- Replace with a `provisioner "local-exec"` that invokes a standalone push script (`apps/web-platform/infra/push-infra-config.sh`), which `curl`s the webhook endpoint through the CF Tunnel with the file payloads. Sensitive values (HMAC secret, CF Access credentials) are passed via the provisioner's `environment {}` block (not interpolated into the command string -- Terraform refuses to interpolate `sensitive = true` values into `local-exec` command strings).
- The `triggers_replace` hash stays the same (sha256 of file contents) so drift detection continues to work.

### Why webhook over alternatives

| Alternative | Rejection |
|---|---|
| Keep SSH bridge (#4177) | Works but adds ~80 lines of workflow infrastructure for a 10-second file push. Every component (cloudflared install, SHA pin, bridge startup, NAT redirect, known_hosts) is an independent failure surface. |
| SSH-over-Tailscale / WireGuard | New VPN dependency; does not exist in this stack. Tunnel is already running. |
| SCP via cloudflared-scp | Not a supported cloudflared mode for service-token auth. |
| Push files via Docker image | Overweight: requires building + pushing an image containing the config files, then a deploy-style container swap. The files are static text, not a service. |
| Cloud-init only (no runtime push) | Cannot push to the existing server (`ignore_changes = [user_data]`). Only works for fresh provisioning. |

## Research Insights

### Local codebase patterns

- **Existing webhook endpoint** (`/hooks/deploy`): HMAC-SHA256 auth via `X-Signature-256` header, fire-and-forget (202), command passed via `pass-environment-to-command` as `SSH_ORIGINAL_COMMAND`. Defined in `apps/web-platform/infra/hooks.json.tmpl`.
- **Existing deploy status endpoint** (`/hooks/deploy-status`): GET, returns JSON state. Defined in same template.
- **CF Tunnel ingress**: `deploy.soleur.ai` routes to `http://localhost:9000` (the webhook listener). Defined in `apps/web-platform/infra/tunnel.tf:31-33`.
- **CF Access protection**: service-token auth (`CF-Access-Client-Id` + `CF-Access-Client-Secret` headers). Defined in `tunnel.tf:55-78`.
- **HMAC secret**: `var.webhook_deploy_secret` rendered into `hooks.json.tmpl` at plan time. Already available in Doppler `prd_terraform`.
- **webhook.service sandbox**: `ProtectSystem=strict` with explicit `ReadWritePaths` for writable paths. The infra-config endpoint needs write access to the same paths the SSH provisioner currently targets: `/usr/local/bin/`, `/etc/systemd/system/`, `/etc/webhook/`, `/etc/sudoers.d/`, `/etc/default/`, `/etc/vector/`, `/var/lib/vector/`.
- **Cloud-init dual-path**: All files managed by `deploy_pipeline_fix` also exist in `cloud-init.yml` for fresh servers. The infra-config handler script will live in both paths (same as `ci-deploy.sh`, `cat-deploy-state.sh`).

### Learnings applied

- `2026-03-21-async-webhook-deploy-cloudflare-timeout.md`: Always use `include-command-output-in-response: false` + `success-http-response-code: 202` for operations behind CF Tunnel. The 120s CF edge timeout is not configurable on non-Enterprise plans.
- `2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`: The drift IS the feature working. The sha256 trigger hash must survive the refactor.
- `2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`: GitHub Actions runners use ~5000+ rotating IP ranges that cannot be allowlisted.
- `2026-05-18-plan-baked-in-operator-ssh-violated-iac-rule.md`: All infrastructure provisioning goes through Terraform, never manual SSH. This plan replaces the SSH provisioner with a webhook call, which is strictly better on this axis.

## User-Brand Impact

- **If this lands broken, the user experiences:** no direct user impact. This is CI/CD infrastructure. Worst case: infra-config updates fail to push, and the existing server-side files remain at the previously-applied version until the issue is diagnosed and a manual apply is run. The webhook deploy path for app releases (`/hooks/deploy`) is unaffected.
- **If this leaks, the user's data / workflow / money is exposed via:** no user-facing exposure. The webhook HMAC secret and CF Access service-token credentials are already in Doppler and are not changed by this plan. The payload contains infrastructure config files (shell scripts, systemd units) -- no user data, no secrets.
- **Brand-survival threshold:** `none`

## Observability

```yaml
liveness_signal:
  what: "scheduled-terraform-drift.yml cron detects deploy_pipeline_fix drift on trigger-file merge; apply-deploy-pipeline-fix.yml auto-resolves it"
  cadence: "on each merge touching trigger files (push event) + drift cron 0 6,18 * * *"
  alert_target: "GitHub issue auto-filed by drift workflow on unresolved drift"
  configured_in: ".github/workflows/scheduled-terraform-drift.yml + .github/workflows/apply-deploy-pipeline-fix.yml"

error_reporting:
  destination: "GitHub Actions workflow logs (apply-deploy-pipeline-fix job)"
  fail_loud: "Workflow step failure + GitHub issue auto-comment on drift issue"

failure_modes:
  - mode: "Webhook returns non-202 (HMAC mismatch, handler script error)"
    detection: "curl exit code in local-exec provisioner fails terraform apply"
    alert_route: "Workflow failure notification + drift issue remains open"
  - mode: "Webhook self-restart fails (service file was malformed)"
    detection: "Post-apply verification step checks systemctl is-active webhook; also detectable via /hooks/deploy-status GET endpoint"
    alert_route: "Workflow failure + drift cron re-files issue next tick"
  - mode: "CF Tunnel down"
    detection: "curl times out in local-exec; CF Tunnel health monitoring (existing)"
    alert_route: "Workflow failure; CF notification policy for tunnel health"

logs:
  where: "journalctl -u webhook on the production host; GitHub Actions workflow run logs"
  retention: "journald default (systemd-managed rotation); GH Actions logs retained 90 days"

discoverability_test:
  command: "gh run list --workflow=apply-deploy-pipeline-fix.yml --limit 5 --json status,conclusion,headBranch | jq '.[] | {status, conclusion, headBranch}'"
  expected_output: '{"status":"completed","conclusion":"success","headBranch":"main"}'
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `terraform_data.deploy_pipeline_fix` in `server.tf` has zero `connection {}`, `provisioner "file" {}`, or `provisioner "remote-exec" {}` blocks. Verification: `awk '/resource "terraform_data" "deploy_pipeline_fix"/,/^resource / { if (/^\s*(connection|provisioner "(file|remote-exec)")/) count++ } END { print count+0 }' apps/web-platform/infra/server.tf` returns `0`. (Note: other terraform_data resources in the same file retain their provisioners -- the grep must be scoped to the deploy_pipeline_fix resource block.)
- [ ] AC2: `terraform_data.deploy_pipeline_fix` uses a `provisioner "local-exec"` that invokes `push-infra-config.sh`, which sends an HTTPS POST to `deploy.${var.app_domain_base}/hooks/infra-config` with the file payloads. Sensitive values (`var.webhook_deploy_secret`, CF Access client ID/secret) are passed via the provisioner's `environment {}` block, not interpolated into the command string (Terraform refuses to interpolate `sensitive = true` values into local-exec commands).
- [ ] AC3: `hooks.json.tmpl` contains a new `infra-config` hook with `include-command-output-in-response: false`, `success-http-response-code: 202`, HMAC-SHA256 trigger-rule matching the existing `deploy` hook envelope, and `pass-environment-to-command` entries for each base64-encoded file content (same pattern as the deploy hook's `SSH_ORIGINAL_COMMAND` env var).
- [ ] AC4: A new handler script (`infra-config-apply.sh`) exists at `apps/web-platform/infra/infra-config-apply.sh` that: (a) reads file contents from environment variables (set by webhook's `pass-environment-to-command`), (b) writes the **hardcoded** set of managed files atomically (mktemp + mv) with fixed paths/modes/owners -- no generic JSON parsing, no arbitrary command execution, (c) runs visudo-validate for the sudoers file, (d) runs `systemctl daemon-reload`, (e) schedules a delayed self-restart via `systemd-run --on-active=3s systemctl restart webhook`.
- [ ] AC5: `cloud-init.yml` provisions `infra-config-apply.sh` to `/usr/local/bin/infra-config-apply.sh` for fresh-server parity.
- [ ] AC6: `webhook.service` ReadWritePaths includes `/etc/sudoers.d` (currently missing -- required for the visudo-validate-then-install pattern which runs INSIDE the service's mount namespace). All other paths written by the handler (`/usr/local/bin`, `/etc/systemd/system`, `/etc/webhook`, `/etc/default`) are already in ReadWritePaths or ReadOnlyPaths. The cloud-init inline copy of webhook.service must be updated in sync.
- [ ] AC7: `apply-deploy-pipeline-fix.yml` removes all cloudflared SSH bridge infrastructure (cloudflared install, CF Access SSH token extraction, bridge startup, iptables NAT, host-key seeding, teardown step). SSH-agent setup and DEPLOY_SSH_PRIVATE_KEY extraction are also removed.
- [ ] AC8: Post-apply verification in `apply-deploy-pipeline-fix.yml` asserts: (a) terraform apply exit code 0, (b) after 5s wait, GET `/hooks/deploy-status` returns JSON with `webhook: active`. File-content-level verification is deferred to the drift cron (runs every 12h; if files diverge, a new drift issue is auto-filed).
- [ ] AC9: `triggers_replace` hash in `terraform_data.deploy_pipeline_fix` continues to include all current trigger files (ci-deploy.sh, ci-deploy-wrapper.sh, webhook.service, cat-deploy-state.sh, canary-bundle-claim-check.sh, deploy-inngest-bootstrap.sudoers, hooks_json, infra-config-apply.sh, push-infra-config.sh) so drift detection remains functional.
- [ ] AC10: `terraform validate` passes in `apps/web-platform/infra/`.
- [ ] AC11: The `infra-config-apply.sh` handler script has a test file (`infra-config-apply.test.sh`) with at least: (a) happy-path file write + permission set to a tmpdir, (b) missing/empty env var rejection, (c) visudo validation failure halts install of sudoers file, (d) atomic write (no partial file visible at destination).

### Post-merge (operator)

- [ ] AC13: `terraform apply -target=terraform_data.deploy_pipeline_fix` succeeds from operator workstation (first apply after merge -- pushes files via webhook instead of SSH). Automation: this is already the existing drift-resolution ritual; the workflow auto-fires on trigger-file merges. The first organic merge to a trigger file demonstrates the webhook path end-to-end.
- [ ] AC14: Post-apply, `/hooks/deploy-status` GET returns `systemctl is-active webhook` = `active` (confirms webhook survived the self-restart).
- [ ] AC15: One organic merge to a pipeline-fix trigger file demonstrates `apply-deploy-pipeline-fix.yml` runs green without SSH.

## Implementation Phases

### Phase 1: Handler script + webhook hook + cloud-init

**Preconditions** (verify before coding):
- Confirm `webhook` binary 2.8.2 supports `pass-environment-to-command` for routing payload fields to the handler script as env vars. Current hooks.json uses this for the deploy hook -- same pattern.
- Confirm `systemd-run --on-active=` is available on Ubuntu 24.04 (it is -- part of systemd 255+).

**Create `apps/web-platform/infra/infra-config-apply.sh`:**

Hardcoded handler script (no generic JSON parsing, no jq dependency). The webhook's `pass-environment-to-command` sets env vars for each base64-encoded file content (e.g., `CI_DEPLOY_SH_B64`, `WEBHOOK_SERVICE_B64`, etc.). The script:

- For each known file: decode the corresponding env var via `base64 -d`, write to mktemp, set hardcoded mode/owner, mv atomically to the known destination path.
- Hardcoded file map (path + mode + owner for each of the 7 managed files -- same as the current provisioner "file" blocks).
- Runs the fixed post-write sequence: `chmod +x` for scripts, `chown root:deploy /etc/webhook/hooks.json`, `chmod 640 /etc/webhook/hooks.json`, visudo-validate-then-install for sudoers (same pattern as current remote-exec), `systemctl daemon-reload`.
- Schedules self-restart: `systemd-run --on-active=3s --unit=webhook-self-restart systemctl restart webhook`.
- Exit 0.

**Create `apps/web-platform/infra/infra-config-apply.test.sh`:**
- Happy-path file write + permission verification to a tmpdir.
- Missing/empty env var rejection.
- visudo validation failure halts sudoers install (mock visudo).
- Atomic write (no partial file visible at destination).

**Edit `apps/web-platform/infra/hooks.json.tmpl`:**
- Add `infra-config` hook entry with same HMAC auth envelope as `deploy`.
- `execute-command`: `/usr/local/bin/infra-config-apply.sh`.
- `include-command-output-in-response: false`, `success-http-response-code: 202`.
- `http-methods: ["POST"]`.
- `pass-environment-to-command`: map each payload field (`ci_deploy_sh_b64`, `webhook_service_b64`, etc.) to env vars consumed by the handler script.

**Edit `apps/web-platform/infra/webhook.service`** (and the cloud-init inline copy):
- Add `/etc/sudoers.d` to `ReadWritePaths` (currently missing -- required because the handler runs inside the service's mount namespace and must `install` the sudoers file to that path).

**Edit `apps/web-platform/infra/cloud-init.yml`:**
- Add `infra-config-apply.sh` to `write_files` section (base64-encoded, same pattern as ci-deploy.sh).
- The new `hooks.json` entry is already handled because `hooks.json.tmpl` is rendered at plan time and injected into cloud-init via `hooks_json_b64`.

**Edit `apps/web-platform/infra/server.tf` (cloud-init templatefile):**
- Add `infra_config_apply_script_b64 = base64encode(file("${path.module}/infra-config-apply.sh"))` parameter.

### Phase 2: Terraform refactor + push script

**Create `apps/web-platform/infra/push-infra-config.sh`:**

Standalone push script invoked by the local-exec provisioner. Receives sensitive values as environment variables (set by the provisioner's `environment {}` block). The script:

1. Constructs the JSON payload with base64-encoded file contents (reads files from `$INFRA_DIR`).
2. Computes HMAC-SHA256 signature: `echo -n "$BODY" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" -binary | xxd -p -c 256`.
3. `curl -s -o /tmp/infra-config-response.txt -w '%{http_code}' --max-time 30 -X POST -H "Content-Type: application/json" -H "X-Signature-256: sha256=$HMAC" -H "CF-Access-Client-Id: $CF_ACCESS_ID" -H "CF-Access-Client-Secret: $CF_ACCESS_SECRET" -d "$BODY" "https://deploy.${APP_DOMAIN_BASE}/hooks/infra-config"`.
4. Asserts HTTP 202; exits non-zero otherwise (fails the terraform apply).

**Edit `apps/web-platform/infra/server.tf`:**
- Remove `connection {}` block from `terraform_data.deploy_pipeline_fix`.
- Remove all `provisioner "file" {}` blocks (7 blocks).
- Remove `provisioner "remote-exec" {}` block.
- Add `provisioner "local-exec"` with:
  - `command = "${path.module}/push-infra-config.sh"`
  - `environment {}` block passing sensitive values: `WEBHOOK_SECRET = var.webhook_deploy_secret`, `CF_ACCESS_ID = cloudflare_zero_trust_access_service_token.deploy.client_id`, `CF_ACCESS_SECRET = cloudflare_zero_trust_access_service_token.deploy.client_secret`, `APP_DOMAIN_BASE = var.app_domain_base`, `INFRA_DIR = path.module`.
  - Note: Terraform's `environment {}` block in local-exec provisioners DOES accept sensitive values (unlike command string interpolation which refuses). This is the standard pattern for passing secrets to local-exec.
- Add `infra-config-apply.sh` and `push-infra-config.sh` to the `triggers_replace` hash.

### Phase 3: Workflow simplification

**Edit `.github/workflows/apply-deploy-pipeline-fix.yml`:**
- Remove: cloudflared install step, CF Access SSH token extraction step, cloudflared SSH bridge startup + iptables NAT step, ssh-agent setup step, DEPLOY_SSH_PRIVATE_KEY verification step, host-key seeding step, cloudflared teardown step, "Generate CI public SSH key" step.
- Remove: `CLOUDFLARED_VERSION`, `CLOUDFLARED_SHA256` env vars.
- Remove: "Capture local hashes (pre-apply)" step and "Verify server-side file hashes match local" step (both use SSH).
- Keep: Terraform init, plan, apply steps (the local-exec provisioner inside the TF resource does the curl -- transparent to the workflow).
- Add: post-apply verification step that waits 5s (for self-restart), then GETs `/hooks/deploy-status` via curl with CF Access headers and asserts `webhook: active` in the JSON response. The existing `WEBHOOK_DEPLOY_SECRET` + `CF_ACCESS_CLIENT_ID` + `CF_ACCESS_CLIENT_SECRET` GitHub secrets are reused.
- Keep: "Auto-close any open drift issues" step (unchanged).

### Phase 4: Documentation + learning

Create a code comment block at the top of `infra-config-apply.sh` documenting the webhook self-restart state machine pattern (the `systemd-run --on-active=3s` approach, why the delay is needed, and the chicken-and-egg bootstrap for the first apply). A standalone learning file is optional -- the pattern is 3 lines of code and is adequately documented by a code comment + the PR description.

## Files to Edit

- `apps/web-platform/infra/server.tf` -- refactor `terraform_data.deploy_pipeline_fix` (remove SSH provisioners, add local-exec + environment block) AND add `infra_config_apply_script_b64` to cloud-init templatefile params
- `apps/web-platform/infra/hooks.json.tmpl` -- add `infra-config` hook with `pass-environment-to-command`
- `apps/web-platform/infra/webhook.service` -- add `/etc/sudoers.d` to ReadWritePaths (P1-B fix)
- `apps/web-platform/infra/cloud-init.yml` -- add `infra-config-apply.sh` to write_files + update inline webhook.service copy with new ReadWritePaths
- `.github/workflows/apply-deploy-pipeline-fix.yml` -- remove SSH bridge infrastructure, simplify post-apply verification

## Files to Create

- `apps/web-platform/infra/infra-config-apply.sh` -- hardcoded handler script for infra-config webhook endpoint (no generic JSON, reads env vars)
- `apps/web-platform/infra/infra-config-apply.test.sh` -- test suite for handler script
- `apps/web-platform/infra/push-infra-config.sh` -- standalone push script invoked by local-exec provisioner (constructs payload, computes HMAC, curls webhook)

## Open Code-Review Overlap

None

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|---|---|---|
| Keep SSH bridge (#4177 status quo) | Rejected | Works but 80+ lines of bridge infrastructure for a 10-second file push. Each component (cloudflared install, SHA pin, bridge startup, NAT redirect, known_hosts) is an independent failure surface. |
| Ansible/push tool over HTTPS | Rejected | New dependency; webhook already runs and is proven. |
| Embed files in Terraform `null_resource` + HTTP provider | Rejected | Terraform HTTP provider does not support HMAC signing or custom headers cleanly. local-exec + curl is simpler. |
| Base the handler on a separate HTTP server (not adnanh/webhook) | Rejected | Adds a second listener process. adnanh/webhook already provides HMAC auth, routing, and async execution. |

## Dependencies & Risks

### Dependencies

- The production webhook listener must be updated to include the `infra-config` hook BEFORE the first terraform apply that uses the new local-exec provisioner. This creates a **chicken-and-egg**: the very mechanism we are replacing (SSH provisioner) is what currently updates `hooks.json` on the host. **Resolution**: the first apply must be done from the operator's local machine via the existing SSH path (operator IP is in `admin_ips`). This one-time bootstrap apply pushes the new `hooks.json` + `infra-config-apply.sh` via SSH. All subsequent applies use the webhook path.
- CF Access service-token credentials must be available to the `local-exec` provisioner. These are Terraform-managed sensitive outputs from `tunnel.tf` (`cloudflare_zero_trust_access_service_token.deploy.client_id` and `.client_secret`). They are passed to the push script via the provisioner's `environment {}` block. For the CI workflow, they resolve from Terraform state during plan/apply. For operator-local applies, the same state file is used. The GitHub secrets `CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET` (used by `web-platform-release.yml`) are the same values -- they were initially seeded from Terraform outputs.

### Risks

| Risk | Mitigation |
|---|---|
| Webhook self-restart kills the HTTP response before 202 is returned | The 3-second `systemd-run --on-active=3s` delay gives the webhook binary time to flush the response. The deploy webhook already uses fire-and-forget (202 returned before ci-deploy.sh runs). Same timing applies -- the response is sent before any long-running work. |
| Handler script bug writes files with wrong permissions | Test suite (Phase 1) covers permission setting. visudo validation gate prevents malformed sudoers. Post-apply file-hash verification catches divergence. |
| local-exec provisioner fails on CI due to missing env vars | Workflow extracts Doppler secrets into env vars before terraform apply (existing pattern). |
| Payload too large for webhook binary | Total payload is ~100KB (6 files base64-encoded). adnanh/webhook default max body is 1MB. No issue. |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change with no user-facing impact.

## Test Scenarios

- Given the webhook listener is running with the new `infra-config` hook, when a valid HMAC-signed POST with base64-encoded file payloads is sent to `/hooks/infra-config`, then the handler writes all managed files atomically and returns 202.
- Given the handler writes files and runs post-commands successfully, when the self-restart is triggered, then `systemd-run --on-active=3s systemctl restart webhook` is scheduled and the 202 response is returned before the restart fires.
- Given the handler receives a request where a required env var (e.g., `CI_DEPLOY_SH_B64`) is missing or empty, then it exits non-zero and logs the error to journalctl.
- Given the handler receives a payload with a sudoers file, when `visudo -cf` fails validation on the staged file, then the staged file is NOT installed to `/etc/sudoers.d/` and an error is logged.
- Given `apply-deploy-pipeline-fix.yml` runs on a GitHub-hosted runner after a trigger-file merge, when terraform apply executes the local-exec provisioner, then the push script curls the webhook with 202 and no SSH connection is attempted.
- Given the post-apply verification step queries `/hooks/deploy-status`, when the webhook has self-restarted successfully, then the response includes `webhook: active`.

## References

- Issue: #3756
- Parent issue: #3723 (reframed to multi-tenant substrate only)
- Original decision: #749 (CI deploy SSH rule removed)
- CF Tunnel SSH bridge: #4177
- Draft PR: #3744 (merged, multi-tenant scaffolding -- separate scope)
- `apps/web-platform/infra/server.tf:216-327` (resource to refactor)
- `apps/web-platform/infra/tunnel.tf` (existing CF Tunnel substrate)
- `apps/web-platform/infra/hooks.json.tmpl` (existing webhook hooks)
- `apps/web-platform/infra/firewall.tf:15` (CI SSH rule removal comment)
- `.github/workflows/apply-deploy-pipeline-fix.yml` (workflow to simplify)
- `knowledge-base/project/learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`
- `knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`
- `knowledge-base/project/learnings/2026-03-21-async-webhook-deploy-cloudflare-timeout.md`
- `knowledge-base/project/learnings/2026-05-18-plan-baked-in-operator-ssh-violated-iac-rule.md`

## Sharp Edges

- **Chicken-and-egg bootstrap**: The first apply after this PR merges must use the OLD SSH path (operator-local apply) to push the new handler script + hooks.json to the host. This uses operator-local SSH (operator IP is in `admin_ips`, always available). After that one-time bootstrap, all subsequent applies use the webhook path. This is explicitly noted in AC13 and must be documented in the PR body as a "Post-merge (operator)" step.
- **webhook.service ReadWritePaths**: [RESOLVED in plan] `/etc/sudoers.d` added to AC6. The handler runs inside the webhook service's mount namespace (`ProtectSystem=strict`). The SSH provisioner wrote to `/tmp/` first (outside the namespace) then `install`'d; the handler runs inside, so `/etc/sudoers.d` must be explicitly listed.
- **Terraform sensitive values in local-exec**: [RESOLVED in plan] `var.webhook_deploy_secret` and CF Access token outputs are `sensitive = true`. Terraform >= 1.0 refuses to interpolate sensitive values into `local-exec` command strings. The push script receives them via the provisioner's `environment {}` block (which does accept sensitive values).
- **HMAC computation in push script**: The push script (`push-infra-config.sh`) computes `HMAC-SHA256(secret, body)` using `echo -n "$BODY" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" -binary | xxd -p -c 256`. The `openssl` and `xxd` commands are available on Ubuntu runner images and macOS operator machines.
- **Payload passing to handler**: The handler uses `pass-environment-to-command` (same pattern as the existing deploy hook), not stdin or argument passing. Each base64-encoded file content is a separate env var. This avoids the need for JSON parsing or jq on the host.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.**

## Plan Review Applied

3-agent review (DHH + Kieran + Code Simplicity) completed 2026-05-26. Applied changes:
- **P0-A**: Replaced generic JSON payload schema with hardcoded file list in handler script (DHH + Simplicity + Kieran).
- **P0-B**: Extracted curl logic into standalone `push-infra-config.sh`; sensitive values passed via `environment {}` block (Kieran).
- **P0-C**: Fixed AC1 verification command to scope to deploy_pipeline_fix resource block using awk (Kieran).
- **P1-A**: Documented one-time operator-local SSH bootstrap explicitly in AC13 and Sharp Edges (Kieran).
- **P1-B**: Added `/etc/sudoers.d` to webhook.service ReadWritePaths in AC6 and Phase 1 (Kieran).
- **P1-C**: Cut Phase 6 (file-hash verification in cat-deploy-state.sh). Post-apply verification simplified to 202 + webhook-active check. Drift cron provides content-level verification (Simplicity).
- **P1-D**: Collapsed 7 phases to 4 phases (DHH).
- **P2-B**: Committed to `pass-environment-to-command` pattern (Kieran).
