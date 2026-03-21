---
title: "fix: add Notifications:Edit permission to CF API token for service token expiry alert"
type: fix
date: 2026-03-21
---

# fix: Add Notifications:Edit Permission to CF API Token

## Overview

The `cloudflare_notification_policy.service_token_expiry` resource (added in #983, defined at `apps/web-platform/infra/tunnel.tf:75`) fails to create because the `soleur-terraform-tunnel` Cloudflare API token lacks the `Account > Notifications > Edit` permission.

```
Error: error creating policy Deploy service token expiring: Authentication error (10000)
```

The `CF_NOTIFICATION_EMAIL` Doppler secret has already been added (`ops@jikigai.com`). Only the token permission is missing.

Closes #992.

## Acceptance Criteria

- [ ] The `soleur-terraform-tunnel` CF API token has `Account > Notifications > Edit` permission
- [ ] `terraform apply` succeeds and creates the `cloudflare_notification_policy.service_token_expiry` resource
- [ ] The `cf_api_token` variable description in `variables.tf` is updated to reflect the expanded permission set
- [ ] No existing resources are affected (plan shows only the notification policy as a new addition)

## Test Scenarios

- Given the updated token, when `terraform plan` runs, then the only change is `cloudflare_notification_policy.service_token_expiry` creation (no drift on existing resources)
- Given the notification policy is created, when `terraform apply` completes, then exit code is 0 and the resource appears in state

## Proposed Solution

### Phase 1: Add permission via Cloudflare dashboard (Playwright-automated)

The CF API token cannot update its own permissions (no "API Tokens Write" scope). The Cloudflare dashboard has an active browser session that Playwright can use.

**Steps:**

1. Navigate to the `soleur-terraform-tunnel` token edit page via the Cloudflare dashboard
2. Add `Account > Notifications > Edit` permission
3. Save the token (no value rotation -- editing permissions preserves the existing token value)

**Target token:** `soleur-terraform-tunnel` (row in the API Tokens table at `dash.cloudflare.com/profile/api-tokens`)
**Current permissions:** `Account.Cloudflare Tunnel`, `Account.Access: Service Tokens`, `Account.Access: Apps and Policies`, `Zone.DNS`
**New permission to add:** `Account.Notifications` (Edit)

### Phase 2: Update variable description

Update the `cf_api_token` variable description in `apps/web-platform/infra/variables.tf:56-60` to reflect the full permission set:

```hcl
variable "cf_api_token" {
  description = "Cloudflare API token (Tunnel, Access, DNS, Notifications permissions)"
  type        = string
  sensitive   = true
}
```

### Phase 3: Run terraform apply

```bash
cd apps/web-platform/infra
doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform init && \
doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform apply -auto-approve
```

Verify that:

- Only the `cloudflare_notification_policy.service_token_expiry` resource is created
- No existing resources show drift or changes
- Exit code is 0

### Phase 4: Commit and PR

Commit the `variables.tf` description update. No Terraform code changes are needed -- the `tunnel.tf` resource definition is already correct.

## Context

- **Token ID:** `62702ea295b7c0a0f6cbaf532ef7dab5` (from API verify endpoint)
- **Token name in dashboard:** `soleur-terraform-tunnel`
- **Resource file:** `apps/web-platform/infra/tunnel.tf:75`
- **Variables file:** `apps/web-platform/infra/variables.tf:56-60`
- **Doppler project/config:** `soleur` / `prd_terraform`
- **Related issues:** #983 (added the notification policy), #987, #988 (discovered during investigation)

## References

- GitHub issue: [#992](https://github.com/jikig-ai/soleur/issues/992)
- Cloudflare API token permissions: [dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens)
- Terraform resource: [`cloudflare_notification_policy`](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/notification_policy)
