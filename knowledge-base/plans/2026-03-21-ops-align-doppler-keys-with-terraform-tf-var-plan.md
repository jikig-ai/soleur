---
title: "ops: align Doppler key names with Terraform tf-var transformer"
type: fix
date: 2026-03-21
deepened: 2026-03-21
---

# ops: Align Doppler Key Names with Terraform tf-var Transformer

## Enhancement Summary

**Deepened on:** 2026-03-21
**Research sources:** Live Doppler CLI testing, Doppler official docs, Terraform S3 backend docs, nested `doppler run` discovery

### Key Improvements

1. Discovered nested `doppler run` pattern that provides a single-line invocation solving the R2 backend credential conflict -- no manual export steps needed
2. Verified `--preserve-env` flag behavior: preserves pre-existing shell env vars alongside transformed Doppler secrets
3. Confirmed `--only-secrets` is incompatible with `--name-transformer` (Doppler bug/design limitation)
4. Verified `--name-transformer tf-var` completely replaces original env var names (not additive) -- `AWS_ACCESS_KEY_ID` becomes only `TF_VAR_aws_access_key_id`
5. Confirmed `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` in `prd_terraform` are direct overrides (not inherited from `prd`, which has no CF keys)

### New Considerations Discovered

- Nested `doppler run` (outer: plain, inner: tf-var) preserves plain AWS creds in shell env while adding TF_VAR_* versions -- eliminates the two-step export pattern
- Doppler official docs do not document the S3 backend credential conflict, making this a genuine undocumented edge case worth capturing in learnings
- The `prd` config has zero Cloudflare keys -- `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` exist only in `prd_terraform` as direct secrets, not inherited overrides

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

The `--name-transformer tf-var` flag replaces ALL key names (not additive) -- `AWS_ACCESS_KEY_ID` becomes only `TF_VAR_aws_access_key_id`, and the original name disappears from the environment. The S3 backend needs plain `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. Three approaches:

**Option A (recommended): Nested `doppler run` invocation.** The outer call injects plain env vars; the inner call adds `TF_VAR_*` versions alongside. Pre-existing shell env vars survive the inner call's transformation:

```bash
doppler run --project soleur --config prd_terraform -- \
  doppler run --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform plan
```

This produces both `AWS_ACCESS_KEY_ID` (plain, from outer call -- S3 backend reads this) and `TF_VAR_cf_api_token` (transformed, from inner call -- Terraform reads this). Verified live: plain AWS creds survive the inner transformer because `doppler run` does not strip pre-existing env vars it did not inject.

**Option B: Two-step export.** Export AWS credentials first, then use Doppler with transformer:

```bash
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID --project soleur --config prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY --project soleur --config prd_terraform --plain)
doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform plan
```

**Option C: Move AWS creds out of prd_terraform.** Store R2 credentials in a separate Doppler config (e.g., `prd_terraform_backend`) without the transformer. This adds config sprawl.

Option A is cleanest -- single line, no manual export, all secrets from one config. Option B is a fallback if nested invocations cause issues.

### Research Insights: Doppler CLI Behavior

**`--name-transformer tf-var` is destructive, not additive** (verified live):
- The transformer replaces the original key name entirely
- `AWS_ACCESS_KEY_ID` becomes `TF_VAR_aws_access_key_id` -- the original name is gone
- This is not documented as a caveat in [Doppler's Terraform docs](https://docs.doppler.com/docs/terraform)

**`--only-secrets` is incompatible with `--name-transformer`** (verified live):
- `doppler run --name-transformer tf-var --only-secrets CF_API_TOKEN` fails with "secret does not exist"
- Doppler looks up secrets by name AFTER transformation, but secrets are stored with pre-transform names
- This eliminates filtering as an approach to the AWS credential problem

**`--preserve-env` preserves shell env vars, not Doppler secrets** (verified live):
- `--preserve-env="AWS_ACCESS_KEY_ID"` only works if `AWS_ACCESS_KEY_ID` is already in the shell environment
- It does NOT prevent the Doppler transformer from renaming the secret
- Useful as defense-in-depth with Option B but not a standalone solution

**Nested `doppler run` calls compose correctly** (verified live):
- Outer call sets plain env vars in the shell
- Inner call with `--name-transformer` adds `TF_VAR_*` versions
- Outer call's env vars persist -- the inner call does not strip them
- Both `AWS_ACCESS_KEY_ID` and `TF_VAR_cf_api_token` coexist in the final environment

### Phase 3: Remove stale long-form keys (optional, after verification)

After confirming `doppler run --name-transformer tf-var -- terraform plan` works for both stacks:

```bash
doppler secrets delete CLOUDFLARE_ACCOUNT_ID --project soleur --config prd_terraform --yes
doppler secrets delete CLOUDFLARE_API_TOKEN --project soleur --config prd_terraform --yes
```

This is optional -- Terraform ignores unmatched `TF_VAR_*` variables. Note: `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` are direct secrets in `prd_terraform`, NOT inherited from `prd` (the `prd` config has zero Cloudflare keys). Deleting them removes them entirely from the config, which is clean.

### Phase 4: Document the workflow

Update the header comment in both `variables.tf` files to document the nested `doppler run` invocation pattern with rationale explaining why the transformer is destructive (replaces names, not additive).

## Technical Considerations

### Doppler inheritance

`prd_terraform` inherits from `prd`. However, `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are direct secrets in `prd_terraform` only -- the `prd` config has zero Cloudflare keys (verified live). Adding `CF_API_TOKEN` and `CF_ACCOUNT_ID` to `prd_terraform` creates additional secrets that coexist with the long-form names. Both will be transformed by `--name-transformer tf-var`, but Terraform only binds to matching declared variable names (the short-form `cf_*` names). The long-form `TF_VAR_cloudflare_*` versions are harmlessly ignored.

