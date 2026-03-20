---
title: "security: confirm HSTS preload intent and submit to hstspreload.org"
type: fix
date: 2026-03-20
semver: patch
---

# security: confirm HSTS preload intent and submit to hstspreload.org

Closes #954.

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

### Phase 1: Submit to HSTS Preload List

1. Navigate to [hstspreload.org](https://hstspreload.org) using Playwright MCP
2. Enter `soleur.ai` in the domain field
3. Confirm the eligibility check passes (expect green checkmarks)
4. Check the acknowledgment checkboxes (understanding that removal is difficult, all subdomains will be HTTPS-only)
5. Submit the domain
6. Capture confirmation screenshot or status text

### Phase 2: Verify Submission

1. Query the hstspreload.org API: `https://hstspreload.org/api/v2/status?domain=soleur.ai`
2. Verify status changed from `unknown` to `pending` (or equivalent)
3. Document the submission date and status in `knowledge-base/operations/domains.md`

### Phase 3: Update Documentation

1. Update `knowledge-base/operations/domains.md` Security Configuration table to add HSTS preload submission status and date
2. Update the learning at `knowledge-base/learnings/2026-03-20-nextjs-static-csp-security-headers.md` to note the preload submission (the learning currently shows `max-age=63072000; includeSubDomains` without `preload` in the headers table)

### Phase 4: Verify Pending Status (Follow-Up)

The preload list is updated in Chromium approximately every 6-8 weeks. After submission:
- The status will show `pending` until the next Chromium release includes the domain
- Once included, all Chromium-based browsers (Chrome, Edge, Brave, Opera) and Firefox (which shares the list) will enforce HTTPS for `soleur.ai` and all subdomains without ever making an HTTP request
- No further action is needed after submission -- the process is automatic

## Acceptance Criteria

- [ ] `soleur.ai` is submitted to hstspreload.org
- [ ] hstspreload.org API returns status other than `unknown` for `soleur.ai` (e.g., `pending`)
- [ ] `knowledge-base/operations/domains.md` is updated with preload submission status and date
- [ ] `knowledge-base/learnings/2026-03-20-nextjs-static-csp-security-headers.md` HSTS table entry updated to include `preload`

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

- **Risk: Removal difficulty.** Once on the preload list, removal requires submitting a removal request to hstspreload.org and waiting for the next Chromium release cycle (6-8 weeks minimum). This is acceptable given the audit confirms no subdomains need HTTP.
- **Risk: Future subdomain creation.** Any new subdomain (e.g., `staging.soleur.ai`, `api.soleur.ai`) will be forced to HTTPS by browsers on the preload list. This is the desired behavior for a production SaaS domain. Document this constraint in `domains.md` as a reminder.
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
- HSTS Preload API: `https://hstspreload.org/api/v2/status?domain=soleur.ai`
- Cloudflare HSTS docs: [developers.cloudflare.com/ssl/edge-certificates/additional-options/http-strict-transport-security](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/http-strict-transport-security/)
- Chromium HSTS preload list: [chromium.googlesource.com/chromium/src/+/main/net/http/transport_security_state_static.json](https://chromium.googlesource.com/chromium/src/+/main/net/http/transport_security_state_static.json)
