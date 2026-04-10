---
title: "feat: Cloudflare security audit for soleur.ai"
type: feat
date: 2026-04-10
---

# feat: Cloudflare security audit for soleur.ai

## Overview

Comprehensive security audit of the Cloudflare configuration for `soleur.ai` and all associated subdomains, triggered by 257 security threats detected in the last month. The audit uses the Cloudflare MCP server (authenticated via OAuth 2.1) and the `infra-security` agent to scan all zones, audit DNS records, SSL/TLS certificates, Cloudflare Access configs, WAF configurations, and identify misconfigurations requiring remediation.

**Critical constraint:** Per `constitution.md` line 172, aggregated security findings must NEVER be persisted to files in this open-source repository. All audit results are output inline in conversation only. The plan file describes the audit *procedure*, not the audit *results*.

## Problem Statement / Motivation

Cloudflare detected 257 security threats against `soleur.ai` infrastructure last month. While Cloudflare's automated defenses handled these, a proactive security audit is needed to:

1. Verify all security configurations are optimal (SSL/TLS mode, DNSSEC, HSTS, etc.)
2. Identify any misconfigurations that could weaken defenses
3. Audit DNS records for correctness and security implications
4. Review Zero Trust Access policies for the deploy webhook
5. Assess WAF coverage and rule effectiveness
6. Ensure the Cloudflare Tunnel configuration follows security best practices

### Current Infrastructure Context

From `apps/web-platform/infra/`:

- **DNS records (dns.tf):** A record for `app.soleur.ai` (proxied), CNAME for `deploy.soleur.ai` (tunnel), email auth records (DKIM, SPF, DMARC for Resend), Supabase custom domain (`api.soleur.ai`, unproxied), Google site verification, Buttondown NS delegation for `mail.soleur.ai`
- **Tunnel (tunnel.tf):** Cloudflare Zero Trust tunnel for deploy webhook, Access application with service token auth, notification policy for token expiry
- **Firewall (firewall.tf):** Hetzner firewall with SSH (admin IPs only), HTTP/HTTPS (0.0.0.0/0), ICMP
- **Provider:** Cloudflare provider ~> 4.0 (v4, not v5)

### Known Issues from Learnings

- Cloudflare Access service tokens expire after 1 year (2026-03-21 learning)
- `@` symbol in DNS records causes Terraform drift -- already fixed (2026-04-03 learning)
- Cloudflare Terraform v4 vs v5 naming differences (2026-03-20 learning)
- WebSocket Cloudflare auth debugging patterns (2026-03-17 learning)

## Proposed Solution

Execute a multi-phase security audit using the Cloudflare MCP server and CLI verification tools. The audit follows the `infra-security` agent's protocol with severity-based findings reporting.

## Technical Approach

### Phase 1: Authentication and Zone Discovery

**Objective:** Establish Cloudflare MCP authentication and enumerate all zones.

**Tasks:**

- [ ] Authenticate with Cloudflare MCP via `mcp__plugin_soleur_cloudflare__authenticate`
- [ ] Use MCP `search` tool to discover zone listing endpoints
- [ ] Use MCP `execute` tool to list all zones in the account
- [ ] Verify `soleur.ai` zone is found and note zone ID
- [ ] Check for any unexpected zones

**Verification:**

- `dig +short soleur.ai` resolves correctly
- MCP returns zone list without errors

### Phase 2: DNS Record Audit

**Objective:** Audit all DNS records for security misconfigurations.

**Tasks:**

- [ ] Retrieve all DNS records via MCP `execute`
- [ ] Cross-reference with Terraform-managed records in `dns.tf`
- [ ] Check for drift: records that exist in Cloudflare but not in Terraform (orphaned records)
- [ ] Check for drift: records in Terraform that differ from Cloudflare state
- [ ] Verify proxy status: web-serving records should be proxied (orange cloud), mail records should NOT be proxied
- [ ] Verify `api.soleur.ai` is correctly unproxied (Supabase requirement)
- [ ] Check SPF, DKIM, DMARC records for email authentication completeness
- [ ] Look for dangling CNAME records pointing to decommissioned services
- [ ] Verify no wildcard records exist that could expose unintended subdomains
- [ ] Check TTL values for appropriateness

**CLI verification:**

- `dig +short soleur.ai` (A record)
- `dig +short app.soleur.ai` (A record, should return Cloudflare IPs)
- `dig +short deploy.soleur.ai` (CNAME, should return tunnel)
- `dig TXT _dmarc.soleur.ai` (DMARC policy)
- `dig TXT soleur.ai` (SPF + Google verification)
- `dig +trace soleur.ai` (delegation chain)

### Phase 3: SSL/TLS Certificate Audit

**Objective:** Verify SSL/TLS configuration follows best practices.

**Tasks:**

