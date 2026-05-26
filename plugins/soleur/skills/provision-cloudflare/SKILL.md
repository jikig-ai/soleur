---
name: provision-cloudflare
description: "This skill should be used when provisioning scoped Cloudflare API tokens for tenant deploys."
---

# Provision Cloudflare

Create a scoped Cloudflare API token via Terraform `cloudflare_api_token` with least-privilege permissions for a tenant's deploy pipeline.

## Art. 32 Pre-condition

**MUST run on the operator's local machine. MUST NOT run in CI.** Bootstrap credentials are accepted via `read -s` (interactive terminal only) and never persisted to disk, env exports, or CLI args.

## Usage

```
soleur:provision-cloudflare <tenant-slug> <cf-zone-id> <cf-account-id> [--dry-run]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `tenant-slug` | Yes | Canonical tenant identifier (kebab-case) |
| `cf-zone-id` | Yes | Cloudflare zone ID for the tenant's domain |
| `cf-account-id` | Yes | Cloudflare account ID |
| `--dry-run` | No | Print TF plan + smoke-test commands without executing |

## Execution

```bash
bash plugins/soleur/skills/provision-cloudflare/scripts/provision-cloudflare.sh <slug> <zone-id> <account-id> [--dry-run]
```

The script:
1. Validates prerequisites (DPA gate, format validation, tool availability)
2. Checks idempotency (warns if `cloudflare.tf` already exists)
3. Generates `provisioning/<slug>/cloudflare.tf` with 4 permission groups + sensitive output
4. Emits a copy-pasteable `terraform apply` compound command with credential re-entry
5. After operator confirms TF apply, runs token extraction + smoke-test pipeline
6. Prints teardown commands and bootstrap revocation reminder

## Sharp Edges

- R2 backend has no state locking. Single operator at N=2.
- Token extraction uses `terraform output -raw` piped to a subshell to avoid terminal scrollback exposure.
- CF provider pinned at `~> 4.0`; upgrade when Soleur's main root upgrades.
- Does NOT grant `User Details:Read` or `Account Settings:Read` (least-privilege).
