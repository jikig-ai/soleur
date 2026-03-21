---
title: "ops: integrate Doppler with Terraform via --name-transformer"
type: feat
date: 2026-03-21
semver: patch
deepened: 2026-03-21
---

# ops: Integrate Doppler with Terraform via --name-transformer

## Enhancement Summary

**Deepened on:** 2026-03-21
**Research sources:** Live Doppler CLI testing, Terraform best practices learning, cloud-deploy integration learning, terraform-architect agent review, infra-security agent review

### Key Improvements

1. Verified `prd_terraform` branch config creation works (`doppler configs create prd_terraform --project soleur --environment prd`) -- config inherits all `prd` secrets automatically
2. Discovered that `--only-secrets` combined with `--name-transformer tf-var` fails (secrets looked up AFTER transformation) -- confirms dedicated config is the only viable approach
3. Confirmed `DOPPLER_TOKEN` is not a Doppler reserved name and can be stored as a secret, but the injected env var does not conflict with `terraform` child process
4. Verified exact `tf-var` transformer output: `CF_API_TOKEN` -> `TF_VAR_cf_api_token` (tested live against dev config)

### New Considerations Discovered

- Branch config inherits ALL parent (`prd`) secrets -- Terraform ignores unmatched `TF_VAR_*` vars, so harmless but worth noting
- `--only-secrets` flag is incompatible with `--name-transformer` (Doppler bug or design limitation) -- eliminates the alternative approach
- `cf_zone_id` and `cf_account_id` should be marked `sensitive = true` in variables.tf (best practice from terraform-architect review -- zone/account IDs enable targeted attacks)
- The `dns.tf` file has exactly 5 `var.cloudflare_zone_id` references, `tunnel.tf` has 3 `var.cloudflare_account_id` + 1 `var.cloudflare_zone_id` references (verified by file read)

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

### Research Insights

**Best Practices (from terraform best practices learning):**
- Variable naming should use `snake_case` -- the `cf_*` prefix is consistent with this convention
- All variables should have `description` and `type` (already satisfied)
- Sensitive variables must be marked with `sensitive = true` -- `cf_zone_id` and `cf_account_id` should be considered for this (they enable targeted attacks on the Cloudflare account)

**Edge Case Verified:** `--only-secrets` flag fails when combined with `--name-transformer tf-var`. The flag looks up secrets by the original Doppler name, but the transformer has already changed the names. Error: `the following secrets you are trying to include do not exist in your config`. This eliminates the alternative approach of filtering from the `prd` config.

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

Add Terraform-specific secrets to a dedicated Doppler `prd_terraform` branch config under the `prd` environment. This is the only viable approach because:

1. **Inheritance works correctly** -- `prd_terraform` inherits all `prd` secrets (verified via `doppler configs create prd_terraform --project soleur --environment prd`). Only Terraform-specific secrets need to be added explicitly.
2. **`--only-secrets` is incompatible** -- Combining `--only-secrets` with `--name-transformer tf-var` fails (verified: Doppler looks up secrets by original name after the transformer has already renamed them).
3. **Isolation** -- Terraform secrets (`HCLOUD_TOKEN`, `CF_API_TOKEN`) stay out of the application-level `prd` config, reducing blast radius.

**Inherited but harmless secrets:** The `prd_terraform` config inherits app secrets (`ANTHROPIC_API_KEY`, `STRIPE_SECRET_KEY`, etc.) from `prd`. With `--name-transformer tf-var`, these become `TF_VAR_anthropic_api_key`, etc. Terraform ignores `TF_VAR_*` variables that don't match any declared variable -- no side effects.

## Technical Considerations

### Terraform State

Renaming variables (`cloudflare_api_token` to `cf_api_token`) is purely a variable interface change. It does NOT affect Terraform state -- state tracks resources, not variable names. No `terraform state mv` needed.

However, the rename must happen atomically: update `variables.tf`, all `.tf` files referencing `var.cloudflare_*`, and the Doppler config in the same `terraform apply`.

### Research Insights

**From cloud-deploy integration learning:**
- Volume mount patterns in `cloud-init.yml` and `server.tf` use `doppler_token` for server-side injection -- this is separate from the Terraform provisioning flow and should NOT be confused with the `DOPPLER_TOKEN` stored in Doppler for Terraform input
- The `doppler_token` TF variable holds a Doppler service token that the cloud-init uses to fetch runtime secrets on the server -- it is NOT the CLI auth token

