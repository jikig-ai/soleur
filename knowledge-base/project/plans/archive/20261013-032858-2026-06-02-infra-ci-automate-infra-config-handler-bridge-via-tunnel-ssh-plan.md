<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
title: "infra: CI-automate the infra-config handler bridge via Cloudflare Tunnel SSH"
issue: 4829
type: infra
branch: feat-one-shot-4829-infra-config-bridge-ci-tunnel
date: 2026-06-02
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related:
  - "#4827 (PR #4828 — escalation helper bootstrap that exposed the dormancy)"
  - "#4811 (the chicken-and-egg the SSH bridge solves)"
  - "#4814 (the SSH bootstrap deploy path)"
  - "#4177 (PRs #4181/#4201/#4192/#4203 — already built the CF Tunnel SSH + CF Access infra)"
---

# infra: CI-automate the infra-config handler bridge via Cloudflare Tunnel SSH

> **Phase 2.8 IaC note:** all infrastructure here is Terraform-managed. The bridge resource already exists in `server.tf` and the tunnel/Access resources already exist in `tunnel.tf` (reused from #4177). This plan changes a connection mechanism and a CI workflow target — it introduces NO new manual provisioning. The in-provisioner webhook service-restart it references is the EXISTING `remote-exec` block, quoted for context only.

🔧 **infra / CI** — eliminate the operator `terraform apply -target=terraform_data.infra_config_handler_bootstrap` step by routing the bridge's root-SSH provisioner through the existing Cloudflare Tunnel + CF Access service token, then add it to the auto-apply workflow's `-target=` set.

## Enhancement Summary

**Deepened on:** 2026-06-02 (in-pipeline deepen-plan; the planning subagent could not fan out Task subagents, so research/review was performed directly against the repo with the same L3→L7 + precedent-diff discipline the agents would apply).
**Sections enhanced:** Overview, Research Reconciliation, Implementation Phases (Phase 0/1/2), Acceptance Criteria; added Hypotheses, Network-Outage Deep-Dive, Research Insights.

### Key Improvements
1. **Bootstrap-ordering gap surfaced (P0).** `terraform_data.root_authorized_keys` (ci-ssh-key.tf) — which appends the CI pubkey to root's `authorized_keys` — is **operator-local-apply only** (CI cannot apply it; its own header says so). The CI bridge apply DEPENDS on that key already being on-host. If it was never applied (or the key rotated), the first CI bridge apply fails with `no supported methods remain` (the #4181-L7 symptom). Added as Phase 0 precondition + Hypothesis L7 + a Sharp Edge.
2. **Network layers verified (L3→L7).** Firewall has only `in` rules (default-allow egress → host-side cloudflared reaches CF edge:7844); inbound SSH over the tunnel hits host-side cloudflared → `localhost:22` and NEVER traverses the `:22` firewall rule. The plan's "no firewall change" claim is **confirmed correct**. `cloudflare_record.ssh` is a proxied CNAME to the tunnel (dns.tf). See Network-Outage Deep-Dive.
3. **Precedent-diff (Phase 4.4): the dual-context connection block is NOVEL.** All 8 sibling SSH provisioners (server.tf ×7 + ci-ssh-key.tf ×1) use `agent = true` with no `private_key`. No precedent for a CI-key path exists in this repo — flagged for scrutiny; `terraform validate` is the gate on the conditional-`agent` HCL.
4. **No destroy/scope-guard suite** in `tests/scripts/` references the deploy-pipeline-fix workflow or the bridge — adding the bridge to `-target=` needs NO guard-suite update (one fewer Files-to-Edit than an allow-list extension usually requires).
5. **Cloudflare provider pinned at v4.52.7** (`~> 4.0`) — tunnel.tf's `cloudflare_zero_trust_*` resource names are v4-consistent. A future v5 bump would rename them; out of scope, noted in Research Insights.

### New Considerations Discovered
- The `files_written == files_total` gate does NOT prove the helper/sudoers landed (they're out of the FILE_MAP). Only the bridge's own `remote-exec` assertions (server.tf:430,433) prove it — and only if the provisioner actually RE-RAN (a no-diff apply skips it). Phase 2 must ensure the bridge re-fires on a handler change (its `triggers_replace` already hashes the helper/sudoers, so it does).
- `infra-config-install.sh` is in the bridge `triggers_replace` but NOT in the workflow `paths:` filter / ship gate array — a helper-ONLY change would not auto-fire (a helper change that also touches server.tf would). Phase 3.3 + Phase 4 close this.

## Overview

Deploy-config **handler** changes (`infra-config-apply.sh`, the `infra-config-install` escalation helper, and the `deploy-inngest-bootstrap.sudoers` grant) reach prod **only** via `terraform_data.infra_config_handler_bootstrap` (`apps/web-platform/infra/server.tf:353`). That resource uses a direct-IP root-SSH provisioner:

```hcl
connection {
  type  = "ssh"
  host  = hcloud_server.web.ipv4_address   # direct IP — firewall-gated
  user  = "root"
  agent = true
}
```

SSH:22 is firewall-allowlisted to `var.admin_ips` only (`firewall.tf` — `dynamic "rule"` over `var.admin_ips`; the "CI deploy SSH rule removed" comment confirms no CI ingress). The GitHub-hosted CI runner egress IP is non-static and not in `admin_ips`, so `apply-deploy-pipeline-fix.yml` **cannot** apply this bridge. Every handler change therefore leaves a manual operator step: run the targeted apply from a firewall-allowlisted machine with an SSH agent. This violates `hr-exhaust-all-automated-options-before`, `hr-never-label-any-step-as-manual-without`, and `hr-all-infrastructure-provisioning-servers`. It surfaced concretely on #4827/PR #4828: the fix merged green but stayed dormant in prod until the operator applied the bridge in-session.

**Why HTTPS can't deliver the handler:** the `/hooks/infra-config` webhook routes *through* the on-host handler, so a broken/stale handler cannot deliver its own replacement (#4811). Root SSH is the only non-circular bootstrap path. We keep SSH; we just change *how the CI runner reaches it*.

The fix routes the bridge SSH through the tunnel the host **already** runs for the webhook HTTPS path, authenticated by the CF Access `ci_ssh` service token — **no firewall IP allowlist change**. The runner opens a `cloudflared access tcp` localhost forward, an `iptables -t nat OUTPUT REDIRECT` rule transparently rewrites the Go-SSH-client dial of `SERVER_IP:22` to that forward, and the bridge is added to the `-target=` set in `apply-deploy-pipeline-fix.yml`.

## Research Reconciliation — Spec (issue body) vs. Codebase

The issue body was written against an earlier codebase state. #4177 (merged PRs #4181/#4201/#4192/#4203) **already built most of the proposed infrastructure**. This table reconciles the issue's proposed steps against current `origin/main`.

| Issue body claim / proposed step | Codebase reality (verified) | Plan response |
| --- | --- | --- |
| Step 1: "Add a `ssh://` route to the Cloudflare Tunnel … gated by a CF Access application + service token" | **Already exists** (#4177): `tunnel.tf:40-43` adds `ingress_rule { hostname = "ssh.${app_domain_base}"; service = "ssh://localhost:22" }`; `tunnel.tf:86-114` adds `cloudflare_zero_trust_access_application.ssh` + `cloudflare_zero_trust_access_service_token.ci_ssh` + policy; `dns.tf:22-27` adds `cloudflare_record.ssh`. | **No new tunnel/Access/DNS resources needed.** Plan reuses them. Drop issue Step 1. |
| "`apply-deploy-pipeline-fix.yml` already holds CF Access service-token creds (`CF_ACCESS_CLIENT_ID`/`_SECRET`)" | Partially true. The workflow pulls `CF_ACCESS_CLIENT_ID`/`_SECRET` with a `\|\| CI_SSH_ACCESS_TOKEN_ID/_SECRET` fallback (`apply-deploy-pipeline-fix.yml:184-185`) — but uses them only as **CF-Access HTTP headers** for the `/hooks/*` curl probes, NOT to open an SSH tunnel. The dedicated SSH token is `CI_SSH_ACCESS_TOKEN_ID/_SECRET` synced to Doppler by `apply-web-platform-infra.yml:397-432`. | Plan uses `CI_SSH_ACCESS_TOKEN_ID/_SECRET` (the SSH-scoped token, 15m session) for the `cloudflared access` sidecar — NOT the 24h deploy webhook token. |
| Step 2: "Change the `connection` block to dial through the tunnel — e.g. a `ProxyCommand`/`bastion_host` using `cloudflared access ssh`, keep `agent = false` + explicit `private_key`" | **Mechanism is load-bearing-incorrect.** Terraform's `provisioner` blocks use `golang.org/x/crypto/ssh` directly (`internal/communicator/ssh`), which does NOT parse `~/.ssh/config`, `ProxyCommand`, or `bastion_host`-via-tunnel-CLI. `connection.bastion_host` exists but expects a reachable SSH bastion, not a `cloudflared` CLI. This exact trap was caught in #4181 review (see learning `2026-05-20-terraform-go-ssh-client-ignores-ssh-config-multi-agent-catch.md`). | **Use the proven #4181 mechanism: `iptables -t nat OUTPUT REDIRECT` on the runner** (transparent to the Go SSH client). Keep `connection.host = ipv4_address` **unchanged** so server.tf needs no edit to the connection target. Switch `agent = true` → explicit `private_key` for CI (see below). |
| "Keep `agent = false` + explicit `private_key` for CI" | The bridge currently uses `agent = true`. CI has no ssh-agent; #4177 generates `tls_private_key.ci_ssh` (`ci-ssh-key.tf:38`), syncs the private half to Doppler `DEPLOY_SSH_PRIVATE_KEY`, and appends the public half to root's `authorized_keys` (`terraform_data.root_authorized_keys`). | Bridge connection must accept BOTH paths: `agent = true` for the operator-local full apply, AND a private-key path for CI. Resolve via a `var.ci_ssh_private_key` (default `null`) that, when set, populates `connection.private_key` + `agent = false`; otherwise `agent = true`. (Mirrors how `deploy_pipeline_fix` is reachable from both contexts.) |
| Step 3: "Add `infra_config_handler_bootstrap` to the `-target=` set in `apply-deploy-pipeline-fix.yml`" | Currently the workflow `-target`s ONLY `terraform_data.deploy_pipeline_fix` (`apply-deploy-pipeline-fix.yml:153,166`). server.tf:339-342 + 461-470 explicitly document NOT adding the bridge "because the runner egress IP is not in admin_ips." | **Add the bridge to `-target=`** AND rewrite those two server.tf comment blocks (the firewall reason is removed by this fix). |
| Step 4: "End-to-end test: trigger the workflow on a handler change; confirm `files_written == files_total`." | The workflow already has the `files_written == files_total` invariant gate (`apply-deploy-pipeline-fix.yml:263-265`) AND a post-apply webhook-alive check. | Reuse the existing gate; the bridge's own `remote-exec` post-write assertions (server.tf:428-439) are the in-provisioner proof. The helper/sudoers are NOT in the FILE_MAP, so their landing is proven by the bridge's own `test -x` / `grep -q` assertions (server.tf:430,433), not the webhook status. |

**Net effect:** the issue is ~70% already-built (the tunnel/Access/token/DNS half from #4177). The remaining work is the **CI consumer side**: the runner-side `cloudflared` + `iptables` bridge step, the dual-context `connection` block, the `-target=` addition, and the two server.tf comment-block rewrites. No new vendor resources.

## Hypotheses

This plan designs a NEW CI→host SSH path; the network-outage discipline (`hr-ssh-diagnosis-verify-firewall`) is applied forward — "will the designed path reach sshd, and what hidden network dependency could fail the first apply?" Unverified/at-risk layers FIRST, L3→L7:

1. **L7 — CI pubkey present in root's authorized_keys (HIGHEST RISK, bootstrap-ordering gap).** The CI bridge apply authenticates with `var.ci_ssh_private_key`; its public half must already be in `/root/.ssh/authorized_keys`. That append is done by `terraform_data.root_authorized_keys` (ci-ssh-key.tf:68-87), which is **operator-local-apply only** (its header, ci-ssh-key.tf:16-24, states CI cannot reach root@host to apply it). **Verification: `[NOT VERIFIED — operator must confirm]`** — before relying on CI auto-apply, the operator's most recent full `terraform apply` must have applied `root_authorized_keys` (and `doppler_secret.deploy_ssh_private_key`) so the live host trusts the current CI key. If skipped, the first CI bridge apply fails `Permission denied (publickey)` / `no supported methods remain` (the #4181-L7 symptom). Phase 0 step makes this a precondition; the plan does NOT add a CI path for `root_authorized_keys` (it can't — same firewall reason).
2. **L3 — firewall allow-list. [VERIFIED — correct by design]** `hcloud_firewall.web` (firewall.tf) has only `direction = "in"` rules (0 outbound rules → Hetzner default-allows egress). Inbound SSH over the tunnel does NOT traverse the `:22` ingress rule: the host-side `cloudflared` daemon delivers to `localhost:22` from inside the box. The runner's outbound to CF edge + the host's outbound to CF edge (7844) are both egress (allowed). So the tunnel genuinely bypasses `admin_ips` without any firewall edit (AC8). No admin-IP-drift dependency — the #2681/#4181 firewall failure class does NOT apply to the tunnel path.
3. **L3 — DNS/routing. [VERIFIED]** `cloudflare_record.ssh` (dns.tf) is a proxied CNAME `ssh → <tunnel-id>.cfargotunnel.com`. `cloudflared access tcp --hostname ssh.${app_domain_base}` resolves through CF, not host IP. No host-IP routing dependency.
4. **L7 — CF Access service-token auth. [NOT VERIFIED — Phase 0 + framework-docs]** `cloudflared access tcp` must authenticate non-interactively with the `ci_ssh` service token. The exact env-var/flag names (`TUNNEL_SERVICE_TOKEN_ID/_SECRET`) are unverified against the installed cloudflared — Phase 0 step 3 probes `cloudflared access tcp --help`. The token itself must be synced to Doppler (`CI_SSH_ACCESS_TOKEN_*`, done by apply-web-platform-infra.yml:397-432) — Phase 0 step 2 confirms.

## Network-Outage Deep-Dive

Layer-by-layer status (forward-looking; the design's reachability rather than an incident):

| Layer | Status | Artifact / gap |
| --- | --- | --- |
| L3 firewall allow-list | **verified — bypass correct** | firewall.tf has only `in` rules; tunnel SSH arrives via host-side `cloudflared → localhost:22`, never the `:22` ingress rule. Egress to CF edge:7844 allowed (Hetzner default). No `admin_ips` change (AC8). |
| L3 DNS/routing | **verified** | `cloudflare_record.ssh` proxied CNAME → `<tunnel-id>.cfargotunnel.com` (dns.tf). Runner resolves via CF, not host IP. |
| L7 TLS/proxy (CF Access) | **not verified — Phase 0** | `cloudflared access tcp` service-token auth flag/env names unconfirmed against installed binary; `CI_SSH_ACCESS_TOKEN_*` Doppler presence unconfirmed. Both → Phase 0. |
| L7 application (sshd accepts CI key) | **GAP — bootstrap-ordering** | `root_authorized_keys` is operator-local-apply only (ci-ssh-key.tf). If the live host doesn't already trust the current CI key, the first CI bridge apply fails. The CI path cannot self-heal this (same firewall reason the bridge itself had). Mitigation: Phase 0 precondition + the operator-local full-apply must precede the first CI bridge apply. |

**Ordering discipline honored:** the highest-risk unverified layer (L7 key presence) is surfaced first; the verified L3 layers confirm the firewall-bypass premise rather than assuming it.

## User-Brand Impact

**If this lands broken, the user experiences:** a deploy-config **handler** change (e.g., a security fix to `infra-config-apply.sh`, or the `infra-config-install` escalation helper) that merges green but never reaches prod — exactly the #4827 dormancy this fixes, except now *silently auto-applied-as-failed* instead of *deferred-to-operator*. A subsequent webhook deploy-config push could then `install_rejected` against a stale handler/sudoers, freezing infra-config delivery (the #4811/#4804 class). The non-technical Soleur user sees deploy/config operations silently stop taking effect.

**If this leaks, the user's infrastructure is exposed via:** the bridge grants **root SSH to the prod host**. The access path becomes the CF Access `ci_ssh` service-token (`CI_SSH_ACCESS_TOKEN_ID/_SECRET` in Doppler `prd_terraform`) + the `DEPLOY_SSH_PRIVATE_KEY`. A leak of *both* the CF Access SSH token AND the CI private key would grant an attacker root over the tunnel without needing a firewall-allowlisted IP. The 15m CF Access SSH session duration (`tunnel.tf:96`) bounds token-reuse blast radius; the private key is Doppler-masked and runner-ephemeral.

**Brand-survival threshold:** `single-user incident` — a broken bridge silently freezes infra-config delivery for the single prod tenant; a credential leak grants root. CPO sign-off required at plan time; `user-impact-reviewer` invoked at review-time.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Bridge connection accepts CI private-key path.** `terraform_data.infra_config_handler_bootstrap.connection` uses `private_key = var.ci_ssh_private_key` + `agent = false` when the var is set, else `agent = true`. Verify: `terraform validate` passes AND `grep -A8 'resource "terraform_data" "infra_config_handler_bootstrap"' apps/web-platform/infra/server.tf | grep -E 'private_key|agent'` shows the conditional. **Implementation:** `server.tf:362-367` (connection block) + new `var.ci_ssh_private_key` in `variables.tf`.
- [x] **AC2 — `var.ci_ssh_private_key` declared, default `null`, sensitive.** Verify: `grep -A4 'variable "ci_ssh_private_key"' apps/web-platform/infra/variables.tf` shows `default = null` + `sensitive = true` + `type = string`. Satisfies `hr-tf-variable-no-operator-mint-default` (value comes from Doppler `DEPLOY_SSH_PRIVATE_KEY`, not an operator mint). **Implementation:** `variables.tf`.
- [x] **AC3 — Workflow opens the cloudflared SSH tunnel + iptables redirect.** `apply-deploy-pipeline-fix.yml` gains a step (before `terraform plan`) that: (a) installs `cloudflared`, (b) runs `cloudflared access tcp --hostname ssh.${APP_DOMAIN_BASE} --url 127.0.0.1:2222 &` carrying `CI_SSH_ACCESS_TOKEN_ID/_SECRET`, (c) adds `sudo iptables -t nat -A OUTPUT -d "$SERVER_IP" -p tcp --dport 22 -j REDIRECT --to-ports 2222`. Verify: `grep -E 'cloudflared access tcp|iptables -t nat .* REDIRECT --to-ports 2222' .github/workflows/apply-deploy-pipeline-fix.yml` returns both lines. **Implementation:** new step in `apply-deploy-pipeline-fix.yml` apply job (precedent: learning `2026-05-20-terraform-go-ssh-client-ignores-ssh-config-multi-agent-catch.md` §Solution).
- [x] **AC4 — `if: always()` teardown removes the iptables rule + kills cloudflared.** Verify: `grep -E 'iptables -t nat -D OUTPUT' .github/workflows/apply-deploy-pipeline-fix.yml` returns ≥1 line inside a step with `if: always()`. **Implementation:** teardown step in `apply-deploy-pipeline-fix.yml`.
- [x] **AC5 — Bridge added to the `-target=` set.** Both `terraform plan` and `terraform apply` steps add `-target=terraform_data.infra_config_handler_bootstrap` alongside the existing `-target=terraform_data.deploy_pipeline_fix`. Verify: `grep -c 'target=terraform_data.infra_config_handler_bootstrap' .github/workflows/apply-deploy-pipeline-fix.yml` returns `2`. **Implementation:** `apply-deploy-pipeline-fix.yml:153,166`.
- [x] **AC6 — CI private key passed to terraform.** The apply/plan steps decode `DEPLOY_SSH_PRIVATE_KEY` from Doppler and pass it as `TF_VAR_ci_ssh_private_key` (env, masked) — NOT on the command line. Verify: `grep -E 'TF_VAR_ci_ssh_private_key' .github/workflows/apply-deploy-pipeline-fix.yml` returns ≥1 line AND the value is `add-mask`ed. **Implementation:** `apply-deploy-pipeline-fix.yml`.
- [x] **AC7 — server.tf comment blocks rewritten.** The "RUNNER-EGRESS CAVEAT … do NOT add it to apply-deploy-pipeline-fix.yml's -target= set" block (server.tf:339-342) and the `deploy_pipeline_fix` "#4827 — deliberately NO depends_on … which fail because the runner egress IP is not in var.admin_ips" block (server.tf:461-470) are updated to reflect tunnel-based CI access. Verify: `grep -c 'do NOT add it to apply-deploy-pipeline-fix' apps/web-platform/infra/server.tf` returns `0`. **Implementation:** `server.tf` comment edits.
- [x] **AC8 — `firewall.tf` `admin_ips` allowlist is byte-unchanged.** Verify: `git diff origin/main...HEAD -- apps/web-platform/infra/firewall.tf` is empty. (The tunnel route is the access path, not an IP grant — issue Acceptance bullet 3.)
- [x] **AC9 — bridge stays excluded from apply-web-platform-infra.** Confirm `apply-web-platform-infra.yml` still excludes `infra_config_handler_bootstrap` (its allow-list is non-SSH-only; the bridge is applied by `apply-deploy-pipeline-fix.yml`, not the full apply). Verify: `grep -c 'target=terraform_data.infra_config_handler_bootstrap' .github/workflows/apply-web-platform-infra.yml` returns `0`.
- [x] **AC10 — `terraform fmt -check` + `terraform validate` pass** on `apps/web-platform/infra/`. Verify: `cd apps/web-platform/infra && terraform fmt -check && terraform init -backend=false && terraform validate`.
- [x] **AC11 — Ship skill Deploy Pipeline Fix Drift Gate updated for in-session apply.** `plugins/soleur/skills/ship/SKILL.md` Deploy Pipeline Fix Drift Gate documents that the bridge (`infra_config_handler_bootstrap`) is now CI-auto-applied (no longer operator-only), AND adds the in-session-apply detection for the operator-machine case (issue "secondary" section). Verify: `grep -c 'infra_config_handler_bootstrap' plugins/soleur/skills/ship/SKILL.md` returns ≥1 AND `grep -c 'ssh-add -l' plugins/soleur/skills/ship/SKILL.md` returns ≥1.
- [x] **AC12 — In-session detection is correct.** The ship-skill in-session block keys on "NOT in CI (`[[ -z "${CI:-}" ]]` / no `GITHUB_ACTIONS`) AND `ssh-add -l` lists a key" to decide whether the agent can apply the bridge locally vs. defer. Verify: read the new block; confirm it does not unconditionally run a prod write (respects `hr-menu-option-ack-not-prod-write-auth` — the interactive terraform `yes` prompt, NOT `-auto-approve`, for the local path).
- [x] **AC13 — No new operator-only step introduced.** Any remaining operator-only reference for the bridge in `plugins/soleur/skills/ship/SKILL.md` carries an `Automation: not feasible because …` justification (there should be none — the whole point is to remove it). Verify: read the gate section.

### Post-merge (operator / CI — automated)

- [ ] **AC14 — End-to-end auto-apply from CI.** After merge, `apply-deploy-pipeline-fix.yml` fires (the diff touches `server.tf` + `infra-config-apply.sh` paths in its `paths:` filter), opens the tunnel, applies the bridge from the runner, and the in-provisioner `remote-exec` assertions (server.tf:428-439) pass. Verify (automated, no host login): the workflow run is green AND the `Verify infra-config apply succeeded` step reports `files_written == files_total`, `files_failed == 0`. **Automation:** the workflow itself + `gh run watch`. NOT operator-only.
- [ ] **AC15 — Helper + sudoers landed.** Because the helper (`/usr/local/bin/infra-config-install`) and sudoers are NOT in the webhook FILE_MAP, confirm they landed via the bridge's own `remote-exec` assertions passing (server.tf:430,433) — these fail the provisioner (and thus the workflow) if absent, so a green run IS the proof. No separate probe required.
- [ ] **AC16 — Issue closure.** This is a feature (not ops-remediation), so the PR body uses `Closes #4829`. The `deferred-automation` label is removed at merge (the capability is now built).
- [ ] **AC17 — Bootstrap-ordering precondition documented (P0).** The PR body states the one-time precondition: the live host must already trust the current CI key (`root_authorized_keys` + `doppler_secret.deploy_ssh_private_key` applied on the operator's most recent full apply). Verify: the PR body contains a "Precondition" note naming `root_authorized_keys`. This is NOT a recurring operator step (full applies happen on infra changes anyway) — it is a stated dependency so a first-apply `Permission denied (publickey)` is diagnosed as key-not-on-host, not as a bridge defect. Per the Network-Outage Deep-Dive L7 gap.

## Implementation Phases

### Phase 0 — Preconditions (verify before any edit)

1. Confirm tunnel SSH infra exists on `origin/main`: `git show origin/main:apps/web-platform/infra/tunnel.tf | grep -E 'access_application" "ssh"|service_token" "ci_ssh"|ssh://localhost:22'` returns 3 matches.
2. Confirm `CI_SSH_ACCESS_TOKEN_ID/_SECRET` are synced to Doppler (read-only check): `doppler secrets get CI_SSH_ACCESS_TOKEN_ID -p soleur -c prd_terraform --plain 2>&1 | head -c 8` is non-empty. If empty, the sync step in `apply-web-platform-infra.yml:397-432` has not run on the live tunnel — note as a precondition the operator's full-apply must satisfy first (do NOT block the plan; the bridge apply degrades to the existing operator-local fallback until the token exists).
3. Confirm `cloudflared access tcp` is the right CLI form (the tunnel ingress is `ssh://localhost:22`, a TCP service): `cloudflared access tcp --help 2>&1 | grep -E 'hostname|url'` — pin the verified flag names into the plan/AC3 (`--hostname`, `--url`). Also confirm the service-token env-var names (`TUNNEL_SERVICE_TOKEN_ID`/`_SECRET`) via `cloudflared access tcp --help`. `<!-- verify at /work time -->`
4. **(P0 bootstrap-ordering) Confirm the live host trusts the current CI key.** The CI bridge apply authenticates with the key whose public half `terraform_data.root_authorized_keys` (ci-ssh-key.tf, operator-local-apply only) appends to root's `authorized_keys`. Before the first CI bridge apply can succeed, the operator's most recent full `terraform apply` must have applied BOTH `root_authorized_keys` AND `doppler_secret.deploy_ssh_private_key`. Verification (read-only, no host login): confirm `tls_private_key.ci_ssh` is in state and `doppler secrets get DEPLOY_SSH_PRIVATE_KEY -p soleur -c prd_terraform --plain 2>&1 | head -c 12` is non-empty. If the key was rotated since the last full apply, the host has a STALE pubkey → first CI apply fails `Permission denied (publickey)`. This is NOT auto-healable from CI (the CI path can't apply `root_authorized_keys` for the same firewall reason). Document the dependency in the PR body as a one-time operator precondition (the full-apply already happens on infra changes; this just makes the dependency explicit — it is NOT a new recurring operator step).
5. Read `apps/web-platform/infra/server.tf:300-442` (bridge resource + comments) and `variables.tf` in full before editing.

### Phase 1 — Terraform: dual-context connection (RED→GREEN)

1. Add `variable "ci_ssh_private_key" { type = string; default = null; sensitive = true; description = "…" }` to `variables.tf`.
2. Rewrite the bridge `connection` block (server.tf:362-367) to:
   ```hcl
   connection {
     type        = "ssh"
     host        = hcloud_server.web.ipv4_address
     user        = "root"
     private_key = var.ci_ssh_private_key            # null in operator-local context
     agent       = var.ci_ssh_private_key == null    # agent in operator context, key in CI
   }
   ```
   (Verify against the terraform-provider docs that `agent` accepts an expression and that `private_key = null` + `agent = true` is the operator-local path — `terraform validate` is the gate.)
3. Rewrite the two comment blocks (server.tf:339-342 RUNNER-EGRESS CAVEAT; server.tf:461-470 deploy_pipeline_fix depends_on rationale) to describe the tunnel-based CI access. Keep the `deploy_pipeline_fix` `depends_on = [terraform_data.apparmor_bwrap_profile]` — do NOT add a `depends_on` on the bridge (the `-target=` set lists both explicitly; ordering is still handled by the handler's per-file self-heal, unchanged).
4. `terraform fmt` + `terraform validate`.

### Phase 2 — Workflow: cloudflared + iptables bridge (the load-bearing mechanism)

Mirror the proven #4181 mechanism (learning `2026-05-20-terraform-go-ssh-client-ignores-ssh-config-multi-agent-catch.md` §Solution). In `apply-deploy-pipeline-fix.yml` apply job, BEFORE `terraform plan`:

1. **Resolve SERVER_IP** from terraform output (the redirect needs the literal IP that `connection.host` expands to). Read it via `terraform output -raw server_ip` after init. Pin the exact output name at /work time (`server_ip` per ship/SKILL.md:669).
2. **Decode SSH key:** pull `DEPLOY_SSH_PRIVATE_KEY` from Doppler `prd_terraform`, `add-mask` it, write to the `TF_VAR_ci_ssh_private_key` env var — terraform reads `TF_VAR_*` natively, avoiding the key on the command line.
3. **Open tunnel:** install `cloudflared` (SHA-pinned download or apt), then `cloudflared access tcp --hostname ssh.${APP_DOMAIN_BASE} --url 127.0.0.1:2222` in the background, carrying `TUNNEL_SERVICE_TOKEN_ID`/`TUNNEL_SERVICE_TOKEN_SECRET` from `CI_SSH_ACCESS_TOKEN_ID/_SECRET` (verify exact env var names at /work time). Wait for `127.0.0.1:2222` to accept connections (bounded retry, ≤30s, fail-loud on timeout).
4. **NAT redirect:** `sudo iptables -t nat -A OUTPUT -d "$SERVER_IP" -p tcp --dport 22 -j REDIRECT --to-ports 2222`.
5. **Pass the target:** add `-target=terraform_data.infra_config_handler_bootstrap` to BOTH the `plan` and `apply` invocations (alongside the existing deploy_pipeline_fix target). `TF_VAR_ci_ssh_private_key` is already in env from step 2.
6. **Teardown (`if: always()`):** `sudo iptables -t nat -D OUTPUT -d "$SERVER_IP" -p tcp --dport 22 -j REDIRECT --to-ports 2222 || true` + kill the cloudflared background process. Place AFTER the apply step.

All untrusted inputs routed through env vars; all action refs SHA-pinned (workflow convention, header lines 31-33).

### Phase 3 — Ship skill: remove the operator-only framing + add in-session detection

In `plugins/soleur/skills/ship/SKILL.md` Deploy Pipeline Fix Drift Gate (lines 610-718):

1. Add `infra_config_handler_bootstrap` to the gate's "auto-apply on merge" narrative: a handler-file change now triggers BOTH `deploy_pipeline_fix` AND the bridge apply via the workflow's `-target=` set. Note the bridge delivers the helper + sudoers over the tunnel.
2. Add the **in-session-apply detection** (issue secondary section): when the ship pipeline runs on the operator's own machine (`[[ -z "${CI:-}" && -z "${GITHUB_ACTIONS:-}" ]]` AND `ssh-add -l` lists the deploy key), the agent CAN apply the bridge in-session (interactive terraform prompt = the `yes` per `hr-menu-option-ack-not-prod-write-auth`; NOT `-auto-approve`) + run the no-host-login `/hooks/infra-config-status` verify, instead of deferring. This is the rare-fallback path only; the CI auto-apply is now the default. Per `hr-no-ssh-fallback-in-runbooks`, keep the no-host-login verify (`files_written == files_total` via the status hook) as the success gate, not an SSH hash compare.
3. **Gate-array audit:** the bridge's `triggers_replace` (server.tf:354-360) lists `infra-config-install.sh`, but the gate array `DEPLOY_PIPELINE_FIX_TRIGGERS` (SKILL.md:626-637) lists `infra-config-apply.sh` and NOT `infra-config-install.sh`. **Audit at /work time** whether `infra-config-install.sh` should be added to the gate array + `DPF_REGEX` + `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` `TRIGGER_FILES` so a helper-only change fires the gate. If added, keep all four (array, regex, test fixture, server.tf) in lockstep in the same commit (the test auto-detects server.tf↔array drift, #3068; the coupling is documented at SKILL.md:623).

### Phase 4 — Workflow `paths:` filter audit

The workflow's `paths:` filter (apply-deploy-pipeline-fix.yml:40-51) gates which merges fire the auto-apply. It currently lists `infra-config-apply.sh`, `push-infra-config.sh`, `cat-infra-config-state.sh`, `deploy-inngest-bootstrap.sudoers`, `server.tf` — but NOT `infra-config-install.sh`. A change to ONLY the escalation helper would not fire the workflow. **Add `apps/web-platform/infra/infra-config-install.sh` to the `paths:` filter** so a helper-only change auto-applies the bridge. Verify: `grep -c 'infra-config-install.sh' .github/workflows/apply-deploy-pipeline-fix.yml` returns ≥1.

## Observability

```yaml
liveness_signal:
  what: "apply-deploy-pipeline-fix.yml workflow run status + the in-provisioner remote-exec assertions (server.tf:428-439) + /hooks/infra-config-status files_written==files_total"
  cadence: "on every merge touching a bridge/handler trigger file (push to main, paths-filtered)"
  alert_target: "GitHub Actions run failure (red X) + existing infra-drift issue auto-file on 12h cron if the apply silently no-ops"
  configured_in: ".github/workflows/apply-deploy-pipeline-fix.yml (apply job) + apps/web-platform/infra/server.tf:403-441 (remote-exec assertions)"
error_reporting:
  destination: "GitHub Actions step error annotations (workflow log) + step summary; bridge provisioner failure aborts the apply non-zero"
  fail_loud: true
failure_modes:
  - mode: "cloudflared tunnel fails to open / 127.0.0.1:2222 never accepts"
    detection: "bounded wait loop in the tunnel-open step times out then step exits non-zero before terraform runs"
    alert_route: "workflow red X + error annotation naming the tunnel-open failure"
  - mode: "CF Access ci_ssh token expired/missing (CI_SSH_ACCESS_TOKEN_* absent in Doppler)"
    detection: "cloudflared access tcp fails auth so the forward never establishes so the wait loop times out"
    alert_route: "workflow red X; the cloudflare_notification_policy.service_token_expiry alert (tunnel.tf:122) fires 7 days pre-expiry"
  - mode: "DEPLOY_SSH_PRIVATE_KEY absent/empty in Doppler prd_terraform"
    detection: "the Decode CI SSH private key step's -z guard fails (::error:: + exit 1) before terraform runs — distinct from the key-mismatch handshake failure below"
    alert_route: "workflow red X + ::error:: annotation naming the missing secret (GH Actions run-log layer)"
  - mode: "SSH key mismatch (DEPLOY_SSH_PRIVATE_KEY not in root authorized_keys)"
    detection: "Go SSH client handshake fails (no supported methods remain) so the provisioner aborts non-zero (the exact #4181-L7 symptom)"
    alert_route: "workflow red X + error annotation from terraform apply"
  - mode: "terraform output server_ip empty (state not populated)"
    detection: "the Start cloudflared step guards -z SERVER_IP (::error:: + exit 1) before the NAT redirect, rather than installing a -d \"\" rule"
    alert_route: "workflow red X + ::error:: annotation (GH Actions run-log layer)"
  - mode: "bridge applies but files_written != files_total (handler delivered, webhook push partial)"
    detection: "existing Verify infra-config apply step gate (apply-deploy-pipeline-fix.yml:263-265)"
    alert_route: "workflow red X via the existing fail-loud adjudication block"
logs:
  where: "GitHub Actions run logs + GITHUB_STEP_SUMMARY"
  retention: "90 days (GH Actions default)"
discoverability_test:
  command: "curl -fsS -o /dev/null -w '%{http_code}' --max-time 10 https://deploy.soleur.ai/hooks/infra-config-status"
  expected_output: "200"
  note: "200 is the authed operator result — the real probe carries X-Signature-256 (HMAC of empty body with WEBHOOK_DEPLOY_SECRET) + CF-Access-Client-Id/Secret headers from Doppler prd_terraform, and the JSON body proves files_written==files_total (no host login). An unauthenticated probe (no headers, e.g. preflight Check 10's credential-free env) returns 403 at the CF Access edge, which still proves the no-SSH status surface is reachable. Post-merge, the apply-deploy-pipeline-fix.yml run itself is the E2E (AC14/AC15): gh run list --workflow=apply-deploy-pipeline-fix.yml --limit 1 --json conclusion shows conclusion=success."
```

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/variables.tf` — new `ci_ssh_private_key` (string, default null, sensitive). Value source: Doppler `prd_terraform/DEPLOY_SSH_PRIVATE_KEY` (already produced by `ci-ssh-key.tf:51-57`), passed as `TF_VAR_ci_ssh_private_key` in CI.
- `apps/web-platform/infra/server.tf` — `terraform_data.infra_config_handler_bootstrap.connection` block: add `private_key` + conditional `agent`. Two comment-block rewrites. No resource-graph change (no new `depends_on`). The existing in-provisioner webhook service-restart + `remote-exec` assertions (server.tf:403-441) are unchanged — referenced in this plan for context only.
- No new tunnel/Access/DNS/token resources — all reused from #4177 (`tunnel.tf`, `dns.tf`).
- Required providers: unchanged (hcloud, cloudflare, tls, doppler, random — all already pinned in `.terraform.lock.hcl`).
- Sensitive variable list: `TF_VAR_ci_ssh_private_key` (from Doppler `DEPLOY_SSH_PRIVATE_KEY`); CF Access SSH token via `CI_SSH_ACCESS_TOKEN_ID/_SECRET` (Doppler).

### Apply path
**(c) connection-mechanism change applied via the existing auto-apply workflow.** The bridge resource already exists in state; this changes its connection mechanism + the workflow that targets it. On merge, `apply-deploy-pipeline-fix.yml` auto-applies the bridge from CI over the tunnel (the PR merge IS the authorization, same model as `deploy_pipeline_fix`). Expected blast radius: re-runs the bridge's existing root-SSH `remote-exec` (re-writes the handler + helper + sudoers, restarts the webhook service). Downtime: the webhook service restart is sub-second (synchronous, server.tf:424). The operator-local full-apply path is preserved as fallback (the `agent = true` branch).

### Distinctness / drift safeguards
- `dev != prd`: this resource is prod-only (the single `hcloud_server.web`); no dev mirror. No regression to the dev/prd Doppler split.
- `lifecycle`: none added; the bridge's `triggers_replace` is unchanged. The new `connection.private_key` reads a var, not state — no perpetual drift.
- State storage: `ci_ssh_private_key` lands in `terraform.tfstate` (R2 backend, encrypted). It is ALREADY there via `tls_private_key.ci_ssh` / `doppler_secret.deploy_ssh_private_key` — no new secret class in state.
- `firewall.tf` is byte-unchanged (AC8) — the tunnel is the access path, the IP allowlist is not touched.

### Vendor-tier reality check
Cloudflare Zero Trust: the tunnel, Access apps, and service tokens already exist and are within the current plan tier (#4177 provisioned them). CF Access `non_identity` service-token policies and `cloudflared access tcp` are free-tier-available. No tier gate needed.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)
**Status:** reviewed (plan-author assessment; full CTO probe deferred to deepen-plan domain agents)
**Assessment:** Pure infra/CI change. The load-bearing risk is the Go-SSH-client mechanism (already mis-designed once in #4181 and caught at review) — this plan adopts the proven iptables-NAT-redirect rather than re-attempting `ProxyCommand`/`bastion_host`. Secondary risk is credential blast radius (root SSH over tunnel); mitigated by the 15m CF Access session + Doppler-masked ephemeral key. Architecture-strategist + security-sentinel at deepen-plan/review should verify: (a) the iptables rule scoping (`-d SERVER_IP` only, not a blanket :22 redirect), (b) teardown runs on failure, (c) the `agent` conditional expression is valid HCL and the operator-local path still works.

### Product/UX Gate
Not relevant — no UI surface in Files to Edit (all `*.tf`, `*.yml`, `SKILL.md`). Mechanical UI-surface override did not fire (no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` in the file list).

## Files to Edit

- `apps/web-platform/infra/variables.tf` — add `ci_ssh_private_key`.
- `apps/web-platform/infra/server.tf` — connection block + two comment rewrites.
- `.github/workflows/apply-deploy-pipeline-fix.yml` — cloudflared+iptables bridge step, teardown, `-target=` addition, `TF_VAR_ci_ssh_private_key`, `paths:` filter (+`infra-config-install.sh`).
- `plugins/soleur/skills/ship/SKILL.md` — Deploy Pipeline Fix Drift Gate: remove bridge operator-only framing, add in-session detection.
- **Audit (may edit):** `plugins/soleur/skills/ship/SKILL.md` `DEPLOY_PIPELINE_FIX_TRIGGERS` array + `DPF_REGEX` AND `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` `TRIGGER_FILES` — IF `infra-config-install.sh` must be added (see Phase 3.3 + Sharp Edges). Keep all four + server.tf in lockstep (per the gate's documented coupling).

## Files to Create
None.

## Open Code-Review Overlap
None — no open `code-review`-labeled issue names these files (verified at plan time; `gh issue list --label code-review --state open` cross-checked against the Files to Edit set).

## Test Scenarios

- `terraform validate` + `terraform fmt -check` (AC10).
- `bun test plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` — must stay green; if `infra-config-install.sh` is added to the gate array, update the fixture in the same commit (the test auto-detects server.tf↔array drift, #3068).
- `actionlint .github/workflows/apply-deploy-pipeline-fix.yml` for YAML; `bash -c '<extracted run snippet>'` for the new shell steps (NOT `bash -n` on the .yml — per Sharp Edges).
- Post-merge: the workflow run itself is the E2E test (AC14/AC15).

## Sharp Edges

- **The Go SSH client does NOT read `~/.ssh/config`, `ProxyCommand`, or use `connection.bastion_host` with a CLI bastion.** The issue's proposed `ProxyCommand`/`bastion_host` mechanism is load-bearing-incorrect (caught at #4181 review). Use the iptables-NAT-redirect. Do not re-attempt the config-file mechanism. (Learning: `2026-05-20-terraform-go-ssh-client-ignores-ssh-config-multi-agent-catch.md`.)
- **`infra-config-install.sh` is in the bridge's `triggers_replace` (server.tf:356) but NOT in the workflow `paths:` filter or the ship gate array.** A helper-only change must still fire the auto-apply. Phase 4 adds it to `paths:`; Phase 3.3 flags the gate-array audit. Verify both with grep before marking done — guard-surface coupling per the gate's own documentation (SKILL.md:623). If the gate array changes, `ship-deploy-pipeline-fix-gate.test.ts` + server.tf must change in the same commit.
- **Confirm `cloudflared access tcp` env-var names + flag shape at /work time** (`TUNNEL_SERVICE_TOKEN_ID`/`_SECRET` vs `--service-token-id`). Doc absence ≠ flag absence — probe via `cloudflared access tcp --help` and pin the verified form into the workflow step (CLI-verification gate).
- **Scope the iptables redirect to `-d "$SERVER_IP"`** — a blanket `--dport 22 REDIRECT` would hijack ALL outbound SSH on the runner. The `-d` match confines it to the prod host.
- **Teardown must run `if: always()`** — a left-over NAT rule or orphaned cloudflared on a self-hosted runner would corrupt later jobs; on GH-hosted ephemeral runners it is moot, but the discipline is required (the runner could become persistent).
- **`ALLOW_MISSING_STATUS` 404 escape hatch is workflow_dispatch-only.** Do not let the bridge addition weaken the existing `files_written == files_total` adjudication — a 404 on a routine push apply must still FAIL (the #4804 false-success vector).
- **`agent` accepts an HCL expression?** Verify `agent = var.ci_ssh_private_key == null` parses (it should — `agent` is a bool attribute). If a literal bool is required, fall back to a `coalesce`-driven form or two connection variants. `terraform validate` is the gate.
- **Bootstrap-ordering: the CI bridge apply depends on `root_authorized_keys` having been applied operator-locally first.** `root_authorized_keys` (ci-ssh-key.tf) appends the CI pubkey to root's `authorized_keys` and is operator-local-apply only — the CI path can't apply it (same firewall reason the bridge had). If the live host doesn't trust the current CI key (never applied, or key rotated since), the first CI bridge apply fails `Permission denied (publickey)` — NOT auto-healable from CI. Phase 0 step 4 verifies this precondition. This is the #4181-L7 failure class; do not assume the host already has the key.
- **The dual-context connection block is NOVEL for this repo** — all 8 sibling SSH provisioners use `agent = true` only. `terraform validate` must confirm `agent = var.ci_ssh_private_key == null` parses AND that the operator-local path (`var` unset → `private_key = null` + `agent = true`) is byte-equivalent to today's behavior so the operator's local apply is not broken. No precedent to copy; this is the scrutinize-carefully shape.
- **`files_written == files_total` does NOT prove the helper/sudoers landed.** They're out of the webhook FILE_MAP; only the bridge's own `remote-exec` assertions (server.tf:430,433) prove it, and only if the provisioner actually re-ran. A no-diff apply skips the provisioner entirely — but the bridge's `triggers_replace` hashes the helper + sudoers (server.tf:354-360), so a handler/helper/sudoers change re-fires it. Do not weaken or remove those in-provisioner assertions.
- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6 — this plan's section is filled with `single-user incident`.
- At `single-user incident` threshold, run deepen-plan (the domain triad catches credential/blast-radius/atomicity issues plan-review structurally misses).

## Research Insights

### Precedent diff (deepen-plan Phase 4.4)

- **SSH-provisioner connection pattern (sibling-precedent):** `git grep -A4 'connection {' apps/web-platform/infra/server.tf apps/web-platform/infra/ci-ssh-key.tf` → all 9 connection blocks use `type/host/user` + `agent = true`, none set `private_key`. The plan's dual-context block has **no in-repo precedent**; flagged novel (per Phase 4.4 "if no precedent exists, note it"). Recommended implementation: keep both attributes present and let terraform prefer `private_key` when non-null — verify the exact precedence in the provisioner docs at /work time; `terraform validate` + a dry `terraform plan` (operator-local, var unset) is the correctness gate for the fallback path.
- **iptables-NAT-redirect precedent:** the canonical mechanism is documented in `knowledge-base/project/learnings/best-practices/2026-05-20-terraform-go-ssh-client-ignores-ssh-config-multi-agent-catch.md` §Solution. Adopt verbatim (the `-d "$SERVER_IP"` scoping + the `if: always()` teardown). The Go SSH client (`golang.org/x/crypto/ssh` via terraform's internal `communicator/ssh`) does NOT read `~/.ssh/config` / `ProxyCommand` — re-confirmed against that learning.
- **Scheduled-work check (Phase 4.4):** N/A — this plan introduces no cron/scheduled job (the auto-apply is push-triggered, not scheduled).
- **No guard-suite coupling:** `grep -rln 'infra_config_handler_bootstrap|apply-deploy-pipeline-fix|deploy_pipeline_fix' tests/scripts/` → 0 hits. Adding the bridge to `-target=` needs no destroy/scope-guard update (unlike the apply-web-platform-infra `-target=` list, which has `tests/scripts/lib/destroy-guard-filter-web-platform.jq`). The only coupled surface is the ship gate array ↔ server.tf `triggers_replace` ↔ `ship-deploy-pipeline-fix-gate.test.ts` (Phase 3.3).

### Provider / version notes

- **Cloudflare provider pinned at `4.52.7` (`~> 4.0`)** (`.terraform.lock.hcl`). tunnel.tf's `cloudflare_zero_trust_tunnel_cloudflared{,_config}`, `cloudflare_zero_trust_access_application/service_token/policy` are v4 resource names — consistent with the pin. A future v5 bump renames many of these; out of scope here, but any `terraform init -upgrade` in this PR must NOT cross the v4→v5 boundary.
- **`cloudflared access tcp` CLI** (Phase 0 step 3 to pin): Cloudflare's documented form is `cloudflared access tcp --hostname <host> --url <local>`; service-token auth is via `TUNNEL_SERVICE_TOKEN_ID` + `TUNNEL_SERVICE_TOKEN_SECRET` env vars (no interactive `cloudflared login` needed). Verify against the installed binary's `--help` at /work time and pin the verified form (CLI-verification gate) — doc absence ≠ flag absence.
- **`server_ip` output exists** (`outputs.tf:1`) — Phase 2.1's `terraform output -raw server_ip` is valid (matches ship/SKILL.md:669).

## Alternative Approaches Considered

| Approach | Why not chosen |
| --- | --- |
| `connection { bastion_host = ... }` via `cloudflared` CLI | terraform's `bastion_host` expects a reachable SSH bastion, not a local CLI forward; the Go SSH client will not invoke `cloudflared access ssh` as a ProxyCommand. Mechanism-incorrect (#4181 class). |
| Add the CI runner egress IP to `var.admin_ips` | Runner IP is non-static (issue body); would require per-run mutation of the firewall (a prod write per apply) — strictly worse than the tunnel. Also violates AC8 (allowlist unchanged). |
| Push the handler over HTTPS / extend the webhook FILE_MAP to the helper+sudoers | The webhook routes through the on-host handler (chicken-and-egg, #4811); a broken handler cannot deliver its own replacement, and the sudoers self-heal is circular on first apply (server.tf:392-397). SSH is the only non-circular path. |
| New dedicated `apply-infra-config-bridge.yml` workflow | The existing `apply-deploy-pipeline-fix.yml` already fires on the same trigger files and has the verify gates; a sibling workflow would duplicate the Doppler/tunnel/verify scaffolding. Reuse it. |

## Deferral Tracking
The `deferred-automation` label on #4829 is removed at merge (this PR builds the deferred capability). No new deferrals introduced. The old-public-key cleanup after CI key rotation (`ci-ssh-key.tf:30-31`) remains a pre-existing separate deferral — out of scope here.
