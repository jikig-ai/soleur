---
module: System
date: 2026-04-10
problem_type: integration_issue
component: tooling
symptoms:
  - "Cloudflare MCP Read Only OAuth scope returns 9109 Unauthorized for zone settings"
  - "CF_API_TOKEN from Doppler also lacks zone settings permissions"
  - "Cannot verify SSL mode, WAF, Bot Fight Mode, Security Analytics, or Audit Logs via API"
root_cause: missing_permission
resolution_type: workflow_improvement
severity: medium
tags: [cloudflare, mcp, oauth, api-token, security-audit, permissions]
---

# Troubleshooting: Cloudflare MCP OAuth Read Only Scope Insufficient for Security Audits

## Problem

During a comprehensive Cloudflare security audit of soleur.ai, the MCP OAuth "Read Only" scope and the existing CF_API_TOKEN both lacked permissions to read zone settings, WAF rulesets, DNSSEC configuration, Security Analytics, and Audit Logs. This blocked ~40% of the planned audit checks.

## Environment

- Module: System (infrastructure audit)
- Affected Component: Cloudflare MCP server + CF_API_TOKEN
- Date: 2026-04-10

## Symptoms

- MCP `execute` calls to `/zones/{id}/settings/*` return `9109: Unauthorized to access requested resource`
- MCP calls to `/zones/{id}/rulesets` return `10000: Authentication error`
- MCP calls to `/accounts/{id}/audit_logs` return `10000: Authentication error`
- CF_API_TOKEN from Doppler returns identical errors for the same endpoints
- Only DNS records, Access apps, service tokens, and tunnel status are accessible

## What Didn't Work

**Attempted Solution 1:** Using the CF_API_TOKEN from Doppler as fallback

- **Why it failed:** The token is scoped for DNS and tunnel operations only (what Terraform needs), not zone settings or WAF

**Attempted Solution 2:** Trying individual zone settings endpoints via MCP (instead of bulk `/settings`)

- **Why it failed:** The OAuth scope limitation applies per-endpoint, not just to the bulk endpoint

**Attempted Solution 3:** Trying to re-authenticate MCP with broader scope

- **Why it failed:** The `authenticate` tool is a one-time bootstrap that disappears after first use. Cannot re-auth without restarting the MCP server.

## Session Errors

**Markdownlint accidentally run on Terraform .tf file**

- **Recovery:** Identified blank lines inserted between HCL comment blocks, reverted manually
- **Prevention:** Never pass non-markdown files to `npx markdownlint-cli2 --fix`. Only pass `*.md` files.

**Browser session lost after closing Playwright**

- **Recovery:** Could not re-access Cloudflare dashboard without re-login. Fell back to CLI probes.
- **Prevention:** Keep browser session open until all dashboard-dependent checks are complete. Only close after all browser work is done.

**`gh issue create` failed due to nonexistent label**

- **Recovery:** Listed existing labels with `gh label list`, found correct label name
- **Prevention:** Always verify label existence with `gh label list --search "<name>"` before using in `gh issue create`.

**MCP authenticate tool disappeared after first OAuth flow**

- **Recovery:** Used CF_API_TOKEN and CLI tools as fallback
- **Prevention:** When MCP requires OAuth, select "Advanced: Select individual permissions" during the first auth flow to ensure all needed scopes are granted upfront. The auth tool is single-use.

**Terraform import blocks missing for new records**

- **Recovery:** Added `import` blocks with record IDs from MCP audit before merge
- **Prevention:** When adding Terraform resources for records that already exist in a provider, always add `import` blocks in the same commit. Records created via API or dashboard need import before `terraform apply`.

**GitHub Pages A records used numbered resources instead of for_each**

- **Recovery:** Refactored to `for_each` with `toset()` during review phase
- **Prevention:** When multiple resources differ only by one attribute value, use `for_each` from the start.

## Solution

The audit proceeded using a three-tier approach:

1. **MCP execute** for endpoints that worked (DNS records, Access apps, service tokens, tunnels)
2. **CF_API_TOKEN via curl** for DNSSEC status (worked where MCP didn't)
3. **CLI tools** (dig, openssl, curl) for everything else (TLS version probing, header checks, cert validation)

Created GitHub issue #1837 to track creating a broader read-only audit token.

## Why This Works

The Cloudflare API has granular permission scoping. The MCP OAuth "Read Only" preset includes DNS, Access, and Workers read permissions but excludes Zone Settings Read, Firewall Services Read, and Audit Logs Read. These require either the "Advanced: Select individual permissions" OAuth flow or a custom API token with explicit permission grants.

CLI tools (dig, openssl, curl) can verify many security properties from the outside without any API access, providing a reliable fallback for TLS configuration, HSTS headers, DNS records, and certificate validity.

## Prevention

- When authenticating Cloudflare MCP for security audits, always select "Advanced: Select individual permissions" and add: Zone Settings Read, Firewall Services Read, Account Settings Read, Notifications Read, Audit Logs Read
- Create a dedicated `CF_API_TOKEN_AUDIT` with broad read permissions, separate from the Terraform-scoped token
- The MCP `authenticate` tool is single-use per session. Plan the permission scope before the first auth attempt.
- Always include CLI verification alongside API checks as defense-in-depth

## Related Issues

- #1837: Expand CF API token permissions for security monitoring
- #1835: Enable DNSSEC for soleur.ai zone
- #1836: Restrict origin firewall to Cloudflare IP ranges only
- #1838: Upgrade DMARC policy from quarantine to reject
- See also: [2026-03-21-cloudflare-api-token-permission-editing.md](../2026-03-21-cloudflare-api-token-permission-editing.md)