**`DOPPLER_TOKEN` as a Doppler secret (verified):**
- `DOPPLER_TOKEN` is not a reserved Doppler name -- it can be stored as a secret
- When injected via `doppler run`, `DOPPLER_TOKEN=<value>` appears in the child process env, but `terraform` does not use this env var, so no conflict
- With `--name-transformer tf-var`, it becomes `TF_VAR_doppler_token`, correctly mapping to the `doppler_token` TF variable

### Complex Types (admin_ips)

`admin_ips` is `list(string)`. Doppler stores strings. Terraform's `TF_VAR_` mechanism supports HCL-encoded complex types:

```bash
# Doppler value for ADMIN_IPS:
["1.2.3.4/32","5.6.7.8/32"]
```

This works because Terraform parses `TF_VAR_*` values as HCL expressions when the variable type is not `string`.

**Edge case:** The HCL parser requires valid JSON array syntax. Verify that Doppler preserves the brackets and quotes exactly -- no whitespace normalization or quote escaping. Test with `doppler run --name-transformer tf-var -- printenv TF_VAR_admin_ips` before the first `terraform plan`.

### No .tfvars Deletion

The `.tfvars` files are already gitignored and exist only on disk (local operator machine). After migration, the operator deletes them manually. The `.gitignore` entries for `*.tfvars` should remain as defense-in-depth.

### Doppler Config Creation

Verified command:

```bash
doppler configs create prd_terraform --project soleur --environment prd
```

Secrets are set individually:

```bash
doppler secrets set HCLOUD_TOKEN <value> --project soleur --config prd_terraform
doppler secrets set CF_API_TOKEN <value> --project soleur --config prd_terraform
# ... etc
```

## Non-Goals

