---
title: "chore: terraform apply -replace to clear private key from state"
type: chore
date: 2026-04-06
issues: [1567]
deepened: 2026-04-06
---

# chore: terraform apply -replace to clear private key from state

## Enhancement Summary

**Deepened on:** 2026-04-06
**Sections enhanced:** 3 (Proposed Solution, Risk, Verification)
**Research sources:** 3 project learnings (terraform-data-remote-exec-drift, ci-terraform-plan-workflow, terraform-state-r2-migration), outputs.tf verification, server.tf analysis

### Key Improvements

1. Simplified the Doppler invocation for local execution (personal CLI token, not CI service token) -- avoids the nested `doppler run` complexity
2. Added `-auto-approve` guidance and explicit drift-check step to avoid accidentally applying unrelated changes
3. Added `deploy_pipeline_fix` verification steps -- the original issue only mentioned `disk_monitor_install` but both resources had private keys

## Overview

Follow-through from PR #1565 which migrated SSH provisioner connections from `private_key = file(var.ssh_private_key_path)` to `agent = true`. The connection block change alone does not trigger resource replacement -- the old Terraform state still contains private key material in R2 remote backend. A forced `-replace` is needed to re-create the resources with agent-based SSH and clear the stale private key from state.

## Correction: Directory Location

Issue #1567 references "the telegram-bridge infra directory" but this is incorrect. The `terraform_data.disk_monitor_install` resource lives in `apps/web-platform/infra/server.tf`, not `apps/telegram-bridge/infra/`. The telegram-bridge infra has no `terraform_data` resources at all.

Additionally, PR #1565 migrated two resources, not just one:

- `terraform_data.disk_monitor_install` (server.tf:47)
- `terraform_data.deploy_pipeline_fix` (server.tf:86)

Both had `private_key = file(var.ssh_private_key_path)` and both need `-replace` to clear stale key material from state. The third resource (`terraform_data.docker_seccomp_config`) was already using `agent = true` before PR #1565 and does not need replacement.

## Proposed Solution

### Research Insights

**Doppler invocation simplification for local execution:**
The nested `doppler run` pattern in `variables.tf` comments is designed for CI, where `--name-transformer tf-var` must coexist with plain `AWS_*` env vars for the S3/R2 backend. Locally, the Doppler CLI authenticates with a personal token (not a service token), so a simpler approach works: one `doppler run` for backend creds, then `--name-transformer tf-var` for Terraform variables. Per learning `2026-03-21-ci-terraform-plan-workflow.md`, the `tf-var` transformer converts ALL keys including `AWS_ACCESS_KEY_ID`, which breaks the S3 backend. The nested pattern avoids this by having the outer call inject plain env vars.

**Concurrent apply risk:**
Per learning `2026-03-21-terraform-state-r2-migration.md`, the R2 backend uses `use_lockfile = false` (R2 does not support S3 conditional writes). There is no state lock. Ensure no other Terraform process (CI drift check, another local session) is running against the same state.

**Drift-check before apply:**
Running `-replace` alongside an unmodified `terraform plan` could surface unrelated drift (firewall, DNS, server config). Always review the full plan output before applying. If unexpected changes appear, address them separately or use `-target` to limit scope.

### Phase 1: Prerequisites

1. Verify SSH agent has keys loaded: `ssh-add -l`
2. Verify no other Terraform process is running against web-platform state
3. `cd apps/web-platform/infra`

### Phase 2: Initialize

4. Run terraform init with R2 backend credentials:

    ```bash
    doppler run --project soleur --config prd_terraform -- \
      terraform init
    ```

### Phase 3: Plan and Review

5. Run terraform plan with `-replace` flags for both resources:

    ```bash
    doppler run --project soleur --config prd_terraform -- \
      doppler run --token "$(doppler configure get token --plain)" \
        --project soleur --config prd_terraform --name-transformer tf-var -- \
      terraform plan \
        -replace=terraform_data.disk_monitor_install \
        -replace=terraform_data.deploy_pipeline_fix
    ```

6. **Review the plan output carefully.** Verify:
    - Exactly 2 resources are being replaced (`disk_monitor_install`, `deploy_pipeline_fix`)
    - No unexpected changes to other resources (server, firewall, DNS, volume)
    - If unexpected drift appears, stop and investigate before proceeding

