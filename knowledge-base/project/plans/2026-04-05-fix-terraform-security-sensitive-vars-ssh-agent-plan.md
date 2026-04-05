---
title: "fix: Terraform security — sensitive variable annotation and SSH agent migration"
type: fix
date: 2026-04-05
issues: [1560, 1561]
---

# fix: Terraform security — sensitive variable annotation and SSH agent migration

## Overview

Two security items from PR #1551 review:

1. **#1560** — `discord_ops_webhook_url` already has `sensitive = true` (fixed in #1551). No code change needed — close the issue.
2. **#1561** — Provisioner `connection` blocks use `private_key = file(var.ssh_private_key_path)`, which stores SSH private key material in Terraform state (R2 remote backend). Migrate to `agent = true`.

## Current State

### Issue #1560 — Already Fixed

Reading `apps/web-platform/infra/variables.tf` line 113-117 reveals that `discord_ops_webhook_url` **already has** `sensitive = true`:

```hcl
variable "discord_ops_webhook_url" {
  description = "Discord webhook URL for infrastructure alerts (#ops-alerts channel)"
  type        = string
  sensitive   = true
}
```

This was likely fixed in the same PR (#1551) that created the issue. **No code change needed for #1560.** The issue should be closed as already resolved.

### Issue #1561 — SSH Key in State

`apps/web-platform/infra/server.tf` lines 53-58 contain the problematic pattern:

```hcl
connection {
  type        = "ssh"
  host        = hcloud_server.web.ipv4_address
  user        = "root"
  private_key = file(var.ssh_private_key_path)
}
```

This appears in the `terraform_data.disk_monitor_install` resource only. The issue mentions `deploy_pipeline_fix` as a second resource, but that resource does not exist in the current codebase — it was likely removed in a previous cleanup.

## Proposed Changes

Four file edits:

1. **`apps/web-platform/infra/server.tf`** — Replace `private_key = file(var.ssh_private_key_path)` with `agent = true` in the `disk_monitor_install` connection block.

2. **`apps/web-platform/infra/variables.tf`** — Remove the `ssh_private_key_path` variable block (lines 32-36). After change 1, this variable has zero usages.

3. **`.github/workflows/infra-validation.yml`** — Remove the `ssh_private_key_path` grep check and `-var` argument (lines 172-173).

4. **`.github/workflows/scheduled-terraform-drift.yml`** — Remove the `ssh_private_key_path` grep check and `-var` argument (lines 88-89).

**Keep the CI `ssh-keygen` step and `ssh_key_path` var.** The public key is still needed by `hcloud_ssh_key.default` (`public_key = file(var.ssh_key_path)`). Only the private key path is removed.

## CI Impact

`agent = true` means the SSH agent must be running when `terraform apply` executes provisioners. CI only runs `terraform plan` (no provisioners), so no SSH agent is needed in CI. Local apply requires the developer's key loaded in ssh-agent (`ssh-add`). The `disk_monitor_install` resource continues to show as "will be created" in drift reports (expected per #1409).

## Acceptance Criteria

- [ ] `connection` block in `disk_monitor_install` uses `agent = true` instead of `private_key = file(...)`
- [ ] `ssh_private_key_path` variable removed from `variables.tf`
- [ ] CI workflows (`infra-validation.yml`, `scheduled-terraform-drift.yml`) no longer pass `-var="ssh_private_key_path=..."` argument
- [ ] `terraform validate` passes (CI infra-validation job)
- [ ] `terraform plan` succeeds locally with SSH agent running
- [ ] #1560 closed as already-resolved (no code change needed)
- [ ] #1561 closed via PR

## Test Scenarios

- Given the updated `server.tf`, when running `terraform validate`, then validation passes
- Given the updated CI workflows, when a PR changes `apps/web-platform/infra/`, then the infra-validation plan job succeeds without `ssh_private_key_path` var
- Given `agent = true` in the connection block, when running `terraform apply` and then `terraform state pull`, then no private key material appears in state for the `disk_monitor_install` resource
- Given the removed `ssh_private_key_path` variable, when grepping the entire `apps/web-platform/infra/` directory for `ssh_private_key_path`, then zero matches

## Post-merge

After applying locally, verify state cleanup: `terraform state pull | jq '.resources[] | select(.type == "terraform_data") | .instances[].attributes'` should show no private key material. Existing state retains the old key until `disk_monitor_install` is re-created (triggered by its `triggers_replace` hash changing).

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Straightforward security hardening — removes secret material from Terraform state by switching to SSH agent forwarding. Low risk. The only connection block in the codebase is in `disk_monitor_install`; no other resources are affected. CI workflows only run `terraform plan` (not `apply`), so the SSH agent requirement does not create a CI gap.

## References

- Issue #1560: Mark discord_ops_webhook_url as sensitive
- Issue #1561: Migrate Terraform provisioner SSH to agent=true
- PR #1551: Original review that identified both issues
- Learning: `knowledge-base/project/learnings/2026-03-21-ci-terraform-plan-workflow.md` (CI SSH key generation pattern)
- Issue #1409: Expected drift report behavior for `disk_monitor_install`
