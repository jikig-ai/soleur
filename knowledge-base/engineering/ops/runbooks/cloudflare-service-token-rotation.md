---
category: infrastructure
tags: [cloudflare, service-token, rotation, terraform]
date: 2026-03-21
---

# Cloudflare Access Service Token Rotation

The `github-actions-deploy` service token in `apps/web-platform/infra/tunnel.tf` authenticates GitHub Actions deploys through the Cloudflare Tunnel. It expires after 8760 hours (~1 year). When expired, deploys fail with HTTP 403 from Cloudflare Access.

## Monitoring

Two layers of monitoring are in place:

1. **Terraform notification policy** (`cloudflare_notification_policy.service_token_expiry`) sends an email alert 7 days before expiry. This is the primary alert.
2. **GitHub Actions workflow** (`scheduled-cf-token-expiry-check.yml`) checks the Cloudflare API and creates a GitHub issue when the token is within 30 days of expiry. This is the backup.

## Rotation Procedures

### Option 1: Refresh (extend expiry, no credential change)

Add or update the `duration` attribute on the service token resource:

```hcl
resource "cloudflare_zero_trust_access_service_token" "deploy" {
  account_id = var.cf_account_id
  name       = "github-actions-deploy"
  duration   = "8760h"  # resets expiry from now
}
```

Then apply:

```bash
cd apps/web-platform/infra
doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform apply
```

No secret rotation needed. The `expires_at` output updates automatically.

### Option 2: Rotate credentials (zero-downtime)

Use `client_secret_version` to generate a new secret while keeping the old one valid during a transition window:

```hcl
resource "cloudflare_zero_trust_access_service_token" "deploy" {
  account_id                      = var.cf_account_id
  name                            = "github-actions-deploy"
  client_secret_version           = 2  # increment to trigger rotation
  previous_client_secret_expires_at = "2027-03-22T00:00:00Z"  # 24h grace period
}
```

Then:

```bash
cd apps/web-platform/infra
doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform apply
terraform output -raw access_service_token_client_id | gh secret set CF_ACCESS_CLIENT_ID
terraform output -raw access_service_token_client_secret | gh secret set CF_ACCESS_CLIENT_SECRET
```

The old secret remains valid until `previous_client_secret_expires_at` passes.

### Option 3: Rotate credentials (hard cut)

Replace the entire resource. The old secret stops working immediately.

```bash
cd apps/web-platform/infra
doppler run --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform apply -replace=cloudflare_zero_trust_access_service_token.deploy
terraform output -raw access_service_token_client_id | gh secret set CF_ACCESS_CLIENT_ID
terraform output -raw access_service_token_client_secret | gh secret set CF_ACCESS_CLIENT_SECRET
```

Uses `terraform apply -replace=` instead of deprecated `terraform taint` (deprecated since Terraform 0.15.2).

## Verification

After any rotation method, trigger a test deploy:

```bash
gh workflow run web-platform-release.yml
```

Confirm the deploy step completes with HTTP 200 (not 403).

## Key Details

- **Token name:** `github-actions-deploy`
- **Resource:** `cloudflare_zero_trust_access_service_token.deploy`
- **Location:** `apps/web-platform/infra/tunnel.tf`
- **GitHub secrets:** `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`
- **Default lifetime:** 8760h (~1 year)
- **Created:** 2026-03-21
- **Expected expiry:** ~2027-03-21
- **Parent issue:** #974
- **Originating PR:** #971 / #967
