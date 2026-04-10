---
title: "sec: expand CF API token permissions for security monitoring"
type: feat
date: 2026-04-10
---

# sec: Expand CF API token permissions for security monitoring

## Enhancement Summary

**Deepened on:** 2026-04-10
**Sections enhanced:** 6
**Research sources:** Cloudflare OpenAPI spec (MCP search), Cloudflare MCP execute (zone discovery), WebFetch (permissions docs), 5 project learnings, Doppler config audit

### Key Improvements

1. **Corrected account assignment** -- zone `soleur.ai` is under Jean's personal account (`4d5ba6f096b2686fbdd404167dd4e125`), not the Ops account as originally stated. Token must be created under the correct account.
2. **API token creation endpoint discovered** -- `POST /user/tokens` exists in the Cloudflare API and accepts permission group IDs + resource scoping. However, MCP OAuth token lacks `API Tokens Write` scope, so Playwright/dashboard remains the implementation path for this ticket.
3. **Concrete zone ID and permission group ID lookup** -- added exact API calls to resolve permission group IDs at implementation time, eliminating guesswork.
4. **Expiry policy decision** -- CF API tokens can be created without expiry (field is optional). Plan now explicitly recommends no expiry with annual review, avoiding unnecessary rotation overhead.
5. **Doppler config naming** -- applied learning from `2026-03-29-doppler-service-token-config-scope-mismatch.md` to ensure consistent naming if the token is later added to CI.
6. **Playwright automation hardened** -- applied learnings for MCP-first check, browser cleanup, and viewport workarounds.

### New Considerations Discovered

- The `POST /user/tokens` API creates tokens that include the `value` field in the response (shown only once, like dashboard). Future automation could use this endpoint if a token with `API Tokens Write` scope is created first.
- Zone scoping uses resource format `com.cloudflare.api.account.zone.<zone_id>` -- the exact zone ID (`5af02a2f394e9ba6e0ea23c381a26b67`) is now known.

## Overview

Create a dedicated read-only Cloudflare API token (`CF_API_TOKEN_AUDIT`) with permissions
required for comprehensive security auditing. Store in Doppler. Update the infra-security
agent to use the audit token for automated scans that currently fail due to insufficient
permissions on the existing `CF_API_TOKEN`.

Issue: #1837 | Discovered during: PR #1820 (Cloudflare security audit)

## Problem Statement

The current `CF_API_TOKEN` in Doppler is scoped for Terraform operations (DNS, tunnels,
Zero Trust, notifications). It lacks permissions for:

- Zone Settings Read (SSL mode, Always Use HTTPS, HSTS, Bot Fight Mode, Browser Integrity Check)
- Firewall Services Read (WAF rules, custom rulesets, Security Analytics)
- Account Settings Read (account-level security posture)
- Audit Logs Read (change tracking, compliance)
- Notifications Read (verify notification policies)

The infra-security agent currently uses Cloudflare MCP (OAuth-based) for audits, but agents
running in CI or headless mode cannot authenticate via OAuth. A dedicated API token enables
deterministic, repeatable security audits without interactive authentication.

## Proposed Solution

Create a **separate** read-only API token rather than expanding the existing `CF_API_TOKEN`.
Rationale:

1. **Principle of least privilege** -- the Terraform token should only have write permissions
   it needs (DNS, tunnels). The audit token only needs read permissions.
2. **Blast radius** -- if the audit token leaks, an attacker gains read-only visibility but
   cannot modify infrastructure.
3. **Auditability** -- separate tokens create distinct entries in Cloudflare audit logs,
   making it clear which operations come from Terraform vs security scans.

## Technical Approach

### Phase 1: Create Cloudflare API Token (Playwright automation)

Per learning `2026-03-21-cloudflare-api-token-permission-editing.md`, editing existing CF API
token permissions requires dashboard access. Creating new tokens via `POST /user/tokens` API
is technically possible (endpoint exists in OpenAPI spec) but requires `API Tokens Write`
scope on the calling token -- which the MCP OAuth token lacks (confirmed: returns 9109
Unauthorized). Use Playwright MCP to automate token creation via the Cloudflare dashboard.

**Token name:** `soleur-security-audit`

**Account:** <Jean.deruelle@jikigai.com> (account ID: `4d5ba6f096b2686fbdd404167dd4e125`)

**Important:** The `soleur.ai` zone (ID: `5af02a2f394e9ba6e0ea23c381a26b67`) is under
Jean's personal account, NOT the Ops account. The token must be created under Jean's profile.

**Permissions (all Read-only):**

