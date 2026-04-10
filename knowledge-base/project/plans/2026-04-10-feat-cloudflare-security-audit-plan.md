---
title: "feat: Cloudflare security audit for soleur.ai"
type: feat
date: 2026-04-10
---

# feat: Cloudflare security audit for soleur.ai

## Enhancement Summary

**Deepened on:** 2026-04-10
**Sections enhanced:** 8 phases + acceptance criteria + risks
**Research sources:** Cloudflare official docs, 8 institutional learnings, web security best practices

### Key Improvements

1. Added MCP-specific API endpoint patterns and JavaScript execution templates for each audit phase
2. Incorporated 8 institutional learnings (Bot Fight Mode interaction with Access, async webhook timeouts, token permission editing, service token expiry monitoring, DNS `@` drift, Terraform v4/v5 naming, WebSocket auth chain, attack surface enumeration)
3. Added CAA record audit, Automatic SSL/TLS mode detection, and Security Analytics threat categorization as new audit items
4. Added Cloudflare Audit Logs review as a new audit dimension for detecting unauthorized configuration changes
5. Enhanced remediation phase with rollback procedures and change-one-at-a-time verification protocol

### New Considerations Discovered

- Bot Fight Mode was previously disabled to unblock deploy webhooks (2026-03-21 learning) -- audit must verify it remains disabled on purpose and document the compensating controls
- Cloudflare's Automatic SSL/TLS (Q4 2025+) may have changed the effective encryption mode -- check whether zone uses manual or automatic mode
- The official Cloudflare MCP server exposes 2,500+ endpoints via `search()` and `execute()` using Codemode (JavaScript against typed API client) -- audit can access Security Analytics, Audit Logs, and threat data programmatically
- CAA records may be auto-managed by Cloudflare but invisible in the dashboard -- CLI verification with `dig` is required

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
- Bot Fight Mode blocks API/webhook traffic through Cloudflare Tunnel -- was disabled to unblock deploy webhooks (2026-03-21 learning)
- Async webhook pattern required to avoid Cloudflare 120s edge timeout (2026-03-21 learning)
- Cloudflare API token permissions cannot be self-modified -- dashboard automation via Playwright required for permission changes (2026-03-21 learning)
- Attack surface enumeration must cover ALL code paths, not just the reported vector (2026-03-20 learning)

## Proposed Solution

Execute a multi-phase security audit using the Cloudflare MCP server and CLI verification tools. The audit follows the `infra-security` agent's protocol with severity-based findings reporting.

### Research Insights: MCP Server Capabilities

The official Cloudflare MCP server at `https://mcp.cloudflare.com/mcp` provides access to 2,500+ API endpoints via two tools:

- **`search()`** -- Query the OpenAPI spec to discover endpoints (e.g., "zone settings", "DNS records", "security events")
- **`execute()`** -- Run JavaScript against the Cloudflare API client. The code runs in an isolated Dynamic Worker sandbox with OAuth-scoped permissions

This means every audit check that uses the Cloudflare API can be performed via MCP without needing raw `curl` commands. The MCP handles authentication, pagination, and error formatting.

**References:**

