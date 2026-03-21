---
title: "fix: add Notifications:Edit permission to CF API token for service token expiry alert"
type: fix
date: 2026-03-21
deepened: 2026-03-21
---

# fix: Add Notifications:Edit Permission to CF API Token

## Enhancement Summary

**Deepened on:** 2026-03-21
**Sections enhanced:** 4
**Sources used:** 3 institutional learnings, Cloudflare API verification, Playwright dashboard inspection

### Key Improvements

1. Added Playwright automation details with specific element references from live dashboard snapshot
2. Added edge cases around token value preservation and `terraform plan` verification before apply
3. Incorporated institutional learnings from #983/#993 about Doppler nested invocation and exit code semantics
4. Added rollback procedure and verification steps

### Relevant Institutional Learnings

- `2026-03-21-cloudflare-service-token-expiry-monitoring.md` -- Documents the exact resource this fix enables; confirms `expiring_service_token_alert` fires for ALL account tokens (no per-token filter)
- `2026-03-21-terraform-drift-dead-code-and-missing-secrets.md` -- Documents the root cause discovery; exit code 1 from `terraform plan` means "plan broken" not "drift detected"
- `2026-03-21-doppler-tf-var-naming-alignment.md` -- Explains the nested Doppler invocation pattern used in Phase 3

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
- [ ] Token value in Doppler (`CF_API_TOKEN`) remains unchanged (editing permissions does not rotate the token)

## Test Scenarios

- Given the updated token, when `terraform plan` runs, then the only change is `cloudflare_notification_policy.service_token_expiry` creation (no drift on existing resources)
- Given the notification policy is created, when `terraform apply` completes, then exit code is 0 and the resource appears in state
- Given `terraform plan` shows unexpected changes beyond the notification policy, then abort and investigate before applying

### Edge Cases

- **Dashboard permission UI changed:** Cloudflare periodically updates the dashboard layout. If the "Add permission" UI differs from what Playwright expects, fall back to manual browser interaction for just the permission addition step
- **Token value rotation:** Editing permissions on an existing CF API token does NOT rotate the token value. The Doppler `CF_API_TOKEN` secret remains valid. Verify by running `curl -s -H "Authorization: Bearer $CF_API_TOKEN" https://api.cloudflare.com/client/v4/user/tokens/verify` after saving
- **Terraform plan exit codes:** Exit 0 = no changes, Exit 1 = error (plan broken), Exit 2 = drift detected. Only Exit 2 with exactly 1 new resource is acceptable (from learning `2026-03-21-terraform-drift-dead-code-and-missing-secrets.md`)

## Proposed Solution

### Phase 1: Add permission via Cloudflare dashboard (Playwright-automated)

The CF API token cannot update its own permissions (verified: `GET /user/tokens/{id}` returns 9109 "Unauthorized" -- no "API Tokens Read/Write" scope). The Cloudflare dashboard has an active browser session that Playwright can use.

**Verified dashboard state:** Playwright snapshot confirms the `soleur-terraform-tunnel` token is visible in the API Tokens table (row `ref=e136`) with current permissions: `Account.Cloudflare Tunnel, Account.Access: Service Tokens, Account.Access: Apps and Policies, Zone.DNS`.

**Steps:**

1. Click the edit button (three-dot menu, `ref=e146`) on the `soleur-terraform-tunnel` row
2. In the edit view, locate the permissions section
3. Add a new permission row: `Account` > `Notifications` > `Edit`
4. Click "Continue to summary" then "Save"
5. Verify the token now shows `Account.Notifications` in its permissions column

**Rollback:** If the permission addition causes any issue, return to the dashboard and remove the `Notifications` permission. No token rotation occurs during permission edits.

### Phase 2: Verify token still works

After editing permissions in the dashboard, verify the token value was not rotated:

```bash
CF_TOKEN=$(doppler secrets get CF_API_TOKEN --project soleur --config prd_terraform --plain)
curl -s -H "Authorization: Bearer $CF_TOKEN" \
  "https://api.cloudflare.com/client/v4/user/tokens/verify" | python3 -m json.tool
```

Expected: `{"result": {"id": "62702ea295b7c0a0f6cbaf532ef7dab5", "status": "active"}, "success": true}`

### Phase 3: Update variable description

Update the `cf_api_token` variable description in `apps/web-platform/infra/variables.tf:56-60` to reflect the full permission set:

```hcl
variable "cf_api_token" {
  description = "Cloudflare API token (Tunnel, Access, DNS, Notifications permissions)"
  type        = string
  sensitive   = true
}
```

### Phase 4: Run terraform plan then apply

**Run `terraform plan` first** to confirm the change scope before applying:

```bash
cd apps/web-platform/infra
doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform init
```

Then plan:

```bash
doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform plan
```

**Gate:** Only proceed to `terraform apply` if the plan shows exactly 1 new resource (`cloudflare_notification_policy.service_token_expiry`) and 0 changes/destroys on existing resources.

```bash
doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform apply -auto-approve
```

**Why nested Doppler invocation:** The outer `doppler run` injects plain env vars (e.g., `AWS_ACCESS_KEY_ID` for R2 backend). The inner `doppler run` with `--name-transformer tf-var` adds `TF_VAR_*` versions. Without nesting, the R2 backend fails because `--name-transformer` renames ALL keys. See learning `2026-03-21-doppler-tf-var-naming-alignment.md`.

### Phase 5: Commit and PR

Commit the `variables.tf` description update. No Terraform code changes are needed -- the `tunnel.tf` resource definition is already correct.

## Context

- **Token ID:** `62702ea295b7c0a0f6cbaf532ef7dab5` (from API verify endpoint)
- **Token name in dashboard:** `soleur-terraform-tunnel`
- **Dashboard row ref:** `e136` (from Playwright snapshot)
- **Resource file:** `apps/web-platform/infra/tunnel.tf:75`
- **Variables file:** `apps/web-platform/infra/variables.tf:56-60`
- **Doppler project/config:** `soleur` / `prd_terraform`
- **CF provider version:** `~> 4.0` (uses `cloudflare_notification_policy`, valid in v4 and v5)
- **Related issues:** #983 (added the notification policy), #987, #988 (discovered during investigation), #993 (removed dead telegram-bridge code)

## References

- GitHub issue: [#992](https://github.com/jikig-ai/soleur/issues/992)
- Cloudflare API token permissions: [dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens)
- Terraform resource: [`cloudflare_notification_policy`](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/notification_policy)
- Learning: [cloudflare-service-token-expiry-monitoring](../learnings/2026-03-21-cloudflare-service-token-expiry-monitoring.md)
- Learning: [terraform-drift-dead-code-and-missing-secrets](../learnings/2026-03-21-terraform-drift-dead-code-and-missing-secrets.md)
- Learning: [doppler-tf-var-naming-alignment](../learnings/2026-03-21-doppler-tf-var-naming-alignment.md)
