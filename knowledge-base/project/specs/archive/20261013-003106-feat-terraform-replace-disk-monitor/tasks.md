# Tasks: terraform apply -replace to clear private key from state

Issue: #1567
Plan: `knowledge-base/project/plans/2026-04-06-chore-terraform-replace-disk-monitor-clear-private-key-plan.md`

## Phase 1: Initialize and Plan

- [ ] 1.1 Run `terraform init` in `apps/web-platform/infra/` via Doppler
- [ ] 1.2 Run `terraform plan -replace=terraform_data.disk_monitor_install -replace=terraform_data.deploy_pipeline_fix`
- [ ] 1.3 Verify plan shows only the two expected resources being replaced

## Phase 2: Apply

- [ ] 2.1 Run `terraform apply -replace=terraform_data.disk_monitor_install -replace=terraform_data.deploy_pipeline_fix`
- [ ] 2.2 Confirm apply completes successfully (exit 0)

## Phase 3: Verify State

- [ ] 3.1 Run `terraform state pull | jq` and confirm no `private_key` field in any `terraform_data` resource
- [ ] 3.2 Run `terraform plan` and confirm zero pending changes (clean state)

## Phase 4: Verify Server

- [ ] 4.1 SSH to server and verify `disk-monitor.timer` is active
- [ ] 4.2 SSH to server and verify `webhook.service` is active
- [ ] 4.3 Close issue #1567