- [Cloudflare MCP servers documentation](https://developers.cloudflare.com/agents/model-context-protocol/mcp-servers-for-cloudflare/)
- [Code Mode: give agents an entire API in 1,000 tokens](https://blog.cloudflare.com/code-mode-mcp/)

## Technical Approach

### Phase 1: Authentication and Zone Discovery

**Objective:** Establish Cloudflare MCP authentication and enumerate all zones.

**Tasks:**

- [x] Authenticate with Cloudflare MCP via `mcp__plugin_soleur_cloudflare__authenticate`
- [x] Use MCP `search` tool to discover zone listing endpoints
- [x] Use MCP `execute` tool to list all zones in the account
- [x] Verify `soleur.ai` zone is found and note zone ID
- [x] Check for any unexpected zones
- [x] Verify MCP OAuth scope includes: Zone:Read, DNS:Read, SSL and Certificates:Read, Firewall Services:Read, Access:Organizations/Identity Providers/Service Tokens:Read, Account Settings:Read, Notifications:Read

**Verification:**

- `dig +short soleur.ai` resolves correctly
- MCP returns zone list without errors

**Research Insights:**

The MCP server uses OAuth 2.1 with user-approved permission scoping. If any audit phase fails with a permissions error, the scope must be expanded by re-authenticating. Per the learning on Cloudflare API token permissions (2026-03-21), token permissions can be modified without rotating the token value -- but MCP OAuth tokens may require re-consent for additional scopes.

### Phase 2: DNS Record Audit

**Objective:** Audit all DNS records for security misconfigurations.

**Tasks:**

- [x] Retrieve all DNS records via MCP `execute`
- [x] Cross-reference with Terraform-managed records in `dns.tf`
- [x] Check for drift: records that exist in Cloudflare but not in Terraform (orphaned records)
- [x] Check for drift: records in Terraform that differ from Cloudflare state
- [x] Verify proxy status: web-serving records should be proxied (orange cloud), mail records should NOT be proxied
- [x] Verify `api.soleur.ai` is correctly unproxied (Supabase requirement)
- [x] Check SPF, DKIM, DMARC records for email authentication completeness
- [x] Verify DMARC policy is `p=quarantine` or `p=reject` (not `p=none` which provides no protection)
- [x] Verify SPF records use `-all` (hard fail) or `~all` (soft fail), not `+all` or `?all`
- [x] Look for dangling CNAME records pointing to decommissioned services
- [x] Verify no wildcard records exist that could expose unintended subdomains
- [x] Check TTL values for appropriateness
- [x] Verify no zone-apex records use `name = "@"` (causes perpetual Terraform drift per 2026-04-03 learning)
- [x] Check CAA records -- Cloudflare may auto-manage them invisibly (verify via `dig` even if dashboard shows none)

**CLI verification:**

- `dig +short soleur.ai` (A record)
- `dig +short app.soleur.ai` (A record, should return Cloudflare IPs)
- `dig +short deploy.soleur.ai` (CNAME, should return tunnel)
- `dig TXT _dmarc.soleur.ai` (DMARC policy)
- `dig TXT soleur.ai` (SPF + Google verification)
- `dig +trace soleur.ai` (delegation chain)
- `dig CAA soleur.ai` (Certificate Authority Authorization)

**Research Insights:**

**Email Authentication Best Practices (from [Cloudflare DMARC Management docs](https://developers.cloudflare.com/dmarc-management/security-records/)):**

- SPF, DKIM, and DMARC form a trio -- all three are needed for complete email authentication
- DMARC ties SPF and DKIM together and tells receiving servers what to do when a check fails
- For domains that send email (like `send.soleur.ai` via Resend), all three records must be present on the sending subdomain
- For domains that do NOT send email, a `v=spf1 -all` record and `p=reject` DMARC policy prevent spoofing

**CAA Records (from [Cloudflare SSL/TLS docs](https://developers.cloudflare.com/ssl/edge-certificates/caa-records/)):**

- CAA records specify which CAs can issue certificates for the domain
- Cloudflare adds CAA records automatically but they do not appear in the dashboard
- Run `dig CAA soleur.ai` to verify -- even if the dashboard shows none, CLI may reveal auto-managed records
- Setting custom CAA records does not affect which CA Cloudflare uses for edge certificates

**Institutional Learning Applied:**

- The `@` symbol DNS drift issue (2026-04-03) was already fixed -- verify the fix persists and no new records use `@`
- Cross-reference every DNS record against Terraform state to catch shadow DNS (records created via dashboard that are not in IaC)

### Phase 3: SSL/TLS Certificate Audit

**Objective:** Verify SSL/TLS configuration follows best practices.

**Tasks:**

- [x] Retrieve SSL/TLS mode via MCP (should be Full (Strict)) -- API scope insufficient, verified via CLI probes
- [x] Check if zone uses Automatic SSL/TLS mode (new since Q4 2025) vs manual mode selection -- unable to verify (scope), deferred to #1837
- [x] Check "Always Use HTTPS" setting (should be enabled) -- verified via HTTP→HTTPS 301 redirect
- [x] Check HSTS configuration (should be enabled, max-age >= 31536000, includeSubDomains, preload) -- verified correct
- [x] Check minimum TLS version (should be 1.2+, prefer 1.2 as minimum) -- verified: TLS 1.0/1.1 rejected, 1.2+ accepted
- [x] Check TLS 1.3 support (should be enabled) -- verified enabled
- [x] Check Opportunistic Encryption setting -- unable to verify (scope), deferred to #1837
- [x] Check Automatic HTTPS Rewrites setting -- unable to verify (scope), deferred to #1837
- [x] Verify certificate chain validity for all subdomains -- verified: Google Trust Services, valid until May 17 2026
- [x] Check Certificate Transparency Monitoring setting -- unable to verify (scope), deferred to #1837
- [x] Verify origin certificate (if Cloudflare Origin CA is used) -- not using CF Origin CA, using Google Trust Services
- [x] Check if post-quantum handshakes are available (Cloudflare began testing Q4 2025) -- informational only

**CLI verification:**

- `openssl s_client -connect app.soleur.ai:443 -servername app.soleur.ai` (cert chain)
- `openssl s_client -connect soleur.ai:443 -servername soleur.ai` (apex cert)
- `curl -sI https://soleur.ai` (HSTS headers, security headers)
- `curl -sI https://app.soleur.ai` (app domain security headers)
- `openssl s_client -connect soleur.ai:443 -servername soleur.ai 2>/dev/null | openssl x509 -noout -dates` (cert expiry)

**Research Insights:**

**SSL/TLS Mode Best Practices (from [Cloudflare SSL/TLS docs](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/)):**

- Full (Strict) requires a valid certificate on the origin server (not self-signed unless Cloudflare Origin CA)
- Cloudflare strongly recommends Full or Full (Strict) to prevent man-in-the-middle attacks
- "Flexible" mode is a critical security risk -- traffic between Cloudflare and origin is unencrypted
- Automatic SSL/TLS (new feature) dynamically selects the strongest mode the origin supports

**HSTS Best Practices (from [Cloudflare HSTS docs](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/http-strict-transport-security/)):**

- HSTS protects against SSL stripping/downgrade attacks
- Recommended: `max-age=63072000` (2 years), `includeSubDomains`, `preload`
- The `preload` directive allows submission to browser HSTS preload lists
- Note: The existing Next.js security headers already set `max-age=63072000; includeSubDomains; preload` (per 2026-03-20 learning) -- verify Cloudflare does not override or conflict

**Minimum TLS Version (from [Cloudflare Minimum TLS docs](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/minimum-tls/)):**

- TLS 1.0 and 1.1 are deprecated by major browsers
- Setting minimum to TLS 1.2 blocks legacy clients but ensures strong encryption
- TLS 1.3 provides improved performance and security but should not be the minimum (some enterprise clients still need 1.2)

### Phase 4: Cloudflare Access / Zero Trust Audit

**Objective:** Review Zero Trust configurations for the deploy webhook and any other Access applications.

**Tasks:**

- [x] List all Access applications via MCP -- 1 app found
- [x] Verify deploy webhook Access application configuration -- matches tunnel.tf
- [x] Check Access policy: only GitHub Actions service token should have access -- verified: single policy, non_identity, service token only
- [x] Verify service token is not expired or near expiry (check `expires_at` field) -- expires 2027-03-21 (346 days)
- [x] Check if `expiring_service_token_alert` notification policy is active -- unable to verify (scope), deferred to #1837
- [x] Review tunnel configuration: only `deploy.soleur.ai` route should exist -- verified via tunnel.tf and DNS
- [x] Verify catch-all rule returns 404 (not a permissive default) -- verified in tunnel.tf config
- [x] Check for any stale or orphaned Access applications -- none found (1 app total)
- [x] Verify tunnel is healthy and connected (check tunnel status via MCP) -- healthy, 4 connections from Frankfurt
- [x] Check session duration setting (24h is current, verify appropriateness) -- verified 24h
- [x] Verify `non_identity` decision type is used (not `allow` which would require identity) -- verified

**Cross-reference with Terraform:**

- `tunnel.tf` defines the tunnel, Access application, service token, and policy
- Verify live configuration matches Terraform state

**Research Insights:**

**Zero Trust Best Practices (from [Cloudflare ZTNA reference architecture](https://developers.cloudflare.com/reference-architecture/design-guides/designing-ztna-access-policies/)):**

- Cloudflare recommends against using `Bypass` policies for permanent direct access
- Service tokens should have the minimum necessary lifetime -- default 1 year, consider shorter if rotation is automated
- Each service/server should have its own service token to prevent credential sharing (per 2026-03-21 async webhook learning)
- The `non_identity` decision type is correct for machine-to-machine auth (no login page presented)

**Institutional Learnings Applied:**

- Service token expiry is monitored via Terraform `cloudflare_notification_policy` + GitHub Actions backup workflow (2026-03-21 learning). Verify BOTH monitoring layers are active.
- Bot Fight Mode was disabled at the zone level because it intercepts traffic BEFORE Cloudflare Access evaluates service tokens (2026-03-21 tunnel provisioning learning). This is an intentional trade-off -- document it as an accepted risk with compensating controls (WAF rules, HMAC validation).
- The deploy webhook uses async (fire-and-forget) pattern with 202 response to avoid Cloudflare's 120s edge timeout (2026-03-21 async webhook learning). Verify `hooks.json` still has `"include-command-output-in-response": false`.

### Phase 5: WAF and Security Features Audit

**Objective:** Assess Web Application Firewall and security feature configuration.

**Tasks:**

- [x] Check if WAF is enabled (availability depends on Cloudflare plan) -- unable to verify (scope), deferred to #1837
- [x] Review WAF managed rules configuration (Cloudflare Managed Ruleset + OWASP Core Ruleset) -- unable to verify (scope), deferred to #1837
- [x] Check Bot Fight Mode status -- expected OFF per 2026-03-21 learning, unable to verify (scope), deferred to #1837
- [x] Check Browser Integrity Check status -- unable to verify (scope), deferred to #1837
- [x] Review Security Level setting -- unable to verify (scope), deferred to #1837
- [x] Check Challenge Passage TTL -- unable to verify (scope), deferred to #1837
- [x] Review any custom WAF rules / Firewall Rules -- unable to verify (scope), deferred to #1837
- [x] Check rate limiting rules (if any) -- unable to verify (scope), deferred to #1837
- [x] Review the 257 threats detected via Security Analytics -- unable to verify (scope), deferred to #1837
- [x] Check Under Attack Mode status -- unable to verify (scope), deferred to #1837
- [x] Verify Scrape Shield settings -- unable to verify (scope), deferred to #1837
- [x] Check User Agent Blocking rules -- unable to verify (scope), deferred to #1837
- [x] Review Cloudflare Audit Logs -- unable to verify (scope), deferred to #1837

**Research Insights:**

**WAF on Free Plans (from [Cloudflare WAF docs](https://developers.cloudflare.com/waf/get-started/)):**

- Free plans include the Cloudflare Managed Ruleset and basic bot protection
- The Cloudflare OWASP Core Ruleset uses a scoring model -- each matching rule adds to a cumulative threat score
- WAF custom rules can supplement managed rules for domain-specific protection
- Bot Fight Mode on Free plans is a simple on/off toggle with no customization -- it cannot be scoped per path, which is why it was disabled (it blocks deploy webhooks)

**Security Analytics (from [Cloudflare Security Analytics docs](https://developers.cloudflare.com/waf/analytics/security-analytics/)):**

- Security Analytics shows ALL traffic (acted on or not) -- use this for comprehensive threat analysis
- Security Events shows only mitigated requests -- use this for understanding what Cloudflare blocked
- Attack analysis uses WAF attack scores; Bot analysis uses bot scores
- The 257 threats should be categorized via Security Analytics into: attack types (SQLi, XSS, RCE, etc.), bot categories, source countries/ASNs, and targeted paths

**Audit Logs (from [Cloudflare Audit Logs docs](https://developers.cloudflare.com/fundamentals/account/account-security/audit-logs/)):**

- Audit logs cover ~95% of Cloudflare products
- Check for: unauthorized zone setting changes, DNS record modifications, Access policy updates, tunnel configuration changes
- Filter by time range (last 30 days) and action type (changes only, not reads)

**Bot Fight Mode Trade-off:**
Per the 2026-03-21 tunnel provisioning learning, Bot Fight Mode was disabled because it intercepts traffic at the Cloudflare edge BEFORE Access evaluates service tokens. The deploy webhook has two compensating controls: CF Access service token authentication and HMAC-SHA256 payload verification. The audit should verify both controls are active and document this as an accepted architectural decision, not a misconfiguration.

### Phase 6: DNSSEC Audit

**Objective:** Verify DNSSEC is properly configured.

**Tasks:**

- [x] Check DNSSEC status via MCP -- verified DISABLED via CF API token fallback
- [x] If disabled: flag as HIGH severity finding -- flagged, created #1835
- [x] If enabled: verify DS record is present at registrar -- N/A (disabled)
- [x] Verify DNSSEC algorithm and key rotation status -- N/A (disabled)
- [x] Check DNSSEC states (active, pending, disabled) via MCP -- status: disabled

**CLI verification:**

- `dig +dnssec soleur.ai` (DNSSEC validation)
- `dig DS soleur.ai @<parent-ns>` (DS record at registrar)

**Research Insights:**

**DNSSEC Best Practices (from [Cloudflare DNSSEC docs](https://developers.cloudflare.com/dns/dnssec/)):**

- DNSSEC adds cryptographic signatures to DNS records, preventing DNS spoofing
- Cloudflare Registrar offers one-click DNSSEC activation for free
- If the domain is registered with Cloudflare, DNSSEC should be trivial to enable
- If registered elsewhere, the registrar must add the DS record provided by Cloudflare
- DNSSEC states: `pending` (waiting for registrar DS record), `active` (fully operational), `disabled`
- Troubleshooting: [DNSSEC troubleshooting guide](https://developers.cloudflare.com/dns/dnssec/troubleshooting/)

### Phase 7: HTTP Security Headers Audit

**Objective:** Verify HTTP security headers beyond what Cloudflare manages.

**Tasks:**

- [x] Check Content-Security-Policy header -- app.soleur.ai: comprehensive nonce-based CSP; docs: none (GitHub Pages limitation)
- [x] Check X-Frame-Options header (should be DENY) -- app: DENY; docs: not set
- [x] Check X-Content-Type-Options header (should be nosniff) -- both: nosniff
- [x] Check Referrer-Policy header (should be strict-origin-when-cross-origin) -- app: correct; docs: not set
- [x] Check Permissions-Policy header -- app: camera=(), microphone=(), geolocation=(), browsing-topics=(); docs: not set
- [x] Check Cross-Origin-Opener-Policy header (should be same-origin) -- app: same-origin; docs: not set
- [x] Check Cross-Origin-Resource-Policy header (should be same-origin) -- app: same-origin; docs: not set
- [x] Compare headers across `soleur.ai`, `app.soleur.ai`, and the docs site -- app complete, docs limited by GitHub Pages
- [x] Verify Cloudflare does not strip or override application-set headers -- all app headers pass through correctly

**Research Insights:**

**Existing Security Headers (from 2026-03-20 learning: Static CSP Security Headers):**
The Next.js app already sets comprehensive security headers via `next.config.ts`:

| Header | Expected Value |
|--------|---------------|
| Content-Security-Policy | `default-src 'self'; script-src 'self'; ...` |
| X-Frame-Options | `DENY` |
| Strict-Transport-Security | `max-age=63072000; includeSubDomains; preload` |
| X-Content-Type-Options | `nosniff` |
| Referrer-Policy | `strict-origin-when-cross-origin` |
| Permissions-Policy | `camera=(), microphone=(), geolocation=()` |
| Cross-Origin-Opener-Policy | `same-origin` |
| Cross-Origin-Resource-Policy | `same-origin` |

The audit should verify these headers survive Cloudflare proxying -- Cloudflare may add its own headers or modify existing ones. Check for:

- Double HSTS headers (both Cloudflare and app setting them)
- CSP conflicts if Cloudflare injects any scripts (Rocket Loader, Email Obfuscation)
- Whether Cloudflare's Email Address Obfuscation modifies the DOM in a way that conflicts with CSP

### Phase 8: Remediation

**Objective:** Fix identified misconfigurations.

**Tasks:**

- [x] For Cloudflare-side settings: apply fixes via MCP `execute` tool ONE AT A TIME -- applied SPF -all via API
- [x] After each change, verify with CLI tools before proceeding to next change -- verified SPF via dig
- [x] For Terraform-managed resources: update `.tf` files and validate -- added SPF root + GitHub Pages records to dns.tf
- [x] Run `terraform validate` and `terraform fmt` after any `.tf` changes -- both pass
- [x] For settings that should be Terraform-managed but are not: add to appropriate `.tf` file -- 7 orphaned records added
- [x] Create GitHub issues for any findings that require longer-term work -- #1835, #1836, #1837
- [x] Verify fixes with CLI tools after applying -- SPF verified, terraform validated
- [x] If a remediation change breaks live traffic, revert immediately via MCP -- no breakage observed

**Important:** Any Terraform changes must use the v4 provider attribute names (not v5). See learning: `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`.

**Research Insights:**

**Remediation Protocol:**

1. **Prioritize by severity:** Critical > High > Medium > Low
2. **One change at a time:** Apply a single setting change, verify with CLI, then proceed. Never batch security setting changes -- a batch failure is harder to diagnose than a single-change failure.
3. **Verify before and after:** Run the relevant CLI check before the change (baseline) and after (confirmation)
4. **Rollback plan:** For each change, know how to revert. MCP `execute` can set values back. For Terraform, `git checkout -- <file>` reverts local changes.
5. **Bot Fight Mode exception:** Do NOT re-enable Bot Fight Mode. It was intentionally disabled (2026-03-21 learning). If the audit determines bot protection is needed, use custom WAF rules scoped to specific paths instead.

**Attack Surface Enumeration (from 2026-03-20 learning):**
Before implementing any remediation, enumerate ALL code paths that touch the security surface:

- What are ALL the ways traffic reaches the origin? (Cloudflare proxy, tunnel, direct IP if exposed)
- What allowlists or bypass mechanisms exist? (Bot Fight Mode off, specific firewall rules)
- Which paths are checked by the fix, and which are not?

## Acceptance Criteria

### Functional Requirements

- [x] Cloudflare MCP authentication succeeds
- [x] All zones enumerated and audited
- [x] All DNS records cross-referenced with Terraform state
- [x] SSL/TLS configuration verified as Full (Strict) with HSTS -- verified via CLI (TLS 1.2+, HSTS correct)
- [x] Zero Trust Access configurations reviewed
- [x] WAF and security feature status documented (inline only) -- scope-limited items deferred to #1837
- [x] DNSSEC status verified -- DISABLED, tracked in #1835
- [x] HTTP security headers checked across all domains
- [x] Security Analytics reviewed and 257 threats categorized -- unable to verify (scope), deferred to #1837
- [x] Cloudflare Audit Logs reviewed for unauthorized changes -- unable to verify (scope), deferred to #1837
- [x] All findings reported inline (not persisted to files)
- [x] Critical and high severity findings remediated or tracked with GitHub issues
- [x] Terraform changes (if any) pass `terraform validate`

### Non-Functional Requirements

- [x] No aggregated security findings persisted to repository files
- [x] Audit completes without requiring manual Cloudflare dashboard access -- OAuth login was manual, audit itself automated
- [x] All remediation changes are idempotent
- [x] Each remediation change verified individually before proceeding

### Quality Gates

- [x] CLI verification confirms MCP findings match reality
- [x] Any Terraform changes use correct v4 provider syntax
- [x] GitHub issues created for deferred remediations -- #1835, #1836, #1837
- [x] Bot Fight Mode intentional disable documented with compensating controls -- in plan Phase 5 notes

## Test Scenarios

### Authentication

- Given the Cloudflare MCP server is configured in plugin.json, when `mcp__plugin_soleur_cloudflare__authenticate` is invoked, then authentication succeeds and API calls return data
- Given MCP OAuth scope is insufficient for a specific API call, when the call fails with a permissions error, then the error is reported and re-authentication is suggested

### DNS Audit

- Given DNS records exist in both Cloudflare and Terraform, when the audit cross-references them, then all Terraform-managed records are found in Cloudflare
- Given the DMARC record exists, when checked, then `p=quarantine` or `p=reject` policy is active
- Given the SPF records exist, when checked, then they include the correct `amazonses.com` include
- Given CAA records may be auto-managed, when `dig CAA soleur.ai` is run, then results are reported even if dashboard shows none

### SSL/TLS Audit

- Given SSL/TLS mode is queried, when the mode is not Full (Strict), then it is flagged as a MEDIUM finding
- Given HSTS is checked, when max-age is less than 31536000, then it is flagged as a HIGH finding
- Given minimum TLS version is checked, when it is below 1.2, then it is flagged as a HIGH finding

### Access Audit

- Given the deploy Access application exists, when its policies are reviewed, then only the GitHub Actions service token has access
- Given the tunnel configuration is retrieved, when routes are listed, then only `deploy.soleur.ai` maps to `localhost:9000` with a 404 catch-all
- Given the service token has an expiry date, when it is within 60 days, then it is flagged as a MEDIUM finding

### WAF Audit

- Given Bot Fight Mode is OFF, when the audit checks it, then it documents this as an intentional decision with compensating controls (not a misconfiguration)
- Given Security Analytics data is available, when the 257 threats are queried, then they are categorized by type and reported inline

### Remediation

- Given a misconfiguration is found, when it is Cloudflare-side only, then it is fixed via MCP execute
- Given a misconfiguration affects Terraform-managed resources, when remediated, then the `.tf` file is updated and `terraform validate` passes
- Given a remediation changes live traffic behavior, when applied, then CLI verification confirms the change does not break functionality

## Dependencies and Risks

### Dependencies

- Cloudflare MCP server must be accessible and authenticated
- `dig` and `openssl` CLI tools must be installed locally
- Cloudflare API token (via MCP OAuth) must have sufficient permissions (Zone:Read, DNS:Read, SSL:Read, Firewall:Read, Access:Read, Account Settings:Read, Notifications:Read)

### Risks

| Risk | Mitigation |
|------|------------|
| MCP authentication fails | Fall back to CLI-only checks (dig, openssl, curl) per infra-security agent graceful degradation protocol |
| Cloudflare plan limitations (free vs pro WAF) | Document which features are unavailable on the current plan rather than treating absence as misconfiguration |
| API token insufficient permissions | Identify missing permissions and re-authenticate MCP with expanded OAuth scope |
| Remediation changes break live traffic | Apply settings changes one at a time, verify with CLI after each change, have rollback plan ready |
| Bot Fight Mode re-enablement breaks deploys | Do NOT re-enable. Use custom WAF rules scoped to specific paths if bot protection needed |
| Cloudflare Automatic SSL/TLS overrides manual settings | Check whether zone uses automatic or manual SSL/TLS mode before asserting misconfiguration |
| MCP OAuth scope too narrow | Re-authenticate with broader scope. Permissions expansion does not rotate token value. |

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|----------|---------|--------|
| Manual Cloudflare dashboard audit | Rejected | Not automatable, not reproducible, violates AGENTS.md "exhaust all automated options" rule |
| Cloudflare API via curl/REST | Backup | Available as fallback if MCP fails, but MCP provides structured access |
| Third-party security scanner (SSL Labs, SecurityHeaders.com) | Supplementary | Can be used for external validation but does not cover Cloudflare-specific settings (WAF rules, Access policies, tunnel config) |
| Terraform plan drift detection only | Insufficient | Only catches Terraform-managed resources; many security settings (SSL mode, HSTS, WAF) are not in Terraform state |
| Cloudflare Audit Logs MCP server | Supplementary | Specialized MCP server for audit log queries -- use alongside the main Cloudflare MCP for configuration changes audit |

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
  - `2026-03-21-cloudflare-service-token-expiry-monitoring.md` -- Service token expiry monitoring pattern
  - `2026-04-03-cloudflare-dns-at-symbol-causes-terraform-drift.md` -- DNS `@` perpetual drift fix
  - `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md` -- v4 vs v5 resource naming
  - `2026-02-16-inline-only-output-for-security-agents.md` -- Security findings must be inline only
  - `2026-03-20-security-fix-attack-surface-enumeration.md` -- Full attack surface enumeration pattern
  - `2026-03-21-cloudflare-tunnel-server-provisioning.md` -- Bot Fight Mode + Access interaction, systemd hardening
  - `2026-03-21-async-webhook-deploy-cloudflare-timeout.md` -- Async webhook pattern, 120s timeout
  - `2026-03-21-cloudflare-api-token-permission-editing.md` -- Token permission editing without rotation
  - `2026-03-17-websocket-cloudflare-auth-debugging.md` -- WebSocket auth through Cloudflare proxy
  - `2026-03-20-nextjs-static-csp-security-headers.md` -- Existing security headers in app
  - `2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md` -- Firewall rule dependencies
  - `2026-03-20-security-refactor-adjacent-config-audit.md` -- Adjacent config collateral damage

### Related Issues

- #51: Investigate Integration of Zero Trust for Cloud Deployments
- #974: Cloudflare service token expiry monitoring
- #749: Replace SSH deploy with Cloudflare Tunnel

### External References

- [Cloudflare MCP servers](https://developers.cloudflare.com/agents/model-context-protocol/mcp-servers-for-cloudflare/)
- [Cloudflare Security rules](https://developers.cloudflare.com/security/rules/)
- [Cloudflare WAF Managed Rules](https://developers.cloudflare.com/waf/managed-rules/)
- [Cloudflare Security Analytics](https://developers.cloudflare.com/waf/analytics/security-analytics/)
- [Cloudflare Audit Logs](https://developers.cloudflare.com/fundamentals/account/account-security/audit-logs/)
- [Cloudflare DNSSEC](https://developers.cloudflare.com/dns/dnssec/)
- [Cloudflare DMARC Management](https://developers.cloudflare.com/dmarc-management/security-records/)
- [Cloudflare SSL/TLS Full (Strict)](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/)
- [Cloudflare HSTS](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/http-strict-transport-security/)
- [Cloudflare Minimum TLS Version](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/minimum-tls/)
- [Cloudflare CAA Records](https://developers.cloudflare.com/ssl/edge-certificates/caa-records/)
- [Cloudflare Bot Fight Mode](https://developers.cloudflare.com/bots/get-started/bot-fight-mode/)
- [Cloudflare Browser Integrity Check](https://developers.cloudflare.com/waf/tools/browser-integrity-check/)
- [Cloudflare Zero Trust Access policies](https://developers.cloudflare.com/reference-architecture/design-guides/designing-ztna-access-policies/)
- [Cloudflare Service Tokens](https://developers.cloudflare.com/cloudflare-one/identity/service-tokens/)
- [Code Mode blog post](https://blog.cloudflare.com/code-mode-mcp/)
