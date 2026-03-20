---
title: "security: confirm HSTS preload intent and submit to hstspreload.org"
type: fix
date: 2026-03-20
semver: patch
deepened: 2026-03-20
---

# security: confirm HSTS preload intent and submit to hstspreload.org

Closes #954.

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sources consulted:** hstspreload.org API (status, preloadable, removable endpoints), MDN HSTS documentation, OWASP HSTS Cheat Sheet, Cloudflare HSTS documentation, live header verification via curl
**Review agents applied:** infra-security (Cloudflare interaction analysis), security-sentinel (preload commitment risk assessment)

### Key Improvements from Research

1. **Removal process clarification** -- The hstspreload.org removable API confirms that once preloaded, removal requires (a) removing the `preload` directive from the HSTS header, (b) contacting hstspreload.org administrators directly, and (c) waiting for a Chromium release cycle. The domain is "protected against removal through the hstspreload.org site" and requires administrator contact. This is stricter than the plan originally stated.
2. **OWASP alignment** -- OWASP HSTS Cheat Sheet recommends `max-age=63072000; includeSubDomains; preload` as the long-term configuration -- the exact value in the application code. The Cloudflare-served value of `max-age=31536000` also exceeds the minimum but OWASP explicitly recommends 2 years for established deployments.
3. **Cloudflare header precedence** -- Cloudflare documentation confirms it serves its own HSTS header to browsers for all HTTPS requests. The origin header from `security-headers.ts` is effectively shadowed. This means the `preload` directive visible to browsers comes from Cloudflare's zone setting, not the application code.
4. **Cookie security consideration** -- OWASP warns that omitting `includeSubDomains` leaves cookie-based attacks viable ("cookies can be manipulated from sub-domains"). Both Cloudflare and the application include `includeSubDomains`, so this risk is mitigated.
5. **hstspreload.org eligibility confirmed programmatically** -- The preloadable API returns zero errors and zero warnings for `soleur.ai`, confirming all four requirements are met without relying on manual browser checks.

### New Considerations Discovered

- The hstspreload.org removal process is more restrictive than documented in the original issue -- it requires direct administrator contact, not just a web form submission
- Cloudflare's HSTS setting is the authoritative source for browsers, making the application-level header defense-in-depth only (if Cloudflare proxy is bypassed or disabled)
- OWASP explicitly warns that HSTS can be exploited for user tracking ("significant privacy leak") via HSTS super cookies -- not a risk for this use case but worth noting for awareness

## Overview

The HSTS header added in #946 (PR #951) includes the `preload` flag (`max-age=63072000; includeSubDomains; preload`), signaling intent to submit `soleur.ai` to the browser HSTS preload list. The `preload` directive has no effect until the domain is actually submitted to [hstspreload.org](https://hstspreload.org). Once on the list, removal takes months. This plan documents the subdomain audit, confirms preload readiness, and defines the steps to submit and verify.

## Problem Statement / Motivation

The `preload` flag in the HSTS header is a promise to browsers: "this domain and all its subdomains will always use HTTPS." Including the flag without submitting to the preload list is misleading configuration -- it implies an intent that has not been followed through. Conversely, submitting without verifying that all subdomains can serve HTTPS risks breaking services.

## Subdomain Audit

### Complete DNS Record Inventory

Source: Terraform config (`apps/web-platform/infra/dns.tf`), `knowledge-base/operations/domains.md`, Cloudflare zone.

| Subdomain | Type | Target | Proxied | Purpose | HTTP Access Needed? |
|-----------|------|--------|---------|---------|---------------------|
| `soleur.ai` (apex) | A (x4) | 185.199.108-111.153 (GitHub Pages) | Yes | Docs site (Eleventy on GitHub Pages) | No -- Cloudflare `Always Use HTTPS` redirects HTTP to HTTPS |
| `www.soleur.ai` | CNAME | jikig-ai.github.io | Yes | Docs site redirect | No -- Cloudflare redirects |
| `app.soleur.ai` | A | Hetzner CX33 IP | Yes | Web platform (Next.js) | No -- Cloudflare redirects, app enforces HTTPS |
| `send.soleur.ai` | TXT + MX | SPF/MX for Amazon SES | No | Email sending via Resend | No -- no HTTP service, email only |
| `resend._domainkey.soleur.ai` | TXT | DKIM public key | No | Email authentication | No -- no HTTP service |
| `_dmarc.soleur.ai` | TXT | DMARC policy | No | Email authentication | No -- no HTTP service |
| `_github-pages-challenge-jikig-ai.soleur.ai` | TXT | Verification token | No | GitHub Pages domain verification | No -- no HTTP service |

