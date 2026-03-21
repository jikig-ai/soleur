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

## R2 Backend Credential Conflict

The `--name-transformer tf-var` flag is **destructive, not additive** — it replaces ALL key names. `AWS_ACCESS_KEY_ID` becomes only `TF_VAR_aws_access_key_id`, and the original name disappears. The S3/R2 backend needs plain `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.

**Solution: Nested `doppler run` with explicit `--token`.**

```bash
doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform plan
```

The outer call injects plain env vars (including `AWS_ACCESS_KEY_ID` for the R2 backend). The inner call adds `TF_VAR_*` versions for Terraform variables.

**Why `--token` is required:** The `DOPPLER_TOKEN` secret (a service token stored for server-side injection via cloud-init) collides with the CLI's own auth token. Without `--token`, the inner `doppler run` tries to authenticate with the service token (which only has access to `prd`, not `prd_terraform`) and fails. The `--token` flag bypasses this by explicitly providing the personal CLI token.

**Other approaches tried and rejected:**
- `--only-secrets` with `--name-transformer`: incompatible (Doppler bug — looks up secrets by post-transform name)
- `--preserve-env`: only preserves pre-existing shell vars, doesn't prevent Doppler from renaming its own secrets
- Two-step export: works but requires manual `export` commands; nested invocation is a single line

## Session Errors

1. **Expired CF API token in dev config** — Cloudflare API returned 401 when trying to source CF_ACCOUNT_ID. Workaround: used known CF_ZONE_ID from dev config directly.
2. **hcloud CLI not configured** — could not programmatically retrieve Hetzner token. Minor impact.
3. **Accidentally deleted tracked .terraform.lock.hcl** — restored via `git checkout`. Lesson: check `git status` before bulk-deleting in infra directories.
4. **Pre-existing terraform fmt issue** — fixed opportunistically in telegram-bridge server.tf.
5. **DOPPLER_TOKEN collision in nested invocation** — adding a `DOPPLER_TOKEN` secret to `prd_terraform` caused the inner `doppler run` to fail authentication. The outer call's plain injection overwrites the CLI auth token with the service token. Fix: pass `--token "$(doppler configure get token --plain)"` on the inner call.
6. **Terraform state empty** — could not retrieve existing `admin_ips` value from remote state because no prior `terraform apply` had been run. Used current public IP as fallback. State must be populated before it can be queried.
7. **Terraform init required before state access** — `terraform show` fails if `.terraform/` is not initialized. Always run `terraform init` before state queries in a fresh worktree.

## References

- [Doppler setup patterns](2026-03-20-doppler-secrets-manager-setup-patterns.md) — predecessor learning
- [Terraform best practices](../project/learnings/2026-02-13-terraform-best-practices-research.md) — variable naming conventions
- [Cloudflare TF v4/v5 names](2026-03-20-cloudflare-terraform-v4-v5-resource-names.md) — related naming issue
- [Terraform R2 state migration](2026-03-21-terraform-state-r2-migration.md) — section 4 documents the same `--name-transformer tf-var` conflict; this doc's nested invocation pattern supersedes the manual env var approach
- Issue #969, PR #964 (deferred from)
- Issue #978 (this alignment task)

## Tags

category: integration-issues
module: web-platform, telegram-bridge