- [ ] Retrieve SSL/TLS mode via MCP (should be Full (Strict))
- [ ] Check "Always Use HTTPS" setting (should be enabled)
- [ ] Check HSTS configuration (should be enabled, max-age >= 31536000, includeSubDomains, preload)
- [ ] Check minimum TLS version (should be 1.2+)
- [ ] Check TLS 1.3 support (should be enabled)
- [ ] Check Opportunistic Encryption setting
- [ ] Check Automatic HTTPS Rewrites setting
- [ ] Verify certificate chain validity for all subdomains
- [ ] Check Certificate Transparency Monitoring setting

**CLI verification:**

- `openssl s_client -connect app.soleur.ai:443 -servername app.soleur.ai` (cert chain)
- `openssl s_client -connect soleur.ai:443 -servername soleur.ai` (apex cert)
- `curl -sI https://soleur.ai` (HSTS headers, security headers)
- `curl -sI https://app.soleur.ai` (app domain security headers)

### Phase 4: Cloudflare Access / Zero Trust Audit

**Objective:** Review Zero Trust configurations for the deploy webhook and any other Access applications.

**Tasks:**

- [ ] List all Access applications via MCP
- [ ] Verify deploy webhook Access application configuration
- [ ] Check Access policy: only GitHub Actions service token should have access
- [ ] Verify service token is not expired or near expiry
- [ ] Check if `expiring_service_token_alert` notification policy is active
- [ ] Review tunnel configuration: only `deploy.soleur.ai` route should exist
- [ ] Verify catch-all rule returns 404 (not a permissive default)
- [ ] Check for any stale or orphaned Access applications
- [ ] Verify tunnel is healthy and connected

**Cross-reference with Terraform:**

- `tunnel.tf` defines the tunnel, Access application, service token, and policy
- Verify live configuration matches Terraform state

### Phase 5: WAF and Security Features Audit

**Objective:** Assess Web Application Firewall and security feature configuration.

**Tasks:**

- [ ] Check if WAF is enabled (availability depends on Cloudflare plan)
- [ ] Review WAF managed rules configuration
- [ ] Check Bot Fight Mode status (should be enabled)
- [ ] Check Browser Integrity Check status
- [ ] Review Security Level setting (Medium recommended as baseline)
- [ ] Check Challenge Passage TTL
- [ ] Review any custom WAF rules / Firewall Rules
- [ ] Check rate limiting rules (if any)
- [ ] Review the 257 threats detected -- categorize by type (DDoS, bot, scanner, etc.)
- [ ] Check Under Attack Mode status (should be off unless actively under attack)
- [ ] Verify Scrape Shield settings (Email Address Obfuscation, Server-side Excludes, Hotlink Protection)

### Phase 6: DNSSEC Audit

**Objective:** Verify DNSSEC is properly configured.

**Tasks:**

- [ ] Check DNSSEC status via MCP
- [ ] If disabled: flag as HIGH severity finding
- [ ] If enabled: verify DS record is present at registrar
- [ ] Verify DNSSEC algorithm and key rotation status

**CLI verification:**

- `dig +dnssec soleur.ai` (DNSSEC validation)

### Phase 7: HTTP Security Headers Audit

**Objective:** Verify HTTP security headers beyond what Cloudflare manages.

**Tasks:**

- [ ] Check Content-Security-Policy header
- [ ] Check X-Frame-Options header
- [ ] Check X-Content-Type-Options header
- [ ] Check Referrer-Policy header
- [ ] Check Permissions-Policy header
- [ ] Compare headers across `soleur.ai`, `app.soleur.ai`, and the docs site

### Phase 8: Remediation

**Objective:** Fix identified misconfigurations.

**Tasks:**

- [ ] For Cloudflare-side settings: apply fixes via MCP `execute` tool
- [ ] For Terraform-managed resources: update `.tf` files and validate
- [ ] Run `terraform validate` and `terraform fmt` after any `.tf` changes
- [ ] For settings that should be Terraform-managed but are not: add to appropriate `.tf` file
- [ ] Create GitHub issues for any findings that require longer-term work
- [ ] Verify fixes with CLI tools after applying

**Important:** Any Terraform changes must use the v4 provider attribute names (not v5). See learning: `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`.

## Acceptance Criteria

### Functional Requirements

- [ ] Cloudflare MCP authentication succeeds
- [ ] All zones enumerated and audited
- [ ] All DNS records cross-referenced with Terraform state
- [ ] SSL/TLS configuration verified as Full (Strict) with HSTS
- [ ] Zero Trust Access configurations reviewed
- [ ] WAF and security feature status documented
- [ ] DNSSEC status verified
- [ ] HTTP security headers checked
- [ ] All findings reported inline (not persisted to files)
- [ ] Critical and high severity findings remediated or tracked with GitHub issues
- [ ] Terraform changes (if any) pass `terraform validate`

### Non-Functional Requirements

- [ ] No aggregated security findings persisted to repository files
- [ ] Audit completes without requiring manual Cloudflare dashboard access
- [ ] All remediation changes are idempotent

### Quality Gates

- [ ] CLI verification confirms MCP findings match reality
- [ ] Any Terraform changes use correct v4 provider syntax
- [ ] GitHub issues created for deferred remediations

## Test Scenarios

### Authentication

- Given the Cloudflare MCP server is configured in plugin.json, when `mcp__plugin_soleur_cloudflare__authenticate` is invoked, then authentication succeeds and API calls return data

