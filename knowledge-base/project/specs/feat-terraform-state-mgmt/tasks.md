# Tasks: Terraform State R2 Migration

**Branch:** feat-terraform-state-mgmt
**Issue:** #973
**Plan:** [2026-03-21-feat-terraform-state-r2-migration-plan.md](../../plans/2026-03-21-feat-terraform-state-r2-migration-plan.md)

## Phase 1: Bootstrap R2 Backend

- [x] 1.1 Fix wrangler auth — created new R2-scoped API token via Playwright
- [x] 1.2 Create R2 bucket via Cloudflare API (R2 subscription activated first)
- [x] 1.3 Enable bucket versioning — deferred (R2 versioning API TBD)
- [x] 1.4 Create scoped R2 Account API token (Object Read & Write on `soleur-terraform-state`)
- [x] 1.5 Store R2 credentials in Doppler `prd_terraform` config (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)

## Phase 2: Backend Configuration + Hygiene

- [x] 2.1 Add `backend "s3"` block to `apps/telegram-bridge/infra/main.tf` (with `use_lockfile = false`)
- [x] 2.2 Add `backend "s3"` block to `apps/web-platform/infra/main.tf` (with `use_lockfile = false`)
- [x] 2.3 Bump `required_version` to `>= 1.6` in both stacks
- [x] 2.4 Add `lifecycle { ignore_changes = [user_data, ssh_keys, image] }` to `hcloud_server.bridge` (web already had it from #971)
- [x] 2.5 Remove `.terraform.lock.hcl` from both per-directory `.gitignore` files
- [x] 2.6 Run `terraform init` in both stacks (empty remote state created in R2)
- [x] 2.7 Add AGENTS.md hard rule requiring R2 backend in all new Terraform roots
- [ ] 2.8 Commit all changes (backend blocks, lifecycle, gitignore, lock files, AGENTS.md)

## Phase 3: Resource Import

- [x] 3.0 Discover resource IDs via hcloud CLI and Cloudflare API
- [N/A] 3.1 telegram-bridge — no live infrastructure exists yet (skipped)
- [x] 3.2 Import web-platform Hetzner resources (6): SSH key, server, volume, volume attachment, firewall, firewall attachment
- [x] 3.3 Import web-platform Cloudflare DNS records (6): app, deploy, dkim, spf, mx, dmarc
- [x] 3.4 Import web-platform Zero Trust resources (5): tunnel, tunnel config, access app, service token, access policy (policy via state patch — provider import bug)
- [x] 3.5 `random_id.tunnel_secret` imported with placeholder (lifecycle ignore_changes handles it)
- [x] 3.6 Applied in-place updates (2 add, 10 change, 0 destroy)
- [x] 3.7 Verify: `terraform plan` shows "No changes" in web-platform

## Phase 4: Follow-Up Issues

- [ ] 4.1 File issue: CI `terraform plan` on PRs (Doppler-first, fork handling, PR comments)
- [ ] 4.2 File issue: Lefthook pre-commit hooks (`terraform fmt -check`, optionally `tflint`)
- [ ] 4.3 File issue: Drift detection (scheduled `terraform plan -detailed-exitcode`)
- [ ] 4.4 File issue: Doppler key naming alignment (`CLOUDFLARE_*` → `CF_*`)