After verifying the short-form keys work, the long-form keys (`CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN`) should be deleted from `prd_terraform` to eliminate redundancy (Phase 3).

### Complex type: admin_ips

`admin_ips` is `list(string)`. Terraform's TF_VAR mechanism parses HCL-encoded values. Store the value as a JSON array string in Doppler: `["1.2.3.4/32","5.6.7.8/32"]`. Verify Doppler preserves brackets and quotes with `doppler run --name-transformer tf-var -- printenv TF_VAR_admin_ips`.

### DOPPLER_TOKEN naming

`DOPPLER_TOKEN` is not a Doppler reserved name. When Doppler injects it, `DOPPLER_TOKEN=<value>` appears alongside `doppler run`'s own implicit `DOPPLER_TOKEN`. The explicit secret value takes precedence. With `--name-transformer tf-var`, it becomes `TF_VAR_doppler_token`, correctly mapping to the `doppler_token` TF variable. However, note that `DOPPLER_SERVICE_TOKEN_PRD` already exists in the config but produces `TF_VAR_doppler_service_token_prd` which does not match. A new `DOPPLER_TOKEN` key with the service token value is needed.

### No Terraform code changes

All TF variable renames were completed in PR #970. This issue is purely Doppler config (out-of-repo) and documentation updates to `variables.tf` header comments.

### Edge Cases

**DOPPLER_TOKEN collision:** `doppler run` injects its own `DOPPLER_TOKEN` env var (the CLI auth token). If a `DOPPLER_TOKEN` secret exists in the config, the explicit secret value takes precedence over the CLI's implicit one. With `--name-transformer tf-var`, both `DOPPLER_TOKEN` (from outer plain call) and `TF_VAR_doppler_token` (from inner transformer) will be present. Terraform reads only `TF_VAR_doppler_token`. The plain `DOPPLER_TOKEN` in the environment is the CLI auth token, not the service token -- no conflict.

**admin_ips JSON escaping:** The HCL parser requires valid JSON array syntax for `list(string)` variables via `TF_VAR_`. Doppler must preserve brackets, quotes, and commas exactly. Verify with `doppler run --name-transformer tf-var -- printenv TF_VAR_admin_ips` before the first `terraform plan`. If Doppler normalizes whitespace or escapes quotes, the value must be adjusted.

**Duplicate TF_VAR_ entries:** After adding `CF_API_TOKEN` alongside `CLOUDFLARE_API_TOKEN`, both `TF_VAR_cf_api_token` and `TF_VAR_cloudflare_api_token` will be present. Terraform only binds to declared variables -- `TF_VAR_cloudflare_api_token` is silently ignored since no variable `cloudflare_api_token` exists. No conflict, but cleaning up the long-form keys (Phase 3) eliminates the noise.

