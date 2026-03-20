# Tasks: deduplicate ci-deploy.sh between standalone file and cloud-init.yml

## Phase 1: Setup

- [ ] 1.1 Read current `apps/web-platform/infra/server.tf` and verify `templatefile()` call structure
- [ ] 1.2 Read current `apps/telegram-bridge/infra/server.tf` and verify `templatefile()` call structure
- [ ] 1.3 Read current `apps/web-platform/infra/cloud-init.yml` to identify the inline script block boundaries
- [ ] 1.4 Read current `apps/telegram-bridge/infra/cloud-init.yml` to identify the inline script block boundaries

## Phase 2: Core Implementation

- [ ] 2.1 Edit `apps/web-platform/infra/server.tf`: add `ci_deploy_script = file("${path.module}/ci-deploy.sh")` to the `templatefile()` variables map
- [ ] 2.2 Edit `apps/web-platform/infra/cloud-init.yml`: replace the 129-line inline script (lines 44-172) with `${indent(6, ci_deploy_script)}` placeholder, preserving the `write_files` entry metadata (`path`, `owner`, `permissions`) and comment
- [ ] 2.3 Edit `apps/telegram-bridge/infra/server.tf`: add `ci_deploy_script = file("${path.module}/../../web-platform/infra/ci-deploy.sh")` to the `templatefile()` variables map
- [ ] 2.4 Edit `apps/telegram-bridge/infra/cloud-init.yml`: replace the 129-line inline script (lines 44-172) with `${indent(6, ci_deploy_script)}` placeholder, preserving the `write_files` entry metadata and comment

## Phase 3: Validation

- [ ] 3.1 Run `terraform init -backend=false && terraform validate` in `apps/web-platform/infra/`
- [ ] 3.2 Run `terraform init -backend=false && terraform validate` in `apps/telegram-bridge/infra/`
- [ ] 3.3 Run `terraform fmt -check -recursive .` in both infra directories
- [ ] 3.4 Run `bash apps/web-platform/infra/ci-deploy.test.sh` to confirm standalone tests still pass
- [ ] 3.5 Verify `cloud-init schema -c cloud-init.yml` does not regress (may need `cloud-init` installed; CI handles this)
- [ ] 3.6 Visually inspect that no `${...}` bash expressions remain inline in either `cloud-init.yml` (grep check)
