# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-20-fix-ci-host-ssh-auth-deploy-pipeline-fix-plan.md
- Status: complete

### Errors
None. All 4 deepen-plan halt gates (4.5 Network-Outage, 4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT) PASS.

### Decisions
- Root cause identified: PR #4181 closed L3 (CF Tunnel SSH bridge) but did not close L7. The `DEPLOY_SSH_PRIVATE_KEY` in Doppler `prd_terraform` does NOT correspond to any public key in root's `~/.ssh/authorized_keys` on the host. The workflow header's claim that the key was registered via cloud-init is FALSE — `cloud-init.yml` has no `ssh_authorized_keys` block, and `user_data` is ignored on the existing host (`hcloud_server.web` `ignore_changes=[user_data, ssh_keys, image]`).
- Fix approach (Option A): New `apps/web-platform/infra/ci-ssh-key.tf` with `tls_private_key.ci_ssh` (ED25519), `doppler_secret.deploy_ssh_private_key` (writes to `prd_terraform`, precedent: `doppler-write-token.tf:42`), and `terraform_data.root_authorized_keys` (idempotent `grep -qxF || echo >>` over the existing CF Tunnel SSH bridge). Plus `ssh_authorized_keys:` in cloud-init for fresh-host parity.
- Bootstrap Path Correction (deepen-pass): `terraform_data.root_authorized_keys` must be applied LOCALLY by the operator (operator IP is in `var.admin_ips`, operator's existing key is in `authorized_keys`). The other two new resources (`tls_private_key.ci_ssh`, `doppler_secret.deploy_ssh_private_key`) go into `apply-web-platform-infra.yml`'s `-target=` allow-list. This satisfies `hr-all-infrastructure-provisioning-servers` (still IaC, not manual SSH) and `hr-fresh-host-provisioning-reachable-from-terraform-apply` (same pattern as fresh-host operator bootstrap).
- Rejected alternatives: Option B (switch `connection { agent = true }` → `private_key = file(...)`) doesn't solve the host-side gap. Option C (CF Access SSH short-lived certificates) requires sshd reconfig — too large for this PR; filed as deferral.
- Out-of-scope confirmed: ACs 15-18 (sudoers, v1.0.1 webhook re-fire, BetterStack 460830 unpause). Per arguments, stop after `apply-deploy-pipeline-fix.yml` goes green.

### Components Invoked
- soleur:plan
- soleur:deepen-plan
- gh CLI (issue/PR verification)
- doppler CLI (provider auth scope verification)
- Read/Bash/Edit/Write/Grep tools
