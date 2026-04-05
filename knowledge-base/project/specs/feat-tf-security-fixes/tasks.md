# Tasks: Terraform Security Fixes (#1560, #1561)

## Implementation

- [ ] 1.1 Edit `apps/web-platform/infra/server.tf`: Replace `private_key = file(var.ssh_private_key_path)` with `agent = true` in `disk_monitor_install` connection block
- [ ] 1.2 Remove `ssh_private_key_path` variable block from `apps/web-platform/infra/variables.tf` (lines 32-36)
- [ ] 1.3 Edit `.github/workflows/infra-validation.yml`: Remove `ssh_private_key_path` grep check and `-var` argument
- [ ] 1.4 Edit `.github/workflows/scheduled-terraform-drift.yml`: Remove `ssh_private_key_path` grep check and `-var` argument

## Validation

- [ ] 2.1 Run `terraform fmt -check` on `apps/web-platform/infra/`
- [ ] 2.2 Run `terraform init -backend=false && terraform validate` on `apps/web-platform/infra/`
- [ ] 2.3 Grep for any remaining references to `ssh_private_key_path` across the repo (expect zero)

## Issue Cleanup

- [ ] 3.1 Close #1560 with comment explaining `sensitive = true` is already present
- [ ] 3.2 Ship PR for #1561 via `/soleur:ship`

## Post-merge

- [ ] 4.1 Run `terraform plan` locally to verify no unexpected changes
- [ ] 4.2 Run `terraform apply` to re-provision `disk_monitor_install` with agent-based SSH
- [ ] 4.3 Verify state: `terraform state pull | jq` shows no private key material in `disk_monitor_install` attributes