- Migrating non-secret defaults to Doppler (they stay as `default =` in variables.tf)
- Creating Terraform wrapper scripts (operator runs `doppler run --config prd_terraform --name-transformer tf-var -- terraform plan` directly)
- Automating Terraform runs in CI (remains a manual quarterly operation)
- Creating README.md files (issue #969 mentions README updates but no READMEs exist for these apps)
- Adding remote state backend (local state is sufficient for quarterly solo-operator usage)
- Marking `cf_zone_id` / `cf_account_id` as `sensitive = true` (deferred -- low risk for local-only Terraform, can be added later)

## Acceptance Criteria

- [ ] Doppler `prd_terraform` config exists with all Terraform-required secrets for both stacks
- [ ] `cloudflare_api_token` renamed to `cf_api_token` in web-platform `variables.tf`, `main.tf`, and all referencing `.tf` files
- [ ] `cloudflare_zone_id` renamed to `cf_zone_id` in web-platform `variables.tf`, `dns.tf` (5 refs), `tunnel.tf` (1 ref)
- [ ] `cloudflare_account_id` renamed to `cf_account_id` in web-platform `variables.tf`, `tunnel.tf` (3 refs)
- [ ] `doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform plan` succeeds with no `.tfvars` file for both stacks
- [ ] `admin_ips` list type works via Doppler (HCL-encoded JSON string)
- [ ] `.gitignore` entries for `*.tfvars` preserved as defense-in-depth
- [ ] Header comment in `variables.tf` documents the Doppler workflow command

## Test Scenarios

- Given Doppler `prd_terraform` config with `HCLOUD_TOKEN` and `CF_API_TOKEN`, when running `doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform plan` in `apps/web-platform/infra/`, then plan succeeds without a `.tfvars` file
- Given Doppler `prd_terraform` config with `ADMIN_IPS` set to `["1.2.3.4/32"]`, when running `doppler run --name-transformer tf-var -- terraform plan`, then `admin_ips` variable receives the list correctly
- Given a renamed variable `cf_api_token` in `variables.tf`, when `main.tf` references `var.cf_api_token`, then the Cloudflare provider authenticates successfully
- Given no `.tfvars` file on disk, when running `terraform plan` without `doppler run`, then Terraform prompts for required variables (confirming no hardcoded secrets)
- Given inherited `prd` secrets (`ANTHROPIC_API_KEY`, etc.) in `prd_terraform`, when running with `--name-transformer tf-var`, then Terraform ignores the unmatched `TF_VAR_*` variables without error

## Affected Files

### web-platform/infra/ (exact reference counts verified)

- `variables.tf` -- rename 3 variables: `cloudflare_api_token` -> `cf_api_token`, `cloudflare_zone_id` -> `cf_zone_id`, `cloudflare_account_id` -> `cf_account_id`
- `main.tf` -- 1 reference: `var.cloudflare_api_token` -> `var.cf_api_token` (line 24)
- `dns.tf` -- 5 references: all `var.cloudflare_zone_id` -> `var.cf_zone_id` (lines 2, 13, 24, 32, 40, 49)
- `tunnel.tf` -- 4 references: 3x `var.cloudflare_account_id` -> `var.cf_account_id` (lines 11, 17, 46), 1x `var.cloudflare_zone_id` -> `var.cf_zone_id` (line 38)
- `firewall.tf` -- 0 references to cloudflare variables (uses `var.admin_ips` only) -- no changes needed
- `outputs.tf` -- 0 references to cloudflare variables -- no changes needed

### telegram-bridge/infra/

- `variables.tf` -- no cloudflare variables exist. All variable names already match Doppler short-name convention. No changes needed.
- `server.tf`, `firewall.tf`, `outputs.tf` -- no cloudflare variable references. No changes needed.

### Doppler (out-of-repo, `prd_terraform` branch config)

Secrets to add (values sourced from current `.tfvars` files on operator machine):

| Secret | Source | Both Stacks? |
|--------|--------|-------------|
| `HCLOUD_TOKEN` | Current `.tfvars` `hcloud_token` | Yes |
| `CF_API_TOKEN` | Current `.tfvars` `cloudflare_api_token` | web-platform only |
| `CF_ZONE_ID` | Current `.tfvars` `cloudflare_zone_id` | web-platform only |
| `CF_ACCOUNT_ID` | Current `.tfvars` `cloudflare_account_id` | web-platform only |
| `WEBHOOK_DEPLOY_SECRET` | Current `.tfvars` `webhook_deploy_secret` | web-platform only |
| `ADMIN_IPS` | Current `.tfvars` `admin_ips` (HCL-encode as JSON array) | Yes |
| `DEPLOY_SSH_PUBLIC_KEY` | Current `.tfvars` `deploy_ssh_public_key` | telegram-bridge only |
| `DOPPLER_TOKEN` | Doppler service token (from server provisioning) | Yes |

## MVP

### variables.tf (web-platform, after rename)

```hcl
# Secrets injected via Doppler:
#   doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform plan

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

### Doppler workflow (operator commands)

```bash
# --- web-platform ---
cd apps/web-platform/infra
doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform plan
doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform apply

# --- telegram-bridge ---
cd apps/telegram-bridge/infra
doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform plan
doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform apply
```

### Doppler setup (one-time, operator runs manually)

```bash
# Config already created during research -- just add secrets
# doppler configs create prd_terraform --project soleur --environment prd

# Add Terraform-specific secrets (values from current .tfvars)
doppler secrets set HCLOUD_TOKEN <value> --project soleur --config prd_terraform
doppler secrets set CF_API_TOKEN <value> --project soleur --config prd_terraform
doppler secrets set CF_ZONE_ID <value> --project soleur --config prd_terraform
doppler secrets set CF_ACCOUNT_ID <value> --project soleur --config prd_terraform
doppler secrets set WEBHOOK_DEPLOY_SECRET <value> --project soleur --config prd_terraform
doppler secrets set ADMIN_IPS '["x.x.x.x/32","y.y.y.y/32"]' --project soleur --config prd_terraform
doppler secrets set DEPLOY_SSH_PUBLIC_KEY <value> --project soleur --config prd_terraform
doppler secrets set DOPPLER_TOKEN <service-token> --project soleur --config prd_terraform
```

## References

- Closes #969
- Deferred from #734 (PR #964)
- Doppler `--name-transformer` docs: https://docs.doppler.com/docs/cli#run
- Terraform TF_VAR_ env var docs: https://developer.hashicorp.com/terraform/language/values/variables#environment-variables
- Learning: `knowledge-base/learnings/2026-02-13-terraform-best-practices-research.md` (variable naming, sensitive marking)
- Learning: `knowledge-base/learnings/integration-issues/2026-02-10-cloud-deploy-infra-and-sdk-integration.md` (cloud-init volume patterns)