### DNS Audit

- Given DNS records exist in both Cloudflare and Terraform, when the audit cross-references them, then all Terraform-managed records are found in Cloudflare
- Given the DMARC record exists, when checked, then `p=quarantine` or `p=reject` policy is active
- Given the SPF records exist, when checked, then they include the correct `amazonses.com` include

### SSL/TLS Audit

- Given SSL/TLS mode is queried, when the mode is not Full (Strict), then it is flagged as a MEDIUM finding
- Given HSTS is checked, when max-age is less than 31536000, then it is flagged as a HIGH finding

### Access Audit

- Given the deploy Access application exists, when its policies are reviewed, then only the GitHub Actions service token has access
- Given the tunnel configuration is retrieved, when routes are listed, then only `deploy.soleur.ai` maps to `localhost:9000` with a 404 catch-all

### Remediation

- Given a misconfiguration is found, when it is Cloudflare-side only, then it is fixed via MCP execute
- Given a misconfiguration affects Terraform-managed resources, when remediated, then the `.tf` file is updated and `terraform validate` passes

## Dependencies and Risks

### Dependencies

- Cloudflare MCP server must be accessible and authenticated
- `dig` and `openssl` CLI tools must be installed locally
- Cloudflare API token must have sufficient permissions (Zone:Read, DNS:Read, SSL:Read, Firewall:Read, Access:Read)

### Risks

| Risk | Mitigation |
|------|------------|
| MCP authentication fails | Fall back to CLI-only checks (dig, openssl, curl) per infra-security agent graceful degradation protocol |
| Cloudflare plan limitations (free vs pro WAF) | Document which features are unavailable on the current plan rather than treating absence as misconfiguration |
| API token insufficient permissions | Identify missing permissions and document what additional scopes are needed |
| Remediation changes break live traffic | Apply settings changes one at a time, verify with CLI after each change |

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|----------|---------|--------|
| Manual Cloudflare dashboard audit | Rejected | Not automatable, not reproducible, violates AGENTS.md "exhaust all automated options" rule |
| Cloudflare API via curl/REST | Backup | Available as fallback if MCP fails, but MCP provides structured access |
| Third-party security scanner (SSL Labs, SecurityHeaders.com) | Supplementary | Can be used for external validation but does not cover Cloudflare-specific settings (WAF rules, Access policies, tunnel config) |
| Terraform plan drift detection only | Insufficient | Only catches Terraform-managed resources; many security settings (SSL mode, HSTS, WAF) are not in Terraform state |

## Domain Review

**Domains relevant:** Engineering, Operations, Legal

### Engineering (CTO)

**Status:** reviewed
**Assessment:** This is a security infrastructure audit touching Cloudflare configuration, DNS, SSL/TLS, and Zero Trust. The primary engineering concern is ensuring Terraform state matches live Cloudflare configuration (drift detection). The firewall configuration in `firewall.tf` still opens HTTP/HTTPS to `0.0.0.0/0` -- this is expected for Cloudflare-proxied traffic but should be validated that direct IP access is blocked by the application or Cloudflare. The Cloudflare provider version (~> 4.0) constrains which API features are available via Terraform.

### Operations (COO)

**Status:** reviewed
**Assessment:** The 257 threats detected represent operational risk. The audit should categorize threat types to determine if current Cloudflare plan tier (free) is sufficient or if a paid plan with advanced WAF/DDoS features is warranted. Service token expiry monitoring (already implemented per #974) should be verified as active. No new vendor costs unless the audit reveals the free tier is insufficient.

### Legal (CLO)

**Status:** reviewed
**Assessment:** DMARC, SPF, and DKIM configurations are relevant to email deliverability and anti-spoofing -- both have compliance implications. If the audit reveals email authentication gaps, these should be prioritized as they affect transactional email integrity. No new legal document updates expected unless the audit triggers a Cloudflare plan change (which would require expense ledger and processor disclosure updates).

## References and Research

### Internal References

- Infrastructure files: `apps/web-platform/infra/dns.tf`, `tunnel.tf`, `firewall.tf`, `main.tf`, `variables.tf`
- Agent: `plugins/soleur/agents/engineering/infra/infra-security.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-03-20-cloudflare-tunnel-deploy-brainstorm.md`
- Learnings:
  - `2026-03-21-cloudflare-service-token-expiry-monitoring.md`
  - `2026-04-03-cloudflare-dns-at-symbol-causes-terraform-drift.md`
  - `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`
  - `2026-02-16-inline-only-output-for-security-agents.md`
  - `2026-03-20-security-fix-attack-surface-enumeration.md`

### Related Issues

- #51: Investigate Integration of Zero Trust for Cloud Deployments
- #974: Cloudflare service token expiry monitoring
- #749: Replace SSH deploy with Cloudflare Tunnel

### External References

- Cloudflare MCP server: `https://mcp.cloudflare.com/mcp`
- Cloudflare security best practices: [Cloudflare Docs](https://developers.cloudflare.com/fundamentals/security/)
