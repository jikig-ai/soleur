---
module: Web Platform Infrastructure
date: 2026-04-03
problem_type: infrastructure_drift
component: terraform
symptoms:
  - "terraform plan shows terraform_data.doppler_install needs replacement"
  - "drift detection workflow fails with non-zero exit"
  - "ssh: parse error in message type 0 on terraform apply"
root_cause: post_merge_gap
resolution_type: manual_apply
severity: medium
tags: [terraform, drift, remote-exec, ssh, encrypted-key, doppler, provisioner]
synced_to: []
---

# terraform_data remote-exec Drift and Encrypted SSH Key Incompatibility

## Problem

PR #1496 added a `terraform_data.doppler_install` resource with a `remote-exec` provisioner to install Doppler CLI on the Hetzner server. The PR was merged but `terraform apply` was never run post-merge. The drift detection workflow (#1505) flagged the unapplied resource.

When attempting to apply, `terraform apply` failed with `ssh: parse error in message type 0` because the local SSH key (`~/.ssh/id_ed25519`) is passphrase-encrypted. Terraform's `file()` function reads raw bytes and cannot use the SSH agent for decryption.

## Root Cause

Two compounding failures:

- **Post-merge apply gap:** `terraform_data` resources with `remote-exec` provisioners that SSH into servers cannot be applied in CI (which uses dummy SSH keys). They must be applied locally in the same session as the merge. The `/ship` skill has no enforcement for this.
- **Encrypted SSH key incompatibility:** Terraform's `connection` block with `private_key = file(...)` requires an unencrypted key. Passphrase-encrypted keys fail silently at the SSH handshake level with an opaque parse error.

## Solution

1. Generated a temporary unencrypted ed25519 key pair
2. Added the temporary public key to the server's `authorized_keys`
3. Ran `terraform apply -target=terraform_data.doppler_install` with the temp key
4. Cleaned up: removed temp public key from `authorized_keys`, deleted local temp key files
5. Verified clean state: `terraform plan` exit 0, Doppler v3.75.3 installed, token file permissions 600 deploy:deploy

## Key Insight

`terraform_data` with `remote-exec` provisioners create a unique drift category: resources that CI cannot apply because they require real SSH access to production servers. These must be applied locally post-merge, but there is no automation to enforce this. The drift detection workflow correctly catches the gap, but prevention requires either: (a) applying in the same session as merge, (b) a post-merge checklist gate in `/ship` for infra PRs with provisioners, or (c) using `connection { agent = true }` to leverage the SSH agent (which handles passphrase decryption).

## Session Errors

### 1. Wrong script path for setup-ralph-loop.sh

**What happened:** `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` failed with file not found. The correct path is `./plugins/soleur/scripts/setup-ralph-loop.sh`.

**Prevention:** The one-shot skill instructions prescribed the wrong path. Fix the skill to use the correct base path. Plans should not prescribe script paths without verifying they exist.

### 2. Wrong terraform output name in plan

**What happened:** The plan prescribed `terraform output -raw server_ipv4` but the actual output is `server_ip`. The command failed with "output not found."

**Prevention:** Always run `terraform output` (no args) to list all available outputs before prescribing specific output variable names in plans. Never assume output names from memory or convention.

### 3. Passphrase-encrypted SSH key incompatible with Terraform file()

**What happened:** `terraform apply` failed with `Failed to parse ssh private key: ssh: parse error in message type 0`. The error is opaque -- it does not mention encryption or passphrases. The root cause is that `private_key = file("~/.ssh/id_ed25519")` reads the encrypted PEM bytes, and Terraform's SSH library cannot decrypt them.

**Prevention:** Document this as a known constraint for `terraform_data` with `remote-exec` provisioners. Options:

- Use `connection { agent = true }` instead of `private_key = file(...)` to leverage the SSH agent (handles passphrase decryption transparently)
- Generate a temporary unencrypted key for the apply, then clean up
- Store an unencrypted deploy key in a secrets manager (Doppler) and reference it via a local file

The `agent = true` approach is the recommended fix for future provisioner blocks.

## Prevention

- When merging PRs that add `terraform_data` or `remote-exec` provisioners, run `terraform apply` in the same session
- Consider adding a `/ship` gate that detects provisioner resources in changed `.tf` files and warns about post-merge apply requirements
- Use `connection { agent = true }` in provisioner blocks to avoid the encrypted key problem entirely
- The drift detection workflow is the safety net, but prevention (same-session apply) is better than detection

## References

- Issue: #1505
- Related PR: #1496
- Related learning: `integration-issues/2026-04-03-doppler-not-installed-env-fallback-outage.md` (original implementation)
- Related learning: `2026-03-21-terraform-drift-dead-code-and-missing-secrets.md` (drift detection patterns)
