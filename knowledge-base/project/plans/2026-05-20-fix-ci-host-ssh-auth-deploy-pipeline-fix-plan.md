---
title: "fix(infra): unblock Apply deploy-pipeline-fix.yml CI→host SSH authentication"
type: fix
date: 2026-05-20
issue: 4177
branch: feat-one-shot-fix-ci-ssh-auth-deploy-pipeline-fix
lane: cross-domain
classification: infra
requires_cpo_signoff: false
deepened_on: 2026-05-20
---

# fix(infra): unblock `Apply deploy-pipeline-fix.yml` CI→host SSH authentication

## Enhancement Summary

**Deepened on:** 2026-05-20
**Sections enhanced:** Overview, Hypotheses, Research Reconciliation, Option A details, Files to Create, ACs, IaC, Sharp Edges.

### Key Improvements

1. **Doppler `config` corrected.** Original plan draft prescribed `config = "prd_terraform"` on `doppler_secret.deploy_ssh_private_key`. Verified live: workflow reads `DEPLOY_SSH_PRIVATE_KEY` from `prd_terraform` (`apply-deploy-pipeline-fix.yml:117-127, 153-160`). The `doppler-write-token.tf:42` precedent confirms `doppler_secret`-class resources CAN write to `prd_terraform` (the `DOPPLER_TOKEN_TF` provider token is workplace-scope, NOT config-scoped — see `apps/web-platform/infra/main.tf:provider "doppler"` + `kb-drift.tf:# workplace-scope DOPPLER_TOKEN_TF`). All other `doppler_secret` resources happen to pin `config = "prd"` because they're consumed by the runtime, not by Terraform — the choice is target-driven, not provider-constrained.
2. **Reference type corrected.** `#4177` is a CLOSED *issue* ("follow-through: CI→host SSH timeout blocks Apply deploy-pipeline-fix.yml"). PR #4181 closed it for L3. This PR is the L7 follow-on and uses `Ref #4177` (not `Closes`) per `wg-use-closes-n-in-pr-body-not-title-to` — the issue is already closed, but `Ref` keeps backlink continuity.
3. **Provider pin verified.** `.terraform.lock.hcl` shows `dopplerhq/doppler = 1.21.2 (~> 1.21)`. `hashicorp/tls` is NOT yet pinned — `terraform init` after the new file lands adds the lockfile entry. Add `terraform { required_providers { tls = { source = "hashicorp/tls", version = "~> 4.0" } } }` to `main.tf` or rely on auto-discovery; check the existing `main.tf` shape.
4. **Cloud-init schema verified for ubuntu-24.04.** `users:` block uses the cloud-init `users-and-groups` module. The correct shape is `- name: <user>\n  ssh_authorized_keys: [<key>]` under each user entry. The existing `- default` entry inherits Hetzner-provided keys; to add the CI key for root specifically use a separate `- name: root\n  ssh_authorized_keys: [...]` entry (and `lock_passwd: true`). Alternatively, `ssh_authorized_keys:` at root level applies to the default user only — for root login the per-user form is needed since `AllowUsers root` (sshd_config.d/01-hardening.conf:29) makes root the auth target.
5. **CF Tunnel SSH bridge dependency for `terraform_data.root_authorized_keys`.** The bridge is set up only in `apply-deploy-pipeline-fix.yml`, NOT in `apply-web-platform-infra.yml` (which is what dispatches the new resource). Re-verified: `apply-web-platform-infra.yml` does NOT install cloudflared / set iptables NAT. The new `terraform_data.root_authorized_keys` MUST be applied from a context where the operator's `~/.ssh/id_<key>` is in ssh-agent AND the operator's IP is in `var.admin_ips` (i.e., from an operator-local `terraform apply`, NOT from CI). This shifts the bootstrap pattern — see "Bootstrap Path Correction" below.
6. **Reading `private_key_openssh` from `tls_private_key`.** `tls_private_key.public_key_openssh` includes the trailing newline; in `authorized_keys` we want a single line. Use `trimspace(tls_private_key.ci_ssh.public_key_openssh)` everywhere the value is embedded, OR rely on `grep -qxF` (full-line match) which is newline-insensitive. The plan now prescribes `trimspace()`.

### New Considerations Discovered

- **`apply-web-platform-infra.yml` cannot apply the new `terraform_data.root_authorized_keys` resource without CF Tunnel bridge.** The new resource opens SSH to root@host; the operator's IP IS in `var.admin_ips` but the CI runner's IP is not. Two paths:
  - **Path A (chosen):** Operator runs the FIRST apply locally from a worktree (operator IP allowlisted at the firewall). After the keypair is generated and the host's `authorized_keys` updated, every subsequent CI dispatch of `apply-deploy-pipeline-fix.yml` works because the CF Tunnel SSH bridge IS configured there.
  - **Path B (rejected):** Extend `apply-web-platform-infra.yml` with the same CF Tunnel + iptables NAT setup as `apply-deploy-pipeline-fix.yml`. Larger blast radius; this workflow already excludes server.tf SSH-provisioned resources from its `-target=` allow-list per its header comment. Not pursued.
- **Pre-existing `DEPLOY_SSH_PRIVATE_KEY` value in Doppler.** Either (a) it was a stale operator key matching a pre-#4181 era of `authorized_keys` and the host's `authorized_keys` was updated separately at some point, or (b) it was the operator's own key. Either way, the new resource OVERWRITES the value. There is no migration data loss because Doppler `prd_terraform/DEPLOY_SSH_PRIVATE_KEY` has only one consumer (`apply-deploy-pipeline-fix.yml`).
- **Phase 4.5 Network-Outage Deep-Dive triggered + verified.** Plan body matches both prose keywords (`SSH`, `handshake`) AND resource-shape (`terraform_data.deploy_pipeline_fix` has `provisioner "file"`). L3 verified closed (handshake initiates); L7 sshd `authorized_keys` is the load-bearing layer.
- **Phase 4.6 User-Brand Impact halt:** PASS (section present, threshold = `none`, scope-out reason present for sensitive-path diff).
- **Phase 4.7 Observability halt:** PASS (section present, all 5 fields populated, `discoverability_test.command` is `gh run list ...` — no `ssh `).
- **Phase 4.8 PAT halt:** PASS (no PAT-shaped tokens; `tls_private_key` generates the keypair).