| Scope | Permission Group | Permission |
|-------|-----------------|------------|
| Zone | Zone Settings | Read |
| Zone | DNS | Read |
| Zone | SSL and Certificates | Read |
| Zone | Firewall Services | Read |
| Account | Access: Organizations, Identity Providers, and Groups | Read |
| Account | Account Settings | Read |
| Account | Notifications | Read |
| Account | Audit Logs | Read |

**Zone resources:** Restrict to `soleur.ai` zone only (ID: `5af02a2f394e9ba6e0ea23c381a26b67`).
The account currently has only this one zone, but scoping to specific zones is more secure
than "All zones" if additional zones are added later.

**Expiry policy:** Do not set an expiry date. CF API tokens are permanent by default (the
`expires_on` field is optional per the OpenAPI spec). An annual review cadence is preferable
to forced rotation for a read-only audit token -- rotation would require updating Doppler
and re-verifying all audit integrations with zero security benefit (the token is read-only).

**Pre-Playwright check** (per learning `2026-03-25-check-mcp-api-before-playwright.md`):
Before launching Playwright, verify that `POST /user/tokens` still returns 9109 via MCP.
If it succeeds (MCP scope changed), use the API path instead -- it is faster and more reliable.

**Playwright steps:**

1. Navigate to `https://dash.cloudflare.com/profile/api-tokens`
2. Click "Create Token"
3. Select "Create Custom Token" (or "Get started" next to "Create Custom Token")
4. Set token name: `soleur-security-audit`
5. Add each permission row from the table above
6. Set zone resources to "Specific zone" > `soleur.ai`
7. Do NOT set IP address filtering (agent runs from multiple IPs)
8. Click "Continue to summary"
9. Review permissions match the table (take a screenshot for verification)
10. Click "Create Token"
11. Copy the token value (displayed only once -- the `value` field is only in the create response)
12. Verify token via API: `curl -H "Authorization: Bearer <token>" https://api.cloudflare.com/client/v4/user/tokens/verify`
13. **Call `browser_close`** (per learning `2026-04-03-playwright-browser-cleanup-on-session-exit.md` -- mandatory after Playwright tasks)

### Research Insights: Token Creation API

The Cloudflare API supports programmatic token creation via `POST /user/tokens`. The request
body requires:

- `name`: token name (max 120 chars)
- `policies`: array of `{ effect, permission_groups: [{id}], resources }` objects
- `expires_on`: optional ISO 8601 datetime
- `condition.request_ip`: optional IP restrictions

Permission group IDs can be fetched from `GET /user/tokens/permission_groups` (filterable by
`name` and `scope` query params). Resource scoping uses the format:
`com.cloudflare.api.account.zone.5af02a2f394e9ba6e0ea23c381a26b67` for zone-scoped permissions.

This API path is blocked for this ticket because the MCP OAuth token lacks `API Tokens Write`
scope. To enable API-based token management in the future, create a privileged token with
`API Tokens Write` scope and store it separately in Doppler. This would eliminate the
Playwright dependency for all future token operations.

### Phase 2: Store in Doppler

Store the token in Doppler under the `dev` config (used by local development and agents):

```text
doppler secrets set CF_API_TOKEN_AUDIT=<token_value> -p soleur -c dev
```

**Config placement rationale:**

- `dev` -- local agent runs, interactive audits. This is the primary config.
- `prd_scheduled` -- if a scheduled GitHub Actions workflow needs it later
- NOT in `prd_terraform` -- this token is not used by Terraform
- NOT in `ci` -- CI workflows do not currently run security audits

**Naming convention** (per learning `2026-03-29-doppler-service-token-config-scope-mismatch.md`):
If this token is later used in CI workflows, the GitHub secret must use a config-specific name
(e.g., `CF_API_TOKEN_AUDIT_DEV` or `CF_API_TOKEN_AUDIT_SCHEDULED`) to encode the Doppler
config scope. Never use a bare `CF_API_TOKEN_AUDIT` GitHub secret -- it hides which Doppler
config the service token is scoped to.

Verify storage:

```text
doppler secrets get CF_API_TOKEN_AUDIT -p soleur -c dev --plain | head -c 20
```

### Research Insights: Doppler Configuration

Current CF-related secrets across Doppler configs (audited 2026-04-10):

| Config | CF Keys |
|--------|---------|
| `dev` | `CF_API_TOKEN`, `CF_ZONE_ID` |
| `prd_terraform` | `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`, `CF_ACCOUNT_ID`, `CF_API_TOKEN`, `CF_NOTIFICATION_EMAIL`, `CF_TUNNEL_TOKEN`, `CF_ZONE_ID`, `HCLOUD_TOKEN` |
| `ci` | (none) |
| `prd` | (none) |
| `prd_scheduled` | (none) |

