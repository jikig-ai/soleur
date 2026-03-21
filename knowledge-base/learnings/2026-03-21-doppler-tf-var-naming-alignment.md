# Learning: Doppler tf-var Transformer — Align TF Variable Names to External Key Names

## Problem

Doppler's `--name-transformer tf-var` converts secret keys to `TF_VAR_<lowercase_key>` format. When the Doppler key is `CF_API_TOKEN`, the transformer produces `TF_VAR_cf_api_token`. However, the existing Terraform variables used full descriptive names (`cloudflare_api_token`), expecting `TF_VAR_cloudflare_api_token`. This mismatch meant Doppler-injected secrets would not bind to the Terraform variables.

Additionally, `--only-secrets` combined with `--name-transformer tf-var` fails — Doppler looks up secrets by original name after the transformer has already renamed them.

## Solution

Rename the Terraform variables to match the Doppler short key names:

- `cloudflare_api_token` -> `cf_api_token`
- `cloudflare_zone_id` -> `cf_zone_id`
- `cloudflare_account_id` -> `cf_account_id`

Use a dedicated `prd_terraform` Doppler branch config for Terraform-specific secrets (inherits app secrets from `prd`, which Terraform silently ignores). Validate with `terraform validate` (no credentials needed) to catch stale references.

## Key Insight

When adapting variable names to match an external tool's naming convention, rename the variables rather than duplicating keys in the external system. Duplication creates maintenance burden. Renaming is a one-time change with no runtime cost, and `terraform validate` catches reference errors without credentials.

## Session Errors

1. **Expired CF API token in dev config** — Cloudflare API returned 401 when trying to source CF_ACCOUNT_ID. Workaround: used known CF_ZONE_ID from dev config directly.
2. **hcloud CLI not configured** — could not programmatically retrieve Hetzner token. Minor impact.
3. **Accidentally deleted tracked .terraform.lock.hcl** — restored via `git checkout`. Lesson: check `git status` before bulk-deleting in infra directories.
4. **Pre-existing terraform fmt issue** — fixed opportunistically in telegram-bridge server.tf.

## References

- [Doppler setup patterns](2026-03-20-doppler-secrets-manager-setup-patterns.md) — predecessor learning
- [Terraform best practices](../project/learnings/2026-02-13-terraform-best-practices-research.md) — variable naming conventions
- [Cloudflare TF v4/v5 names](2026-03-20-cloudflare-terraform-v4-v5-resource-names.md) — related naming issue
- Issue #969, PR #964 (deferred from)

## Tags

category: integration-issues
module: web-platform
