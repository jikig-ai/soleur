# Tasks: CI Terraform Plan on PRs

## Phase 1: Setup

- [ ] 1.1 Look up SHA pins for `DopplerHQ/cli-action` and `marocchino/sticky-pull-request-comment`
- [ ] 1.2 Verify `DOPPLER_TOKEN` GitHub Secret exists (or document it as a prerequisite)

## Phase 2: Core Implementation

- [ ] 2.1 Add `check-secrets` job to `infra-validation.yml` that detects `DOPPLER_TOKEN` availability
- [ ] 2.2 Add `plan` job to `infra-validation.yml` with:
  - [ ] 2.2.1 Job dependencies on `detect-changes`, `validate`, and `check-secrets`
  - [ ] 2.2.2 Matrix strategy reusing `detect-changes` directory output
  - [ ] 2.2.3 Concurrency group per PR number per directory
  - [ ] 2.2.4 `timeout-minutes: 10`
  - [ ] 2.2.5 Security comment header
  - [ ] 2.2.6 Permissions: `contents: read`, `pull-requests: write`
- [ ] 2.3 Add Doppler CLI installation step (`DopplerHQ/cli-action`, SHA-pinned)
- [ ] 2.4 Add backend credential extraction step (plain `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`)
- [ ] 2.5 Add `terraform init -input=false` step
- [ ] 2.6 Add `terraform plan -no-color -input=false` step with output capture and truncation
- [ ] 2.7 Add sticky PR comment step (`marocchino/sticky-pull-request-comment`, SHA-pinned)
- [ ] 2.8 Update workflow-level permissions to include `pull-requests: write`

## Phase 3: Testing

- [ ] 3.1 Run `terraform fmt -check` and `terraform validate` on the workflow YAML (syntax)
- [ ] 3.2 After merge, trigger manual `workflow_dispatch` run and verify plan output
- [ ] 3.3 Create a test PR touching `apps/web-platform/infra/` and verify sticky comment appears
- [ ] 3.4 Verify fork PR graceful skip behavior (if testable)
