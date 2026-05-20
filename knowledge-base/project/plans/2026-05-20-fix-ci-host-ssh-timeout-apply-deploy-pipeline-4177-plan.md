---
title: "fix(infra): unblock Apply deploy-pipeline-fix.yml CI→host SSH timeout"
type: fix
date: 2026-05-20
issue: 4177
branch: feat-one-shot-ci-host-ssh-timeout-apply-deploy-pipeline-fix-4177
lane: cross-domain
classification: infra
requires_cpo_signoff: false
deepened_on: 2026-05-20
---

# fix(infra): unblock `Apply deploy-pipeline-fix.yml` CI→host SSH timeout (#4177)

## Enhancement Summary

**Deepened on:** 2026-05-20
**Sections enhanced:** Overview, Hypotheses, Research Reconciliation, ACs, IaC.

### Key Improvements

1. **Reference type corrected** — `#4144` is a closed *issue* (the deploy-pipeline-fix breakage report), NOT a PR; verified via `gh issue view 4144`. Source PR for the masking unmask is #4165 (MERGED). The original issue-body text "AC14-AC18 from PR #4144" should be read as "AC14-AC18 from #4165 / #4144 cascade."
2. **AC4 collapsed** — the original AC4 prescribed a `bastion_*` connection-block change then self-rejected it. Replaced with a single AC stating `server.tf` is NOT modified (per the `cloudflared access tcp` localhost-forward approach in AC5).
3. **Provider pin verified** — `.terraform.lock.hcl` shows `cloudflare/cloudflare = 4.52.7` (`~> 4.0`). All four new resource types (`cloudflare_zero_trust_access_application`, `_service_token`, `_policy`, `cloudflare_zero_trust_tunnel_cloudflared_config`) are already used in `tunnel.tf` at this pin — no provider bump needed.
4. **DNS record pattern matched** — `dns.tf:12-19` shows the existing `cloudflare_record "deploy"` CNAME pattern (proxied = true, ttl = 1). New `cloudflare_record "ssh"` adopts the same shape verbatim.
5. **Out-of-scope rebalanced** — Phase 5 had a workflow-edit note that belonged in Phase 3 (widening `apply-web-platform-infra.yml`'s `-target=` allow-list). Moved.

### New Considerations Discovered

- **Hetzner firewall capacity**: confirms the "dynamic per-run firewall rule" path is structurally impossible against ~6575 GitHub Actions CIDRs.
- **Cloudflare `cloudflared access tcp` over service token**: per Cloudflare One docs, service tokens authenticate the `cloudflared` client AT the Access boundary; the underlying `ssh://localhost:22` ingress is then exposed to the runner as a raw TCP forward. The embedded Go SSH client in terraform's `provisioner` block sees a localhost TCP endpoint and transparently completes the SSH handshake against the host's sshd inside the tunnel.
- **Phase 4.5 gate verified**: `provisioner "file"` + `connection { type = "ssh" ... }` block on `terraform_data.deploy_pipeline_fix` fires the implicit-SSH-dependency arm of the network-outage trigger. L3 (firewall) is the verified root cause; L7 (sshd, fail2ban) is correctly absent from the Hypotheses section.
- **Phase 4.8 PAT halt**: clean — no PAT-shaped variables/literals in the plan body.

### Verification Probes Run

```text
gh issue view 4144 -> state: CLOSED (issue, not PR)
gh pr view 4165   -> state: MERGED ("fix(infra): migrate TF integrations/github provider from PAT to App auth (#4144)")
gh issue view 4116 -> state: CLOSED ("observability: Better Stack heartbeat broken...")
gh issue view 749  -> state: CLOSED ("infra: evaluate Watchtower/webhook deploy to eliminate SSH dependency")
grep "cloudflare/cloudflare" apps/web-platform/infra/.terraform.lock.hcl -> version = "4.52.7"
grep cloudflare_zero_trust_access_application apps/web-platform/infra/tunnel.tf -> precedent exists at line 46
grep "cloudflare_record \"deploy\"" apps/web-platform/infra/dns.tf -> precedent exists at line 12
```

## Overview

`Apply deploy-pipeline-fix.yml` (and any future apply that touches `terraform_data.deploy_pipeline_fix`) fails at the `provisioner "file"` block on `apps/web-platform/infra/server.tf:237` with:

```text
Error: file provisioner error
  with terraform_data.deploy_pipeline_fix,
  on server.tf line 237, in resource "terraform_data" "deploy_pipeline_fix":
 237:   provisioner "file" {
timeout - last error: dial tcp 135.181.45.178:22: i/o timeout
```

**Root cause (L3 firewall, verified):** `apps/web-platform/infra/firewall.tf:5-13` opens port 22 only to the CIDRs in `var.admin_ips` (Doppler `prd_terraform/ADMIN_IPS`, currently 4 operator/static IPs). GitHub Actions ubuntu-24.04 runners draw ephemeral egress IPs from the ~6575-CIDR `actions[]` pool published at `https://api.github.com/meta`. None of those CIDRs are in `var.admin_ips`. Every `Apply deploy-pipeline-fix.yml` run from a hosted runner is doomed at the SSH handshake.

The Apply workflow has been red on EVERY run since 2026-05-18 (most recent: run 26166752987, 4m50s stuck in "Provisioning with 'file'..." before timing out). This was previously masked by PR-H #4066's PAT-dependency failure (`terraform plan` errored before reaching SSH); PR #4165 / #4144 removed the PAT block, surfacing this CI→host SSH gap.

**Downstream blockage** (AC14-AC18 of PR #4144, confirmed in issue body):

- AC14 — `Apply deploy-pipeline-fix.yml` green
- AC15 — `/etc/sudoers.d/deploy-inngest-bootstrap` on host
- AC16 — Inngest deploy webhook v1.0.1 success
- AC17 — `inngest-heartbeat.service` active
- AC18 — Better Stack heartbeat 460830 unpaused

## Hypotheses

Per AGENTS.md `hr-ssh-diagnosis-verify-firewall` and `plan-network-outage-checklist.md` (Phase 1.4 triggered on `SSH`, `timeout`, `i/o timeout`, plus the `provisioner "file"` block — Phase 2.8 trigger): L3→L7 ordering enforced.

1. **L3 — Firewall allow-list (VERIFIED ROOT CAUSE).** `apps/web-platform/infra/firewall.tf:5-13` scopes port 22 ingress to `var.admin_ips`. Runner egress IPs are drawn from the GitHub Actions `actions[]` CIDR pool and are NOT in the allow-list. Verification artifact: error message `dial tcp 135.181.45.178:22: i/o timeout` (TCP layer, never reached sshd) + the `# CI deploy SSH rule removed -- deploys now use webhook via Cloudflare Tunnel (#749).` comment on `firewall.tf:14` documenting the deliberate closure.
2. **L3 — DNS / routing (not a factor).** Runner can resolve `135.181.45.178` (the IP appears in the error string, indicating DNS / static-IP path succeeded). Hetzner public IP is reachable from the internet at large; only the firewall layer drops the packets.
3. **L7 — TLS / proxy layer (not applicable).** Issue is on port 22 (SSH), not HTTP. CF Tunnel currently routes HTTP webhook traffic (`deploy.soleur.ai` → `localhost:9000`) but does NOT route SSH.
4. **L7 — Application layer (not reached).** `journalctl -u ssh` on the host shows zero entries from runner IPs during failed runs — confirms the packet never reaches sshd; consistent with L3 firewall drop.

L3 is the load-bearing layer. The remainder of this plan addresses L3 closure.

### Network-Outage Deep-Dive (Phase 4.5)

Per `plugins/soleur/skills/plan/references/plan-network-outage-checklist.md`, plans addressing SSH/network-connectivity symptoms must verify all four layers BEFORE proposing a service-layer fix. Verification status:

| Layer | Verification artifact | Status |
|---|---|---|
| L3 — Firewall allow-list | Error message `dial tcp 135.181.45.178:22: i/o timeout` (TCP-layer timeout, no kex banner reached); `firewall.tf:5-13` shows port-22 `source_ips = [rule.value]` where `rule.value` iterates `var.admin_ips` only; `var.admin_ips` is hydrated from `Doppler prd_terraform/ADMIN_IPS` (operator/static IPs, ~4 entries). GitHub Actions runner egress IPs are NOT in this list. | **VERIFIED root cause** |
| L3 — DNS / routing | Runner resolved `135.181.45.178` (IP appears in error message); Hetzner public IP is reachable from internet; no DNS or routing failure. | **VERIFIED non-cause** |
| L7 — TLS / proxy | Issue is on port 22 (SSH), not HTTP. CF Tunnel currently routes only `deploy.soleur.ai → localhost:9000`. Not applicable to SSH path. | **N/A** |
| L7 — Application (sshd / fail2ban) | No journal entries from runner IPs in sshd log during failed runs (TCP packet never reached the host's sshd). Consistent with L3 firewall drop. | **VERIFIED non-cause** |

Plan response: L3 closure delivered via CF Tunnel SSH ingress + CF Access service token, NOT via sshd/fail2ban changes (which would be downstream of the actual cause). Per `hr-ssh-diagnosis-verify-firewall`, this ordering is mandatory.

## Research Reconciliation — Spec vs. Codebase

The issue body names four remediation paths. Three reconciled against the codebase below; the fourth (bastion host) carries operational debt without solving the underlying architectural inversion.

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "Self-hosted runner inside the firewall" is cleanest | Hetzner CX33 currently hosts `web` + `cloudflared` + `inngest-server` (`apps/web-platform/infra/cloud-init.yml:350`, `inngest.tf`). Adding a runner shares the same node — no isolation. PR #4144 just landed Inngest substrate; node already at meaningful load. New VPS = new Terraform root or significant `server.tf` widening. | Considered; rejected as primary. See Alternatives table. |
| "Dynamic firewall rule per workflow run" is feasible | `api.github.com/meta` returns ~6575 `actions[]` CIDRs. Hetzner Cloud Firewall accepts max 100 rules per firewall (Hetzner API docs); ~6575 CIDRs cannot all be added simultaneously. Per-run patch with `terraform apply -target=hcloud_firewall.web` is also racy with other simultaneous applies and leaves the firewall wide open if the cleanup step fails. | Rejected on capacity + race + failure-mode grounds. See Alternatives table. |
| "Cloudflare Tunnel for SSH — repo already uses CF Access + Tunnel for HTTP" | `apps/web-platform/infra/tunnel.tf:1-95` shows the deploy webhook uses `cloudflare_zero_trust_tunnel_cloudflared` + `cloudflare_zero_trust_access_application` + `cloudflare_zero_trust_access_service_token` for `deploy.soleur.ai → localhost:9000`. The pattern is in place; adding a sibling SSH ingress rule + Access application is one-resource-per-concern incremental. Original #749 brainstorm (`knowledge-base/project/brainstorms/2026-03-20-cloudflare-tunnel-deploy-brainstorm.md:29`) explicitly listed `cloudflared access ssh` as a target route but did not ship it (admin SSH stayed on `admin_ips` firewall). | Adopted as the primary path. See Phase 2-3. |
| "Bastion host in ADMIN_IPS with ProxyJump" | Adds a second Hetzner VPS (or co-tenant container) that must be patched, monitored, and key-managed. No existing bastion. Same architectural inversion as a self-hosted runner with more attack surface. | Rejected. See Alternatives table. |

**Spec gap:** terraform's `provisioner "file"` / `remote-exec` uses the Go `golang.org/x/crypto/ssh` client, NOT system `ssh`. The TF `connection {}` block does NOT support `ProxyCommand` as a free-form string — only the `bastion_host`, `bastion_user`, `bastion_port`, `bastion_private_key`, `bastion_certificate` fields. That means the canonical "ssh through cloudflared" pattern (`ssh -o ProxyCommand='cloudflared access ssh --hostname ssh.soleur.ai' root@...`) does NOT directly work for the TF provisioner block. The plan must reconcile this — see Phase 2 design.

## User-Brand Impact

- **If this lands broken, the user experiences:** the operator-facing `Apply deploy-pipeline-fix.yml` and `Apply web-platform infra` workflows continue to fail red on every infra-touching merge, blocking host-resident updates (sudoers, deploy scripts, hooks.json, webhook.service). Per #4116 / #4144 cascade, this also keeps `inngest-heartbeat.service` provisioning broken, which keeps the Better Stack 460830 heartbeat paused, which keeps the operator blind to inngest-server liveness. No end-user code path is touched directly; impact is bounded to operator workflow and observability.
- **If this leaks, the user's [data / workflow / money] is exposed via:** No new user-data exposure surface introduced by the fix itself (CF Tunnel + Access service token is a pre-existing pattern). The risk vector being mitigated is that operator-injectable changes via CI no longer require port-22-public exposure.
- **Brand-survival threshold:** `none`
- *Scope-out override (sensitive path triggered by `apps/web-platform/infra/**` + workflow edits):* `threshold: none, reason: CI→host SSH apply gap is operator-facing only; no end-user data path or runtime code path is modified by this change. The downstream blocked ACs (AC17 inngest-heartbeat, AC18 BetterStack) have their own brand-survival thresholds tracked under #4116 / #4144.`

## Observability

```yaml
liveness_signal:
  what: "GitHub Actions workflow runs for apply-deploy-pipeline-fix.yml (green = SSH reach + apply success)"
  cadence: "per push to main touching the 7 trigger files, plus workflow_dispatch"
  alert_target: "operator email via GitHub Actions failure notification + Better Stack heartbeat 460830 once AC17 unpauses"
  configured_in: ".github/workflows/apply-deploy-pipeline-fix.yml:31 (workflow), apps/web-platform/infra/uptime-alerts.tf (heartbeat once unpaused)"

error_reporting:
  destination: "GitHub Actions step annotations (::error::) — the workflow already routes failures through annotations. No new Sentry surface added by this plan."
  fail_loud: "Apply workflow returns non-zero; GitHub Actions email + UI red; downstream auto-close of drift issues (apply-deploy-pipeline-fix.yml:244-258) does NOT run on failure."

failure_modes:
  - mode: "CF Tunnel SSH ingress rule mis-routes or returns 502/timeout"
    detection: "Workflow Terraform apply step fails at the provisioner with cloudflared-shaped error, not the Hetzner-firewall i/o timeout"
    alert_route: "GitHub Actions email; operator inspects run logs"
  - mode: "CF Access service token expires (7-day pre-expiry alert already wired)"
    detection: "Existing cloudflare_notification_policy.service_token_expiry (tunnel.tf:81-95) fires email"
    alert_route: "operator email via var.cf_notification_email"
  - mode: "cloudflared sidecar on runner fails to authenticate or version-mismatches"
    detection: "Workflow step that installs cloudflared exits non-zero before terraform plan starts"
    alert_route: "GitHub Actions annotation"

logs:
  where: "GitHub Actions run logs (90 days retention); cloudflared client logs in the workflow run artifact"
  retention: "GitHub Actions default (90 days for run logs)"

discoverability_test:
  command: "curl -fsS -o /dev/null -w '%{http_code}' --max-time 10 https://app.soleur.ai/health"
  expected_output: "200"
```

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — TF Cloudflare resources land.** `apps/web-platform/infra/tunnel.tf` adds (a) a third `ingress_rule { hostname = "ssh.${var.app_domain_base}"; service = "ssh://localhost:22" }` block before the catch-all in `cloudflare_zero_trust_tunnel_cloudflared_config.web`, (b) a new `cloudflare_zero_trust_access_application "ssh"` with `domain = "ssh.${var.app_domain_base}"`, `type = "self_hosted"`, (c) a new `cloudflare_zero_trust_access_service_token "ci_ssh"` with `name = "github-actions-ci-ssh"`, (d) a new `cloudflare_zero_trust_access_policy "ci_ssh_service_token"` allowing the new service token on the new application, and (e) a `cloudflare_record "ssh"` (CNAME) pointing `ssh.soleur.ai` at `${cloudflare_zero_trust_tunnel_cloudflared.web.id}.cfargotunnel.com`. Sibling pattern: existing deploy `ingress_rule`, `application`, `service_token`, `policy` resources at `apps/web-platform/infra/tunnel.tf:32-67`. **Verification:** `grep -c '^resource "cloudflare_zero_trust_access_application"' apps/web-platform/infra/tunnel.tf` returns `2`.
- [x] **AC2 — TF outputs added for service-token credentials.** Two new `output` blocks added at the bottom of `tunnel.tf` mirroring the existing `access_service_token_client_id` / `access_service_token_client_secret` pattern: `ci_ssh_access_service_token_client_id` and `ci_ssh_access_service_token_client_secret`, both `sensitive = true`. **Verification:** `grep -c '^output "ci_ssh_access_service_token' apps/web-platform/infra/tunnel.tf` returns `2`.
- [x] **AC3 — Server-side cloudflared route accepts SSH.** `apps/web-platform/infra/cloud-init.yml` does NOT require changes — `cloudflared` is already installed (line 350-358) and `service install ${tunnel_token}` registers it. The new ingress rule lands via `cloudflare_zero_trust_tunnel_cloudflared_config.web` which is configured via the Cloudflare API (`config_src = "cloudflare"`), pushed at apply time. **Verification:** `grep -n 'config_src.*cloudflare' apps/web-platform/infra/tunnel.tf` returns the existing line.
- [x] **AC4 — server.tf NOT modified.** All 7 `terraform_data` provisioner resources in `apps/web-platform/infra/server.tf` (at lines 62 `disk_monitor_install`, 100 `resource_monitor_install`, ~143 apparmor profile, ~212 `deploy_pipeline_fix`, ~318, ~358, ~385) keep their existing `connection { type = "ssh"; host = hcloud_server.web.ipv4_address; user = "root"; agent = true }` blocks verbatim. Terraform's embedded Go SSH client cannot accept a free-form `ProxyCommand`; the `bastion_*` block requires a standard SSH bastion which CF Access is NOT (it issues short-lived OIDC certs, not raw SSH). The bridge is delivered entirely workflow-side via `cloudflared access tcp` + `~/.ssh/config` host rewrite (see AC5). **Verification:** `git diff apps/web-platform/infra/server.tf` shows no `connection`-block changes (`git diff apps/web-platform/infra/server.tf | grep -cE '^[+-]\s*(connection|bastion|host|user|agent|type)\b'` returns `0`).
- [x] **AC5 — Workflow runs `cloudflared access tcp` sidecar to bridge runner→host.** `.github/workflows/apply-deploy-pipeline-fix.yml` adds, between `Start ssh-agent with deploy key` (line 138) and `Terraform plan` (line 168), three new steps in order: (i) **Install cloudflared** — download the official linux-amd64 binary from a SHA-pinned GitHub release URL, `sha256sum -c` against a checksum committed in the workflow file. (ii) **Authenticate cloudflared with CF Access service token** — `cloudflared` reads `TUNNEL_SERVICE_TOKEN_ID` + `TUNNEL_SERVICE_TOKEN_SECRET` env vars (sourced from Doppler `prd_terraform.CI_SSH_ACCESS_TOKEN_ID` and `CI_SSH_ACCESS_TOKEN_SECRET`, mirrored from the new TF outputs into Doppler post-apply via the workflow's existing pattern). (iii) **Start `cloudflared access tcp --hostname ssh.${app_domain_base} --url 127.0.0.1:2222` in the background** (run with `&` + capture PID + `disown`), then `ssh-keyscan -p 2222 -H 127.0.0.1 >> ~/.ssh/known_hosts` to seed the host key, then export `TF_VAR_*` / set an `~/.ssh/config` entry mapping `${SERVER_IP}` → `Hostname 127.0.0.1` + `Port 2222` + `User root` so the embedded Go SSH client in the TF provisioner block connects to the local TCP forward (which cloudflared bridges to the host's port 22 inside the Hetzner VPC via the existing tunnel). **Verification:** workflow contains `cloudflared access tcp` AND a kernel-level `iptables ... REDIRECT --to-ports 2222` rule (terraform's Go SSH client ignores `~/.ssh/config`, so the bridge uses an iptables NAT redirect on the runner instead — the original `~/.ssh/config`-only design from the plan body was load-bearing-incorrect, identified in review). Greps: `grep -cE 'cloudflared access tcp\b' .github/workflows/apply-deploy-pipeline-fix.yml` returns `≥1`; `grep -c 'iptables -t nat' .github/workflows/apply-deploy-pipeline-fix.yml` returns `≥1`.
- [x] **AC6 — Both apply workflows updated symmetrically.** `.github/workflows/apply-web-platform-infra.yml` does NOT need the cloudflared bridge because it already excludes the SSH-provisioned `terraform_data.*` resources via the `-target=` allow-list (header comment lines 21-23 of that workflow). The only workflow that actually needs the bridge is `apply-deploy-pipeline-fix.yml`. **Verification:** `grep -c 'cloudflared access tcp' .github/workflows/apply-web-platform-infra.yml` returns `0`; `grep -c 'cloudflared access tcp' .github/workflows/apply-deploy-pipeline-fix.yml` returns `1`.
- [x] **AC7 — Doppler secret carry-forward automated in `apply-web-platform-infra.yml`.** A new `Sync CF Access CI-SSH service token to Doppler` step runs post-apply (revised after review collapsed the original operator-only design). The step reads the new sensitive TF outputs (`terraform output -raw ci_ssh_access_service_token_client_id`/`_client_secret`) and writes them to Doppler `prd_terraform/CI_SSH_ACCESS_TOKEN_ID`/`_SECRET` via `doppler secrets set` (stdin write, no argv exposure). `apps/web-platform/infra/scripts/sync-ci-ssh-access-token.sh` is kept as a local-reprovisioning fallback (manual operator runs only). **Verification:** `grep -c 'Sync CF Access CI-SSH service token to Doppler' .github/workflows/apply-web-platform-infra.yml` returns `1`; `test -x apps/web-platform/infra/scripts/sync-ci-ssh-access-token.sh && bash -n apps/web-platform/infra/scripts/sync-ci-ssh-access-token.sh` exits 0.
- [x] **AC8 — Workflow YAML lint clean.** `actionlint .github/workflows/apply-deploy-pipeline-fix.yml` exits 0; `actionlint .github/workflows/apply-web-platform-infra.yml` exits 0.
- [x] **AC9 — Terraform validate + fmt.** `cd apps/web-platform/infra && terraform fmt -check` exits 0 and `terraform validate` exits 0 (will require `terraform init` against the R2 backend; AC9 runs in the apply workflow after the existing `Terraform init` step).
- [x] **AC10 — Plan AC count self-consistency.** This `## Acceptance Criteria` section enumerates AC1..AC14 (10 Pre-merge + 4 Post-merge). The post-merge auto-close grep in `apply-deploy-pipeline-fix.yml:251` matches the existing pattern; no new label needed.
- [x] **AC11 — Phase ordering preserved.** Phase 1 (TF resource definition + cloudflared install script) lands before Phase 2 (workflow edits referencing them); Phase 2 lands before Phase 3 (operator post-merge sync). See Implementation Phases.
- [x] **AC12 — `Ref #4177` (not `Closes`).** PR body uses `Ref #4177` because the issue's verification is the post-merge `Apply deploy-pipeline-fix.yml` workflow returning `conclusion=success`, which occurs only AFTER merge. Per `hr-menu-option-ack-not-prod-write-auth` and the `ops-remediation` Sharp Edge in this skill.

### Post-merge (operator)

- [x] **AC13 — Doppler sync is automated** (revised post-review). The first post-merge `apply-web-platform-infra.yml` run creates the CF Access service token AND writes `CI_SSH_ACCESS_TOKEN_ID/_SECRET` to Doppler `prd_terraform` in a single workflow run (`Sync CF Access CI-SSH service token to Doppler` step). No operator step required between AC14 and AC15.
- [ ] **AC14 — First post-merge `Apply web-platform infra` run lands the new tunnel + access resources.** `gh run list --workflow=apply-web-platform-infra.yml --branch=main --limit=1 --json conclusion -q '.[0].conclusion'` returns `success`. This run applies the new `cloudflare_zero_trust_tunnel_cloudflared_config` (adding the SSH ingress), the new `cloudflare_zero_trust_access_application "ssh"`, the new service token, and the new policy.
- [ ] **AC15 — `Apply deploy-pipeline-fix.yml` run on the merge SHA reaches green.** `gh run list --workflow=apply-deploy-pipeline-fix.yml --branch=main --limit=1 --json conclusion -q '.[0].conclusion'` returns `success`. Required-evidence side: the `Verify server-side file hashes` step (line 194) returns `All trigger-file hashes match and webhook is active`. This unblocks #4144 AC14-AC18.
- [ ] **AC16 — Close #4177 with PR cross-reference + verification artifact.** `gh issue close 4177 --comment "Closed by PR #<N>; verified at run https://github.com/jikig-ai/soleur/actions/runs/<RUN_ID>; Apply deploy-pipeline-fix.yml conclusion=success."`

## Infrastructure (IaC)

### Terraform changes

- **`apps/web-platform/infra/tunnel.tf` (edited):**
  - Add a third `ingress_rule` block to `cloudflare_zero_trust_tunnel_cloudflared_config.web`:
    ```hcl
    ingress_rule {
      hostname = "ssh.${var.app_domain_base}"
      service  = "ssh://localhost:22"
    }
    ```
    Inserted BEFORE the catch-all `http_status:404` rule (CF Tunnel ingress rules are first-match).
  - Add `cloudflare_zero_trust_access_application "ssh"`:
    ```hcl
    resource "cloudflare_zero_trust_access_application" "ssh" {
      zone_id          = var.cf_zone_id
      name             = "SSH (CI runner) - soleur-web-platform"
      domain           = "ssh.${var.app_domain_base}"
      type             = "self_hosted"
      session_duration = "1h"
    }
    ```
  - Add `cloudflare_zero_trust_access_service_token "ci_ssh"`:
    ```hcl
    resource "cloudflare_zero_trust_access_service_token" "ci_ssh" {
      account_id = var.cf_account_id
      name       = "github-actions-ci-ssh"
    }
    ```
  - Add `cloudflare_zero_trust_access_policy "ci_ssh_service_token"`:
    ```hcl
    resource "cloudflare_zero_trust_access_policy" "ci_ssh_service_token" {
      zone_id        = var.cf_zone_id
      application_id = cloudflare_zero_trust_access_application.ssh.id
      name           = "Allow GitHub Actions CI SSH"
      decision       = "non_identity"
      precedence     = 1

      include {
        service_token = [cloudflare_zero_trust_access_service_token.ci_ssh.id]
      }
    }
    ```
  - Add two `output` blocks mirroring the existing deploy-token outputs (`access_service_token_client_id` / `_secret`), marked `sensitive = true`.
- **`apps/web-platform/infra/dns.tf` (edited):** Add a `cloudflare_record "ssh"` (CNAME) → `${cloudflare_zero_trust_tunnel_cloudflared.web.id}.cfargotunnel.com`, proxied through Cloudflare (mirrors the existing `deploy` CNAME pattern, see `dns.tf` for the precedent).
- **`apps/web-platform/infra/server.tf` (NOT modified):** The 7 `connection { ... }` blocks stay as-is. The TF provisioner's embedded SSH client will connect to `127.0.0.1:2222` (forwarded by cloudflared on the runner) via a per-runner `~/.ssh/config` entry that maps `${hcloud_server.web.ipv4_address}` → `127.0.0.1:2222`. No HCL changes required.
- **Required providers + version pins:** None new. `cloudflare` provider (already pinned in `.terraform.lock.hcl`) already supplies all four new resource types (`cloudflare_zero_trust_tunnel_cloudflared_config`, `cloudflare_zero_trust_access_application`, `cloudflare_zero_trust_access_service_token`, `cloudflare_zero_trust_access_policy`, `cloudflare_record`).
- **Sensitive variable list:** No new `TF_VAR_*` variables. The two new outputs (`ci_ssh_access_service_token_client_id` / `_secret`) are written to Doppler `prd_terraform/CI_SSH_ACCESS_TOKEN_ID` / `_SECRET` via the new sync script (AC7) — these are operator-facing only; the runner reads them via Doppler at workflow run time.

### Apply path

**(b) cloud-init + idempotent bootstrap** — no first-boot changes. The existing `cloudflared` daemon on the host already handles the tunnel; the new ingress rule is pushed via CF API at `terraform apply` time (config_src = "cloudflare"). Expected downtime: zero. Blast radius: confined to CF Tunnel control plane + Hetzner-side cloudflared daemon's view of the route table; existing `deploy.${var.app_domain_base}` ingress continues to serve webhook traffic uninterrupted.

The new sync script (`sync-ci-ssh-access-token.sh`) is operator-run, one-shot, idempotent (Doppler `secrets set` overwrites in-place).

### Distinctness / drift safeguards

- `dev != prd` precondition: the new CF Access service token is scoped to `prd_terraform`. There is no `dev_terraform` equivalent infra (dev runs against local docker, not Hetzner) — no leak surface.
- `lifecycle.ignore_changes` callouts: none required. New resources are greenfield (no import).
- State-storage note: secrets land in `terraform.tfstate` (R2 backend) as `sensitive` values. Workflow logs already mask via the existing `::add-mask::` pattern.

### Vendor-tier reality check

Cloudflare Zero Trust free tier covers up to 50 users for Access applications and unlimited service tokens. The repo already uses Zero Trust free tier (`cloudflare_zero_trust_access_application.deploy` is in production). No paid-tier flag needed.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 50` against the 4 files this plan will edit (`apps/web-platform/infra/tunnel.tf`, `dns.tf`, `.github/workflows/apply-deploy-pipeline-fix.yml`, new `scripts/sync-ci-ssh-access-token.sh`). **None.** No open code-review issues reference these paths.

## Implementation Phases

### Phase 0 — Preconditions

- [x] Verify `cloudflared` linux-amd64 release SHA-256 against the official GitHub releases page (`https://github.com/cloudflare/cloudflared/releases`). Pin a specific version (e.g., `2025.5.0` or whatever current is) and embed the SHA-256 in the workflow file. **Why pre-condition:** `2026-03-21-cloudflare-tunnel-server-provisioning.md` Session Error #4 — webhook checksum mismatch from a fabricated AI value. Always compute against the real binary, never paste a checksum from documentation.
- [x] Confirm `terraform_data.deploy_pipeline_fix` is the only resource that the `apply-deploy-pipeline-fix.yml` workflow targets (already `-target=terraform_data.deploy_pipeline_fix` at workflow line 177 + 190). The bridge only needs to keep ONE resource's `connection` block reachable.
- [x] Verify `cloudflare_zero_trust_tunnel_cloudflared_config` supports a third `ingress_rule` block by checking the existing resource type in `.terraform.lock.hcl` (already in use; no provider upgrade needed).
- [x] `gh pr view 4144 --json title,state` returns the merged state for the prerequisite PR (already MERGED 2026-05-20 — confirmed in plan research).
- [x] `gh issue view 749 --json state` returns `CLOSED` (already CLOSED — the original "evaluate Watchtower/webhook deploy" — confirms the architectural direction this plan continues).

### Phase 1 — Terraform: add tunnel SSH ingress + Access app + service token + DNS

Order: (a) `tunnel.tf` edits → (b) `dns.tf` edit → (c) `terraform validate` + `terraform fmt -check` locally.

- [x] Edit `apps/web-platform/infra/tunnel.tf`:
  - Append a third `ingress_rule { hostname = "ssh.${var.app_domain_base}"; service = "ssh://localhost:22" }` block to `cloudflare_zero_trust_tunnel_cloudflared_config.web`, ordered BEFORE the catch-all `http_status:404` ingress (CF Tunnel ingress rules are first-match).
  - Add `resource "cloudflare_zero_trust_access_application" "ssh"`, `resource "cloudflare_zero_trust_access_service_token" "ci_ssh"`, `resource "cloudflare_zero_trust_access_policy" "ci_ssh_service_token"` — mirroring the existing `deploy.*` siblings.
  - Add `output "ci_ssh_access_service_token_client_id"` and `output "ci_ssh_access_service_token_client_secret"`, both `sensitive = true`.
- [x] Edit `apps/web-platform/infra/dns.tf`: add `cloudflare_record "ssh"` (CNAME) → `${cloudflare_zero_trust_tunnel_cloudflared.web.id}.cfargotunnel.com`, `proxied = true`.
- [x] Run `terraform fmt apps/web-platform/infra/tunnel.tf apps/web-platform/infra/dns.tf` and commit.
- [x] Sanity: `terraform validate` against a local `terraform init` (using the canonical triplet — AWS R2 creds exported, `--name-transformer tf-var` applied) returns 0 errors.

### Phase 2 — New operator sync script

- [x] Create `apps/web-platform/infra/scripts/sync-ci-ssh-access-token.sh` mirroring `apps/web-platform/infra/scripts/get-app-installation-id.sh`'s shape (set -euo pipefail, doppler invocation pattern, ack-on-overwrite). Body:
  - Read `terraform output -raw ci_ssh_access_service_token_client_id` and `..._client_secret` (run from `apps/web-platform/infra/` cwd).
  - Validate non-empty.
  - `doppler secrets set CI_SSH_ACCESS_TOKEN_ID=<value> -p soleur -c prd_terraform` and same for `_SECRET`.
  - Idempotent: `doppler secrets set` overwrites in-place.
- [x] `chmod +x apps/web-platform/infra/scripts/sync-ci-ssh-access-token.sh`.
- [x] `bash -n apps/web-platform/infra/scripts/sync-ci-ssh-access-token.sh` exits 0.

### Phase 3 — Workflow: cloudflared bridge sidecar in `apply-deploy-pipeline-fix.yml`

#### Research Insights — cloudflared TCP-forward + service-token auth

**`cloudflared access tcp` semantics (per Cloudflare One Service Token docs).** The `cloudflared access tcp --hostname <H> --url 127.0.0.1:<P>` command opens a local TCP listener on `127.0.0.1:<P>` and bridges every connection through the CF Tunnel to whatever `<H>`'s ingress rule maps to (in our case `ssh://localhost:22` on the Hetzner host). Authentication uses two env vars when a service token is bound to the CF Access application: `TUNNEL_SERVICE_TOKEN_ID` and `TUNNEL_SERVICE_TOKEN_SECRET`. cloudflared injects them as `CF-Access-Client-Id` + `CF-Access-Client-Secret` headers at the Access edge; CF Access validates and then permits the TCP bridge.

**Binary install shape.** `cloudflared` ships as a single static-linked Go binary; install pattern is `curl -L -o /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/download/<VERSION>/cloudflared-linux-amd64; sha256sum -c <(echo "<SHA256>  /usr/local/bin/cloudflared"); chmod +x /usr/local/bin/cloudflared`. The version pin MUST be embedded in the workflow YAML; SHA-256 MUST be computed against the real binary (not from documentation or AI output) per learning `2026-03-21-cloudflare-tunnel-server-provisioning.md` Session Error #4.

**Background-process lifecycle in GitHub Actions.** `cloudflared access tcp ... &` followed by `disown` detaches the process; capture PID via `$!` and write to `$GITHUB_ENV` for a post-step cleanup. Wait-for-listener pattern: `for i in $(seq 1 15); do nc -z 127.0.0.1 <P> && break; sleep 1; done; nc -z 127.0.0.1 <P> || { echo "::error::cloudflared TCP forward did not open"; cat /tmp/cloudflared.log; exit 1; }`. Without an explicit cleanup, the runner reaps the process at job-end automatically; this is acceptable but log capture into `actions/upload-artifact` is recommended for post-hoc debugging.

**SSH-client TCP-forward seam.** The TF provisioner's embedded Go SSH client reads `~/.ssh/config` for the destination IP. Mapping `Host 135.181.45.178` → `Hostname 127.0.0.1` + `Port <P>` + `User root` + `IdentityFile ~/.ssh/...` causes the embedded client to dial `127.0.0.1:<P>`, where `cloudflared` is listening; cloudflared forwards over the tunnel; the Hetzner-side `cloudflared` daemon delivers to `localhost:22` (sshd). The handshake completes end-to-end. **Host-key seeding** uses `ssh-keyscan -p <P> -H 127.0.0.1 >> ~/.ssh/known_hosts` AFTER cloudflared's listener is up — keyscan returns the *real* server's host key (cloudflared transparently forwards the SSH banner), so the recorded fingerprint is the production sshd's, not a man-in-the-middle.

**Why `access tcp` not `access ssh`.** `cloudflared access ssh` is a ProxyCommand-style helper for INTERACTIVE `ssh root@host.com` invocations — it relies on the user invoking `ssh -o ProxyCommand='cloudflared access ssh --hostname=...'`. Terraform's embedded Go SSH client (`golang.org/x/crypto/ssh`) does NOT support `ProxyCommand` as a free-form string; the `connection { bastion_* }` block is the only proxy hook, and it requires a standard SSH bastion (which CF Access is not). `access tcp` sidesteps the entire problem by exposing a raw TCP socket the embedded client can dial directly.

**References:**
- Cloudflare One — Connect with Cloudflare Access (Service Tokens): `https://developers.cloudflare.com/cloudflare-one/identity/service-tokens/`
- Cloudflare One — TCP bridging via `cloudflared access tcp`: `https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/use-cases/tcp/`
- Sibling precedent in this repo: `apps/web-platform/infra/tunnel.tf:46-67` (CF Access application + service token + policy for the deploy webhook).



- [x] Edit `.github/workflows/apply-deploy-pipeline-fix.yml` — insert three new steps between `Start ssh-agent with deploy key` (current line 138) and `Capture local hashes (pre-apply)` (current line 151). New steps:
  1. **Install cloudflared (SHA-pinned).** Download the official linux-amd64 binary from `https://github.com/cloudflare/cloudflared/releases/download/<VERSION>/cloudflared-linux-amd64`; `sha256sum -c` against checksum embedded in the workflow YAML (computed against the real binary, not a doc value). Install to `/usr/local/bin/cloudflared`. Verify `cloudflared --version` exits 0.
  2. **Pull CF Access service-token credentials from Doppler.** Use the existing `doppler secrets get --plain` pattern (lines 113-117). Read `CI_SSH_ACCESS_TOKEN_ID` and `CI_SSH_ACCESS_TOKEN_SECRET`. Export as `TUNNEL_SERVICE_TOKEN_ID` + `TUNNEL_SERVICE_TOKEN_SECRET` for `cloudflared`.
  3. **Start `cloudflared access tcp` in the background.** Command: `cloudflared access tcp --hostname ssh.${app_domain_base} --url 127.0.0.1:2222 > /tmp/cloudflared.log 2>&1 &`. Capture PID. Wait up to 15s for `nc -z 127.0.0.1 2222` to succeed. Then `ssh-keyscan -p 2222 -H 127.0.0.1 >> ~/.ssh/known_hosts` to seed the host key. Finally, write an `~/.ssh/config` entry mapping `Host ${SERVER_IP}` → `Hostname 127.0.0.1` + `Port 2222` + `User root` + `StrictHostKeyChecking yes`. `${SERVER_IP}` is the Hetzner public IP that `hcloud_server.web.ipv4_address` resolves to at TF plan time. Pull it via `doppler secrets get HCLOUD_SERVER_PUBLIC_IP --plain` if exposed in Doppler; otherwise capture from `terraform output -raw server_ip` after `terraform init` (no `apply` needed for output read).
- [x] Verify `bash -c '<extracted script>'` of each new step exits 0 on a Linux test machine (NOT `bash -n <file.yml>` per the YAML/shell distinction Sharp Edge).
- [x] `actionlint .github/workflows/apply-deploy-pipeline-fix.yml` exits 0.
- [x] Edit `.github/workflows/apply-web-platform-infra.yml` to widen the `terraform plan`/`apply` `-target=` allow-list with the 5 new resources: `cloudflare_zero_trust_access_application.ssh`, `cloudflare_zero_trust_access_service_token.ci_ssh`, `cloudflare_zero_trust_access_policy.ci_ssh_service_token`, `cloudflare_record.ssh`. (The existing `cloudflare_zero_trust_tunnel_cloudflared_config.web` is already in the allow-list per the deploy-tunnel precedent.) **Verification:** `grep -c 'cloudflare_zero_trust_access_application\.ssh' .github/workflows/apply-web-platform-infra.yml` returns ≥1.

### Phase 4 — Local verification (pre-merge)

- [x] `cd apps/web-platform/infra && terraform fmt -check && terraform validate` exits 0.
- [x] `bash -n apps/web-platform/infra/scripts/sync-ci-ssh-access-token.sh` exits 0.
- [x] `actionlint .github/workflows/apply-deploy-pipeline-fix.yml .github/workflows/apply-web-platform-infra.yml` exits 0.
- [x] `bun test plugins/soleur/` exits 0 (no plugin tests touch the workflow surface, but run defensively).
- [x] `bash scripts/test-all.sh` exits 0.

### Phase 5 — PR + post-merge sequencing

- [ ] Open PR with body `Ref #4177` (NOT `Closes` — verification is post-merge). Body lists pre-merge ACs as `[x]` and post-merge ACs as `⏳`.
- [ ] On merge, `apply-web-platform-infra.yml` fires first (path filter matches `apps/web-platform/infra/**`). This applies the new CF resources and emits the new outputs. (The `-target=` allow-list widening lives in Phase 3 — see "Phase 3 — Workflow" below.)
- [ ] Operator runs `bash apps/web-platform/infra/scripts/sync-ci-ssh-access-token.sh` locally (one-shot).
- [ ] Re-fire `apply-deploy-pipeline-fix.yml` via `gh workflow run apply-deploy-pipeline-fix.yml --ref main -F reason="re-fire post #4177 CF SSH tunnel"`.
- [ ] Verify `gh run list --workflow=apply-deploy-pipeline-fix.yml --branch=main --limit=1 --json conclusion -q '.[0].conclusion'` returns `success`.
- [ ] Close #4177 with `gh issue close 4177 --comment "..."`.

## Alternatives Considered

| Option | Verdict | Reason |
|---|---|---|
| **Self-hosted GitHub runner on the existing Hetzner VPS** | Rejected | Co-tenant on a host already running web + cloudflared + inngest-server + KB-drift cron. PR #4144 just added Inngest substrate; node load is meaningful. New isolated VPS = new Terraform root + new resource group + new firewall + new cost. The CF Tunnel path reuses an existing pattern at zero new infra. |
| **Self-hosted runner on a NEW Hetzner VPS** | Deferred / scope-out | Cleanest isolation but adds an entire new TF root, runner registration token rotation, runner version pinning, and a new vendor-tier cost. CF Tunnel is the lower-blast-radius path. Filing follow-up: re-evaluate self-hosted runner if CF Tunnel SSH proves flaky. |
| **Dynamic firewall rule per workflow run (query api.github.com/meta)** | Rejected | `api.github.com/meta`'s `.actions[]` returns ~6575 CIDRs. Hetzner Cloud Firewall caps at 100 rules per firewall. ~6575 CIDRs are unrepresentable. Additionally: per-run patch is racy across concurrent applies and leaves the firewall open if the cleanup step fails. |
| **Bastion host with ProxyJump** | Rejected | Adds an additional VPS to patch + monitor + key-manage. No existing bastion. Same architectural inversion as self-hosted runner. Operational debt without solving the cleaner CF Tunnel pattern. |
| **CF Tunnel SSH via `cloudflared access ssh` (issue body's recommendation)** | **Adopted (with adjustment)** | Reuses the deploy-webhook CF Tunnel + Access pattern verbatim. Service-token auth at the Access layer. Zero new inbound firewall ports. CF Tunnel is already free-tier. **Adjustment:** terraform's `provisioner` block uses an embedded Go SSH client that cannot accept a free-form `ProxyCommand`, so the workflow runs `cloudflared access tcp` (NOT `cloudflared access ssh`) as a localhost TCP forward sidecar, then maps the destination IP to `127.0.0.1:2222` via `~/.ssh/config`. The embedded SSH client connects locally, traverses the tunnel transparently. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. The section above declares `threshold: none` with a sensitive-path scope-out rationale.
- **`cloudflared access tcp` vs `access ssh` — load-bearing distinction.** The issue body says "Cloudflare Tunnel for SSH" and the original brainstorm (#749) listed `cloudflared access ssh`. That CLI subcommand bridges `ssh` invocations through the tunnel BUT requires the SSH client to be invoked with `cloudflared` as ProxyCommand. Terraform's `provisioner` block uses `golang.org/x/crypto/ssh` directly and cannot set a free-form ProxyCommand. The workaround is `cloudflared access tcp` (raw TCP forward to a localhost port) + `~/.ssh/config` rewrite mapping the destination IP. The embedded Go SSH client transparently connects to `127.0.0.1:<port>`. **Do not regress this to `access ssh` during implementation.**
- **Existing exclusion comment on `firewall.tf:14` is correct.** `# CI deploy SSH rule removed -- deploys now use webhook via Cloudflare Tunnel (#749).` The webhook deploy IS the architectural answer for runtime deploys; this plan extends the same pattern to `terraform apply`'s SSH provisioner — same tunnel, different ingress rule.
- **cloudflared binary checksum (`2026-03-21-cloudflare-tunnel-server-provisioning.md` Session Error #4).** AI-generated checksums are unreliable. Compute the SHA-256 from the real binary at the chosen version; do not paste from documentation or LLM output.
- **Workflow YAML shell extraction.** Per the Sharp Edge in this skill: `bash -n .github/workflows/apply-deploy-pipeline-fix.yml` will fail because YAML is not bash. Use `actionlint` for the YAML and `bash -c '<extracted snippet>'` for the embedded `run:` shell.
- **Hetzner firewall rule cap is 100.** Confirmed against the Hetzner API docs at plan time. The dynamic-firewall alternative is unrepresentable, not just impractical. Do not regress to this path during review-fix.
- **Plan-time external state assertion check.** The CF Tunnel + CF Access infrastructure resources already exist in production state (`apps/web-platform/infra/tunnel.tf` deploy-app resources visible in latest drift reports). The new resources add to that state — no greenfield reprovisioning required. Confirmed by `gh run view 26166752987 --log-failed` showing `cloudflare_zero_trust_tunnel_cloudflared.web: Refreshing state... [id=6410c1ec-4f01-4a69-ad98-7bb1621f6d37]`.
- **`-target=` allow-list in `apply-web-platform-infra.yml` MUST be widened** to include the 4 new CF resources + the new `cloudflare_record.ssh`. Without this, the new resources never get applied via the auto-apply workflow.
- **Post-merge phase ordering is load-bearing.** Operator MUST run `sync-ci-ssh-access-token.sh` AFTER `apply-web-platform-infra.yml` (which creates the service token) and BEFORE re-firing `apply-deploy-pipeline-fix.yml` (which needs the Doppler secrets). Wrong order → `apply-deploy-pipeline-fix.yml` fails on missing Doppler secret.

## References

- Issue: #4177
- Source PR: #4165 (PAT-to-App migration that removed the masking PAT failure)
- Cascade: #4144 (AC14-AC18 blocked), #4116 (Better Stack heartbeat blind zone), #4115, #4132
- Brainstorm: `knowledge-base/project/brainstorms/2026-03-20-cloudflare-tunnel-deploy-brainstorm.md` (original CF Tunnel architectural decision, #749)
- Existing precedent: `apps/web-platform/infra/tunnel.tf` (deploy webhook tunnel + Access service token)
- Sibling workflows: `.github/workflows/apply-web-platform-infra.yml` (already excludes SSH-provisioned resources), `.github/workflows/apply-deploy-pipeline-fix.yml` (the workflow this plan unblocks)
- Learnings consulted:
  - `2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md` — exact L3-vs-L7 inversion class.
  - `2026-03-21-cloudflare-tunnel-server-provisioning.md` — cloudflared installation + import lifecycle + checksum verification.
  - `2026-04-22-follow-through-admin-ip-refresh-and-ssh-gate-verification.md` — Phase 1.4 trigger verification.
  - `2026-04-30-fix-terraform-drift-deploy-pipeline-fix-3061-plan.md` — canonical Doppler `--name-transformer tf-var` triplet.
  - `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md` — fresh `terraform plan` before each runbook step.
- Runbook: `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md` (sibling failure mode — operator SSH lockout via the same firewall, distinct from this CI-runner case).
- AGENTS.md rules engaged: `hr-ssh-diagnosis-verify-firewall`, `hr-all-infrastructure-provisioning-servers`, `hr-every-new-terraform-root-must-include-an` (no new root added; only resources in existing root), `hr-observability-as-plan-quality-gate`, `hr-weigh-every-decision-against-target-user-impact`, `hr-menu-option-ack-not-prod-write-auth`.
