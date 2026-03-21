# Tasks: Terraform State R2 Migration

**Branch:** feat-terraform-state-mgmt
**Issue:** #973
**Plan:** [2026-03-21-feat-terraform-state-r2-migration-plan.md](../../plans/2026-03-21-feat-terraform-state-r2-migration-plan.md)

## Phase 1: Bootstrap R2 Backend

- [ ] 1.1 Fix wrangler auth (source valid CF API token from Doppler or `wrangler login`)
- [ ] 1.2 Create R2 bucket: `wrangler r2 bucket create soleur-terraform-state`
- [ ] 1.3 Enable bucket versioning via S3-compatible API (`aws s3api put-bucket-versioning`)
- [ ] 1.4 Create scoped R2 API token (Object Read & Write on `soleur-terraform-state`)
- [ ] 1.5 Store R2 credentials in Doppler `prd_terraform` config (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)

## Phase 2: Backend Configuration + Hygiene

- [ ] 2.1 Add `backend "s3"` block to `apps/telegram-bridge/infra/main.tf` (with `use_lockfile = false`)
- [ ] 2.2 Add `backend "s3"` block to `apps/web-platform/infra/main.tf` (with `use_lockfile = false`)
- [ ] 2.3 Bump `required_version` to `>= 1.6` in both stacks
- [ ] 2.4 Add `lifecycle { ignore_changes = [user_data] }` to `hcloud_server.bridge` and `hcloud_server.web`
- [ ] 2.5 Remove `.terraform.lock.hcl` from both per-directory `.gitignore` files
- [ ] 2.6 Run `terraform init` in both stacks (creates empty remote state + lock files)
- [ ] 2.7 Add AGENTS.md hard rule requiring R2 backend in all new Terraform roots
- [ ] 2.8 Commit all changes (backend blocks, lifecycle, gitignore, lock files, AGENTS.md)

## Phase 3: Resource Import

- [ ] 3.0 Discover resource IDs
  - [ ] 3.0.1 Install `hcloud` CLI if not present
  - [ ] 3.0.2 List Hetzner resources (servers, volumes, firewalls, SSH keys)
  - [ ] 3.0.3 List Cloudflare resources (DNS records, tunnels, access apps/policies/tokens)
- [ ] 3.1 Import telegram-bridge resources (6)
  - [ ] 3.1.1 `hcloud_ssh_key.default`
  - [ ] 3.1.2 `hcloud_server.bridge`
  - [ ] 3.1.3 `hcloud_volume.data`
  - [ ] 3.1.4 `hcloud_volume_attachment.data`
  - [ ] 3.1.5 `hcloud_firewall.bridge`
  - [ ] 3.1.6 `hcloud_firewall_attachment.bridge` (import by firewall ID only)
- [ ] 3.2 Import web-platform Hetzner resources (6)
  - [ ] 3.2.1 `hcloud_ssh_key.default`
  - [ ] 3.2.2 `hcloud_server.web`
  - [ ] 3.2.3 `hcloud_volume.workspaces`
  - [ ] 3.2.4 `hcloud_volume_attachment.workspaces`
  - [ ] 3.2.5 `hcloud_firewall.web`
  - [ ] 3.2.6 `hcloud_firewall_attachment.web` (import by firewall ID only)
- [ ] 3.3 Import web-platform Cloudflare DNS records (6)
- [ ] 3.4 Import web-platform Zero Trust resources (5)
- [ ] 3.5 Handle `random_id.tunnel_secret` (DANGEROUS — verify via CF API, use base64url encoding)
- [ ] 3.6 Verify: `terraform plan` shows "No changes" in telegram-bridge
- [ ] 3.7 Verify: `terraform plan` shows "No changes" in web-platform

## Phase 4: Follow-Up Issues

- [ ] 4.1 File issue: CI `terraform plan` on PRs (Doppler-first, fork handling, PR comments)
- [ ] 4.2 File issue: Lefthook pre-commit hooks (`terraform fmt -check`, optionally `tflint`)
- [ ] 4.3 File issue: Drift detection (scheduled `terraform plan -detailed-exitcode`)
- [ ] 4.4 Update #967 — state is now available, unblock tunnel provisioning
