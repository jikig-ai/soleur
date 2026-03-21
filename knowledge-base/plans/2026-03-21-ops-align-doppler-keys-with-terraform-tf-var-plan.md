---
title: "ops: align Doppler key names with Terraform tf-var transformer"
type: fix
date: 2026-03-21
---

# ops: Align Doppler Key Names with Terraform tf-var Transformer

## Overview

The Doppler `prd_terraform` config has key naming mismatches that prevent `doppler run --name-transformer tf-var -- terraform plan` from working cleanly. Three categories of problems exist: (1) long-form Cloudflare keys that produce wrong TF_VAR names, (2) missing keys that Terraform requires, and (3) R2 backend credentials that get incorrectly transformed.

## Problem Statement

PR #970 renamed Terraform variables from `cloudflare_*` to `cf_*` to match Doppler's short-name convention. However, the Doppler `prd_terraform` config was not updated to match -- it still contains `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` instead of `CF_ACCOUNT_ID` and `CF_API_TOKEN`.

**Verified live mismatches** (from `doppler run --name-transformer tf-var -- env`):

| Doppler Key | tf-var Produces | TF Variable Expects |
|---|---|---|
| `CLOUDFLARE_ACCOUNT_ID` | `TF_VAR_cloudflare_account_id` | `TF_VAR_cf_account_id` |
| `CLOUDFLARE_API_TOKEN` | `TF_VAR_cloudflare_api_token` | `TF_VAR_cf_api_token` |

**Missing keys** (no TF_VAR produced, but Terraform requires them):

| Key Needed | TF Variable | Purpose |
|---|---|---|
| `ADMIN_IPS` | `admin_ips` | IP allowlist for SSH firewall rules (both stacks) |
| `DOPPLER_TOKEN` | `doppler_token` | Service token injected into server cloud-init (web-platform) |
| `DEPLOY_SSH_PUBLIC_KEY` | `deploy_ssh_public_key` | SSH key for CI deploy user (telegram-bridge) |

