---
title: "ops: integrate Doppler with Terraform via --name-transformer"
type: feat
date: 2026-03-21
semver: patch
---

# ops: Integrate Doppler with Terraform via --name-transformer

## Overview

Wire `doppler run --name-transformer tf-var -- terraform plan/apply` for both infrastructure stacks (web-platform, telegram-bridge), eliminating `.tfvars` files as the secrets mechanism for Terraform. This was explicitly deferred from #734 (PR #964) due to a naming mismatch between Doppler keys and Terraform variable names.

## Problem Statement

Terraform infrastructure provisioning still relies on `.tfvars` files for sensitive variables (`hcloud_token`, `cloudflare_api_token`, etc.). While Doppler was adopted as the centralized secrets manager in #734/#964, Terraform was carved out because:

1. **Naming mismatch** -- Doppler's `--name-transformer tf-var` lowercases and prepends `TF_VAR_`. The Doppler key `CF_API_TOKEN` becomes `TF_VAR_cf_api_token`, but the Terraform variable is `cloudflare_api_token` (expects `TF_VAR_cloudflare_api_token`).
2. **Low frequency** -- Terraform runs quarterly at most.

The `.tfvars` approach works but fragments secrets management: some secrets in Doppler, some in local files. Consolidating into Doppler provides a single pane of glass.

## Proposed Solution

**Rename Terraform variables to match Doppler short names**, then add the missing Terraform-specific secrets to Doppler. This is preferred over adding duplicate Doppler keys because:

- Fewer total secrets to manage
- Variable names become shorter and more consistent across stacks
- No naming divergence between Doppler and Terraform

### Naming Mapping

Current Doppler keys exist in the `dev` config with short names (`CF_API_TOKEN`, `CF_ZONE_ID`). The `--name-transformer tf-var` converts them to `TF_VAR_<lowercase_snake>`. The plan is to match TF variable names to these transformed names.

| Doppler Key (to add) | TF_VAR Transform | Current TF Variable | New TF Variable |
|---|---|---|---|
| `HCLOUD_TOKEN` | `TF_VAR_hcloud_token` | `hcloud_token` | `hcloud_token` (no change) |
| `CF_API_TOKEN` | `TF_VAR_cf_api_token` | `cloudflare_api_token` | `cf_api_token` |
| `CF_ZONE_ID` | `TF_VAR_cf_zone_id` | `cloudflare_zone_id` | `cf_zone_id` |
| `CF_ACCOUNT_ID` | `TF_VAR_cf_account_id` | `cloudflare_account_id` | `cf_account_id` |
| `WEBHOOK_DEPLOY_SECRET` | `TF_VAR_webhook_deploy_secret` | `webhook_deploy_secret` | `webhook_deploy_secret` (no change) |
| `ADMIN_IPS` | `TF_VAR_admin_ips` | `admin_ips` | `admin_ips` (no change) |
| `DEPLOY_SSH_PUBLIC_KEY` | `TF_VAR_deploy_ssh_public_key` | `deploy_ssh_public_key` | `deploy_ssh_public_key` (no change) |
| `DOPPLER_TOKEN` | `TF_VAR_doppler_token` | `doppler_token` | `doppler_token` (no change) |

Only 3 variables need renaming (the `cloudflare_*` prefixed ones to `cf_*`).

### Non-Secret Variables

Variables with defaults in `variables.tf` (`server_type`, `location`, `image_name`, `volume_size`, `ssh_key_path`, `app_domain`, `app_domain_base`) do NOT need Doppler entries. They keep their defaults.

The `admin_ips` list variable is special -- Terraform supports complex types via `TF_VAR_` using HCL syntax (e.g., `TF_VAR_admin_ips='["1.2.3.4/32"]'`). Store as a JSON-encoded string in Doppler.

### Doppler Config Strategy

Add Terraform-specific secrets to a dedicated Doppler config (e.g., `prd_terraform` branched from `prd`) rather than polluting the application-level `prd` config. This keeps Terraform secrets isolated from runtime application secrets.

Alternative: use the existing `prd` config with `--only-secrets` flag to limit which secrets are injected. But a dedicated config is cleaner -- Terraform needs different secrets than the running application.

## Technical Considerations

### Terraform State

Renaming variables (`cloudflare_api_token` to `cf_api_token`) is purely a variable interface change. It does NOT affect Terraform state -- state tracks resources, not variable names. No `terraform state mv` needed.

However, the rename must happen atomically: update `variables.tf`, all `.tf` files referencing `var.cloudflare_*`, and the Doppler config in the same `terraform apply`.

### Complex Types (admin_ips)

`admin_ips` is `list(string)`. Doppler stores strings. Terraform's `TF_VAR_` mechanism supports HCL-encoded complex types:

```bash
# Doppler value for ADMIN_IPS:
["1.2.3.4/32","5.6.7.8/32"]
```

This works because Terraform parses `TF_VAR_*` values as HCL expressions when the variable type is not `string`.