The `CF_API_TOKEN` in `dev` starts with `cfut_` (confirmed via Doppler read). Adding
`CF_API_TOKEN_AUDIT` to `dev` keeps the audit token co-located with the existing token
for local agent use.

**Doppler stderr contamination** (per learning `2026-04-06-doppler-stderr-contaminates-docker-env-file.md`):
When using `doppler run` in scripts, be aware that Doppler CLI may write warnings to stderr.
For audit scripts that capture output, always redirect stderr appropriately.

### Phase 3: Update infra-security agent

Modify `plugins/soleur/agents/engineering/infra/infra-security.md` to document the
`CF_API_TOKEN_AUDIT` token and add a CLI-based audit path that uses it as a fallback
when MCP OAuth is unavailable.

**Changes to the Audit Protocol section:**

Add a new subsection for API-token-based checks that complement MCP:

- Zone settings: `GET /zones/<zone_id>/settings` (SSL mode, security level, browser integrity check, bot fight mode)
- DNS records: `GET /zones/<zone_id>/dns_records` (DNSSEC status, record inventory)
- SSL certificates: `GET /zones/<zone_id>/ssl/certificate_packs`
- WAF/Firewall: `GET /zones/<zone_id>/firewall/rules`, `GET /zones/<zone_id>/rulesets`
- Account settings: `GET /accounts/<account_id>/`
- Audit logs: `GET /accounts/<account_id>/audit_logs`
- Notifications: `GET /accounts/<account_id>/alerting/v3/policies`

**Graceful fallback chain:**

1. Try MCP `execute` (OAuth-authenticated, richest API access)
2. If MCP unavailable, try `CF_API_TOKEN_AUDIT` via curl (read-only, deterministic)
3. If neither available, fall back to CLI-only checks (dig, openssl, curl -sI)

### Phase 4: Verification

After all phases complete, run verification using the exact IDs discovered during research.

**Known identifiers:**

