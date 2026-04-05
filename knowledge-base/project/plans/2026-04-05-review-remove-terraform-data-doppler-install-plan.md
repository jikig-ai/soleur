---
title: "review: remove terraform_data.doppler_install after first apply"
type: fix
date: 2026-04-05
issue: "#1501"
---

# Remove terraform_data.doppler_install from server.tf

## Overview

The `terraform_data.doppler_install` resource was a one-time bootstrap provisioner that installed Doppler CLI on the existing Hetzner server via SSH `remote-exec`. It was added in PR #1496, applied successfully (confirmed in learning `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`), and its purpose is complete.

The resource cannot be planned in CI (no real SSH keys), so every scheduled drift check reports it as "will be created" (exit code 2), generating a false-positive drift issue and Discord notification every 12 hours.

## Problem Statement

- `terraform plan -detailed-exitcode` returns exit 2 for `terraform_data.doppler_install` because CI uses dummy SSH keys
- The drift detection workflow (`scheduled-terraform-drift.yml`) creates/updates a GitHub issue and sends a Discord notification on every run
- The resource's job is done -- Doppler CLI is installed, the token file is in place, and the webhook service is running

## Proposed Solution

Three-step cleanup, all automatable by the agent:

### Step 1: Remove the resource block from `server.tf`

Delete lines 41-70 of `apps/web-platform/infra/server.tf` -- the entire `terraform_data.doppler_install` resource block, including the preceding comment block (lines 41-47).

### Step 2: Remove the orphaned `ssh_private_key_path` variable

The `ssh_private_key_path` variable in `apps/web-platform/infra/variables.tf:32-36` is only referenced by the `doppler_install` resource's connection block. With the resource removed, this variable is dead code. Remove it.

**CI workflow impact:** Both `scheduled-terraform-drift.yml` (line 88-89) and `infra-validation.yml` (line 172-173) conditionally pass `-var="ssh_private_key_path=..."` via a `grep -q` check against `variables.tf`. Once the variable definition is removed, the grep will not match and the `-var` flag will not be passed. No workflow file changes are needed.

### Step 3: Run `terraform state rm`

```bash
cd apps/web-platform/infra
doppler run -p soleur -c prd_terraform -- terraform init
doppler run -p soleur -c prd_terraform -- terraform state rm terraform_data.doppler_install
```

This removes the resource from the remote R2 state backend without destroying anything on the server. The Doppler CLI installation, token file, and webhook service remain intact.

### Step 4: Verify clean state

```bash
doppler run -p soleur -c prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
  -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform plan -detailed-exitcode
```

Expected: exit code 0 (no changes). If exit code 2, investigate what else has drifted.

## Acceptance Criteria

- [ ] `terraform_data.doppler_install` resource block removed from `server.tf`
- [ ] `ssh_private_key_path` variable removed from `variables.tf`
- [ ] Resource removed from Terraform state (`terraform state rm`)
- [ ] `terraform plan -detailed-exitcode` returns exit 0 for web-platform stack
- [ ] Drift workflow no longer shows false positive for this resource

## Test Scenarios

- Given the resource is removed from both code and state, when `terraform plan -detailed-exitcode` runs, then exit code is 0
- Given `ssh_private_key_path` is removed from `variables.tf`, when the drift workflow runs `grep -q 'variable "ssh_private_key_path"'`, then the grep does not match and no `-var` flag is passed
- Given the resource is removed from state, when checking the server, then Doppler CLI is still installed and `/etc/default/webhook-deploy` still exists (server state is unaffected)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Context

### Files Changed

| File | Change |
|------|--------|
| `apps/web-platform/infra/server.tf` | Remove `terraform_data.doppler_install` resource block (lines 41-70) |
| `apps/web-platform/infra/variables.tf` | Remove `ssh_private_key_path` variable (lines 32-36) |

### Files NOT Changed (self-healing)

| File | Why |
|------|-----|
| `.github/workflows/scheduled-terraform-drift.yml` | Grep-based conditional already handles missing variable gracefully |
| `.github/workflows/infra-validation.yml` | Same grep-based conditional |

### Risk Assessment

**Risk: Low.** This is a deletion of a completed one-time provisioner. The server-side state (Doppler CLI, token file, webhook service) is untouched. Terraform state is cleaned via `state rm` (not `destroy`). The only risk is if someone later needs to re-bootstrap Doppler on a new server -- but that is handled by `cloud-init.yml` for newly provisioned servers.

## References

- Issue: #1501
- Original PR: #1496 (added the resource)
- Drift issue: #1505 (resolved)
- Learning: `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`
- Learning: `2026-03-21-terraform-drift-dead-code-and-missing-secrets.md`