### Phase 4: Apply

7. Run the same command with `terraform apply` (no `-auto-approve` -- review the plan interactively to catch any last-second issues):

    ```bash
    doppler run --project soleur --config prd_terraform -- \
      doppler run --token "$(doppler configure get token --plain)" \
        --project soleur --config prd_terraform --name-transformer tf-var -- \
      terraform apply \
        -replace=terraform_data.disk_monitor_install \
        -replace=terraform_data.deploy_pipeline_fix
    ```

8. The apply will SSH into the server via agent, re-run the provisioners (upload disk-monitor.sh, ci-deploy.sh, webhook.service, reload systemd, enable timers), and store new state without private key material

### Phase 5: Verify State

9. Pull state and check all `terraform_data` resources for stale private key material:

    ```bash
    doppler run --project soleur --config prd_terraform -- \
      terraform state pull | \
      jq '.resources[] | select(.type == "terraform_data") | {name: .name, attributes: .instances[].attributes}'
    ```

10. Verify: no `private_key` field in any resource's attributes. All three `terraform_data` resources should use `agent = true` connections.

11. Run a clean plan to confirm zero pending changes:

    ```bash
    doppler run --project soleur --config prd_terraform -- \
      doppler run --token "$(doppler configure get token --plain)" \
        --project soleur --config prd_terraform --name-transformer tf-var -- \
      terraform plan
    ```

    Expected output: "No changes. Your infrastructure matches the configuration."

### Phase 6: Verify Server

12. Get server IP from Terraform outputs:

    ```bash
    doppler run --project soleur --config prd_terraform -- \
      doppler run --token "$(doppler configure get token --plain)" \
        --project soleur --config prd_terraform --name-transformer tf-var -- \
      terraform output -raw server_ip
    ```

13. Verify disk-monitor timer (read-only diagnosis per AGENTS.md):

    ```bash
    ssh root@<ip> systemctl list-timers disk-monitor.timer --no-pager
    ```

    Expected: timer is active with a next-run timestamp.

14. Verify deploy pipeline webhook service:

    ```bash
    ssh root@<ip> systemctl status webhook --no-pager
    ```

    Expected: active (running).

15. Verify disk-monitor script was deployed correctly:

    ```bash
    ssh root@<ip> head -5 /usr/local/bin/disk-monitor.sh
    ```

    Expected: script header matches the local file.

## Acceptance Criteria

- [x] `terraform apply -replace` completes successfully for both `disk_monitor_install` and `deploy_pipeline_fix`
- [x] `terraform state pull | jq` shows no `private_key` field in any `terraform_data` resource attributes
- [x] `disk-monitor.timer` is active and running on the server
- [x] `webhook.service` is active on the server (deploy pipeline not broken by re-provisioning)
- [x] `terraform plan` shows no pending changes after apply (clean state)

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

**Low.** The `-replace` flag re-runs provisioners that upload disk-monitor.sh, ci-deploy.sh, and webhook.service to the server. These are idempotent operations (file copy + systemd reload).

### Edge Cases

- **Transient SSH failure:** Would leave the resource in a tainted state. Resolution: re-run `terraform apply` (tainted resources are automatically replaced on next apply).
- **Concurrent state access:** R2 backend has no state locking (`use_lockfile = false`). If the scheduled drift detection workflow runs concurrently, state corruption is possible. Mitigation: check `gh run list --workflow=scheduled-terraform-drift.yml --json status` before applying.
- **Unrelated drift bundled into apply:** If other resources have drifted since last apply (firewall rules, DNS records, server config), the plan will show those changes alongside the two replacements. Mitigation: review plan output in Phase 3 before applying. If unexpected changes appear, use `-target` instead of `-replace` to limit scope.
- **Provisioner script changes since last apply:** If `disk-monitor.sh`, `ci-deploy.sh`, or `webhook.service` were modified on disk since the last apply, the `triggers_replace` hash will differ and Terraform will show the resources as needing replacement anyway. This is expected and harmless -- the `-replace` flag is redundant in that case but causes no issues.

## References

- Issue: #1567
- PR: #1565
- Plan: `2026-04-05-fix-terraform-security-sensitive-vars-ssh-agent-plan.md`
- Terraform docs: connection block `agent` argument defaults to `true`