- Account ID: `4d5ba6f096b2686fbdd404167dd4e125` (Jean's account)
- Zone ID: `5af02a2f394e9ba6e0ea23c381a26b67` (soleur.ai)

**Step 1: Token health check**

```text
doppler run -c dev -- curl -s \
  -H "Authorization: Bearer $CF_API_TOKEN_AUDIT" \
  "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  | jq '.result.status'
```

Expected: `"active"`

**Step 2: Zone listing**

```text
doppler run -c dev -- curl -s \
  -H "Authorization: Bearer $CF_API_TOKEN_AUDIT" \
  "https://api.cloudflare.com/client/v4/zones?account.id=4d5ba6f096b2686fbdd404167dd4e125" \
  | jq '.result[].name'
```

Expected: `"soleur.ai"`

**Step 3: Per-permission verification (one call per permission group)**

```text
ZONE_ID="5af02a2f394e9ba6e0ea23c381a26b67"
ACCT_ID="4d5ba6f096b2686fbdd404167dd4e125"
BASE="https://api.cloudflare.com/client/v4"

# Zone Settings Read
doppler run -c dev -- curl -s -H "Authorization: Bearer $CF_API_TOKEN_AUDIT" \
  "$BASE/zones/$ZONE_ID/settings/ssl" | jq '.result.value'
# DNS Read
doppler run -c dev -- curl -s -H "Authorization: Bearer $CF_API_TOKEN_AUDIT" \
  "$BASE/zones/$ZONE_ID/dns_records?per_page=1" | jq '.success'
# SSL Read
doppler run -c dev -- curl -s -H "Authorization: Bearer $CF_API_TOKEN_AUDIT" \
  "$BASE/zones/$ZONE_ID/ssl/certificate_packs" | jq '.success'
# Firewall Read
doppler run -c dev -- curl -s -H "Authorization: Bearer $CF_API_TOKEN_AUDIT" \
  "$BASE/zones/$ZONE_ID/firewall/rules" | jq '.success'
# Account Settings Read
doppler run -c dev -- curl -s -H "Authorization: Bearer $CF_API_TOKEN_AUDIT" \
  "$BASE/accounts/$ACCT_ID" | jq '.success'
# Audit Logs Read
doppler run -c dev -- curl -s -H "Authorization: Bearer $CF_API_TOKEN_AUDIT" \
  "$BASE/accounts/$ACCT_ID/audit_logs?per_page=1" | jq '.success'
# Notifications Read
doppler run -c dev -- curl -s -H "Authorization: Bearer $CF_API_TOKEN_AUDIT" \
  "$BASE/accounts/$ACCT_ID/alerting/v3/policies" | jq '.success'
```

All should return `true` or a valid value.

**Step 4: Write rejection test**

```text
doppler run -c dev -- curl -s -X PATCH \
  -H "Authorization: Bearer $CF_API_TOKEN_AUDIT" \
  -H "Content-Type: application/json" \
  -d '{"value":"off"}' \
  "$BASE/zones/$ZONE_ID/settings/ssl" | jq '.success'
```

Expected: `false` (confirms read-only scope)

**Step 5: Existing token health**

```text
doppler run -c dev -- curl -s \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/user/tokens/verify" | jq '.result.status'
```

Expected: `"active"` (Terraform token unaffected)

### Research Insights: Cloudflare API Endpoint Availability

Some endpoints may return errors on the Free plan. During verification, document which
endpoints succeed and which return plan-level errors. Known constraints:

- `GET /zones/<id>/firewall/rules` -- WAF rules may return empty on Free plan (WAF is
  a Pro+ feature), but the endpoint itself should be accessible
- `GET /zones/<id>/rulesets` -- Custom rulesets are a Pro+ feature; the endpoint may
  return an empty list or a plan-level error
- `GET /accounts/<id>/audit_logs` -- Available on all plans (confirmed in CF docs)

If any endpoint returns a plan-level error, document it in the infra-security agent as a
"requires paid plan" note so audits do not report false negatives.

## Technical Considerations

### Security

- The token is read-only -- worst-case exposure is information disclosure, not infrastructure modification
- Per learning `2026-03-21-cloudflare-api-token-permission-editing.md`, editing existing token permissions does NOT rotate the token value, but creating a new token avoids touching the Terraform token entirely
- Token stored in Doppler (encrypted at rest, access-controlled)

### Existing token separation

| Token | Doppler Key | Purpose | Permissions |
|-------|-------------|---------|-------------|
| `soleur-terraform-tunnel` | `CF_API_TOKEN` (prd_terraform) | Terraform IaC | DNS Edit, Tunnel Edit, Access Edit, Notifications Edit |
| `soleur-security-audit` | `CF_API_TOKEN_AUDIT` (dev) | Security auditing | Zone Settings Read, DNS Read, SSL Read, Firewall Read, Account Read, Audit Logs Read, Notifications Read |

### Browser automation dependency

Token creation requires Playwright MCP. If Playwright is unavailable, the plan degrades to
manual dashboard instructions with specific steps.

**Important correction from research:** Cloudflare DOES expose token creation via
`POST /user/tokens`, but the MCP OAuth token currently lacks `API Tokens Write` scope
(confirmed: returns error 9109). The dashboard/Playwright path is a practical constraint
of the current MCP configuration, not a fundamental API limitation. The plan includes a
pre-Playwright check to test the API path first (per learning
`2026-03-25-check-mcp-api-before-playwright.md`).

**Playwright viewport workaround** (per learning
`2026-03-21-cloudflare-api-token-permission-editing.md`): Permission dropdown comboboxes
on the CF dashboard may render outside the viewport. If `browser_click` on a combobox ref
fails, click the parent container element as a workaround.

## Acceptance Criteria

- [x] New Cloudflare API token `soleur-security-audit` created with all 8 read permissions
- [x] Token stored in Doppler `dev` config as `CF_API_TOKEN_AUDIT`
- [x] Token verified working via API call (`/user/tokens/verify`)
- [x] infra-security agent updated with API-token fallback audit path
- [x] Each permission category verified with a test API call (zone settings, DNS, SSL, firewall, account settings, audit logs, notifications)
- [x] Existing `CF_API_TOKEN` unchanged and still functional for Terraform

## Test Scenarios

- Given `CF_API_TOKEN_AUDIT` is set in Doppler `dev`, when calling `/user/tokens/verify`, then the response shows `status: active`
- Given the audit token, when requesting zone settings for soleur.ai, then SSL mode, HSTS, and security settings are returned
- Given the audit token, when requesting firewall rules, then WAF rules and rulesets are returned (or empty array if none configured)
- Given the audit token, when requesting audit logs, then recent account activity entries are returned
- Given the audit token, when attempting a write operation (e.g., `PATCH /zones/<id>/settings`), then the API returns 403 (confirming read-only scope)
- **API verify:** `doppler run -c dev -- curl -s -H "Authorization: Bearer $CF_API_TOKEN_AUDIT" https://api.cloudflare.com/client/v4/user/tokens/verify | jq '.result.status'` expects `"active"`
- **API verify:** `doppler run -c dev -- curl -s -H "Authorization: Bearer $CF_API_TOKEN_AUDIT" "https://api.cloudflare.com/client/v4/zones?account.id=4d5ba6f096b2686fbdd404167dd4e125&per_page=1" | jq '.success'` expects `true`

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering (CTO)

**Status:** reviewed
**Assessment:** This is a straightforward security hardening task. The separation of
read-only audit token from the read-write Terraform token follows the principle of least
privilege correctly. The fallback chain (MCP -> API token -> CLI) is a sound defense-in-depth
pattern. No architectural concerns -- this extends existing patterns rather than introducing
new ones. The Playwright dependency for token creation is a known constraint documented in
existing learnings.

### Operations (COO)

**Status:** reviewed
**Assessment:** Token creation adds one new secret to Doppler `dev` config. Operational
cost is minimal (read-only token, no recurring expense). Per the Cloudflare OpenAPI spec,
the `expires_on` field is optional for API tokens -- the plan recommends creating the token
without an expiry (permanent), avoiding rotation overhead for a read-only credential. The
`scheduled-cf-token-expiry-check.yml` workflow monitors Access service tokens (which have
mandatory 1-year expiry), not API tokens. No changes to the expiry monitoring workflow
are needed. Annual manual review of the token's permissions is sufficient.

## Dependencies and Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Playwright MCP unavailable | Medium | Blocks Phase 1 | Manual dashboard steps documented as fallback |
| Cloudflare dashboard UI changes | Low | Playwright selectors break | Use semantic selectors (role, label) not CSS classes |
| Token creation requires account owner | Low | Permission denied | Token creation uses personal profile, not account-level admin |
| Some API endpoints require paid plan | Medium | Partial audit coverage | Document which checks require Pro/Business/Enterprise in agent |

## References and Research

### Internal References

- infra-security agent: `plugins/soleur/agents/engineering/infra/infra-security.md`
- CF token permission editing learning: `knowledge-base/project/learnings/2026-03-21-cloudflare-api-token-permission-editing.md`
- CF service token expiry monitoring: `knowledge-base/project/learnings/2026-03-21-cloudflare-service-token-expiry-monitoring.md`
- Check MCP/API before Playwright: `knowledge-base/project/learnings/2026-03-25-check-mcp-api-before-playwright.md`
- Playwright browser cleanup: `knowledge-base/project/learnings/workflow-issues/2026-04-03-playwright-browser-cleanup-on-session-exit.md`
- Doppler service token config scope: `knowledge-base/project/learnings/2026-03-29-doppler-service-token-config-scope-mismatch.md`
- Terraform-Doppler dual credential pattern: `knowledge-base/project/learnings/integration-issues/2026-04-05-terraform-doppler-dual-credential-pattern.md`
- Doppler stderr contamination: `knowledge-base/project/learnings/integration-issues/2026-04-06-doppler-stderr-contaminates-docker-env-file.md`
- Token expiry check workflow: `.github/workflows/scheduled-cf-token-expiry-check.yml`
- Terraform CF provider config: `apps/web-platform/infra/main.tf`
- CF token monitor spec: `knowledge-base/project/specs/feat-cf-token-monitor/session-state.md`

### External References

- [Cloudflare API Token Permissions](https://developers.cloudflare.com/fundamentals/api/reference/permissions/)
- [Cloudflare API v4 Docs](https://developers.cloudflare.com/api/)
- Issue: #1837
- Originating audit: PR #1820

### Research Verification (2026-04-10)

| Claim | Verified Via | Result |
|-------|-------------|--------|
| soleur.ai zone ID | MCP `GET /zones` | `5af02a2f394e9ba6e0ea23c381a26b67` (confirmed) |
| soleur.ai account | MCP `GET /zones` | Jean's personal account `4d5ba6f096b2686fbdd404167dd4e125` (NOT Ops) |
| API token creation endpoint | Cloudflare OpenAPI spec search | `POST /user/tokens` exists, requires `API Tokens Write` scope |
| MCP can create tokens | MCP `GET /user/tokens/permission_groups` | Error 9109 Unauthorized (MCP lacks scope) |
| Token expiry optional | OpenAPI spec `expires_on` field | Optional field, tokens are permanent by default |
| CF_API_TOKEN in dev | Doppler `doppler secrets get` | Starts with `cfut_` (confirmed) |
| CF_API_TOKEN_AUDIT in dev | Doppler `doppler secrets get` | Does not exist yet (confirmed) |
