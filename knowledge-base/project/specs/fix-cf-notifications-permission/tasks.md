# Tasks: fix CF Notifications Permission

## Phase 1: Add Permission (Playwright)

- [ ] 1.1 Click edit menu on `soleur-terraform-tunnel` row (ref=e146) in CF dashboard
- [ ] 1.2 Add `Account > Notifications > Edit` permission
- [ ] 1.3 Save token (preserves existing token value)

## Phase 2: Verify Token

- [ ] 2.1 Verify token still active via `curl` to `/user/tokens/verify` endpoint
- [ ] 2.2 Confirm token ID `62702ea295b7c0a0f6cbaf532ef7dab5` unchanged

## Phase 3: Code Change

- [ ] 3.1 Update `cf_api_token` variable description in `apps/web-platform/infra/variables.tf:56-60`

## Phase 4: Terraform Apply

- [ ] 4.1 Run `terraform init` in `apps/web-platform/infra/` (via nested Doppler invocation)
- [ ] 4.2 Run `terraform plan` -- gate: exactly 1 new resource, 0 changes/destroys
- [ ] 4.3 Run `terraform apply -auto-approve`
- [ ] 4.4 Verify exit code 0 and resource created in state

## Phase 5: Ship

- [ ] 5.1 Commit `variables.tf` description update
- [ ] 5.2 Create PR with `Closes #992` in body
- [ ] 5.3 Merge and cleanup