### No .tfvars Deletion

The `.tfvars` files are already gitignored and exist only on disk (local operator machine). After migration, the operator deletes them manually. The `.gitignore` entries for `*.tfvars` should remain as defense-in-depth.

### Doppler Config Creation

Use `doppler configs create` or the Doppler CLI to branch a new config. Secrets can be set via `doppler secrets set`.

## Non-Goals

- Migrating non-secret defaults to Doppler (they stay as `default =` in variables.tf)
- Creating Terraform wrapper scripts (operator runs `doppler run --config prd_terraform --name-transformer tf-var -- terraform plan` directly)
- Automating Terraform runs in CI (remains a manual quarterly operation)
- Creating README.md files (issue #969 mentions README updates but no READMEs exist for these apps)

## Acceptance Criteria

- [ ] Doppler `prd_terraform` config (or equivalent) exists with all Terraform-required secrets for both stacks
- [ ] `cloudflare_api_token` renamed to `cf_api_token` in web-platform `variables.tf`, `main.tf`, and all referencing `.tf` files
- [ ] `cloudflare_zone_id` renamed to `cf_zone_id` in web-platform `variables.tf`, `dns.tf`, `tunnel.tf`
- [ ] `cloudflare_account_id` renamed to `cf_account_id` in web-platform `variables.tf`, `tunnel.tf`
- [ ] `doppler run --name-transformer tf-var -- terraform plan` succeeds with no `.tfvars` file for both stacks
- [ ] `admin_ips` list type works via Doppler (HCL-encoded JSON string)
- [ ] `.gitignore` entries for `*.tfvars` preserved as defense-in-depth
- [ ] Inline comments in affected `.tf` files document the Doppler workflow

## Test Scenarios

- Given Doppler `prd_terraform` config with `HCLOUD_TOKEN` and `CF_API_TOKEN`, when running `doppler run --config prd_terraform --name-transformer tf-var -- terraform plan` in `apps/web-platform/infra/`, then plan succeeds without a `.tfvars` file
- Given Doppler `prd_terraform` config with `ADMIN_IPS` set to `["1.2.3.4/32"]`, when running `doppler run --name-transformer tf-var -- terraform plan`, then `admin_ips` variable receives the list correctly
- Given a renamed variable `cf_api_token` in `variables.tf`, when `main.tf` references `var.cf_api_token`, then the Cloudflare provider authenticates successfully
- Given no `.tfvars` file on disk, when running `terraform plan` without `doppler run`, then Terraform prompts for required variables (confirming no hardcoded secrets)

## Affected Files

### web-platform/infra/

- `variables.tf` -- rename `cloudflare_api_token` to `cf_api_token`, `cloudflare_zone_id` to `cf_zone_id`, `cloudflare_account_id` to `cf_account_id`
- `main.tf` -- update `provider "cloudflare"` block: `api_token = var.cf_api_token`
- `dns.tf` -- update all `zone_id = var.cf_zone_id` references (5 occurrences)
- `tunnel.tf` -- update `var.cloudflare_account_id` to `var.cf_account_id`, `var.cloudflare_zone_id` to `var.cf_zone_id`
- `firewall.tf` -- verify no cloudflare variable references (uses `var.admin_ips` only)

### telegram-bridge/infra/

- `variables.tf` -- no cloudflare variables exist (only `hcloud_token`, `admin_ips`, `ssh_key_path`, `server_type`, `location`, `image_name`, `deploy_ssh_public_key`, `doppler_token`). No renames needed.
- All variables already match Doppler short-name convention.

### Doppler (out-of-repo)

- Create `prd_terraform` config branched from `prd`
- Add: `HCLOUD_TOKEN`, `CF_API_TOKEN`, `CF_ZONE_ID`, `CF_ACCOUNT_ID`, `WEBHOOK_DEPLOY_SECRET`, `ADMIN_IPS`, `DEPLOY_SSH_PUBLIC_KEY`, `DOPPLER_TOKEN`
- Populate values from current `.tfvars` files

## MVP

### variables.tf (web-platform, after rename)

```hcl
variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "cf_api_token" {
  description = "Cloudflare API token with DNS edit permissions"
  type        = string
  sensitive   = true
}

variable "cf_zone_id" {
  description = "Cloudflare zone ID for soleur.ai"
  type        = string
}

variable "cf_account_id" {
  description = "Cloudflare account ID (required for Zero Trust tunnel resources)"
  type        = string
}
```

### main.tf (web-platform, after rename)

```hcl
provider "cloudflare" {
  api_token = var.cf_api_token
}
```

### Doppler workflow (operator command)

```bash
# Plan
cd apps/web-platform/infra
doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform plan

# Apply
doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform apply
```

## References

- Closes #969
- Deferred from #734 (PR #964)
- Doppler `--name-transformer` docs: https://docs.doppler.com/docs/cli#run
- Terraform TF_VAR_ env var docs: https://developer.hashicorp.com/terraform/language/values/variables#environment-variables
