---
title: "sec: expand CF API token permissions for security monitoring"
type: feat
date: 2026-04-10
---

# sec: Expand CF API token permissions for security monitoring

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

Per learning `2026-03-21-cloudflare-api-token-permission-editing.md`, CF API tokens cannot
be created or modified via the API itself. Use Playwright MCP to automate token creation
via the Cloudflare dashboard.

**Token name:** `soleur-security-audit`

**Account:** <Ops@jikigai.com> (account ID: `1ed2b077487f00f5baf7498af6975d95`)

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

**Zone resources:** Include all zones (or restrict to `soleur.ai` and `jikigai.com` if the
dashboard supports zone filtering for custom tokens).

**Playwright steps:**

1. Navigate to `https://dash.cloudflare.com/profile/api-tokens`
2. Click "Create Token"
3. Select "Create Custom Token"
4. Set token name: `soleur-security-audit`
5. Add each permission row from the table above
6. Set zone resources to all zones in the account
7. Click "Continue to summary"
8. Review permissions match the table
9. Click "Create Token"
10. Copy the token value (displayed only once)
11. Verify token via API: `curl -H "Authorization: Bearer <token>" https://api.cloudflare.com/client/v4/user/tokens/verify`

### Phase 2: Store in Doppler

Store the token in Doppler under the `dev` config (used by local development and agents):

```text
doppler secrets set CF_API_TOKEN_AUDIT=<token_value> -p soleur -c dev
```

**Config placement rationale:**

- `dev` -- local agent runs, interactive audits
- `prd_scheduled` -- if a scheduled GitHub Actions workflow needs it later
- NOT in `prd_terraform` -- this token is not used by Terraform
- NOT in `ci` -- CI workflows do not currently run security audits

Verify storage:

```text
doppler secrets get CF_API_TOKEN_AUDIT -p soleur -c dev --plain | head -c 20
```

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

After all phases complete, run a test audit using the new token:

```text
doppler run -c dev -- curl -s \
  -H "Authorization: Bearer $CF_API_TOKEN_AUDIT" \
  "https://api.cloudflare.com/client/v4/zones?account.id=1ed2b077487f00f5baf7498af6975d95" \
  | jq '.result[].name'
```

Expected: returns zone names (soleur.ai, jikigai.com, etc.)

Then test each permission category:

- Zone settings: `GET /zones/<zone_id>/settings/ssl`
- Firewall: `GET /zones/<zone_id>/firewall/rules`
- Audit logs: `GET /accounts/<account_id>/audit_logs?per_page=1`

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

Token creation requires Playwright MCP. If Playwright is unavailable, the plan degrades to manual dashboard instructions with specific steps. This is one of the genuinely manual steps -- Cloudflare does not expose token creation via its API.

## Acceptance Criteria

- [ ] New Cloudflare API token `soleur-security-audit` created with all 8 read permissions
- [ ] Token stored in Doppler `dev` config as `CF_API_TOKEN_AUDIT`
- [ ] Token verified working via API call (`/user/tokens/verify`)
- [ ] infra-security agent updated with API-token fallback audit path
- [ ] Each permission category verified with a test API call (zone settings, DNS, SSL, firewall, account settings, audit logs, notifications)
- [ ] Existing `CF_API_TOKEN` unchanged and still functional for Terraform

## Test Scenarios

- Given `CF_API_TOKEN_AUDIT` is set in Doppler `dev`, when calling `/user/tokens/verify`, then the response shows `status: active`
- Given the audit token, when requesting zone settings for soleur.ai, then SSL mode, HSTS, and security settings are returned
- Given the audit token, when requesting firewall rules, then WAF rules and rulesets are returned (or empty array if none configured)
- Given the audit token, when requesting audit logs, then recent account activity entries are returned
- Given the audit token, when attempting a write operation (e.g., `PATCH /zones/<id>/settings`), then the API returns 403 (confirming read-only scope)
- **API verify:** `doppler run -c dev -- curl -s -H "Authorization: Bearer $CF_API_TOKEN_AUDIT" https://api.cloudflare.com/client/v4/user/tokens/verify | jq '.result.status'` expects `"active"`
- **API verify:** `doppler run -c dev -- curl -s -H "Authorization: Bearer $CF_API_TOKEN_AUDIT" "https://api.cloudflare.com/client/v4/zones?account.id=1ed2b077487f00f5baf7498af6975d95&per_page=1" | jq '.success'` expects `true`

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
cost is minimal (read-only token, no recurring expense). The token should be added to the
credential expiry monitoring pattern established in #974 if Cloudflare API tokens have
expiry dates. Verify during creation whether the token has an expiry or is permanent.
If it expires, add it to the `scheduled-cf-token-expiry-check.yml` workflow scope.

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
- Token expiry check workflow: `.github/workflows/scheduled-cf-token-expiry-check.yml`
- Terraform CF provider config: `apps/web-platform/infra/main.tf`
- CF token monitor spec: `knowledge-base/project/specs/feat-cf-token-monitor/session-state.md`

### External References

- [Cloudflare API Token Permissions](https://developers.cloudflare.com/fundamentals/api/reference/permissions/)
- [Cloudflare API v4 Docs](https://developers.cloudflare.com/api/)
- Issue: #1837
- Originating audit: PR #1820