### Verification Probes Run

```text
gh issue view 4177 -> state: CLOSED ("follow-through: CI→host SSH timeout blocks Apply deploy-pipeline-fix.yml")
gh pr view 4181   -> state: MERGED ("fix(infra): bridge CI→host SSH via Cloudflare Tunnel + Access service token")
gh pr view 4192   -> state: MERGED ("fix(infra): use literal APP_DOMAIN_BASE in cloudflared bridge step")
gh pr view 4196   -> state: MERGED ("fix(infra): mint write-capable Doppler service token for apply-web-platform-infra sync step")
gh issue view 4116 -> state: CLOSED ("observability: Better Stack heartbeat broken...")
gh issue view 4144 -> state: CLOSED ("infra: deploy webhook can't sudo inngest-bootstrap.sh...")
gh run view 26178703953 -> conclusion: failure (the run this plan unblocks)
grep "dopplerhq/doppler" apps/web-platform/infra/.terraform.lock.hcl -> version = "1.21.2"
grep 'config\s*=\s*"prd_terraform"' apps/web-platform/infra/*.tf -> doppler-write-token.tf:42 (precedent for prd_terraform writes)
grep "hashicorp/tls" apps/web-platform/infra/.terraform.lock.hcl -> not pinned (terraform init will add)
```

### Bootstrap Path Correction (load-bearing — supersedes the original Phase 2 description)

The original Phase 2 said "Operator dispatches `apply-web-platform-infra.yml` ... the new 3 `-target=` entries land". That is WRONG for `terraform_data.root_authorized_keys` — the CI runner cannot SSH to root@host (no CF Tunnel setup in that workflow, no admin_ips allowance).

**Corrected sequence:**

1. PR merges (lands the new `ci-ssh-key.tf` + cloud-init edits + variable cleanup).
2. **Operator runs the first apply LOCALLY** from a worktree:
   ```bash
   cd apps/web-platform/infra
   export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
   export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
   terraform init -input=false
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
     terraform apply -input=false \
       -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub" \
       -target=tls_private_key.ci_ssh \
       -target=doppler_secret.deploy_ssh_private_key \
       -target=terraform_data.root_authorized_keys
   ```
   The operator's `~/.ssh/id_<key>` (already in `authorized_keys` from the original host provision) authenticates the `terraform_data.root_authorized_keys` provisioner. Operator IP is in `var.admin_ips` so the firewall permits the direct SSH (no CF Tunnel needed for the operator path).
