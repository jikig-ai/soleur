# L7 follow-on to PR #4181 (which closed the L3 CF Tunnel SSH bridge gap).
# The bridge made CI's SSH handshake to root@host reach sshd, but sshd
# rejected with `attempted methods [none publickey], no supported methods
# remain` because Doppler `prd_terraform/DEPLOY_SSH_PRIVATE_KEY` did NOT
# correspond to any public key in root's `~/.ssh/authorized_keys`. The
# workflow header in `apply-deploy-pipeline-fix.yml` asserted parity via
# cloud-init but cloud-init.yml had no `ssh_authorized_keys` block AND
# `hcloud_server.web.lifecycle.ignore_changes = [user_data, ssh_keys]`
# means cloud-init never re-applies to the existing host. See plan
# `knowledge-base/project/plans/2026-05-20-fix-ci-host-ssh-auth-deploy-pipeline-fix-plan.md`.
#
# This file generates the CI SSH keypair in Terraform, syncs the private
# half to Doppler, and appends the public half to root's authorized_keys
# via an idempotent provisioner.
#
# Bootstrap path (load-bearing): on the FIRST apply after this lands, the
# new `terraform_data.root_authorized_keys` resource opens SSH to
# root@host. The CI workflow `apply-web-platform-infra.yml` cannot reach
# root@host (no CF Tunnel SSH bridge in that workflow, runner IP not in
# `var.admin_ips`). The operator runs the bootstrap apply LOCALLY from a
# worktree using their own `~/.ssh/id_ed25519` (already in
# `authorized_keys`). After that one-time operator apply, every
# subsequent dispatch of `apply-deploy-pipeline-fix.yml` uses the new
# `DEPLOY_SSH_PRIVATE_KEY` and authenticates successfully.
#
# Rotation: `terraform apply -replace=tls_private_key.ci_ssh` rolls the
# keypair. `doppler_secret.deploy_ssh_private_key.value` rolls in the
# same apply (no `ignore_changes`). `terraform_data.root_authorized_keys`
# re-fires because its `triggers_replace` hash changes; the new public
# key is appended. The OLD public key remains in `authorized_keys` until
# a follow-up cleanup runs (filed as deferral — out of scope here).
#
# Fresh-host parity: `cloud-init.yml` adds a top-level
# `ssh_authorized_keys:` block carrying the same public key, so a
# brand-new host lands the key on first boot before this resource fires;
# `grep -qxF` then no-ops.

resource "tls_private_key" "ci_ssh" {
  algorithm = "ED25519"
}

locals {
  # trimspace() strips the trailing newline tls_private_key.public_key_openssh
  # carries. Used in 3 sites (remote-exec grep + echo, cloud-init template
  # interpolation in server.tf) — without trim, grep -qxF never matches on
  # the appended literal AND cloud-init renders an indented blank line under
  # ssh_authorized_keys.
  ci_ssh_pubkey = trimspace(tls_private_key.ci_ssh.public_key_openssh)
}

resource "doppler_secret" "deploy_ssh_private_key" {
  project    = "soleur"
  config     = "prd_terraform"
  name       = "DEPLOY_SSH_PRIVATE_KEY"
  value      = tls_private_key.ci_ssh.private_key_openssh
  visibility = "masked"
}

# Appends `tls_private_key.ci_ssh.public_key_openssh` to root's
# `~/.ssh/authorized_keys` on the existing host. Operator-local apply
# only — see file header.
#
# Idempotent on the host side: `grep -qxF <key> || echo <key> >>`. The
# `trimspace()` strips the trailing newline that
# `tls_private_key.public_key_openssh` carries; without it the appended
# literal would be a two-line block (one of them blank), breaking the
# `grep -qxF` exact-line match on subsequent runs.
resource "terraform_data" "root_authorized_keys" {
  triggers_replace = sha256(tls_private_key.ci_ssh.public_key_openssh)

  connection {
    type  = "ssh"
    host  = hcloud_server.web["web-1"].ipv4_address
    user  = "root"
    agent = true
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "mkdir -p /root/.ssh",
      "chmod 700 /root/.ssh",
      "touch /root/.ssh/authorized_keys",
      "chmod 600 /root/.ssh/authorized_keys",
      "grep -qxF '${local.ci_ssh_pubkey}' /root/.ssh/authorized_keys || echo '${local.ci_ssh_pubkey}' >> /root/.ssh/authorized_keys",
    ]
  }
}

# Cloud-init's `ssh_authorized_keys:` block on a fresh host needs the
# same public key. server.tf:29-43 reads this output into the
# `templatefile()` interpolation map so `cloud-init.yml`'s
# `${ci_ssh_public_key_openssh}` resolves at plan time.
#
# Public key, safe to log — not marked sensitive.
output "ci_ssh_public_key_openssh" {
  description = "OpenSSH-format public half of the CI SSH keypair. Appended to root's authorized_keys via terraform_data.root_authorized_keys and to cloud-init.yml's ssh_authorized_keys block for fresh-host parity."
  value       = tls_private_key.ci_ssh.public_key_openssh
}
