---
module: Web Platform Infrastructure
date: 2026-04-06
problem_type: infrastructure_state
component: terraform
symptoms:
  - "terraform_data resources still contain private_key in state after connection block migration"
  - "terraform plan shows no changes despite connection block switching from private_key to agent=true"
root_cause: terraform_behavior
resolution_type: manual_replace
severity: low
tags: [terraform, terraform_data, connection, agent, private_key, state, replace]
synced_to: []
---

# terraform_data Connection Block Changes Don't Trigger Replacement

## Problem

PR #1565 migrated `terraform_data` provisioner connection blocks from `private_key = file(var.ssh_private_key_path)` to `agent = true` in `apps/web-platform/infra/server.tf`. After merge, `terraform plan` showed zero changes — the connection block modification alone does not trigger resource replacement. The old state in R2 remote backend still contained private key material.

Additionally, issue #1567 referenced the wrong directory (`apps/telegram-bridge/infra/` instead of `apps/web-platform/infra/`) and only mentioned one resource (`disk_monitor_install`) when two resources (`disk_monitor_install` AND `deploy_pipeline_fix`) needed replacement.

## Root Cause

Terraform's `terraform_data` resource uses `triggers_replace` to determine when re-creation is needed. The `connection` block inside a `provisioner` is not part of `triggers_replace` — it's metadata about how to connect, not what to provision. Changing from `private_key` to `agent` silently updates the configuration but does not force state refresh. The old state retains whatever attributes were stored during the last `terraform apply`, including the private key value.

## Solution

Force replacement of both affected resources:

```bash
doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform apply \
    -replace=terraform_data.disk_monitor_install \
    -replace=terraform_data.deploy_pipeline_fix
```

Verification:

1. `terraform state pull | jq` — no `private_key` field in any `terraform_data` resource
2. `terraform plan` — "No changes"
3. SSH to server — `disk-monitor.timer` active, `webhook.service` running

## Key Insight

When migrating `terraform_data` provisioner connection blocks (e.g., from `private_key` to `agent`), always follow up with `terraform apply -replace` for each affected resource. The connection block is invisible to Terraform's change detection. This applies to any connection attribute change (host, user, private_key, agent, certificate) — none trigger replacement.

When creating follow-through issues for `-replace` operations, enumerate all affected resources by reviewing the full PR diff, not just the issue title's resource.

## Prevention

- When PRs modify `connection` blocks in `terraform_data` or `null_resource`, the ship skill should create a follow-through issue that lists ALL affected resources, not just one
- Always verify the directory path in follow-through issues — cross-reference with `grep -r "resource_name" apps/*/infra/`
- Consider adding connection block attributes to `triggers_replace` hash so future changes are automatically detected

## References

- Issue: #1567
- Source PR: #1565
- Related learning: `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`