## Non-Goals

- Renaming TF variables (already done in #970)
- Automating Terraform in CI (remains manual quarterly operation)
- Creating wrapper scripts (operator runs commands directly)
- Moving to a different secrets manager

## Acceptance Criteria

- [x] `CF_API_TOKEN` key exists in Doppler `prd_terraform` config with correct value
- [x] `CF_ACCOUNT_ID` key exists in Doppler `prd_terraform` config with correct value
- [x] `ADMIN_IPS` key exists in Doppler `prd_terraform` config as JSON array
- [x] `DOPPLER_TOKEN` key exists in Doppler `prd_terraform` config with service token value
- [x] `DEPLOY_SSH_PUBLIC_KEY` key exists in Doppler `prd_terraform` config
- [x] Nested `doppler run` invocation succeeds for `terraform init` in `apps/web-platform/infra/`
- [x] Nested `doppler run` invocation succeeds for `terraform init` in `apps/telegram-bridge/infra/`
- [x] `variables.tf` header comment documents the nested invocation pattern with rationale
- [x] Stale long-form keys (`CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN`) deleted from `prd_terraform`
- [x] Learning document updated with R2 credential conflict workaround and DOPPLER_TOKEN collision fix

## Test Scenarios

- Given `CF_API_TOKEN` in `prd_terraform`, when running `doppler run --name-transformer tf-var -- printenv TF_VAR_cf_api_token`, then the correct Cloudflare API token is printed
- Given `ADMIN_IPS` set to `["1.2.3.4/32"]` in `prd_terraform`, when running `doppler run --name-transformer tf-var -- printenv TF_VAR_admin_ips`, then the JSON array string is printed with brackets and quotes intact
- Given nested `doppler run` invocation (outer: plain, inner: tf-var), when running `terraform init` in `apps/web-platform/infra/`, then S3/R2 backend initializes successfully (plain `AWS_ACCESS_KEY_ID` from outer call is readable by backend)
- Given nested `doppler run` invocation, when running `env | grep AWS_ACCESS`, then both `AWS_ACCESS_KEY_ID` (plain) and `TF_VAR_aws_access_key_id` (transformed) are present
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
# Secrets injected via Doppler (nested invocation for R2 backend + TF variables):
#   doppler run --project soleur --config prd_terraform -- \
#     doppler run --token "$(doppler configure get token --plain)" \
#       --project soleur --config prd_terraform --name-transformer tf-var -- \
#     terraform plan
#
# Why nested: --name-transformer tf-var replaces ALL key names (AWS_ACCESS_KEY_ID
# becomes TF_VAR_aws_access_key_id). The S3/R2 backend needs plain AWS_ACCESS_KEY_ID.
# The outer call injects plain env vars; the inner call adds TF_VAR_* versions.
# Why --token: DOPPLER_TOKEN secret collides with CLI auth token.
```

### variables.tf header comment (telegram-bridge)

```hcl
# Secrets injected via Doppler (nested invocation for R2 backend + TF variables):
#   doppler run --project soleur --config prd_terraform -- \
#     doppler run --token "$(doppler configure get token --plain)" \
#       --project soleur --config prd_terraform --name-transformer tf-var -- \
#     terraform plan
#
# Why nested: --name-transformer tf-var replaces ALL key names (AWS_ACCESS_KEY_ID
# becomes TF_VAR_aws_access_key_id). The S3/R2 backend needs plain AWS_ACCESS_KEY_ID.
# The outer call injects plain env vars; the inner call adds TF_VAR_* versions.
# Why --token: DOPPLER_TOKEN secret collides with CLI auth token.
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
- Learning: `knowledge-base/learnings/2026-03-20-doppler-secrets-manager-setup-patterns.md`
- Prior plan: `knowledge-base/plans/2026-03-21-ops-doppler-terraform-integration-plan.md`
- [Doppler Terraform integration docs](https://docs.doppler.com/docs/terraform)
- [Terraform S3 backend docs](https://developer.hashicorp.com/terraform/language/backend/s3)
