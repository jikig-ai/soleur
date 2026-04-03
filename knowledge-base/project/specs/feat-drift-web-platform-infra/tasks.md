# Tasks: Resolve web-platform infrastructure drift — doppler_install

Source: `knowledge-base/project/plans/2026-04-03-fix-web-platform-infra-drift-doppler-install-plan.md`

## Phase 1: Apply Terraform

- [x] 1.1 Initialize terraform with R2 backend credentials
- [x] 1.2 Run `terraform apply -target=terraform_data.doppler_install` with real SSH key
- [x] 1.3 Verify provisioner output shows all 7 commands completed

## Phase 2: Verify Clean State

- [x] 2.1 Run `terraform plan -detailed-exitcode` — expect exit code 0
- [x] 2.2 If exit code is not 0, investigate and resolve remaining drift

## Phase 3: Verify Server State

- [x] 3.1 SSH into server: `doppler --version` returns installed version (v3.75.3)
- [x] 3.2 SSH into server: `/etc/default/webhook-deploy` exists with mode 600, deploy:deploy
- [x] 3.3 SSH into server: `systemctl status webhook` shows active/running
- [x] 3.4 Verify Doppler secrets accessible from server environment

## Phase 4: Verify Drift Workflow

- [x] 4.1 Trigger drift workflow: `gh workflow run scheduled-terraform-drift.yml`
- [x] 4.2 Poll until complete and verify web-platform job steps 9-11 are skipped (no drift)

## Phase 5: Cleanup

- [x] 5.1 Close issue #1505 with resolution comment
