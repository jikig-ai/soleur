# Tasks: Pin Doppler CLI Install with Checksum Verification

## Phase 1: Implementation

### 1.1 Replace Doppler CLI install in cloud-init.yml

- [x] 1.1.1 Read `apps/web-platform/infra/cloud-init.yml`
- [x] 1.1.2 Replace line 171 (`curl | sh` install) with pinned binary download block
- [x] 1.1.3 Use version `3.75.3` and SHA-256 `9c840cdd32cffff06d048329549ba2fa908146b385f21cd1d54bf34a0082d0db`
- [x] 1.1.4 Match the webhook binary install pattern (lines 222-229)
- [x] 1.1.5 Use `$${VAR}` Terraform template escape syntax for shell variables
- [x] 1.1.6 Extract `doppler` binary (at tarball root, no `--strip-components`)

## Phase 2: Verification

### 2.1 Validate Terraform template rendering

- [x] 2.1.1 Run `terraform fmt` on `apps/web-platform/infra/` to verify HCL formatting
- [x] 2.1.2 Run `terraform validate` to confirm cloud-init template renders correctly
- [x] 2.1.3 Verify `$${DOPPLER_VERSION}` renders as `${DOPPLER_VERSION}` (not empty)

### 2.2 Validate no unintended changes

- [x] 2.2.1 Confirm `server.tf` is NOT modified
- [x] 2.2.2 Confirm Doppler token setup (lines 173-176) is unchanged
- [x] 2.2.3 Confirm `doppler secrets download` usage (lines 251-253) is unchanged
- [x] 2.2.4 Grep for any remaining `cli.doppler.com/install.sh` references
