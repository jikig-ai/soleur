# Tasks: Remove terraform_data.doppler_install

## Phase 1: Code Changes

- [ ] 1.1 Remove `terraform_data.doppler_install` resource block from `apps/web-platform/infra/server.tf` (lines 41-70, including comment block)
- [ ] 1.2 Remove `ssh_private_key_path` variable from `apps/web-platform/infra/variables.tf` (lines 32-36)
- [ ] 1.3 Run `terraform validate` to confirm no dangling references

## Phase 2: State Cleanup

- [ ] 2.1 Run `terraform init` in `apps/web-platform/infra/` with Doppler credentials
- [ ] 2.2 Run `terraform state rm terraform_data.doppler_install`
- [ ] 2.3 Verify `terraform plan -detailed-exitcode` returns exit 0

## Phase 3: Verification

- [ ] 3.1 Confirm no other `.tf` files reference `ssh_private_key_path` or `doppler_install`
- [ ] 3.2 Confirm CI workflows handle missing variable gracefully (grep-based conditional)