### Audit Conclusion

**No subdomains require HTTP access.** All web-serving subdomains (`soleur.ai`, `www.soleur.ai`, `app.soleur.ai`) are proxied through Cloudflare with `Always Use HTTPS` enabled. Email-related subdomains (`send`, `resend._domainkey`, `_dmarc`) are TXT/MX records only and do not serve HTTP traffic. There are no staging, internal API, or development subdomains.

### Research Insights: Subdomain Completeness Verification

**Terraform is the single source of truth for DNS records.** All Cloudflare DNS records are managed via `apps/web-platform/infra/dns.tf`. The telegram-bridge infrastructure (`apps/telegram-bridge/infra/`) has no DNS records -- it is accessed via IP or Telegram API, not via a `soleur.ai` subdomain. This means the Terraform config covers the complete DNS record set.

**OWASP `includeSubDomains` rationale:** OWASP warns that omitting `includeSubDomains` leaves cookie-based attacks viable because "cookies can be manipulated from sub-domains." Both the Cloudflare zone setting and the application code include `includeSubDomains`, closing this attack vector for all current and future subdomains.

## Live Header Verification

Verified on 2026-03-20 via `curl -sI`:

| Endpoint | HSTS Header | Source |
|----------|-------------|--------|
| `https://soleur.ai` | `max-age=31536000; includeSubDomains; preload` | Cloudflare zone-level HSTS |
| `https://www.soleur.ai` | `max-age=31536000; includeSubDomains; preload` | Cloudflare zone-level HSTS |
| `https://app.soleur.ai` | `max-age=31536000; includeSubDomains; preload` | Cloudflare zone-level HSTS (overrides app-level header) |
| `http://soleur.ai` | 301 redirect to `https://soleur.ai/` | Cloudflare `Always Use HTTPS` |

### Header Value Discrepancy

The application code in `apps/web-platform/lib/security-headers.ts` sets `max-age=63072000` (2 years), but the live response shows `max-age=31536000` (1 year). This is because Cloudflare's zone-level HSTS setting (documented in `knowledge-base/operations/domains.md`) takes precedence -- Cloudflare deduplicates HSTS headers and uses its own value. Both values exceed the hstspreload.org minimum of `31536000` (1 year), so this discrepancy does not block preload eligibility.

**No code change required.** The Cloudflare-served value satisfies all preload requirements. The application-level value serves as defense-in-depth (it would take effect if Cloudflare's HSTS setting were accidentally disabled).

### Research Insights: Cloudflare HSTS Precedence

**Cloudflare documentation confirms:** Cloudflare "serves HSTS headers to browsers for all HTTPS requests." When Cloudflare's zone-level HSTS is enabled, it generates its own `Strict-Transport-Security` header. The origin's HSTS header (from `security-headers.ts`) is not forwarded to the browser -- Cloudflare replaces it with its own value.

**MDN recommendation:** MDN states that "two years is the recommended value as explained on hstspreload.org." The application code uses 2 years (`63072000`), aligning with MDN's recommendation. The Cloudflare zone uses 1 year (`31536000`), which is the minimum for preload eligibility. Consider updating the Cloudflare zone HSTS `max-age` to `63072000` (2 years) to align with OWASP/MDN recommendations -- but this is optional and does not block the preload submission.

**Defense-in-depth value:** The application-level HSTS header becomes active if: (a) Cloudflare proxy is bypassed (direct IP access to the Hetzner server), (b) Cloudflare's HSTS setting is accidentally disabled, or (c) the domain is migrated away from Cloudflare. Keeping the application-level header at `63072000` (stricter than Cloudflare's `31536000`) is the correct layering.

## Preload Eligibility

Verified via the hstspreload.org API on 2026-03-20:

- **Status:** `unknown` (not yet submitted)
- **Preloadable check:** Passed with zero errors and zero warnings
- **Requirements met:**
  1. Valid TLS certificate (Cloudflare Universal SSL)
  2. HTTP to HTTPS redirect on port 80 (Cloudflare `Always Use HTTPS`)
  3. All subdomains serve HTTPS (verified above)
  4. HSTS header on base domain with `max-age >= 31536000`, `includeSubDomains`, and `preload` (verified above)

## Proposed Solution

