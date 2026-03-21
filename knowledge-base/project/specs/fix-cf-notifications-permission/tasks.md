# Tasks: fix CF Notifications Permission

## Phase 1: Add Permission (Playwright)

- [ ] 1.1 Navigate to `soleur-terraform-tunnel` token edit page in CF dashboard
- [ ] 1.2 Add `Account > Notifications > Edit` permission
- [ ] 1.3 Save token (preserves existing token value)

## Phase 2: Code Change

- [ ] 2.1 Update `cf_api_token` variable description in `apps/web-platform/infra/variables.tf:56-60`

## Phase 3: Terraform Apply

- [ ] 3.1 Run `terraform init` in `apps/web-platform/infra/`
- [ ] 3.2 Run `terraform plan` to verify only `cloudflare_notification_policy.service_token_expiry` is created
- [ ] 3.3 Run `terraform apply -auto-approve`
- [ ] 3.4 Verify exit code 0 and resource created

## Phase 4: Ship

- [ ] 4.1 Commit `variables.tf` description update
- [ ] 4.2 Create PR referencing `Closes #992`
- [ ] 4.3 Merge and cleanup
