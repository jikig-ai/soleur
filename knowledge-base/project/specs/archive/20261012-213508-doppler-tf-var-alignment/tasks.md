# Tasks: Align Doppler Key Names with Terraform tf-var Transformer

## Phase 1: Add Aliased/Missing Keys to Doppler

- [x] 1.1 Add `CF_API_TOKEN` to `prd_terraform` (copy value from `CLOUDFLARE_API_TOKEN`)
- [x] 1.2 Add `CF_ACCOUNT_ID` to `prd_terraform` (copy value from `CLOUDFLARE_ACCOUNT_ID`)
- [x] 1.3 Add `ADMIN_IPS` to `prd_terraform` as JSON array (`["82.67.29.121/32"]`)
- [x] 1.4 Add `DOPPLER_TOKEN` to `prd_terraform` (Doppler service token for prd)
- [x] 1.5 Add `DEPLOY_SSH_PUBLIC_KEY` to `prd_terraform` (generated deploy_ed25519 key pair)

## Phase 2: Nested Invocation Pattern for R2 Backend

- [x] 2.1 Verify nested `doppler run` invocation produces both plain `AWS_ACCESS_KEY_ID` and `TF_VAR_cf_api_token` (requires `--token` on inner call)
- [x] 2.2 Update `apps/web-platform/infra/variables.tf` header comment with nested invocation pattern and rationale
- [x] 2.3 Update `apps/telegram-bridge/infra/variables.tf` header comment with nested invocation pattern and rationale

## Phase 3: Validation

- [x] 3.1 Verify `TF_VAR_cf_api_token` outputs correct value via nested invocation
- [x] 3.2 Verify `TF_VAR_cf_account_id` outputs correct value via nested invocation
- [x] 3.3 Verify `TF_VAR_admin_ips` outputs JSON array intact (brackets and quotes preserved)
- [x] 3.4 Run `terraform init` in `apps/web-platform/infra/` with nested Doppler invocation
- [x] 3.5 Run `terraform init` in `apps/telegram-bridge/infra/` with nested Doppler invocation

## Phase 4: Cleanup

- [x] 4.1 Delete `CLOUDFLARE_API_TOKEN` from `prd_terraform` (direct secret, not inherited -- safe to remove)
- [x] 4.2 Delete `CLOUDFLARE_ACCOUNT_ID` from `prd_terraform` (direct secret, not inherited -- safe to remove)

## Phase 5: Documentation

- [x] 5.1 Update learning `2026-03-21-doppler-tf-var-naming-alignment.md` with nested invocation discovery, R2 credential workaround, and DOPPLER_TOKEN collision fix
- [ ] 5.2 Create compound learning capturing full alignment process
