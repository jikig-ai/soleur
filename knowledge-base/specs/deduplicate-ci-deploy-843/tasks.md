# Tasks: deduplicate ci-deploy.sh between standalone file and cloud-init.yml

## Phase 1: Setup

- [ ] 1.1 Read current `apps/web-platform/infra/server.tf` and verify `templatefile()` call structure
- [ ] 1.2 Read current `apps/telegram-bridge/infra/server.tf` and verify `templatefile()` call structure
- [ ] 1.3 Read current `apps/web-platform/infra/cloud-init.yml` to identify the inline script block boundaries (lines 39-174)
- [ ] 1.4 Read current `apps/telegram-bridge/infra/cloud-init.yml` to identify the inline script block boundaries (lines 38-173)

## Phase 2: Core Implementation (Approach A -- base64encode)

- [ ] 2.1 Edit `apps/web-platform/infra/server.tf`: add `ci_deploy_script_b64 = base64encode(file("${path.module}/ci-deploy.sh"))` to the `templatefile()` variables map
- [ ] 2.2 Edit `apps/web-platform/infra/cloud-init.yml`: replace the 129-line inline script (lines 39-174) with the base64 `write_files` entry: `encoding: b64`, `content: ${ci_deploy_script_b64}`. Preserve `path`, `owner`, `permissions`, and the comment block
- [ ] 2.3 Edit `apps/telegram-bridge/infra/server.tf`: add `ci_deploy_script_b64 = base64encode(file("${path.module}/../../web-platform/infra/ci-deploy.sh"))` to the `templatefile()` variables map. Path trace: `apps/telegram-bridge/infra/` + `../../` = `apps/`, then `web-platform/infra/ci-deploy.sh`
- [ ] 2.4 Edit `apps/telegram-bridge/infra/cloud-init.yml`: replace the 129-line inline script (lines 38-173) with the base64 `write_files` entry, same pattern as 2.2 but with bridge-specific comment

## Phase 3: Validation

- [ ] 3.1 Run `terraform fmt -write=true` in both infra directories to fix any formatting
- [ ] 3.2 Run `terraform init -backend=false && terraform validate` in `apps/web-platform/infra/`
- [ ] 3.3 Run `terraform init -backend=false && terraform validate` in `apps/telegram-bridge/infra/`
- [ ] 3.4 Run `terraform fmt -check` in both infra directories to confirm formatting
- [ ] 3.5 Run `bash apps/web-platform/infra/ci-deploy.test.sh` to confirm standalone tests still pass
- [ ] 3.6 Test `cloud-init schema -c cloud-init.yml` on the modified template to check if template variables cause validation failure. If yes, update CI step in `.github/workflows/infra-validation.yml` to handle templates
- [ ] 3.7 Grep check: confirm no inline bash `${...}` expressions remain in either `cloud-init.yml` (only Terraform template variables should be present)
- [ ] 3.8 Verify the diff is clean: the only changes should be in `server.tf` (2 files) and `cloud-init.yml` (2 files). `ci-deploy.sh` and `ci-deploy.test.sh` must be unchanged