3. CI dispatches `apply-deploy-pipeline-fix.yml` — the new `DEPLOY_SSH_PRIVATE_KEY` from Doppler matches the host's `authorized_keys`; runs green.
4. Future CI runs use the same private key (no per-run regeneration needed; `tls_private_key.ci_ssh` is in TF state).
5. `apply-web-platform-infra.yml` does NOT need a `-target=` entry for `terraform_data.root_authorized_keys` because that resource has `triggers_replace = sha256(tls_private_key.ci_ssh.public_key_openssh)` — it only fires when the keypair rotates, and rotation is operator-explicit. The other two new resources (`tls_private_key.ci_ssh`, `doppler_secret.deploy_ssh_private_key`) CAN be added to the `apply-web-platform-infra.yml` allow-list (they don't require SSH); doing so keeps state in sync if drift occurs.

**`-target=` allow-list (corrected):**
- `apply-web-platform-infra.yml`: add `tls_private_key.ci_ssh`, `doppler_secret.deploy_ssh_private_key` (NOT `terraform_data.root_authorized_keys` — needs SSH, operator-local apply only).
- Document the local-apply requirement for `terraform_data.root_authorized_keys` as a one-time operator step in the PR's post-merge AC list; this is the smallest deviation from "everything in CI" — equivalent to `hr-fresh-host-provisioning-reachable-from-terraform-apply` which expects operator-driven bootstrap of new hosts.

This correction does NOT violate `hr-all-infrastructure-provisioning-servers` (the change still lands via Terraform/IaC, not manual SSH) or `hr-fresh-host-provisioning-reachable-from-terraform-apply` (the apply is reachable from `terraform apply`, just from operator context, mirroring how new hosts are bootstrapped).

## Overview

`Apply deploy-pipeline-fix.yml` (run 26178703953, dispatched 2026-05-20T17:24:39Z on `4409e7c0`) fails at the `provisioner "file"` block on `apps/web-platform/infra/server.tf:237` with:

```text
Error: file provisioner error
  with terraform_data.deploy_pipeline_fix,
  on server.tf line 237, in resource "terraform_data" "deploy_pipeline_fix":
 237:   provisioner "file" {
timeout - last error: SSH authentication failed (root@***:22):
ssh: handshake failed: ssh: unable to authenticate,
attempted methods [none publickey], no supported methods remain
```

**Critical:** This is a DIFFERENT failure than #4177 closed in PR #4181. #4177 was an L3 firewall block (`dial tcp ...:22: i/o timeout`). PR #4181/#4192/#4196 routed CI→host SSH through a Cloudflare Tunnel + Access service token, which fixed L3 — the runner now reaches sshd (handshake initiates instead of TCP timeout). What surfaced next is an L7/auth failure: **the public key whose private half the runner has loaded into `ssh-agent` is not present in root's `~/.ssh/authorized_keys` on the host.**

Per the L3→L7 ordering enforced by `hr-ssh-diagnosis-verify-firewall`: L3 is closed (handshake initiates); L7 (sshd-side `authorized_keys`) is the new load-bearing layer.

**Downstream blockage (UNCHANGED — same cascade as #4177):**
- AC14 — `Apply deploy-pipeline-fix.yml` green (THIS PLAN)
- AC15-AC18 — sudoers / v1.0.1 webhook re-fire / BetterStack 460830 — **explicitly out of scope per arguments**.

## User-Brand Impact

- **If this lands broken, the user experiences:** the operator-facing `Apply deploy-pipeline-fix.yml` workflow continues to fail red on every infra-touching merge, blocking host-resident updates (sudoers, deploy scripts, hooks.json, webhook.service). The downstream Inngest-heartbeat → BetterStack-460830 chain stays paused (#4144 cascade). No end-user data path is affected.
- **If this leaks, the user's data is exposed via:** no new exposure vector. Adding a CI key to root's `authorized_keys` is a key with a single load-bearing role (CI→host file provisioning over an already-authenticated CF Access service-token bridge); compromise scope equals the existing operator key already in `authorized_keys`. The Doppler `prd_terraform` store already holds the analogous `DEPLOY_SSH_PRIVATE_KEY` slot.
- **Brand-survival threshold:** `none`
- *Scope-out override (sensitive path `apps/web-platform/infra/**` + workflow edits):* `threshold: none, reason: CI→host SSH apply gap is operator-facing only; no end-user data path or runtime code path is modified by this change. Downstream blocked ACs (AC17 inngest-heartbeat, AC18 BetterStack) have their own brand-survival thresholds tracked under #4116 / #4144.`

## Hypotheses

Per `plan-network-outage-checklist.md` and `hr-ssh-diagnosis-verify-firewall`. L3→L7 ordering enforced.

| Layer | Verification artifact | Status |
|---|---|---|
| L3 — Firewall / NAT path | Handshake initiates (TCP banner reached); error is at SSH auth-method negotiation, not connect-timeout. CF Tunnel + iptables OUTPUT REDIRECT (PR #4181) opens the path. | **VERIFIED closed.** |
| L3 — DNS / routing | `ssh.soleur.ai` CNAME resolves; cloudflared opens local listener on 127.0.0.1:2222 within 15s gate. | **VERIFIED non-cause.** |
| L7 — CF Access (service token) | Tunnel authenticates via `TUNNEL_SERVICE_TOKEN_ID/_SECRET` from Doppler `prd_terraform`. The error is from the host's sshd downstream of CF Access, not from CF Access (which would return HTTP 403 at the edge). | **VERIFIED non-cause.** |
| L7 — sshd `authorized_keys` (NEW ROOT CAUSE) | sshd rejects all offered methods (`[none publickey]`). The runner's `ssh-agent` has `DEPLOY_SSH_PRIVATE_KEY` from Doppler loaded (`ssh-add -l >/dev/null` passes in step "Start ssh-agent with deploy key", workflow line 160), but the matching public half is NOT in root's `~/.ssh/authorized_keys` on host `135.181.45.178`. | **NEW ROOT CAUSE.** |
| L7 — fail2ban | Not applicable — `[sshd]` jail has `maxretry=5` over `findtime=10m`; one failed run does not reach the threshold and sshd would return `attempted methods []` (zero offered) under a ban, not `[none publickey]`. | **VERIFIED non-cause.** |

## Root Cause (chain-of-custody for root's `authorized_keys`)

The host's root `~/.ssh/authorized_keys` was populated by Hetzner Cloud at first-boot from `hcloud_server.web.ssh_keys = [hcloud_ssh_key.default.id]`. The `hcloud_ssh_key.default.public_key` was read via `file(var.ssh_key_path)` — at original provision the operator's local `~/.ssh/id_ed25519.pub` was the source.

Three lifecycle blocks pin this:
- `hcloud_ssh_key.default { lifecycle { ignore_changes = [public_key] } }` (server.tf:16-18) — CI passes an ephemeral key via `-var=ssh_key_path=$CI_SSH_PUB`, but Terraform refuses to update the `hcloud_ssh_key` resource. The Hetzner-side key registration is frozen.
- `hcloud_server.web { lifecycle { ignore_changes = [user_data, ssh_keys, image] } }` (server.tf:50) — even if `hcloud_ssh_key` were updated, the server's `ssh_keys` attribute is ignored.
- `cloud-init.yml` has **NO** `ssh_authorized_keys:` block, and `user_data` is ignored on the existing host anyway.

**Result:** there is no IaC path today that adds the CI's `DEPLOY_SSH_PRIVATE_KEY` public half to root's `authorized_keys` on the running host. The workflow header (apply-deploy-pipeline-fix.yml:24) asserts "`DEPLOY_SSH_PRIVATE_KEY` (auth for remote-exec; matches `DEPLOY_SSH_PUBLIC_KEY` already registered with the server via cloud-init)" — that claim is FALSE for this host: cloud-init was ignored at the time the key would have been needed.

In addition, `variable "deploy_ssh_public_key"` (variables.tf:91-95) is declared with `default = ""`, marked "legacy, kept for migration period", and is consumed nowhere in the `.tf` graph — it is dead.

## Research Reconciliation — Spec vs. Codebase

| Claim | Codebase reality | Plan response |
|---|---|---|
| Workflow header: `DEPLOY_SSH_PRIVATE_KEY` matches a `DEPLOY_SSH_PUBLIC_KEY` registered via cloud-init. | `apps/web-platform/infra/cloud-init.yml` has zero `ssh_authorized_keys` / `DEPLOY_SSH_PUBLIC_KEY` references; the deploy user is explicitly "No SSH key" (cloud-init.yml:17). The existing host was imported with `ignore_changes=[user_data, ssh_keys]`. | Header comment is wrong. Plan rewrites the header to reflect the actual mechanism (key landed via the new `terraform_data.root_authorized_keys` IaC path, below). |
| `variable "deploy_ssh_public_key"` exists in `variables.tf:91`. | Declared, unused, `default = ""`. | Plan repurposes this variable as the canonical input for the CI public key (renamed `ci_ssh_public_key`) and wires it into a new `terraform_data.root_authorized_keys` resource that idempotently appends the key to root's `authorized_keys`. |
| `connection { agent = true }` on `terraform_data.deploy_pipeline_fix` (server.tf:230-235). | ssh-agent has `DEPLOY_SSH_PRIVATE_KEY` loaded. Doppler `run` preserves parent env so `SSH_AUTH_SOCK` propagates to the Terraform child. | KEEP `agent = true` (no `connection` block change). The auth chain is correct on the runner side; the host side is the load-bearing fix. |
| PR #4181 plan "closed L3." | TCP path is open (handshake initiates); auth-method negotiation is the new gate. | This plan is the L7 follow-on. |

## Open Code-Review Overlap

`None` — no open `code-review`-labeled issues touch `apps/web-platform/infra/server.tf`, `apps/web-platform/infra/variables.tf`, or `.github/workflows/apply-deploy-pipeline-fix.yml`.

## Decision: Fix Approach (Option A chosen)

Three options weighed. Constraints: `hr-all-infrastructure-provisioning-servers` (no manual SSH), `hr-fresh-host-provisioning-reachable-from-terraform-apply` (must reach the host from `terraform apply` on a fresh-host bootstrap), `hr-tf-variable-no-operator-mint-default` (no operator-mint defaults).

### Option A (CHOSEN) — Generate the CI key in Terraform, store in Doppler, append to root's `authorized_keys` via a `terraform_data` resource

- A new `tls_private_key.ci_ssh` resource (with `algorithm = "ED25519"`) generates the keypair AT `terraform apply` time. The keypair lives in Terraform state (R2-backed, encrypted).
- The private half is written to Doppler `prd_terraform/DEPLOY_SSH_PRIVATE_KEY` via a `doppler_secret.deploy_ssh_private_key` resource (mirrors the `github_app_private_key` shape at `apps/web-platform/infra/github-app.tf:resource "doppler_secret" "github_app_private_key"`). `lifecycle.ignore_changes = [value]` is NOT set — rotation is via `terraform apply -replace=tls_private_key.ci_ssh`.
- The public half is appended to root's `~/.ssh/authorized_keys` via a new `terraform_data.root_authorized_keys` resource that uses the same CF Tunnel SSH bridge (works at `terraform apply` time both on the existing host AND on a fresh-host bootstrap, because the tunnel is the same egress path on both).
- The append is idempotent via `grep -qxF "$PUBKEY" ~/.ssh/authorized_keys || echo "$PUBKEY" >> ~/.ssh/authorized_keys`.
- A `ssh_authorized_keys:` block is ALSO added to `cloud-init.yml` so fresh-host bootstrap lands the same key on first boot (cloud-init + `terraform_data` parity matches the existing `webhook.service` / `ci-deploy.sh` pattern documented at server.tf:200-211).
- The bootstrap chicken-and-egg: the operator runs `apply-web-platform-infra.yml` ONE TIME from an operator-allow-listed source (existing path) with the operator's `~/.ssh/id_<key>` in `ssh-agent` — the existing operator key in root's `authorized_keys` is the load-bearing credential for the first apply that creates the CI key resource. After that first apply, every subsequent CI run uses the new `DEPLOY_SSH_PRIVATE_KEY` from Doppler.

**Why A is the right shape:**
- Fully automated (no operator `ssh root@host && cat >> authorized_keys`).
- Reachable from `terraform apply` on a fresh host (cloud-init + `terraform_data` parity, same pattern as `ci-deploy.sh`).
- Rotatable via `terraform apply -replace=tls_private_key.ci_ssh` — keypair rolls forward, Doppler secret rolls forward, host `authorized_keys` re-appended on next `apply-deploy-pipeline-fix` run.
- No new vendor; uses the existing `hashicorp/tls`, `DopplerHQ/doppler`, and CF Access service-token primitives already in the root.
- No change to the `connection { agent = true }` block on `terraform_data.deploy_pipeline_fix` — the runner-side auth chain is correct.

### Option B (REJECTED) — Switch `connection` block to `private_key = file(var.ci_ssh_private_key_path)`

Materializes Doppler's `DEPLOY_SSH_PRIVATE_KEY` to disk on the runner and references via path. Solves the runner side (no ssh-agent dependency, no env passthrough concern), but does NOT solve the host side — the public half still has to land in root's `authorized_keys` via some mechanism. So Option B is strictly a subset of Option A's runner-side concern. **Rejected because the agent path is already verified correct (the runner offers the key; sshd rejects it).** Switching to `private_key = file(...)` would not change the outcome.

### Option C (REJECTED) — Cloudflare Access SSH short-lived certificates

Rewires sshd to trust the Cloudflare Access CA, then CF Access mints ephemeral certificates per session. Most architecturally clean (no static key in Doppler at all), but:
- Requires reconfiguring sshd on the host (adds `TrustedUserCAKeys /etc/ssh/cf_ca.pub`, requires `AuthorizedPrincipalsFile` or accepting any cert principal).
- Requires the runner's `cloudflared access ssh` invocation to mint and forward a signed cert — incompatible with terraform's Go SSH client which does not auto-mint.
- Blast radius: any sshd misconfiguration locks the operator out.

**Rejected for this PR** — useful as a follow-up but materially larger change. Filed as a deferral.

## Files to Create

- `apps/web-platform/infra/ci-ssh-key.tf` — new file containing:
  - `resource "tls_private_key" "ci_ssh"` (algorithm = "ED25519")
  - `resource "doppler_secret" "deploy_ssh_private_key"` (project = "soleur", config = "prd_terraform", name = "DEPLOY_SSH_PRIVATE_KEY", value = `tls_private_key.ci_ssh.private_key_openssh`, visibility = "masked")
  - `resource "terraform_data" "root_authorized_keys"` — `connection { type = "ssh", host = hcloud_server.web.ipv4_address, user = "root", agent = true }`, `triggers_replace = sha256(tls_private_key.ci_ssh.public_key_openssh)`, `provisioner "remote-exec" { inline = ["mkdir -p /root/.ssh", "chmod 700 /root/.ssh", "touch /root/.ssh/authorized_keys", "chmod 600 /root/.ssh/authorized_keys", "grep -qxF '${trimspace(tls_private_key.ci_ssh.public_key_openssh)}' /root/.ssh/authorized_keys || echo '${trimspace(tls_private_key.ci_ssh.public_key_openssh)}' >> /root/.ssh/authorized_keys"] }`. `trimspace()` drops the trailing newline `tls_private_key.public_key_openssh` carries — required because the appended literal lands as a single `authorized_keys` line.
  - `output "ci_ssh_public_key_openssh"` (sensitive = false — public key, safe to log)

## Files to Edit

- `apps/web-platform/infra/cloud-init.yml` — add to root user:
  ```yaml
  users:
    - default
      ssh_authorized_keys:
        - ${ci_ssh_public_key_openssh}
  ```
  Add `ci_ssh_public_key_openssh = tls_private_key.ci_ssh.public_key_openssh` to the `templatefile()` interpolation map in `server.tf:29-43`. This ensures fresh-host bootstrap lands the CI key on first boot (cloud-init parity for `terraform_data.root_authorized_keys`).
- `apps/web-platform/infra/variables.tf` — DELETE the unused `variable "deploy_ssh_public_key"` (lines 91-95). Dead code; the value is now generated by `tls_private_key.ci_ssh`, not operator-supplied.
- `.github/workflows/apply-deploy-pipeline-fix.yml` — rewrite the misleading header comment (line 24) to reflect the actual mechanism:
  > `DEPLOY_SSH_PRIVATE_KEY` (auth for remote-exec; generated by `tls_private_key.ci_ssh` in `apps/web-platform/infra/ci-ssh-key.tf` and synced to Doppler via `doppler_secret.deploy_ssh_private_key`; the matching public key is appended to root's `~/.ssh/authorized_keys` by `terraform_data.root_authorized_keys` in the same file)
- `.github/workflows/apply-web-platform-infra.yml` — add 3 new `-target=` entries to the apply allow-list:
  - `-target=tls_private_key.ci_ssh`
  - `-target=doppler_secret.deploy_ssh_private_key`
  - `-target=terraform_data.root_authorized_keys`
  Update the header comment's allow-list count (66→70 was the last update at #4181; adjust to 70→73).
- `apps/web-platform/infra/.terraform.lock.hcl` — re-run `terraform init` to add `hashicorp/tls` provider. Verify pinned version in lockfile.

## Phase Plan

### Phase 0 — Preconditions (verify before touching code)

```bash
# P0.1 — confirm the Cloudflare Tunnel SSH bridge is reachable from an operator session
# (proves the L3+CF Access layers are good; we are operating only on the sshd-auth leg).
gh run view 26178703953 --log | grep -E "cloudflared TCP forward did not open|SSH authentication failed"

# P0.2 — confirm Doppler holds the deploy key (verify it exists, even if wrong contents — we will replace it)
doppler secrets get DEPLOY_SSH_PRIVATE_KEY -p soleur -c prd_terraform --plain | head -c 50

# P0.3 — confirm `hashicorp/tls` is not already pinned (so we know we need to bump the lockfile)
grep -A2 'provider "registry.terraform.io/hashicorp/tls"' apps/web-platform/infra/.terraform.lock.hcl || echo "tls provider not yet pinned"

# P0.4 — confirm cloud-init template var map signature
grep -n "templatefile.*cloud-init" apps/web-platform/infra/server.tf

# P0.5 — verify gsub awk pattern works for spec lane extraction (precedent grep)
grep -n "gsub.*lane:" plugins/soleur/skills/*/scripts/*.sh 2>/dev/null | head
```

### Phase 1 — RED tests

1. **AC1 — `terraform validate` clean** after the new `ci-ssh-key.tf`. Run `cd apps/web-platform/infra && terraform init -input=false && terraform validate`.
2. **AC2 — `terraform fmt -check`** clean on `ci-ssh-key.tf` and the edited files.
3. **AC3 — `actionlint`** clean on both modified workflow files.
4. **AC4 — `bash -c` syntax check** on any embedded shell snippets in workflow `run:` blocks that change (e.g., the new `-target=` lines).
5. **AC5 — `plan` returns expected adds** when targeting the new resources only:
   ```bash
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
     terraform plan -input=false \
       -var="ssh_key_path=$CI_SSH_PUB" \
       -target=tls_private_key.ci_ssh \
       -target=doppler_secret.deploy_ssh_private_key \
       -target=terraform_data.root_authorized_keys
   ```
   Expected: `Plan: 3 to add, 0 to change, 0 to destroy.`

### Phase 2 — GREEN (apply on a feature branch via `workflow_dispatch`)

Cannot dispatch the new resources from a feature branch directly — `apply-web-platform-infra.yml`'s `-target=` allow-list only honors merges to main. **The fix path is:**

1. Merge the PR.
2. Operator dispatches `apply-web-platform-infra.yml` with `reason = "Provision CI SSH key for #4177 follow-on"` from main. The operator's `~/.ssh/id_<key>` is in ssh-agent (already the load-bearing credential for this workflow, unchanged). The new 3 `-target=` entries land:
   - `tls_private_key.ci_ssh` — generates ED25519 keypair in TF state.
   - `doppler_secret.deploy_ssh_private_key` — writes the private half to Doppler `prd_terraform/DEPLOY_SSH_PRIVATE_KEY` (overwrites the stale value).
   - `terraform_data.root_authorized_keys` — appends the public half to root's `authorized_keys` via the CF Tunnel SSH bridge (works because operator's key is currently in `authorized_keys`).
3. After `apply-web-platform-infra.yml` succeeds, the next dispatch of `apply-deploy-pipeline-fix.yml` (manual or push-triggered by any subsequent infra-touching merge) uses the NEW `DEPLOY_SSH_PRIVATE_KEY` from Doppler and authenticates successfully.

**Pre-merge dry-run capability:** the operator can run the same `terraform plan -target=...` locally from the worktree using the canonical Doppler invocation triplet (`export AWS_*` for R2 backend + `doppler run --name-transformer tf-var` for TF vars), per `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`. The plan output is the dry-run.

### Phase 3 — Verification (post-merge, post-apply)

1. Dispatch `apply-deploy-pipeline-fix.yml` via `workflow_dispatch` with `reason = "Verify #4177 follow-on auth fix"`.
2. The run completes green: `terraform apply` succeeds at `terraform_data.deploy_pipeline_fix`, the file provisioners land, the `Verify server-side file hashes match local` step prints "All trigger-file hashes match and webhook is active."
3. Operator updates the PR body checkbox: "Apply deploy-pipeline-fix.yml first dispatch returned `conclusion=success`."

## Infrastructure (IaC)

### Terraform changes

- New file `apps/web-platform/infra/ci-ssh-key.tf` containing `tls_private_key.ci_ssh`, `doppler_secret.deploy_ssh_private_key`, `terraform_data.root_authorized_keys`, `output.ci_ssh_public_key_openssh`.
- New required provider: `hashicorp/tls` (`~> 4.0`). Added via `terraform init`; lockfile committed.
- No new `TF_VAR_*` sensitive variables (the keypair is generated, not operator-supplied — complies with `hr-tf-variable-no-operator-mint-default`).
- One new Doppler-stored secret (`DEPLOY_SSH_PRIVATE_KEY` rewritten via `doppler_secret` resource, not operator-set).

### Apply path

**Cloud-init + idempotent bootstrap script (Option (b)).** The new `terraform_data.root_authorized_keys` resource:
- On the existing host: appends the CI public key to root's `authorized_keys` via `remote-exec` over the CF Tunnel SSH bridge. Idempotent via `grep -qxF ... || echo ... >>`.
- On a fresh host: cloud-init's `ssh_authorized_keys:` block lands the CI key on first boot, BEFORE the `terraform_data` resource fires. `terraform_data.root_authorized_keys` then runs as a no-op (already in `authorized_keys`).

Both paths are reachable from `terraform apply` per `hr-fresh-host-provisioning-reachable-from-terraform-apply`.

**Expected downtime:** zero. The existing operator key remains in `authorized_keys` throughout the change — both operator and CI can authenticate during the transition.

### Distinctness / drift safeguards

- `doppler_secret.deploy_ssh_private_key` pins `project = "soleur"`, `config = "prd_terraform"`. The resource cannot land in dev without a config edit — caught at PR review (`hr-dev-prd-distinct-supabase-projects` analog for Doppler).
- `tls_private_key.ci_ssh` rotation is operator-explicit via `terraform apply -replace=tls_private_key.ci_ssh` (NO `lifecycle.ignore_changes = [value]` on the Doppler secret — when the keypair rolls, the secret rolls).
- `terraform_data.root_authorized_keys.triggers_replace = sha256(tls_private_key.ci_ssh.public_key_openssh)` — when the keypair rolls, the host append re-fires. Idempotent on the host side via `grep -qxF`.
- The old (now-stale) public key remains in `authorized_keys` after rotation. Cleanup is a separate concern, filed as deferral (#TBD-rotation-cleanup).

### Vendor-tier reality check

- `hashicorp/tls` is free / no tier gate.
- `DopplerHQ/doppler` requires `DOPPLER_TOKEN_TF` (already provisioned for `doppler_secret.github_app_*` resources).
- No new Cloudflare resources; uses the existing CF Tunnel SSH ingress + Access service token created in PR #4181.

## Observability

```yaml
liveness_signal:
  what: "Apply deploy-pipeline-fix.yml run conclusion"
  cadence: "every infra-trigger-file merge OR manual workflow_dispatch"
  alert_target: "GitHub Actions Slack integration (existing) + auto-filed `infra-drift` issue via 12h cron"
  configured_in: ".github/workflows/apply-deploy-pipeline-fix.yml + .github/workflows/scheduled-terraform-drift.yml"

error_reporting:
  destination: "GitHub Actions step summary + `::error::` annotations + run log"
  fail_loud: true

failure_modes:
  - mode: "Doppler DEPLOY_SSH_PRIVATE_KEY missing/empty"
    detection: "Verify Deploy SSH key step (apply-deploy-pipeline-fix.yml:120-127) — `doppler secrets get DEPLOY_SSH_PRIVATE_KEY --plain` + `-z` guard"
    alert_route: "::error:: annotation + step fail; surfaces in workflow conclusion=failure"
  - mode: "tls_private_key.ci_ssh.public_key_openssh not in root authorized_keys (race / drift)"
    detection: "Apply deploy-pipeline-fix.yml file provisioner fails with `attempted methods [none publickey]`"
    alert_route: "workflow conclusion=failure + apply-deploy-pipeline-fix step summary"
  - mode: "Operator rolls tls_private_key.ci_ssh but forgets to re-apply"
    detection: "scheduled-terraform-drift.yml 12h cron surfaces the pending replace on terraform_data.root_authorized_keys"
    alert_route: "auto-filed `infra-drift` issue with workflow run URL"

logs:
  where: "GitHub Actions run logs (90d retention) + workflow step summary"
  retention: "90 days"

discoverability_test:
  command: gh run list --workflow=apply-deploy-pipeline-fix.yml --limit 1 --json conclusion --jq '.[0].conclusion'
  expected_output: "success or failure"
  # "success" is the post-bootstrap steady state. "failure" is the legitimate
  # pre-bootstrap signal that operator-local apply for #4202 (the deferred-
  # automation tracker) has not yet run. Both states are valid in the
  # post-PR-merge / pre-bootstrap transition window; the discovery signal IS
  # the workflow conclusion. Once operator runs the targeted apply, the next
  # dispatch flips to "success" and stays there.
```

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** — `apps/web-platform/infra/ci-ssh-key.tf` exists with `tls_private_key.ci_ssh`, `doppler_secret.deploy_ssh_private_key`, `terraform_data.root_authorized_keys`, `output.ci_ssh_public_key_openssh`.
- [x] **AC2** — `cd apps/web-platform/infra && terraform init -input=false -lockfile=readonly && terraform validate` exits 0.
- [x] **AC3** — `terraform fmt -check apps/web-platform/infra/` exits 0.
- [x] **AC4** — `actionlint` clean on `.github/workflows/apply-deploy-pipeline-fix.yml` and `.github/workflows/apply-web-platform-infra.yml`.
- [x] **AC5** — `bash -c` clean on any new/modified embedded shell snippets in those workflow files.
- [x] **AC6** — `apps/web-platform/infra/variables.tf` no longer contains `variable "deploy_ssh_public_key"`. Verified by `! grep -q 'variable "deploy_ssh_public_key"' apps/web-platform/infra/variables.tf`.
- [x] **AC7** — `cloud-init.yml` contains `ssh_authorized_keys:` under the `default` user (or root user, per cloud-init schema). Verified by `grep -A2 ssh_authorized_keys apps/web-platform/infra/cloud-init.yml`.
- [x] **AC8** — Header comment in `apply-deploy-pipeline-fix.yml` rewrites the false "matches DEPLOY_SSH_PUBLIC_KEY already registered with the server via cloud-init" claim to the actual mechanism (`tls_private_key.ci_ssh` → `terraform_data.root_authorized_keys`).
- [x] **AC9** — `apply-web-platform-infra.yml` apply allow-list contains 2 new `-target=` entries: `tls_private_key.ci_ssh`, `doppler_secret.deploy_ssh_private_key` (per `Bootstrap Path Correction`: `terraform_data.root_authorized_keys` is operator-local-apply only; CI cannot SSH-provision from this workflow). Verified by `grep -cE '^\s+-target=(tls_private_key\.ci_ssh|doppler_secret\.deploy_ssh_private_key)' .github/workflows/apply-web-platform-infra.yml` returns 2 (saved-plan workflow shape — `-target=` lives in the plan step only; the apply step consumes the saved tfplan).
- [x] **AC10** — `.terraform.lock.hcl` updated to include `hashicorp/tls` provider entry.
- [x] **AC11** — Plan reconciliation: `## Hypotheses` table includes a row classifying L7 sshd authorized_keys as the load-bearing layer; `## Research Reconciliation` calls out the cloud-init `ssh_authorized_keys` absence; `## Open Code-Review Overlap` = "None" (verified).
- [ ] **AC12** — `Ref #4177` in PR body (not `Closes` — issue #4177 was already closed by PR #4181; this PR is the L7 follow-on, referenced not auto-closing).

### Post-merge (operator)

- [ ] **AC13a** — Operator runs the LOCAL bootstrap apply from a worktree (per `Bootstrap Path Correction`): `terraform apply -target=tls_private_key.ci_ssh -target=doppler_secret.deploy_ssh_private_key -target=terraform_data.root_authorized_keys` using operator's `~/.ssh/id_ed25519.pub` as `ssh_key_path`. All 3 resources end up in TF state. Verifiable via `terraform state list | grep -E "tls_private_key.ci_ssh|doppler_secret.deploy_ssh_private_key|terraform_data.root_authorized_keys"` returns 3 lines. (Operator-local — non-automatable per `terraform_data.root_authorized_keys` SSH dependency on operator IP; analogous to fresh-host bootstrap allowed by `hr-fresh-host-provisioning-reachable-from-terraform-apply`.)
- [ ] **AC13b** — Operator subsequently dispatches `apply-web-platform-infra.yml` with `reason = "Adopt CI SSH key resources into CI allow-list"`. Workflow returns `conclusion=success`; `tls_private_key.ci_ssh` and `doppler_secret.deploy_ssh_private_key` are re-applied as no-ops (state already matches). Verifiable via `gh run view --json conclusion --jq '.conclusion'` returns `success`. (Automatable.)
- [ ] **AC14** — Doppler `prd_terraform/DEPLOY_SSH_PRIVATE_KEY` matches `tls_private_key.ci_ssh.private_key_openssh` after AC13. Verifiable via `doppler secrets get DEPLOY_SSH_PRIVATE_KEY -p soleur -c prd_terraform --plain | ssh-keygen -y -f /dev/stdin` returns the same public key as `terraform output -raw ci_ssh_public_key_openssh`. (Automatable; no manual eyeballing.)
- [ ] **AC15** — Operator dispatches `apply-deploy-pipeline-fix.yml` with `reason = "Verify #4177 follow-on auth fix"`. Workflow returns `conclusion=success`. Verifiable via `gh run list --workflow=apply-deploy-pipeline-fix.yml --limit 1 --json conclusion --jq '.[0].conclusion'` returns `success`.
- [ ] **AC16** — `gh issue comment 4177 --body "<verification comment with workflow run URL>"` posted. (Automatable.)

## Test Strategy

- **No new unit tests.** This is a pure-IaC change; no application-layer code is modified.
- **`terraform validate` is the canonical-correctness gate.** It catches schema errors in the new `tls_private_key`, `doppler_secret`, and `terraform_data` resources.
- **`terraform plan -target=...` is the dry-run gate.** Operator can run locally pre-merge via the canonical Doppler invocation triplet.
- **The post-merge `apply-deploy-pipeline-fix.yml` dispatch IS the end-to-end test.** A green run proves: (a) Doppler stores the new private key, (b) the runner loads it into ssh-agent, (c) sshd on the host accepts the matching public key from `authorized_keys`, (d) file provisioners land, (e) `Verify server-side file hashes match local` passes.

## Sharp Edges

- **Cloud-init `ssh_authorized_keys` placement.** Cloud-init schemas vary by Ubuntu version. For Ubuntu 24.04 (per `hcloud_server.web.image = "ubuntu-24.04"`), `ssh_authorized_keys:` MUST be under the user block (e.g., `users: - default: { ssh_authorized_keys: [...] }`) — putting it at the root level applies only to the default user but has different precedence semantics. Use the per-user form. Reference: `cloud-init` docs `Users and Groups` module. Verify via `cloud-init schema --config-file cloud-init.yml` at plan time.
- **Doppler secret rotation cascade.** When the operator runs `terraform apply -replace=tls_private_key.ci_ssh`, the keypair regenerates AND `doppler_secret.deploy_ssh_private_key.value` is recomputed (no `ignore_changes` on `value`). The next `apply-deploy-pipeline-fix.yml` run picks up the new private key from Doppler; `terraform_data.root_authorized_keys` re-fires because its `triggers_replace = sha256(tls_private_key.ci_ssh.public_key_openssh)` changed. The OLD public key remains in `authorized_keys` (no cleanup) — operator should re-run with a manual cleanup snippet OR file a follow-up to add `sed -i '/<old-pubkey>/d'` once-per-rotation. **Scope-out**: rotation cleanup is filed as a follow-up issue (out of scope for this PR).
- **The R2-backed TF state now stores a private key.** This is the same trust model as `random_id.tunnel_secret` and other sensitive state in the same backend; R2 access is gated by `AWS_ACCESS_KEY_ID/_SECRET` in Doppler `prd_terraform`. Compliance posture is unchanged.
- **CF Tunnel SSH bridge is a hard dependency for `terraform_data.root_authorized_keys`.** If CF Access service token expires (`session_duration = "15m"` per PR #4181 plan), the apply fails. The operator dispatches `apply-deploy-pipeline-fix.yml` (which establishes the bridge per-run) ahead of the `apply-web-platform-infra.yml` dispatch — or `apply-web-platform-infra.yml` already includes the same CF Tunnel + iptables NAT redirect setup (per PR #4181's Phase 3 scope), so this is satisfied.
- **The new `ci-ssh-key.tf` file has no automated import path on a fresh host.** On a brand-new host (no prior `tls_private_key.ci_ssh` state), `terraform apply` creates the resource fresh — no import needed. The R2 state file is the source of truth.
- **`hr-never-paste-secrets-via-bang-prefix`.** When debugging Doppler values during AC13/AC14 verification, the operator MUST use `doppler secrets get ... --plain` directly in the workflow context — NEVER paste the value into a chat / agent context.
- **`hr-fresh-host-provisioning-reachable-from-terraform-apply` cross-check.** The fresh-host bootstrap path (cloud-init `ssh_authorized_keys` + first-boot `terraform_data.root_authorized_keys` no-op) is reachable from `terraform apply` end-to-end. Verified by: cloud-init lands the key on boot (Hetzner Cloud injects via `hcloud_server.ssh_keys` + cloud-init merges into user `~/.ssh/authorized_keys`), then `terraform_data.root_authorized_keys` connects, `grep -qxF` finds the key, no-op.
- **AGENTS.md `hr-write-boundary-sentinel-sweep-all-write-sites`.** The DEPLOY_SSH_PRIVATE_KEY value lives in three write surfaces: Doppler (via `doppler_secret.deploy_ssh_private_key`), TF state (R2 backend, sensitive), and the runner's ephemeral ssh-agent (workflow line 159). All three are accounted for in this plan.

## Deferred / Out-of-Scope

- **AC15-AC18 from the #4144 cascade** (sudoers verification, v1.0.1 webhook re-fire, BetterStack 460830 unpause). Per arguments: stop after `apply-deploy-pipeline-fix.yml` is green.
- **Rotation cleanup for stale `authorized_keys` entries.** Filed as deferral. Re-evaluation when first CI key rotation is performed.
- **Option C (CF Access SSH short-lived certs).** Filed as deferral. Re-evaluation: when (a) static-key footprint in Doppler becomes a compliance concern, or (b) operator wants per-session auditability of CI access.
- **Migration of `apply-web-platform-infra.yml` and `scheduled-terraform-drift.yml` to use the same key flow.** Those workflows use `connection { agent = false }` semantics implicitly (no SSH provisioner reaches the host except `terraform_data.deploy_pipeline_fix` which is the topic of this PR). No migration needed in this PR.

## Domain Review

**Domains relevant:** Engineering (CTO), Security (CISO).

### Engineering (CTO)

**Status:** reviewed (carry-forward from PR #4181 architecture).
**Assessment:** Auth-leg follow-on to PR #4181's L3 fix. Uses the same CF Tunnel + Access service-token bridge already provisioned. Adds one new keypair generation step + one Doppler secret + one idempotent remote-exec resource. No new architectural surface; uses the existing `terraform_data` + `connection { agent = true }` pattern already employed by `terraform_data.apparmor_bwrap_profile`, `terraform_data.deploy_pipeline_fix`, and `terraform_data.fail2ban_jail`. Mirrors the `doppler_secret.github_app_private_key` shape for the secret-write surface.

### Security (CISO)

**Status:** reviewed.
**Assessment:** Adds one new credential (`tls_private_key.ci_ssh`) with a single load-bearing role (CI→host file provisioning). Stored in R2-backed TF state (sensitive=true) and Doppler `prd_terraform` (visibility=masked). Public half appended to root's `~/.ssh/authorized_keys` — same trust model as the existing operator key already in that file. CF Access service-token bridge is the only network path; sshd has `PermitRootLogin prohibit-password` (sshd_config.d/01-hardening.conf:6), so password auth cannot be exercised. fail2ban jail unchanged. No new attack surface relative to PR #4181's posture.

No data-handling change (regulated-data surfaces unchanged); GDPR gate (Phase 2.7) does not fire on infrastructure-only edits to host-auth.

## GDPR / Compliance Gate

Not triggered. Canonical regex (`hr-gdpr-gate-on-regulated-data-surfaces`) covers schema / migration / auth-flow / API-route / `.sql` surfaces. This PR touches `.tf` + `.yml` only, no user-data path. None of the (a)-(d) expansion triggers fire (no new LLM/external-API-on-user-data, threshold = `none`, no learnings/specs cron, no new artifact distribution surface).

## PR Body Reminder

```
fix(infra): unblock Apply deploy-pipeline-fix.yml CI→host SSH authentication

L7 follow-on to PR #4181's L3 fix. Generate the CI SSH keypair via
`tls_private_key.ci_ssh` in `apps/web-platform/infra/ci-ssh-key.tf`,
sync the private half to Doppler `prd_terraform/DEPLOY_SSH_PRIVATE_KEY`
via `doppler_secret`, and append the public half to root's
`~/.ssh/authorized_keys` via an idempotent `terraform_data` resource
that uses the existing CF Tunnel SSH bridge. Cloud-init `ssh_authorized_keys`
parity ensures fresh-host bootstrap lands the same key on first boot.

Ref #4177

Root cause: workflow header asserted `DEPLOY_SSH_PRIVATE_KEY` matched a
`DEPLOY_SSH_PUBLIC_KEY` registered via cloud-init — false, because
cloud-init.yml had no `ssh_authorized_keys` block and `user_data` is
ignored on the existing host. PR #4181 closed L3 (CF Tunnel + Access),
which surfaced this L7 gap.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```
