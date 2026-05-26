---
name: provision-doppler
description: "This skill should be used when provisioning Doppler projects and OIDC identities for tenants."
---

# Provision Doppler

Create a Doppler project + config via Terraform and configure an OIDC service-account-identity via the Doppler API for a tenant's deploy pipeline.

## Art. 32 Pre-condition

**MUST run on the operator's local machine. MUST NOT run in CI.** Bootstrap credentials are accepted via `read -s` (interactive terminal only) and never persisted to disk, env exports, or CLI args. The `read -s` call blocks non-interactive shells by design.

## Usage

```
soleur:provision-doppler <tenant-slug> <tenant-org> <tenant-repo> [--dry-run]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `tenant-slug` | Yes | Canonical tenant identifier (kebab-case, e.g. `acme-prd`) |
| `tenant-org` | Yes | GitHub org owning the tenant repo (for OIDC trust binding) |
| `tenant-repo` | Yes | GitHub repo name (for OIDC trust binding) |
| `--dry-run` | No | Print TF plan + API commands without executing |

## Execution

Run the provisioning script:

```bash
bash plugins/soleur/skills/provision-doppler/scripts/provision-doppler.sh <slug> <org> <repo> [--dry-run]
```

The script:
1. Validates prerequisites (DPA gate, slug format, tool availability)
2. Checks idempotency (warns if Doppler project already exists)
3. Generates `provisioning/<slug>/doppler.tf` with R2 remote backend
4. Emits a copy-pasteable `terraform apply` compound command with credential re-entry
5. After operator confirms TF apply, configures OIDC service-account-identity via Doppler API
6. Smoke-tests the service account
7. Prints teardown commands and bootstrap revocation reminder

## Sharp Edges

- R2 backend has no state locking. Single operator at N=2. Coordinate manually if parallel applies ever become possible.
- OIDC trust binding cannot be fully verified locally. Test via deploy workflow (runbook Step 9) after all provisioning.
- The Doppler API for service accounts (`POST /v3/workplace/service_accounts`) has no CLI equivalent and no TF resource.
- Next-step hint points to `provision-cloudflare`, which differs from runbook step order (Step 3 here → Step 2 there).
