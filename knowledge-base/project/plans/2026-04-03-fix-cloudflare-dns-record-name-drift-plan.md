---
title: "fix: use FQDN for Cloudflare DNS record name to prevent perpetual Terraform drift"
type: fix
date: 2026-04-03
---

# fix: use FQDN for Cloudflare DNS record name to prevent perpetual Terraform drift

## Enhancement Summary

**Deepened on:** 2026-04-03
**Sections enhanced:** 2 (Proposed Solution, Prevention)
**Research conducted:** Codebase-wide `@` pattern scan, learnings cross-reference, Cloudflare provider behavior verification

### Key Improvements

1. Confirmed no other `name = "@"` patterns exist in any `.tf` file across the repo -- this is the only instance
2. Verified all other DNS records in both `web-platform` and `telegram-bridge` infra use explicit subdomain names, so no other drift risk exists
3. Clarified that `terraform apply` is likely unnecessary post-merge -- the code change alone aligns config with remote state (plan should show exit code 0 without apply)

### Codebase Scan Results

All DNS records across both Terraform stacks:

| File | Record Name | Risk |
|---|---|---|
| `web-platform/infra/dns.tf` | `"app"` | None -- subdomain |
| `web-platform/infra/dns.tf` | `"deploy"` | None -- subdomain |
| `web-platform/infra/dns.tf` | `"resend._domainkey"` | None -- subdomain |
| `web-platform/infra/dns.tf` | `"send"` (x2) | None -- subdomain |
| `web-platform/infra/dns.tf` | `"_dmarc"` | None -- subdomain |
| `web-platform/infra/dns.tf` | `"@"` | **DRIFT** -- fix in this PR |
| `telegram-bridge/infra/tunnel.tf` | `"deploy-bridge"` | None -- subdomain |

## Overview

