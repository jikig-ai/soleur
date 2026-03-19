# Tasks: Infrastructure Validation

## Phase 1: Setup

- [ ] 1.1 Fix pre-existing `dns.tf` formatting issue
  - [ ] 1.1.1 Run `terraform fmt apps/web-platform/infra/` to auto-fix formatting
  - [ ] 1.1.2 Verify `terraform fmt -check apps/web-platform/infra/` returns exit 0

## Phase 2: Core Implementation

### 2.1 GitHub Actions CI Workflow

- [ ] 2.1.1 Create `.github/workflows/infra-validation.yml` with `pull_request` and `workflow_dispatch` triggers
- [ ] 2.1.2 Add security comment header documenting trust boundaries
- [ ] 2.1.3 Implement `detect-changes` job to find changed `apps/*/infra/` directories
  - [ ] 2.1.3.1 Use `git diff` against base branch to extract unique infra directory prefixes
  - [ ] 2.1.3.2 Output JSON array of directories for matrix strategy
  - [ ] 2.1.3.3 Handle `workflow_dispatch` case (validate all infra dirs)
- [ ] 2.1.4 Implement `validate` job with matrix strategy per directory
  - [ ] 2.1.4.1 Add YAML syntax check step (`python3 -c "import yaml; yaml.safe_load(...)"`)
  - [ ] 2.1.4.2 Add cloud-init schema check step (`cloud-init schema -c cloud-init.yml`)
  - [ ] 2.1.4.3 Add `hashicorp/setup-terraform` step with pinned version
  - [ ] 2.1.4.4 Add `terraform fmt -check` step
  - [ ] 2.1.4.5 Add `terraform init -backend=false` + `terraform validate` step
- [ ] 2.1.5 Set `fail-fast: false` so all directories validate independently
- [ ] 2.1.6 Pin all action versions with SHA hashes (per existing workflow conventions)

### 2.2 Work Skill Phase 2 Infra Validation Rule

- [ ] 2.2.1 Edit `plugins/soleur/skills/work/SKILL.md` line 198 to replace "tests may be skipped" with "unit tests may be skipped, but config-specific validation is required"
- [ ] 2.2.2 Add "Infrastructure Validation" subsection after the "Test Continuously" section (section 5)
  - [ ] 2.2.2.1 Document git diff detection pattern for `apps/*/infra/**` files
  - [ ] 2.2.2.2 Document YAML syntax check command
  - [ ] 2.2.2.3 Document cloud-init schema check command
  - [ ] 2.2.2.4 Document terraform fmt check command
  - [ ] 2.2.2.5 Document terraform validate command (init -backend=false + validate)

## Phase 3: Testing

- [ ] 3.1 Verify CI workflow locally
  - [ ] 3.1.1 Run all validation commands against `apps/web-platform/infra/` manually
  - [ ] 3.1.2 Run all validation commands against `apps/telegram-bridge/infra/` manually
  - [ ] 3.1.3 Confirm `terraform fmt -check` passes after `dns.tf` fix
- [ ] 3.2 Verify workflow syntax
  - [ ] 3.2.1 Validate `.github/workflows/infra-validation.yml` YAML syntax
- [ ] 3.3 Post-merge verification
  - [ ] 3.3.1 After merge, trigger `gh workflow run infra-validation.yml`
  - [ ] 3.3.2 Poll until complete and verify success
