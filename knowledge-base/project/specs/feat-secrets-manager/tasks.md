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
  - [ ] 0.3.7 Create service token `ci-sync` scoped to `ci` config
  - [ ] 0.3.8 Create service token `prd-server` scoped to `prd` config
- [ ] 0.4 Configure Doppler sync to GitHub Actions
  - [ ] 0.4.1 Add GitHub integration in Doppler dashboard
  - [ ] 0.4.2 Configure sync: `ci` config → GH Actions secrets
  - [ ] 0.4.3 Verify: `gh secret list` shows all expected secrets

## Phase 1: Local Dev Migration

- [ ] 1.1 Install Doppler CLI locally (`curl -Ls https://cli.doppler.com/install.sh | sh`)
- [ ] 1.2 Authenticate and setup (`doppler login && doppler setup`)
- [ ] 1.3 Add `.doppler.yaml` to repo root (project: soleur, config: dev)
- [ ] 1.4 Update worktree manager `copy_env_files()` to also copy `.doppler.yaml`
  - File: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:96-134`
- [ ] 1.5 Add `write-doppler` command to community setup scripts
  - [ ] 1.5.1 `plugins/soleur/skills/community/scripts/discord-setup.sh`
  - [ ] 1.5.2 `plugins/soleur/skills/community/scripts/x-setup.sh`
  - [ ] 1.5.3 `plugins/soleur/skills/community/scripts/bsky-setup.sh`
  - [ ] 1.5.4 `plugins/soleur/skills/community/scripts/linkedin-setup.sh`
  - [ ] 1.5.5 Fix linkedin-setup.sh:282 — replace `git rev-parse --show-toplevel` with `$GIT_ROOT`
- [ ] 1.6 Create `scripts/doppler-run.sh` wrapper (Doppler → .env fallback)
- [ ] 1.7 Validate: `doppler run -- env | grep DISCORD` shows expected vars
- [ ] 1.8 Validate: `doppler run -- bun run dev` starts dev server

## Phase 2: CI Migration (Sync Approach)

- [ ] 2.1 Verify Doppler sync is active and all 23 secrets present in GH
- [ ] 2.2 Trigger `scheduled-linkedin-token-check.yml` — validate secret access
- [ ] 2.3 Trigger a release workflow — validate Docker build-args still work
- [ ] 2.4 Add `DOPPLER_TOKEN` as GH secret (for future direct CLI usage)
- [ ] 2.5 Document: "Secrets managed via Doppler, do not use `gh secret set`"

## Phase 3: Server Runtime Migration

- [ ] 3.1 Add Doppler CLI installation to cloud-init files
  - [ ] 3.1.1 `apps/web-platform/infra/cloud-init.yml`
  - [ ] 3.1.2 `apps/telegram-bridge/infra/cloud-init.yml`
- [ ] 3.2 Add `doppler_token` variable to Terraform
  - [ ] 3.2.1 `apps/web-platform/infra/variables.tf` — add `doppler_token` (sensitive)
  - [ ] 3.2.2 `apps/telegram-bridge/infra/variables.tf` — add `doppler_token` (sensitive)
  - [ ] 3.2.3 `apps/web-platform/infra/server.tf` — pass to `templatefile()`
  - [ ] 3.2.4 `apps/telegram-bridge/infra/server.tf` — pass to `templatefile()`
- [ ] 3.3 Modify `ci-deploy.sh` — replace `--env-file` with `doppler run --fallback passthrough --`
  - [ ] 3.3.1 Web-platform container (line ~82)
  - [ ] 3.3.2 Bridge container (line ~109)
- [ ] 3.4 Modify cloud-init initial container start commands
  - [ ] 3.4.1 `apps/web-platform/infra/cloud-init.yml:101`
  - [ ] 3.4.2 `apps/telegram-bridge/infra/cloud-init.yml:90`
- [ ] 3.5 Update legacy deploy script: `apps/telegram-bridge/scripts/deploy.sh:16`
- [ ] 3.6 Validate: deploy web-platform via CI, health check passes
- [ ] 3.7 Validate: deploy telegram-bridge via CI, bot responds
- [ ] 3.8 Validate: simulate Doppler outage, container restarts with cached secrets

## Phase 4: Terraform Migration

- [ ] 4.1 Add Terraform-compatible secret names to Doppler dev config
  - `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ZONE_ID`, `HCLOUD_TOKEN`
- [ ] 4.2 Verify name mapping: `doppler run --name-transformer tf-var -- env | grep TF_VAR`
- [ ] 4.3 Test: `doppler run --name-transformer tf-var -- terraform plan` (both stacks)
- [ ] 4.4 Delete local `.tfvars` files
- [ ] 4.5 Update README docs with new Terraform workflow
- [ ] 4.6 Add `tf` shortcut to `scripts/doppler-run.sh`

## Phase 5: Rotation & Cleanup

- [ ] 5.1 Rotate all migrated secrets at their sources (Discord, X, Stripe, etc.)
- [ ] 5.2 Update new values in Doppler (single location, auto-syncs)
- [ ] 5.3 Trigger a deploy to pick up rotated production secrets
- [ ] 5.4 Delete root `.env` file from developer machine
- [ ] 5.5 Remove `/mnt/data/.env` from production server
- [ ] 5.6 Add pre-commit secret scanning hook (`git-secrets` or similar)
- [ ] 5.7 Update `.env.example` files with Doppler reference comment
