# Tasks: Terraform Security Fixes (#1560, #1561)

## Implementation

- [x] 1.1 Edit `apps/web-platform/infra/server.tf`: Replace `private_key = file(var.ssh_private_key_path)` with `agent = true` in `disk_monitor_install` connection block
- [x] 1.2 Remove `ssh_private_key_path` variable block from `apps/web-platform/infra/variables.tf` (lines 32-36)
- [x] 1.3 Edit `.github/workflows/infra-validation.yml`: Remove `ssh_private_key_path` grep check and `-var` argument
- [x] 1.4 Edit `.github/workflows/scheduled-terraform-drift.yml`: Remove `ssh_private_key_path` grep check and `-var` argument

## Validation

- [x] 2.1 Run `terraform fmt -check` on `apps/web-platform/infra/`
- [x] 2.2 Run `terraform init -backend=false && terraform validate` on `apps/web-platform/infra/`
- [x] 2.3 Grep for any remaining references to `ssh_private_key_path` across the repo (expect zero)

## Issue Cleanup

- [x] 3.1 Close #1560 with comment explaining `sensitive = true` is already present
- [ ] 3.2 Ship PR for #1561 via `/soleur:ship`

## Post-merge

- [ ] 4.1 Run `terraform apply -replace=terraform_data.disk_monitor_install` to force re-creation with agent-based SSH (connection block change alone does not trigger replacement)
- [ ] 4.2 Verify state: `terraform state pull | jq '.resources[] | select(.type == "terraform_data") | .instances[].attributes'` shows no `private_key` field
- [ ] 4.3 Verify disk-monitor timer: `ssh root@<ip> systemctl list-timers disk-monitor.timer --no-pager`
