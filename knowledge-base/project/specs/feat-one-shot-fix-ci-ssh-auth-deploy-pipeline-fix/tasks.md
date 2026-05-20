---
title: "Tasks — fix(infra): unblock Apply deploy-pipeline-fix.yml CI→host SSH authentication"
date: 2026-05-20
issue: 4177
plan: knowledge-base/project/plans/2026-05-20-fix-ci-host-ssh-auth-deploy-pipeline-fix-plan.md
lane: cross-domain
---

# Tasks — Unblock `Apply deploy-pipeline-fix.yml` CI→host SSH authentication

## Phase 0 — Preconditions

- 0.1 Confirm CF Tunnel SSH bridge reachable: `gh run view 26178703953 --log | grep "SSH authentication failed"` (proves L3+CF Access OK).
- 0.2 Read current Doppler `DEPLOY_SSH_PRIVATE_KEY` (header check only, no value paste): `doppler secrets get DEPLOY_SSH_PRIVATE_KEY -p soleur -c prd_terraform --plain | head -c 50`.
- 0.3 Confirm `hashicorp/tls` not pinned: `grep -A2 'hashicorp/tls' apps/web-platform/infra/.terraform.lock.hcl || echo "needs init"`.
- 0.4 Read cloud-init `templatefile()` interpolation map: `grep -n templatefile apps/web-platform/infra/server.tf`.
- 0.5 Verify cloud-init `ssh_authorized_keys` schema for ubuntu-24.04 default user: `cloud-init schema --config-file apps/web-platform/infra/cloud-init.yml`.

## Phase 1 — Author TF resources

- 1.1 Create `apps/web-platform/infra/ci-ssh-key.tf` with `tls_private_key.ci_ssh` (algorithm = "ED25519").
- 1.2 In same file, add `resource "doppler_secret" "deploy_ssh_private_key"` (project = "soleur", config = "prd_terraform", name = "DEPLOY_SSH_PRIVATE_KEY", value = `tls_private_key.ci_ssh.private_key_openssh`, visibility = "masked", no `ignore_changes`).
- 1.3 In same file, add `resource "terraform_data" "root_authorized_keys"`:
  - `connection { type = "ssh", host = hcloud_server.web.ipv4_address, user = "root", agent = true }`
  - `triggers_replace = sha256(tls_private_key.ci_ssh.public_key_openssh)`
  - `provisioner "remote-exec" { inline = [ "mkdir -p /root/.ssh", "chmod 700 /root/.ssh", "touch /root/.ssh/authorized_keys", "chmod 600 /root/.ssh/authorized_keys", "grep -qxF \"${tls_private_key.ci_ssh.public_key_openssh}\" /root/.ssh/authorized_keys || echo \"${tls_private_key.ci_ssh.public_key_openssh}\" >> /root/.ssh/authorized_keys" ] }`
- 1.4 In same file, add `output "ci_ssh_public_key_openssh" { value = tls_private_key.ci_ssh.public_key_openssh, sensitive = false }`.
- 1.5 `cd apps/web-platform/infra && terraform init -input=false` to fetch tls provider + write lockfile.
- 1.6 `terraform fmt apps/web-platform/infra/ci-ssh-key.tf`.

## Phase 2 — Wire cloud-init for fresh-host parity

- 2.1 Edit `apps/web-platform/infra/cloud-init.yml`:
  - Update the `users:` block so `default` includes `ssh_authorized_keys: [${ci_ssh_public_key_openssh}]` (per ubuntu-24.04 cloud-init schema).
- 2.2 Edit `apps/web-platform/infra/server.tf` (lines 29-43): add `ci_ssh_public_key_openssh = tls_private_key.ci_ssh.public_key_openssh` to the `templatefile()` interpolation map for `user_data`.

## Phase 3 — Cleanup dead variable + workflow header

- 3.1 Edit `apps/web-platform/infra/variables.tf` lines 91-95: DELETE the unused `variable "deploy_ssh_public_key"`.
- 3.2 Edit `.github/workflows/apply-deploy-pipeline-fix.yml` line 24: rewrite the header comment to reflect the actual mechanism (`tls_private_key.ci_ssh` → `doppler_secret.deploy_ssh_private_key` + `terraform_data.root_authorized_keys`).

## Phase 4 — Extend apply allow-list

- 4.1 Edit `.github/workflows/apply-web-platform-infra.yml`: add ONLY `-target=tls_private_key.ci_ssh` and `-target=doppler_secret.deploy_ssh_private_key` to BOTH the plan and apply steps (per saved-plan workflow shape — `-var=` on plan only, `-target=` on both). DO NOT add `-target=terraform_data.root_authorized_keys` — that resource requires SSH to root@host, and `apply-web-platform-infra.yml` does NOT set up the CF Tunnel SSH bridge (only `apply-deploy-pipeline-fix.yml` does). Per the plan's Bootstrap Path Correction (plan §line-78), `terraform_data.root_authorized_keys` is applied operator-locally on the first bootstrap and re-fires only on key rotation (operator-explicit).
- 4.2 Update header allow-list count comment in the same file.

## Phase 5 — Pre-merge validation

- 5.1 `cd apps/web-platform/infra && terraform validate` exits 0.
- 5.2 `terraform fmt -check apps/web-platform/infra/` exits 0.
- 5.3 `actionlint .github/workflows/apply-deploy-pipeline-fix.yml .github/workflows/apply-web-platform-infra.yml` exits 0.
- 5.4 `! grep -q 'variable "deploy_ssh_public_key"' apps/web-platform/infra/variables.tf` (AC6).
- 5.5 `grep -c "tls_private_key.ci_ssh\|doppler_secret.deploy_ssh_private_key" .github/workflows/apply-web-platform-infra.yml` returns ≥ 4 (2 -target each on plan + apply). Also verify `terraform_data.root_authorized_keys` does NOT appear in this workflow file.
- 5.6 Commit + push + open PR with `Ref #4177` (not `Closes`).

## Phase 6 — Post-merge apply (operator)

- 6.1 Dispatch `apply-web-platform-infra.yml` (workflow_dispatch) with `reason = "Provision CI SSH key for #4177 follow-on"`. Wait for `conclusion=success` (AC13).
- 6.2 Verify Doppler/keypair alignment (AC14):
  ```bash
  doppler secrets get DEPLOY_SSH_PRIVATE_KEY -p soleur -c prd_terraform --plain | ssh-keygen -y -f /dev/stdin > /tmp/doppler.pub
  cd apps/web-platform/infra && terraform output -raw ci_ssh_public_key_openssh > /tmp/tf.pub
  diff /tmp/doppler.pub /tmp/tf.pub && echo MATCH
  ```
- 6.3 Dispatch `apply-deploy-pipeline-fix.yml` (workflow_dispatch) with `reason = "Verify #4177 follow-on auth fix"`. Wait for `conclusion=success` (AC15).
- 6.4 `gh issue comment 4177 --body "Verified L7 auth fix lands via PR #<N>. Apply deploy-pipeline-fix.yml dispatch <run-url> returned success."` (AC16).

## Phase 7 — Compound + ship

- 7.1 Write learning at `knowledge-base/project/learnings/<topic>.md` capturing: (a) the workflow header's false claim was the root-cause smoking gun (a comment was technical debt that misdirected the prior #4181 plan author), (b) auth-leg follow-on pattern after L3 closure, (c) the `tls_private_key` → `doppler_secret` → `terraform_data.root_authorized_keys` chain as a reusable "rotate-by-Terraform" primitive for host-side ssh access.
- 7.2 `/soleur:ship`.
