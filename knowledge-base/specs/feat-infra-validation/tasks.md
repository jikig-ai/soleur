# Tasks: Infrastructure Validation

## Phase 1: Setup

- [ ] 1.1 Fix pre-existing `dns.tf` formatting issue
  - [ ] 1.1.1 Run `terraform fmt apps/web-platform/infra/` to auto-fix formatting
  - [ ] 1.1.2 Verify `terraform fmt -check apps/web-platform/infra/` returns exit 0

## Phase 2: Core Implementation

### 2.1 GitHub Actions CI Workflow

- [ ] 2.1.1 Create `.github/workflows/infra-validation.yml` with `pull_request` (paths: `apps/*/infra/**`) and `workflow_dispatch` triggers
- [ ] 2.1.2 Add security comment header documenting trust boundaries and SHA-pinning
- [ ] 2.1.3 Implement `detect-changes` job using pure bash (no third-party change detection actions)
  - [ ] 2.1.3.1 Use `git diff --name-only` against base branch to extract unique infra directory prefixes
  - [ ] 2.1.3.2 Output JSON array of directories for matrix strategy using `printf '%s\n'` for GITHUB_OUTPUT
  - [ ] 2.1.3.3 Handle `workflow_dispatch` case: use `find apps/*/infra -maxdepth 0` to validate all infra dirs
- [ ] 2.1.4 Implement `validate` job with matrix strategy per directory
  - [ ] 2.1.4.1 Add cloud-init schema check step: `sudo apt-get install -y -qq cloud-init` then `cloud-init schema -c cloud-init.yml` (covers both YAML syntax and schema)
  - [ ] 2.1.4.2 Add conditional skip when `cloud-init.yml` does not exist in directory
  - [ ] 2.1.4.3 Add `hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85 # v4.0.0` step
  - [ ] 2.1.4.4 Add `terraform fmt -check -recursive .` step
  - [ ] 2.1.4.5 Add `terraform init -backend=false` + `terraform validate` step
- [ ] 2.1.5 Set `fail-fast: false` so all directories validate independently
- [ ] 2.1.6 Pin ALL action references with SHA hashes: `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`, `hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85 # v4.0.0`
- [ ] 2.1.7 Use `ubuntu-24.04` (not `ubuntu-latest`) for runner pinning

### 2.2 Work Skill Phase 2 Infra Validation Rule

- [ ] 2.2.1 Edit `plugins/soleur/skills/work/SKILL.md` line 198: replace "tests may be skipped" with "unit tests may be skipped, but config-specific validation is required -- see Infrastructure Validation below"
- [ ] 2.2.2 Add section 5b "Infrastructure Validation" after the "Test Continuously" section (section 5)
  - [ ] 2.2.2.1 Document `git diff --name-only` detection pattern for `apps/*/infra/**` files
  - [ ] 2.2.2.2 Document `cloud-init schema -c <file>` command (validates both YAML syntax and schema)
  - [ ] 2.2.2.3 Document `terraform fmt -check <dir>` command
  - [ ] 2.2.2.4 Document `terraform init -backend=false && terraform validate` command
  - [ ] 2.2.2.5 Add graceful degradation note: warn and continue if `cloud-init` not installed locally

## Phase 3: Testing

- [ ] 3.1 Verify CI workflow locally
  - [ ] 3.1.1 Run `cloud-init schema -c cloud-init.yml` against both infra directories
  - [ ] 3.1.2 Run `terraform fmt -check` against both infra directories
  - [ ] 3.1.3 Run `terraform init -backend=false && terraform validate` against both infra directories
  - [ ] 3.1.4 Confirm all checks pass after `dns.tf` fix
- [ ] 3.2 Verify workflow YAML syntax
  - [ ] 3.2.1 Validate `.github/workflows/infra-validation.yml` with `python3 -c "import yaml; yaml.safe_load(open(...))"` or equivalent
- [ ] 3.3 Post-merge verification
  - [ ] 3.3.1 After merge, trigger `gh workflow run infra-validation.yml`
  - [ ] 3.3.2 Poll with `gh run view <id> --json status,conclusion` until complete
  - [ ] 3.3.3 Investigate failures before moving on (per constitution gate)
