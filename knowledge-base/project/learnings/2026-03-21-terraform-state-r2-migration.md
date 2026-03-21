# Learning: Terraform State Migration to Cloudflare R2

## Problem

Both Terraform stacks (`telegram-bridge` and `web-platform`) used the implicit local backend — state had been lost, live infrastructure existed but Terraform couldn't track it. No remote backend, no backup, no guardrails. This blocked #967 and created ongoing operational risk.

## Solution

### 1. R2 as S3-compatible Terraform backend

Cloudflare R2 works as a Terraform S3 backend with specific `skip_*` flags. The critical configuration:

```hcl
backend "s3" {
  bucket                      = "soleur-terraform-state"
  key                         = "<app-name>/terraform.tfstate"
  region                      = "auto"
  endpoints                   = { s3 = "https://<ACCOUNT_ID>.r2.cloudflarestorage.com" }
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_s3_checksum            = true
  use_path_style              = true
  use_lockfile                = false  # R2 does not support S3 conditional writes
}
```

`use_lockfile = false` is critical — R2 doesn't support S3 conditional writes. Terraform 1.11+ defaults to `true`, which would break `init`. Setting it explicitly future-proofs against version upgrades.

### 2. R2 bucket bootstrap is a legitimate Terraform-rule exception

The state bucket itself can't be managed by the Terraform that depends on it (chicken-and-egg). Create it via the Cloudflare API or wrangler CLI. This is an explicit exception to the AGENTS.md "Terraform for provisioning" rule.

### 3. R2 requires separate S3-compatible credentials

R2 has two credential types: Cloudflare API tokens (for bucket management) and S3-compatible Access Key/Secret Key (for S3 API operations like Terraform state). These are created separately — API tokens from the profile page, S3 credentials from the R2 API Tokens page (Account API tokens recommended for production).

### 4. Doppler `--name-transformer tf-var` and S3 backend credentials conflict

The `tf-var` transformer converts ALL keys to `TF_VAR_*` format, including `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. The S3 backend reads these as plain env vars, not `TF_VAR_*`. Solution: set backend credentials separately (plain env vars), then use `--name-transformer tf-var` only for Terraform variable injection. Or set all env vars manually.

### 5. Stale `.terraform` directory causes TLS failures on backend switch

Running `terraform init -backend=false` creates a `.terraform` directory configured for no backend. If you then add a backend block and run `terraform init` again, the stale backend configuration can cause TLS handshake failures. Fix: `rm -rf .terraform` before initializing with the new backend.

### 6. `cloudflare_zero_trust_access_policy` import is broken in provider v4.x

The Cloudflare Terraform provider v4.52.5 cannot import `cloudflare_zero_trust_access_policy` — all import ID formats (`zone_id/app_id/policy_id`, `zones/zone_id/...`, `accounts/account_id/...`) fail with "zone_id or account_id required" during refresh. Workaround: pull state, manually add the resource JSON, push state back.

### 7. `random_id` import uses base64url without padding

`terraform import random_id.<name> <value>` expects base64url encoding with NO padding (no trailing `=`). Standard base64 with padding is rejected. When the original value is irrecoverable (e.g., lost state), import a placeholder and use `lifecycle { ignore_changes }` on the dependent resource.

## Key Insight

Infrastructure import into Terraform is not "run terraform import" — it's a multi-step process: bootstrap the backend, add backend + lifecycle blocks, initialize, import each resource, patch provider bugs via state manipulation, apply to sync defaults, then verify zero drift. The lifecycle `ignore_changes` blocks for create-time-only attributes (user_data, ssh_keys, image, secret, config_src) are import artifacts that should be marked with TODO comments for removal after clean reprovisioning.

## Session Errors

1. **Wrangler auth failure** — `CF_API_TOKEN` expired, 401 on R2 bucket list. Created new R2-scoped token via Playwright.
2. **R2 not enabled** — Cloudflare API returned 10042. Had to activate R2 subscription ($0.00 free tier) via dashboard.
3. **TLS handshake failure** — Stale `.terraform` dir from `-backend=false` init. Fixed by removing `.terraform`.
4. **`--name-transformer tf-var` broke backend auth** — Converted `AWS_ACCESS_KEY_ID` to `TF_VAR_AWS_ACCESS_KEY_ID`. Switched to manual env var mapping.
5. **Doppler key naming mismatch** — `CLOUDFLARE_ACCOUNT_ID` doesn't produce `TF_VAR_cf_account_id`. Set env vars manually.
6. **Access policy import provider bug** — All import ID formats failed. Worked around via `terraform state pull/push`.
7. **`random_id` base64 padding error** — `=` padding rejected. Used no-padding base64url format.
8. **telegram-bridge has no live infrastructure** — Plan assumed 24 resources across 2 stacks; only web-platform (18) had live resources.

## Tags

category: integration-issues
module: web-platform, infrastructure
