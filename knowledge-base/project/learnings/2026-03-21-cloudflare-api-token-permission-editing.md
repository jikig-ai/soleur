---
category: integration-issues
tags: [cloudflare, api-token, playwright, terraform, permissions]
date: 2026-03-21
module: apps/web-platform/infra
problem_type: authentication-error
---

# Learning: Cloudflare API Token Permission Editing via Playwright

## Problem

The `cloudflare_notification_policy.service_token_expiry` resource failed to create with "Authentication error (10000)" because the `soleur-terraform-tunnel` CF API token lacked `Account > Notifications > Edit` permission. The token cannot modify its own permissions via API (no "API Tokens Read/Write" scope).

## Solution

Automated the permission addition via Playwright MCP:

1. Navigate to `https://dash.cloudflare.com/profile/api-tokens`
2. Click three-dot menu on the target token row, select "Edit"
3. Click "Add more" in permissions section
4. Select Account > Notifications > Edit from dropdowns
5. Click "Continue to summary" then "Update token"
6. Verify token still active via API: `curl -H "Authorization: Bearer $TOKEN" https://api.cloudflare.com/client/v4/user/tokens/verify`

**Playwright gotcha:** The permissions level combobox input (`role=combobox`) may be outside the viewport. Clicking the parent container element works as a workaround when `scrollIntoView` doesn't resolve the issue.

## Key Insight

Editing permissions on an existing Cloudflare API token does NOT rotate the token value. The secret stored in Doppler remains valid. This means permission expansion is a safe, non-disruptive operation -- no need to update secrets in Doppler or re-run any dependent infrastructure.

The CF API token cannot modify its own permissions (requires "API Tokens Read/Write" scope, which would be a security anti-pattern to grant). Dashboard automation via Playwright is the correct automated path.

## Session Errors

1. Markdown lint (MD032/MD022): blank lines required around headings and before lists in markdown files
2. kb-structure-guard: knowledge-base artifacts must go under `knowledge-base/project/` not `knowledge-base/` directly
3. Playwright viewport: combobox inputs positioned offscreen need parent-container click workaround

## Cross-References

- Issue: #992
- Related learnings: `2026-03-21-cloudflare-service-token-expiry-monitoring.md`, `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`
- Playwright workaround pattern: `2026-03-09-x-provisioning-playwright-automation.md`, `2026-03-13-browser-tasks-require-playwright-not-manual-labels.md`

## Tags

category: integration-issues
module: apps/web-platform/infra