Submit `soleur.ai` to the HSTS preload list via the hstspreload.org web form using Playwright MCP. No code changes are needed -- the existing header configuration already satisfies all preload requirements.

### Decision Rationale

The `preload` commitment is appropriate because:

1. **HTTPS-only infrastructure.** All web-serving subdomains are behind Cloudflare with `Always Use HTTPS`. The web platform enforces HTTPS at both the Cloudflare proxy layer and the application layer.
2. **No HTTP-dependent subdomains.** No staging, internal API, or development subdomains exist. Email subdomains do not serve HTTP.
3. **Production SaaS commitment.** The domain serves a production application with user accounts, payment processing, and legal documents. HTTPS is a permanent requirement, not a temporary choice.
4. **Cloudflare already enforces HSTS.** The zone-level HSTS setting with `includeSubDomains; preload` is already active in the Cloudflare dashboard. The preload list submission formalizes what is already enforced.
5. **Solo operator domain.** There is no risk of a separate team creating an HTTP-only subdomain -- all DNS changes go through Terraform and Cloudflare, both controlled by the same operator.

## Implementation Steps

### Phase 0: Pre-Flight Verification (API-Based)

Before launching Playwright, verify eligibility programmatically to fail fast:

1. Query preloadable API: `curl -s 'https://hstspreload.org/api/v2/preloadable?domain=soleur.ai'` -- expect empty `errors` and `warnings` arrays
2. Query status API: `curl -s 'https://hstspreload.org/api/v2/status?domain=soleur.ai'` -- expect `"status": "unknown"` (confirming not yet submitted)
3. Verify live HSTS header: `curl -sI https://soleur.ai | grep -i strict-transport-security` -- expect `preload` in the value

If any check fails, investigate before proceeding. Do not launch Playwright for a domain that will fail the eligibility check.

### Phase 1: Submit to HSTS Preload List

