# Tasks: Doppler Terraform Integration

## Phase 1: Setup (Doppler Config)

Note: `prd_terraform` branch config already created during plan research. Verify it exists before adding secrets.

- [ ] 1.1 Verify `prd_terraform` config exists: `doppler configs --project soleur | grep prd_terraform`
- [ ] 1.2 Add `HCLOUD_TOKEN` to `prd_terraform` config (value from current web-platform `.tfvars`)
- [ ] 1.3 Add `CF_API_TOKEN` to `prd_terraform` config (value from current `.tfvars` `cloudflare_api_token`)
- [ ] 1.4 Add `CF_ZONE_ID` to `prd_terraform` config
- [ ] 1.5 Add `CF_ACCOUNT_ID` to `prd_terraform` config
- [ ] 1.6 Add `WEBHOOK_DEPLOY_SECRET` to `prd_terraform` config
- [ ] 1.7 Add `ADMIN_IPS` to `prd_terraform` config (HCL-encoded JSON array: `["x.x.x.x/32","y.y.y.y/32"]`)
  - [ ] 1.7.1 Verify Doppler preserves brackets and quotes: `doppler run --project soleur --config prd_terraform --name-transformer tf-var -- printenv TF_VAR_admin_ips`
- [ ] 1.8 Add `DEPLOY_SSH_PUBLIC_KEY` to `prd_terraform` config (value from current telegram-bridge `.tfvars`)
- [ ] 1.9 Add `DOPPLER_TOKEN` to `prd_terraform` config (Doppler service token for server-side injection)
- [ ] 1.10 Verify all 8 secrets present: `doppler secrets --project soleur --config prd_terraform --only-names`

## Phase 2: Core Implementation (Variable Renames)

All changes in `apps/web-platform/infra/` only. Telegram-bridge has no cloudflare variables.

- [ ] 2.1 Rename `cloudflare_api_token` to `cf_api_token` in `variables.tf`
- [ ] 2.2 Rename `cloudflare_zone_id` to `cf_zone_id` in `variables.tf`
- [ ] 2.3 Rename `cloudflare_account_id` to `cf_account_id` in `variables.tf`
- [ ] 2.4 Update `main.tf` line 24: `var.cloudflare_api_token` -> `var.cf_api_token` (1 reference)
- [ ] 2.5 Update `dns.tf`: all `var.cloudflare_zone_id` -> `var.cf_zone_id` (5 references across 5 resource blocks)
- [ ] 2.6 Update `tunnel.tf`: `var.cloudflare_account_id` -> `var.cf_account_id` (3 refs), `var.cloudflare_zone_id` -> `var.cf_zone_id` (1 ref)
- [ ] 2.7 Verify `firewall.tf` has no cloudflare variable references (confirmed: uses `var.admin_ips` only)
- [ ] 2.8 Verify `outputs.tf` has no cloudflare variable references (confirmed: no cloudflare refs)
- [ ] 2.9 Add header comment to `apps/web-platform/infra/variables.tf` documenting the Doppler workflow command
- [ ] 2.10 Add header comment to `apps/telegram-bridge/infra/variables.tf` documenting the Doppler workflow command
- [ ] 2.11 Run `grep -r 'cloudflare_api_token\|cloudflare_zone_id\|cloudflare_account_id' apps/` to verify no remaining old references

## Phase 3: Testing

- [ ] 3.1 Rename/remove local `.tfvars` file in `apps/web-platform/infra/` (back it up first)
- [ ] 3.2 Run `doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform plan` in `apps/web-platform/infra/`
- [ ] 3.3 Run `doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform plan` in `apps/telegram-bridge/infra/`
- [ ] 3.4 Verify `admin_ips` list type parses correctly (check plan output for firewall rules)
- [ ] 3.5 Verify `terraform plan` without `doppler run` prompts for required variables (no secrets leak)
- [ ] 3.6 Verify inherited `prd` secrets (e.g., `TF_VAR_anthropic_api_key`) are silently ignored by Terraform
- [ ] 3.7 Delete local `.tfvars` files permanently after successful validation
