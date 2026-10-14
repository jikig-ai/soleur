# Tasks: KPI Remediation Dispatcher

## Phase 1: Setup

- [x] 1.1 Merge `origin/main` into `feat/kpi-remediation-dispatcher` to get latest workflow file
- [x] 1.2 Read `.github/workflows/scheduled-weekly-analytics.yml` to confirm current structure

## Phase 2: Core Implementation

- [x] 2.1 Add `actions: write` to the `permissions` block in `scheduled-weekly-analytics.yml`
- [x] 2.2 Add new step "Dispatch CMO remediation workflows" after the "Discord notification (KPI miss)" step and before "Create PR with snapshot"
  - [x] 2.2.1 Step condition: `if: steps.analytics.outputs.kpi_miss == 'true'`
  - [x] 2.2.2 Environment: `GH_TOKEN: ${{ github.token }}`
  - [x] 2.2.3 Run block: three `gh workflow run` calls with `|| echo "::warning::..."` fallback per call
- [x] 2.3 Update Discord KPI miss notification message to append remediation dispatch line

## Phase 3: Testing and Validation

- [x] 3.1 Validate YAML syntax (`python3 -c "import yaml; yaml.safe_load(open('.github/workflows/scheduled-weekly-analytics.yml'))"`)
- [x] 3.2 Verify step ordering: analytics -> Discord KPI miss -> dispatch -> Create PR -> Discord failure
- [x] 3.3 Verify `actions: write` is present in permissions block
- [ ] 3.4 Run compound (`skill: soleur:compound`)
- [ ] 3.5 Commit, push, create PR with `Closes #640` in body
