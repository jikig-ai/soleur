---
title: "chore: terraform apply -replace to clear private key from state"
type: chore
date: 2026-04-06
issues: [1567]
---

# chore: terraform apply -replace to clear private key from state

## Overview

Follow-through from PR #1565 which migrated SSH provisioner connections from `private_key = file(var.ssh_private_key_path)` to `agent = true`. The connection block change alone does not trigger resource replacement -- the old Terraform state still contains private key material in R2 remote backend. A forced `-replace` is needed to re-create the resources with agent-based SSH and clear the stale private key from state.

## Correction: Directory Location

Issue #1567 references "the telegram-bridge infra directory" but this is incorrect. The `terraform_data.disk_monitor_install` resource lives in `apps/web-platform/infra/server.tf`, not `apps/telegram-bridge/infra/`. The telegram-bridge infra has no `terraform_data` resources at all.

Additionally, PR #1565 migrated two resources, not just one:

- `terraform_data.disk_monitor_install` (server.tf:47)
- `terraform_data.deploy_pipeline_fix` (server.tf:86)

Both had `private_key = file(var.ssh_private_key_path)` and both need `-replace` to clear stale key material from state. The third resource (`terraform_data.docker_seccomp_config`) was already using `agent = true` before PR #1565 and does not need replacement.

## Proposed Solution

### Phase 1: Initialize and Plan

1. `cd apps/web-platform/infra`
2. Run `doppler run --project soleur --config prd_terraform -- terraform init` to initialize the backend
3. Run `doppler run --project soleur --config prd_terraform -- doppler run --token "$(doppler configure get token --plain)" --project soleur --config prd_terraform --name-transformer tf-var -- terraform plan -replace=terraform_data.disk_monitor_install -replace=terraform_data.deploy_pipeline_fix` to preview the replacement
4. Verify the plan shows only the two resources being replaced (no unexpected changes)

### Phase 2: Apply

5. Run the same command with `terraform apply` instead of `terraform plan`
6. The apply will SSH into the server via agent, re-run the provisioners (upload scripts, reload systemd, enable timers), and store new state without private key material

### Phase 3: Verify State

7. Run `doppler run --project soleur --config prd_terraform -- terraform state pull | jq '.resources[] | select(.type == "terraform_data") | {name: .name, attributes: .instances[].attributes}'` and confirm no `private_key` field appears in any `terraform_data` resource

### Phase 4: Verify Server

8. Get server IP: `doppler run --project soleur --config prd_terraform -- doppler run --token "$(doppler configure get token --plain)" --project soleur --config prd_terraform --name-transformer tf-var -- terraform output -raw server_ip`
9. Run `ssh root@<ip> systemctl list-timers disk-monitor.timer --no-pager` (read-only diagnosis per AGENTS.md) to confirm the timer is active and running
10. Run `ssh root@<ip> systemctl status webhook --no-pager` to confirm the deploy pipeline service is also healthy after re-provisioning

## Acceptance Criteria

- [ ] `terraform apply -replace` completes successfully for both `disk_monitor_install` and `deploy_pipeline_fix`
- [ ] `terraform state pull | jq` shows no `private_key` field in any `terraform_data` resource attributes
- [ ] `disk-monitor.timer` is active and running on the server
- [ ] `webhook.service` is active on the server (deploy pipeline not broken by re-provisioning)
- [ ] `terraform plan` shows no pending changes after apply (clean state)

## Test Scenarios

- Given the `-replace` flag on both resources, when `terraform apply` runs, then both resources are destroyed and re-created with `agent = true` connections
- Given the re-created state, when pulling state via `terraform state pull`, then no `private_key` field exists in any `terraform_data` resource
- Given the re-provisioned server, when checking `systemctl list-timers disk-monitor.timer`, then the timer shows as active with a next-run time
- Given the re-provisioned server, when checking `systemctl status webhook`, then the service is active/running

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure state cleanup with no user-facing, legal, or marketing impact.

## Context

- **Source PR:** #1565 (merged 2026-04-05)
- **Follow-through issue:** #1567
- **Related learning:** `knowledge-base/project/learnings/2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md` -- documents the encrypted key problem and recommends `agent = true`
- **Related plan:** `knowledge-base/project/plans/2026-04-05-fix-terraform-security-sensitive-vars-ssh-agent-plan.md` -- the plan that produced PR #1565
- **Doppler config:** `prd_terraform` (contains all required secrets: HCLOUD_TOKEN, CF_API_TOKEN, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
- **Nested Doppler invocation:** Required per `apps/web-platform/infra/variables.tf` comment -- outer call injects plain env vars for R2 backend, inner call adds `TF_VAR_*` versions
- **SSH agent:** Must be running with keys loaded (`ssh-add -l` to verify)

## Risk

**Low.** The `-replace` flag re-runs provisioners that upload disk-monitor.sh, ci-deploy.sh, and webhook.service to the server. These are idempotent operations (file copy + systemd reload). The only risk is a transient SSH failure, which would leave the resource in a tainted state resolvable by re-running apply.

## References

- Issue: #1567
- PR: #1565
- Plan: `2026-04-05-fix-terraform-security-sensitive-vars-ssh-agent-plan.md`
- Terraform docs: connection block `agent` argument defaults to `true`
