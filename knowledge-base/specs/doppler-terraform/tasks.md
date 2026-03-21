# Tasks: Doppler Terraform Integration

## Phase 1: Setup (Doppler Config)

- [ ] 1.1 Create `prd_terraform` Doppler config (`doppler configs create prd_terraform --project soleur --environment prd`)
- [ ] 1.2 Add `HCLOUD_TOKEN` to `prd_terraform` config
- [ ] 1.3 Add `CF_API_TOKEN` to `prd_terraform` config (value from current `.tfvars` `cloudflare_api_token`)
- [ ] 1.4 Add `CF_ZONE_ID` to `prd_terraform` config
- [ ] 1.5 Add `CF_ACCOUNT_ID` to `prd_terraform` config
- [ ] 1.6 Add `WEBHOOK_DEPLOY_SECRET` to `prd_terraform` config
- [ ] 1.7 Add `ADMIN_IPS` to `prd_terraform` config (HCL-encoded: `["x.x.x.x/32","y.y.y.y/32"]`)
- [ ] 1.8 Add `DEPLOY_SSH_PUBLIC_KEY` to `prd_terraform` config
- [ ] 1.9 Add `DOPPLER_TOKEN` to `prd_terraform` config (Doppler service token for server-side injection)
- [ ] 1.10 Verify all secrets present: `doppler secrets --project soleur --config prd_terraform --only-names`

## Phase 2: Core Implementation (Variable Renames)

- [ ] 2.1 Rename `cloudflare_api_token` to `cf_api_token` in `apps/web-platform/infra/variables.tf`
- [ ] 2.2 Rename `cloudflare_zone_id` to `cf_zone_id` in `apps/web-platform/infra/variables.tf`
- [ ] 2.3 Rename `cloudflare_account_id` to `cf_account_id` in `apps/web-platform/infra/variables.tf`
- [ ] 2.4 Update `apps/web-platform/infra/main.tf`: `var.cloudflare_api_token` to `var.cf_api_token`
- [ ] 2.5 Update `apps/web-platform/infra/dns.tf`: all `var.cloudflare_zone_id` to `var.cf_zone_id` (5 occurrences)
- [ ] 2.6 Update `apps/web-platform/infra/tunnel.tf`: `var.cloudflare_account_id` to `var.cf_account_id`, `var.cloudflare_zone_id` to `var.cf_zone_id`
- [ ] 2.7 Update `apps/web-platform/infra/firewall.tf`: verify no cloudflare variable references need updating
- [ ] 2.8 Verify telegram-bridge variables.tf needs no renames (no cloudflare variables)
- [ ] 2.9 Add header comment to both `variables.tf` files documenting the Doppler workflow

## Phase 3: Testing

- [ ] 3.1 Run `doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform plan` in `apps/web-platform/infra/` (with no `.tfvars` file)
- [ ] 3.2 Run `doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform plan` in `apps/telegram-bridge/infra/` (with no `.tfvars` file)
- [ ] 3.3 Verify `admin_ips` list type parses correctly from Doppler HCL-encoded value
- [ ] 3.4 Verify `terraform plan` without `doppler run` prompts for required variables (no secrets leak)
- [ ] 3.5 Delete local `.tfvars` files after successful validation