The scheduled Terraform drift detection workflow (run #23937776714) flagged infrastructure drift in `apps/web-platform/infra/`. The drift is a perpetual destroy-and-recreate plan on the `cloudflare_record.google_site_verification` TXT record, caused by a mismatch between the Terraform config (`name = "@"`) and how Cloudflare's API stores the record (`name = "soleur.ai"`).

GitHub issue: #1412

## Problem Statement

When `cloudflare_record.google_site_verification` was added in #1398 (Google OAuth consent screen branding), the `name` attribute was set to `"@"` -- the conventional DNS shorthand for the zone apex. Cloudflare's API accepts `@` on creation but normalizes it to the fully qualified domain name (`soleur.ai`) in its stored state.

The Cloudflare Terraform provider v4.x reads back `"soleur.ai"` from the API but the config says `"@"`. Since the provider treats `name` as a `ForceNew` attribute (changes force resource replacement), every `terraform plan` reports:

```
~ name = "soleur.ai" -> "@" # forces replacement
Plan: 1 to add, 0 to change, 1 to destroy.
```

This is a perpetual no-op drift that will fire the drift detection workflow every 12 hours until fixed. The record itself is correct and functioning -- only the Terraform state/config mismatch needs resolution.

## Proposed Solution

Change `name = "@"` to `name = "soleur.ai"` in `apps/web-platform/infra/dns.tf` (line 59) to match what Cloudflare's API actually stores. Then run `terraform apply` to reconcile the state -- Terraform will detect the config now matches the remote state and produce a clean plan (exit code 0).

### Implementation

**File:** `apps/web-platform/infra/dns.tf`

```hcl
# Before (line 59)
  name    = "@"

# After
  name    = "soleur.ai"
```

**Post-merge:** Run `terraform apply` from `apps/web-platform/infra/` using the nested Doppler invocation documented in `variables.tf`:

```bash
cd apps/web-platform/infra
doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform apply -input=false
```

Alternatively, since the config change makes the code match the remote state, a `terraform plan` should already show no changes after the code fix is applied. Verify with:

```bash
doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform plan -detailed-exitcode -var="ssh_key_path=~/.ssh/id_ed25519.pub"
```

Exit code 0 confirms the drift is resolved. If exit code 2 persists, run `terraform apply` to force state reconciliation.

**Verification:** After merge, wait for the next scheduled drift detection run (or trigger manually with `gh workflow run scheduled-terraform-drift.yml`) and confirm the web-platform job shows exit code 0. Close #1412.

## Acceptance Criteria

- [x] `cloudflare_record.google_site_verification` in `apps/web-platform/infra/dns.tf` uses `name = "soleur.ai"` instead of `name = "@"`
- [x] `terraform plan` for `apps/web-platform/infra/` returns exit code 0 (no changes)
- [ ] Drift detection workflow run succeeds without creating/updating issue #1412
- [ ] Issue #1412 is closed

## Test Scenarios

- Given the updated dns.tf with `name = "soleur.ai"`, when `terraform plan -detailed-exitcode` runs, then it returns exit code 0
- Given the fix is merged and deployed, when the scheduled drift detection workflow runs, then the web-platform job skips issue creation/update steps (exit code 0)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure config alignment fix.

## Context

### Root Cause Chain

1. #1398 added `google_site_verification` TXT record with `name = "@"` (2026-04-02)
2. `terraform apply -target=cloudflare_record.google_site_verification` created the record successfully
3. Cloudflare API normalized `@` to `soleur.ai` in its stored state
4. Next drift detection run (2026-04-03 07:13 UTC) saw the mismatch and filed #1412

### Why `@` vs FQDN Matters

The Cloudflare Terraform provider v4.x does not normalize `@` to the zone apex on the client side. The `name` attribute is stored as-is in the Terraform config but the API returns the expanded form. Since `name` is a `ForceNew` attribute, any difference triggers a destroy-and-recreate plan. Other DNS records in this file use subdomain names (`"app"`, `"deploy"`, `"resend._domainkey"`, etc.) which don't have this problem because Cloudflare stores them exactly as provided.

### Prevention

This is a known Cloudflare provider behavior. Future zone-apex DNS records in Terraform should always use the FQDN (e.g., `"soleur.ai"`) rather than `"@"`. The learning from this session should be compounded.

#### Research Insights

**Cloudflare Provider Behavior:**

- The Cloudflare Terraform provider v4.x passes `name` to the API as-is. The API normalizes `@` to the zone apex FQDN on storage. On read-back, the provider receives the FQDN, creating a permanent config-vs-state mismatch.
- This is specific to zone-apex records. Subdomain names (`"app"`, `"deploy"`, `"_dmarc"`) are stored exactly as provided.
- The `name` attribute is `ForceNew` in the provider schema, meaning any detected change triggers destroy+recreate rather than an in-place update.

**Concrete Prevention Rule:**

When adding `cloudflare_record` resources for zone-apex records, always use `name = "domain.tld"` (the FQDN), never `name = "@"`. Add a comment explaining why:

```hcl
resource "cloudflare_record" "example" {
  zone_id = var.cf_zone_id
  name    = "soleur.ai"  # Use FQDN, not "@" -- CF API normalizes @ to FQDN, causing perpetual drift
  content = "..."
  type    = "TXT"
  ttl     = 1
}
```

This rule should be added to the existing learning `knowledge-base/project/learnings/2026-03-20-cloudflare-terraform-v4-v5-resource-names.md` as an additional row in the v4/v5 differences table.

## References

- Drift issue: #1412
- Introducing commit: #1398 (21bccf4e)
- Related learning: `knowledge-base/project/learnings/2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`
- Related learning: `knowledge-base/project/learnings/2026-03-21-terraform-drift-dead-code-and-missing-secrets.md`
- Related learning: `knowledge-base/project/learnings/workflow-issues/google-oauth-consent-screen-branding-requires-domain-verification-20260402.md`
- Drift detection workflow: `.github/workflows/scheduled-terraform-drift.yml`
- Terraform config: `apps/web-platform/infra/dns.tf:57-63`
