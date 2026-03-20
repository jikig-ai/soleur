# Tasks: Adopt Doppler as Secrets Manager

**Issue:** #734
**Plan:** `knowledge-base/plans/2026-03-20-feat-adopt-doppler-secrets-manager-plan.md`

## Phase 0: Prerequisites

- [ ] 0.1 Back up BYOK_ENCRYPTION_KEY to offline storage (password manager or encrypted note)
- [ ] 0.2 Fix `apps/web-platform/infra/.gitignore` — add `terraform.tfvars`, `*.tfvars`, `.terraform.lock.hcl`
- [ ] 0.3 Create Doppler account and project via Playwright
  - [ ] 0.3.1 Sign up at doppler.com
  - [ ] 0.3.2 Create project "soleur"
  - [ ] 0.3.3 Rename `stg` config to `ci`
  - [ ] 0.3.4 Populate `dev` config with ~10 local dev secrets
  - [ ] 0.3.5 Populate `ci` config with ~23 CI secrets
  - [ ] 0.3.6 Populate `prd` config with ~12 production secrets
  - [ ] 0.3.7 Create service tokens: `ci-sync`, `prd-web`, `prd-bridge`
- [ ] 0.4 Configure Doppler sync to GitHub Actions
  - [ ] 0.4.1 Add GitHub integration in Doppler dashboard
  - [ ] 0.4.2 Configure sync: `ci` config → GH Actions secrets
  - [ ] 0.4.3 Verify: `gh secret list` shows all expected secrets

## Phase 1: Local Dev Migration

- [ ] 1.1 Install Doppler CLI locally (`curl -Ls https://cli.doppler.com/install.sh | sh`)
- [ ] 1.2 Authenticate and setup (`doppler login && doppler setup`)
- [ ] 1.3 Commit `.doppler.yaml` to repo root (tracked file — worktrees get it automatically)
- [ ] 1.4 Validate: `doppler run -- env | grep DISCORD` shows expected vars
- [ ] 1.5 Validate: `doppler run -- bun run dev` starts dev server

## Phase 2: CI Migration (Sync Approach — Zero Workflow Changes)

- [ ] 2.1 Verify Doppler sync is active and all 23 secrets present in GH
- [ ] 2.2 Trigger `scheduled-linkedin-token-check.yml` — validate secret access
- [ ] 2.3 Trigger a release workflow — validate Docker build-args still work

## Phase 3: Server Runtime Migration

- [ ] 3.1 Add Doppler CLI installation to cloud-init files (pinned version)
  - [ ] 3.1.1 `apps/web-platform/infra/cloud-init.yml`
  - [ ] 3.1.2 `apps/telegram-bridge/infra/cloud-init.yml`
  - [ ] 3.1.3 Add `DOPPLER_TOKEN` to `/etc/environment` via cloud-init
- [ ] 3.2 Add `doppler_token` variable to Terraform
  - [ ] 3.2.1 `apps/web-platform/infra/variables.tf` — add `doppler_token` (sensitive)
  - [ ] 3.2.2 `apps/telegram-bridge/infra/variables.tf` — add `doppler_token` (sensitive)
  - [ ] 3.2.3 `apps/web-platform/infra/server.tf` — pass to `templatefile()`
  - [ ] 3.2.4 `apps/telegram-bridge/infra/server.tf` — pass to `templatefile()`
- [ ] 3.3 Modify `ci-deploy.sh` — replace `--env-file` with `doppler secrets download | docker run --env-file /dev/stdin`
  - [ ] 3.3.1 Web-platform container (line ~82)
  - [ ] 3.3.2 Bridge container (line ~109)
  - [ ] 3.3.3 Add fallback to `/mnt/data/.env` if Doppler download fails
- [ ] 3.4 Modify cloud-init initial container start commands
  - [ ] 3.4.1 `apps/web-platform/infra/cloud-init.yml:101`
  - [ ] 3.4.2 `apps/telegram-bridge/infra/cloud-init.yml:90`
- [ ] 3.5 Validate: deploy web-platform via CI, health check passes
- [ ] 3.6 Validate: deploy telegram-bridge via CI, bot responds

## Phase 4: Rotation & Cleanup

- [ ] 4.1 Rotate all migrated secrets at their sources (Discord, X, Stripe, etc.)
- [ ] 4.2 Update new values in Doppler (single location, auto-syncs to GH)
- [ ] 4.3 Trigger a deploy to pick up rotated production secrets
- [ ] 4.4 Delete root `.env` file from developer machine
- [ ] 4.5 Update `.env.example` files with Doppler reference comment
- [ ] 4.6 Update `/mnt/data/.env` on server from Doppler export (cold-start fallback)

## Deferred (Follow-Up Issues)

- [ ] Terraform integration (`doppler run --name-transformer tf-var`)
- [ ] Pre-commit secret scanning (`git-secrets` or similar)
- [ ] Remove legacy deploy script (`apps/telegram-bridge/scripts/deploy.sh`)
- [ ] Update spec FR3 to match sync approach