1. Navigate to [hstspreload.org](https://hstspreload.org) using Playwright MCP
2. Enter `soleur.ai` in the domain field
3. Confirm the eligibility check passes (expect green checkmarks)
4. Check the acknowledgment checkboxes (understanding that removal is difficult, all subdomains will be HTTPS-only)
5. Submit the domain
6. Capture confirmation screenshot or status text

### Phase 2: Verify Submission

1. Query the hstspreload.org API: `curl -s 'https://hstspreload.org/api/v2/status?domain=soleur.ai'`
2. Verify status changed from `unknown` to `pending` (or equivalent)
3. If status is still `unknown`, wait 30 seconds and re-query -- the API may have propagation delay
4. Document the submission date and final status in `knowledge-base/operations/domains.md`

### Phase 3: Update Documentation

1. Update `knowledge-base/operations/domains.md` Security Configuration table to add HSTS preload submission status and date
2. Update the learning at `knowledge-base/learnings/2026-03-20-nextjs-static-csp-security-headers.md` to note the preload submission (the learning currently shows `max-age=63072000; includeSubDomains` without `preload` in the headers table)

### Phase 4: Verify Pending Status (Follow-Up)

The preload list is updated in Chromium approximately every 6-8 weeks. After submission:
- The status will show `pending` until the next Chromium release includes the domain
- Once included, all Chromium-based browsers (Chrome, Edge, Brave, Opera) and Firefox (which shares the list) will enforce HTTPS for `soleur.ai` and all subdomains without ever making an HTTP request
- No further action is needed after submission -- the process is automatic

## Acceptance Criteria

- [x] `soleur.ai` is submitted to hstspreload.org
- [x] hstspreload.org API returns status other than `unknown` for `soleur.ai` (e.g., `pending`)
- [x] `knowledge-base/operations/domains.md` is updated with preload submission status and date
- [x] `knowledge-base/learnings/2026-03-20-nextjs-static-csp-security-headers.md` HSTS table entry updated to include `preload`

## Test Scenarios

- Given `soleur.ai` has been submitted to hstspreload.org, when querying `https://hstspreload.org/api/v2/status?domain=soleur.ai`, then the status is not `unknown`
- Given the domains.md file, when inspecting the Security Configuration section, then it documents the HSTS preload submission date and status
- Given the learnings file, when inspecting the headers table, then the HSTS value includes `preload`

## Non-Goals

- Changing the `max-age` value in `security-headers.ts` (the Cloudflare-served value is authoritative; the app value is defense-in-depth)
- Aligning the Cloudflare HSTS `max-age` (31536000) with the app-level value (63072000) -- both exceed the minimum and serve different purposes
- Monitoring Chromium release schedule for preload list inclusion -- this is automatic and requires no action
- Removing `X-Powered-By` header (separate issue)

## Dependencies and Risks

- **Risk: Removal difficulty (higher than initially assessed).** The hstspreload.org removable API reveals the process is stricter than a simple web form. Removal requires: (1) removing the `preload` directive from the HSTS header, (2) the domain must NOT have the `preload` directive when the removable check runs, (3) the domain is "protected against removal through the hstspreload.org site" and requires direct administrator contact. After these conditions are met, removal still requires waiting for a Chromium release cycle (6-8 weeks minimum). OWASP explicitly warns: "Sending the preload directive from your site can have PERMANENT CONSEQUENCES." This is acceptable given the audit confirms no subdomains need HTTP and the domain is a production SaaS with a permanent HTTPS commitment.
- **Risk: Future subdomain creation.** Any new subdomain (e.g., `staging.soleur.ai`, `api.soleur.ai`) will be forced to HTTPS by browsers on the preload list. This is the desired behavior for a production SaaS domain. Document this constraint in `domains.md` as a reminder. All DNS changes already go through Terraform, providing a natural review gate.
- **Risk: HSTS super cookies (negligible).** OWASP notes that HSTS can be exploited by malicious sites to fingerprint users without cookies ("significant privacy leak"). This is a browser-level concern, not an operator concern -- it affects users of sites that abuse HSTS, not sites that legitimately use it. No mitigation needed.
- **Dependency: Playwright MCP.** The hstspreload.org form submission requires browser interaction. Playwright MCP can automate this. If CAPTCHA is present, the user will need to solve it manually (Playwright drives to the CAPTCHA step).

## MVP

No code changes. The implementation is:

### `knowledge-base/operations/domains.md` (update)

Add HSTS preload submission status to the Security Configuration table:

```markdown
| HSTS | max-age=31536000; includeSubDomains; preload |
| HSTS Preload | Submitted 2026-03-20 (pending inclusion in Chromium preload list) |
```

Add a note about the preload commitment:

```markdown
## HSTS Preload Commitment

The domain `soleur.ai` was submitted to the [HSTS preload list](https://hstspreload.org) on 2026-03-20. This means:

- All subdomains must serve HTTPS. Creating an HTTP-only subdomain will be unreachable for browsers using the preload list.
- Removal from the list takes months (requires a removal request and a Chromium release cycle).
- New subdomains created via Terraform must have Cloudflare proxy enabled (`proxied = true`) with `Always Use HTTPS` active.
```

### `knowledge-base/learnings/2026-03-20-nextjs-static-csp-security-headers.md` (update)

Update the HSTS row in the headers table from:

```markdown
| Strict-Transport-Security | `max-age=63072000; includeSubDomains` |
```

to:

```markdown
| Strict-Transport-Security | `max-age=63072000; includeSubDomains; preload` |
```

## References

- Issue: #954
- Parent PR: #951 (added HSTS header with preload flag)
- Parent issue: #946 (security headers)
- HSTS Preload submission site: [hstspreload.org](https://hstspreload.org)
- HSTS Preload API endpoints:
  - Status: `https://hstspreload.org/api/v2/status?domain=soleur.ai`
  - Preloadable check: `https://hstspreload.org/api/v2/preloadable?domain=soleur.ai`
  - Removable check: `https://hstspreload.org/api/v2/removable?domain=soleur.ai`
- MDN HSTS documentation: [developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Strict-Transport-Security](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Strict-Transport-Security)
- OWASP HSTS Cheat Sheet: [cheatsheetseries.owasp.org/cheatsheets/HTTP_Strict_Transport_Security_Cheat_Sheet.html](https://cheatsheetseries.owasp.org/cheatsheets/HTTP_Strict_Transport_Security_Cheat_Sheet.html)
- Cloudflare HSTS docs: [developers.cloudflare.com/ssl/edge-certificates/additional-options/http-strict-transport-security](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/http-strict-transport-security/)
- Chromium HSTS preload list: [chromium.googlesource.com/chromium/src/+/main/net/http/transport_security_state_static.json](https://chromium.googlesource.com/chromium/src/+/main/net/http/transport_security_state_static.json)
- Related learning: `knowledge-base/learnings/2026-03-20-nextjs-static-csp-security-headers.md`
- Security headers implementation: `apps/web-platform/lib/security-headers.ts`
- DNS Terraform config: `apps/web-platform/infra/dns.tf`
