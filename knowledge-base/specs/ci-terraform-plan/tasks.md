# Tasks: Scheduled Terraform Drift Detection

## Phase 1: Setup

- [ ] 1.1 Create `.github/workflows/scheduled-terraform-drift.yml` with workflow skeleton (name, triggers, concurrency, permissions)
- [ ] 1.2 Add `checkout` and `setup-terraform` steps with SHA-pinned actions matching `infra-validation.yml`
- [ ] 1.3 Add Doppler CLI installation step (binary download to `~/.local/bin`, no sudo)
- [ ] 1.4 Add CI SSH key generation step (`ssh-keygen -t ed25519`)
- [ ] 1.5 Verify required GitHub Secrets exist: `DOPPLER_TOKEN`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `DISCORD_WEBHOOK_URL`
  - [ ] 1.5.1 Check if R2 credentials are synced from Doppler or manually set in GitHub Secrets
  - [ ] 1.5.2 If not present, add them via `gh secret set` or Doppler sync

## Phase 2: Core Implementation

- [ ] 2.1 Add `terraform init` step with R2 backend credentials as plain env vars (NOT through `--name-transformer tf-var`)
- [ ] 2.2 Add `terraform plan -detailed-exitcode` step wrapped in `doppler run --name-transformer tf-var`
  - [ ] 2.2.1 Capture exit code with `set +e` / `set -e` pattern
  - [ ] 2.2.2 Save plan output to file, truncated to 60,000 chars
  - [ ] 2.2.3 Export `exit_code` and `stack_name` as step outputs
- [ ] 2.3 Add matrix strategy for both stacks: `apps/telegram-bridge/infra`, `apps/web-platform/infra`
- [ ] 2.4 Add security comment header documenting secrets used and trust boundaries

## Phase 3: Notifications

- [ ] 3.1 Add `infra-drift` label creation step (idempotent `gh label create || true`)
- [ ] 3.2 Add GitHub issue creation step (exit code 2 only)
  - [ ] 3.2.1 Search for existing open issue with `infra-drift` label and matching stack name
  - [ ] 3.2.2 If exists: append comment with updated plan output and timestamp
  - [ ] 3.2.3 If not: create new issue with plan output in collapsible details block
- [ ] 3.3 Add Discord notification step (exit code 1 or 2)
  - [ ] 3.3.1 Differentiate message for drift (exit 2) vs error (exit 1)
  - [ ] 3.3.2 Use existing Discord webhook pattern from `post-merge-monitor.yml`
  - [ ] 3.3.3 Gracefully skip if `DISCORD_WEBHOOK_URL` is not set

## Phase 4: SSH Key False Positive Mitigation

- [ ] 4.1 Add `lifecycle { ignore_changes = [public_key] }` to `hcloud_ssh_key.default` in `apps/telegram-bridge/infra/server.tf`
- [ ] 4.2 Add `lifecycle { ignore_changes = [public_key] }` to `hcloud_ssh_key.default` in `apps/web-platform/infra/server.tf`
- [ ] 4.3 Verify plan shows zero diff after applying `ignore_changes` (run locally with dummy key)

## Phase 5: Validation

- [ ] 5.1 Run `actionlint` on the workflow file
- [ ] 5.2 Trigger manual workflow run via `gh workflow run scheduled-terraform-drift.yml`
- [ ] 5.3 Poll until complete: `gh run view <id> --json status,conclusion`
- [ ] 5.4 Verify: clean plan produces no issues and no Discord notifications
- [ ] 5.5 Verify: `workflow_dispatch` trigger works identically to scheduled trigger
- [ ] 5.6 Verify: security comment header is present and accurate
