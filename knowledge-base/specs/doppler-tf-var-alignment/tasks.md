# Tasks: Align Doppler Key Names with Terraform tf-var Transformer

## Phase 1: Add Aliased/Missing Keys to Doppler

- [ ] 1.1 Add `CF_API_TOKEN` to `prd_terraform` (copy value from `CLOUDFLARE_API_TOKEN`)
- [ ] 1.2 Add `CF_ACCOUNT_ID` to `prd_terraform` (copy value from `CLOUDFLARE_ACCOUNT_ID`)
- [ ] 1.3 Add `ADMIN_IPS` to `prd_terraform` as JSON array (e.g., `["x.x.x.x/32"]`)
- [ ] 1.4 Add `DOPPLER_TOKEN` to `prd_terraform` (Doppler service token for prd)
- [ ] 1.5 Add `DEPLOY_SSH_PUBLIC_KEY` to `prd_terraform` (CI deploy user SSH key)

## Phase 2: R2 Backend Credential Workaround

- [ ] 2.1 Verify two-step invocation: export AWS creds, then `doppler run --name-transformer tf-var`
- [ ] 2.2 Update `apps/web-platform/infra/variables.tf` header comment with two-step pattern
- [ ] 2.3 Update `apps/telegram-bridge/infra/variables.tf` header comment with two-step pattern

## Phase 3: Validation

- [ ] 3.1 Verify `doppler run --name-transformer tf-var -- printenv TF_VAR_cf_api_token` outputs correct value
- [ ] 3.2 Verify `doppler run --name-transformer tf-var -- printenv TF_VAR_cf_account_id` outputs correct value
- [ ] 3.3 Verify `doppler run --name-transformer tf-var -- printenv TF_VAR_admin_ips` outputs JSON array intact
- [ ] 3.4 Run `terraform plan` in `apps/web-platform/infra/` with Doppler injection (two-step)
- [ ] 3.5 Run `terraform plan` in `apps/telegram-bridge/infra/` with Doppler injection (two-step)

## Phase 4: Cleanup (Optional)

- [ ] 4.1 Delete `CLOUDFLARE_API_TOKEN` override from `prd_terraform` (inherited value remains harmless)
- [ ] 4.2 Delete `CLOUDFLARE_ACCOUNT_ID` override from `prd_terraform` (inherited value remains harmless)

## Phase 5: Documentation

- [ ] 5.1 Update learning `2026-03-21-doppler-tf-var-naming-alignment.md` with R2 credential workaround
- [ ] 5.2 Create compound learning capturing full alignment process