**R2 backend credential conflict** (documented in learning `2026-03-21-terraform-state-r2-migration.md`, session error #4):

`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are stored in `prd_terraform` for the S3/R2 backend. The `--name-transformer tf-var` converts them to `TF_VAR_aws_access_key_id` and `TF_VAR_aws_secret_access_key`, which the S3 backend cannot read. The backend needs plain `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` env vars.

## Proposed Solution

### Phase 1: Add aliased/missing keys to Doppler

Add short-name keys to `prd_terraform` config. Doppler supports multiple keys with the same value -- no duplication conflict.

```bash
# Add short-name aliases for Cloudflare credentials
doppler secrets set CF_API_TOKEN <same-value-as-CLOUDFLARE_API_TOKEN> --project soleur --config prd_terraform
doppler secrets set CF_ACCOUNT_ID <same-value-as-CLOUDFLARE_ACCOUNT_ID> --project soleur --config prd_terraform

# Add missing Terraform-required keys
doppler secrets set ADMIN_IPS '["<ip1>/32","<ip2>/32"]' --project soleur --config prd_terraform
doppler secrets set DOPPLER_TOKEN <doppler-service-token> --project soleur --config prd_terraform
doppler secrets set DEPLOY_SSH_PUBLIC_KEY <ssh-public-key> --project soleur --config prd_terraform
```

### Phase 2: Handle R2 backend credentials

The `--name-transformer tf-var` flag transforms ALL keys, including `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` which the S3 backend needs as plain env vars. Two approaches:

**Option A (recommended): Two-step invocation.** Export AWS credentials first, then use Doppler with transformer:

```bash
# In operator's shell profile or a wrapper alias:
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID --project soleur --config prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY --project soleur --config prd_terraform --plain)
doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform plan
```

**Option B: Move AWS creds out of prd_terraform.** Store R2 credentials in a separate Doppler config (e.g., `prd_terraform_backend`) without the transformer. This adds config sprawl.

Option A is simpler and keeps all Terraform-related secrets in one config.

### Phase 3: Remove stale long-form keys (optional, after verification)

After confirming `doppler run --name-transformer tf-var -- terraform plan` works for both stacks:

```bash
doppler secrets delete CLOUDFLARE_ACCOUNT_ID --project soleur --config prd_terraform --yes
doppler secrets delete CLOUDFLARE_API_TOKEN --project soleur --config prd_terraform --yes
```

This is optional -- Terraform ignores unmatched `TF_VAR_*` variables. The long-form keys are inherited from `prd` anyway, so deleting the `prd_terraform` override just means the inherited value still produces the wrong TF_VAR name (harmless, since `cf_api_token` gets the correct value from the new short-form key).

### Phase 4: Document the workflow

Update the header comment in both `variables.tf` files to document the two-step invocation pattern for R2 backend credentials.

## Technical Considerations

### Doppler inheritance

`prd_terraform` inherits from `prd`. The `prd` config has `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`. Adding `CF_API_TOKEN` and `CF_ACCOUNT_ID` to `prd_terraform` creates overrides that coexist with the inherited long-form names. Both will be transformed, but Terraform only binds to matching variable names.

### Complex type: admin_ips

`admin_ips` is `list(string)`. Terraform's TF_VAR mechanism parses HCL-encoded values. Store the value as a JSON array string in Doppler: `["1.2.3.4/32","5.6.7.8/32"]`. Verify Doppler preserves brackets and quotes with `doppler run --name-transformer tf-var -- printenv TF_VAR_admin_ips`.

### DOPPLER_TOKEN naming

`DOPPLER_TOKEN` is not a Doppler reserved name. When Doppler injects it, `DOPPLER_TOKEN=<value>` appears alongside `doppler run`'s own implicit `DOPPLER_TOKEN`. The explicit secret value takes precedence. With `--name-transformer tf-var`, it becomes `TF_VAR_doppler_token`, correctly mapping to the `doppler_token` TF variable. However, note that `DOPPLER_SERVICE_TOKEN_PRD` already exists in the config but produces `TF_VAR_doppler_service_token_prd` which does not match. A new `DOPPLER_TOKEN` key with the service token value is needed.

### No Terraform code changes

All TF variable renames were completed in PR #970. This issue is purely Doppler config (out-of-repo) and optionally documentation updates to `variables.tf` header comments.

## Non-Goals

- Renaming TF variables (already done in #970)
- Automating Terraform in CI (remains manual quarterly operation)
- Creating wrapper scripts (operator runs commands directly)
- Moving to a different secrets manager

## Acceptance Criteria

- [ ] `CF_API_TOKEN` key exists in Doppler `prd_terraform` config with correct value
- [ ] `CF_ACCOUNT_ID` key exists in Doppler `prd_terraform` config with correct value
- [ ] `ADMIN_IPS` key exists in Doppler `prd_terraform` config as JSON array
- [ ] `DOPPLER_TOKEN` key exists in Doppler `prd_terraform` config with service token value
- [ ] `DEPLOY_SSH_PUBLIC_KEY` key exists in Doppler `prd_terraform` config
- [ ] `doppler run --name-transformer tf-var -- terraform plan` succeeds in `apps/web-platform/infra/` (with AWS creds exported separately)
- [ ] `doppler run --name-transformer tf-var -- terraform plan` succeeds in `apps/telegram-bridge/infra/` (with AWS creds exported separately)
- [ ] `variables.tf` header comment documents the two-step invocation pattern for R2 backend credentials
- [ ] Learning document created capturing the R2 credential conflict workaround

## Test Scenarios

- Given `CF_API_TOKEN` in `prd_terraform`, when running `doppler run --name-transformer tf-var -- printenv TF_VAR_cf_api_token`, then the correct Cloudflare API token is printed
- Given `ADMIN_IPS` set to `["1.2.3.4/32"]` in `prd_terraform`, when running `doppler run --name-transformer tf-var -- printenv TF_VAR_admin_ips`, then the JSON array string is printed with brackets and quotes intact
- Given AWS creds exported as plain env vars and Doppler transformer active, when running `terraform init` in `apps/web-platform/infra/`, then S3/R2 backend initializes successfully
- Given both `CLOUDFLARE_API_TOKEN` (inherited) and `CF_API_TOKEN` (override) in `prd_terraform`, when running with `--name-transformer tf-var`, then both `TF_VAR_cloudflare_api_token` and `TF_VAR_cf_api_token` are set, and Terraform uses only `TF_VAR_cf_api_token` (the declared variable)

## Affected Files

### In-repo changes (minimal)

- `apps/web-platform/infra/variables.tf` -- update header comment to document two-step invocation
- `apps/telegram-bridge/infra/variables.tf` -- update header comment to document two-step invocation

### Out-of-repo changes (Doppler config)

| Action | Key | Config | Value Source |
|---|---|---|---|
| Add | `CF_API_TOKEN` | `prd_terraform` | Same as `CLOUDFLARE_API_TOKEN` |
| Add | `CF_ACCOUNT_ID` | `prd_terraform` | Same as `CLOUDFLARE_ACCOUNT_ID` |
| Add | `ADMIN_IPS` | `prd_terraform` | JSON array of admin IP CIDRs |
| Add | `DOPPLER_TOKEN` | `prd_terraform` | Doppler service token for prd |
| Add | `DEPLOY_SSH_PUBLIC_KEY` | `prd_terraform` | CI deploy user SSH public key |

### Knowledge base

- `knowledge-base/learnings/2026-03-21-doppler-tf-var-naming-alignment.md` -- update with R2 credential conflict workaround

## MVP

### variables.tf header comment (web-platform)

```hcl
# Secrets injected via Doppler (two-step for R2 backend credentials):
#   export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID --project soleur --config prd_terraform --plain)
#   export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY --project soleur --config prd_terraform --plain)
#   doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform plan
```

### variables.tf header comment (telegram-bridge)

```hcl
# Secrets injected via Doppler (two-step for R2 backend credentials):
#   export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID --project soleur --config prd_terraform --plain)
#   export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY --project soleur --config prd_terraform --plain)
#   doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform plan
```

### Doppler setup commands

```bash
# Copy values from existing long-form keys
CF_API_TOKEN_VAL=$(doppler secrets get CLOUDFLARE_API_TOKEN --project soleur --config prd_terraform --plain)
CF_ACCOUNT_ID_VAL=$(doppler secrets get CLOUDFLARE_ACCOUNT_ID --project soleur --config prd_terraform --plain)

doppler secrets set CF_API_TOKEN "$CF_API_TOKEN_VAL" --project soleur --config prd_terraform
doppler secrets set CF_ACCOUNT_ID "$CF_ACCOUNT_ID_VAL" --project soleur --config prd_terraform

# Add missing keys (values must be provided by operator)
doppler secrets set ADMIN_IPS '["<admin-ip-1>/32","<admin-ip-2>/32"]' --project soleur --config prd_terraform
doppler secrets set DOPPLER_TOKEN <doppler-prd-service-token> --project soleur --config prd_terraform
doppler secrets set DEPLOY_SSH_PUBLIC_KEY "<ssh-rsa ...>" --project soleur --config prd_terraform
```

## References

- Closes #978
- Follow-up from #970 (PR that renamed TF variables)
- Deferred from #973 (R2 migration, session error #5)
- Learning: `knowledge-base/learnings/2026-03-21-doppler-tf-var-naming-alignment.md`
- Learning: `knowledge-base/learnings/2026-03-21-terraform-state-r2-migration.md` (session error #4, #5)
- Prior plan: `knowledge-base/plans/2026-03-21-ops-doppler-terraform-integration-plan.md`
