---
title: "fix: Cloudflare challenge script blocked by CSP on docs site"
type: fix
date: 2026-03-26
---

# fix: Cloudflare challenge script blocked by CSP on docs site

## Overview

After PR #1145 added a hash-based CSP `<meta>` tag to the docs site, Cloudflare's Bot Management challenge platform script is blocked by the `script-src` directive. The script is injected by Cloudflare's reverse proxy at the end of the HTML body and contains per-request parameters (`r`, `t`), making its SHA-256 hash unpredictable. The blocked script has no user-facing impact -- all site functionality (analytics, forms, styles) works correctly.

Closes #1149.

## Problem Statement / Motivation

The CSP meta tag added in #1145 correctly restricts script execution to allowlisted hashes and domains. However, Cloudflare's Bot Fight Mode injects an inline `<script>` at the end of the HTML body that bootstraps `/cdn-cgi/challenge-platform/scripts/jsd/main.js`. This inline script contains per-request tokens (`r`, `t` parameters), so its SHA-256 hash changes on every request and cannot be pre-computed.

Console error:

```
Executing inline script violates the following Content Security Policy directive 'script-src ...'
Either the 'unsafe-inline' keyword, a hash ('sha256-YYtTAbDJIob3C6UC4gt1N94H3mJJ5DWIo+ZXhlkl78U='), or a nonce ('nonce-...') is required.
```

The error is harmless -- Cloudflare's bot detection being blocked does not affect any user-facing functionality. However, console errors create noise during development and could mask real issues.

## Options Analysis

### Option 1: Accept as known limitation (RECOMMENDED)

**Approach:** Do nothing to the CSP policy. Document the known console error so developers do not waste time investigating it.

**Pros:**

- Zero code changes, zero infrastructure changes
- CSP remains maximally restrictive -- no weakening of script-src
- The blocked script has no user-facing impact (confirmed in issue #1149)
- Cloudflare's bot protection still operates at the network level (challenge pages, rate limiting) even when the client-side script is blocked

**Cons:**

- Console error noise during development
- Cloudflare's client-side bot fingerprinting is degraded (but Cloudflare's server-side protections remain active)

**Risk:** Low. Cloudflare Bot Fight Mode is a free-tier feature that provides basic bot detection. The docs site has no sensitive user data, no authentication, and no forms that process payments. The server-side protections (IP reputation, rate limiting, challenge pages) remain fully functional.

### Option 2: Migrate CSP to HTTP header via Cloudflare Transform Rule

**Approach:** Remove the `<meta>` CSP tag. Add a `cloudflare_ruleset` Terraform resource with `phase = "http_response_headers_transform"` that injects a `Content-Security-Policy` HTTP header for `soleur.ai` requests. This enables `strict-dynamic` and potentially nonce-based CSP via a Cloudflare Worker, which would allow Cloudflare's injected scripts to execute.

**Pros:**

- Enables full CSP feature set (frame-ancestors, report-to, strict-dynamic)
- Cloudflare's bot script would execute normally

**Cons:**

- Requires new Terraform infrastructure module for the docs site (no docs infra module exists today -- DNS for `soleur.ai` apex is managed outside Terraform)
- Requires a Cloudflare Worker to inject per-request nonces into both the CSP header and inline scripts -- significant complexity for a static site
- `strict-dynamic` is not well-suited here: the docs site has exactly 2 inline scripts with stable content, and `strict-dynamic` adds complexity without proportional benefit
- The Cloudflare API token (`cf_api_token`) needs Rulesets Write permission added to its scope
- Ongoing maintenance of Worker code + Terraform resources for a single header
- Disproportionate engineering effort to suppress a harmless console error

**Risk:** Medium. Introduces infrastructure complexity and a new failure mode (Worker errors, Transform Rule misconfiguration) to solve a cosmetic problem.

### Option 3: Disable Cloudflare Bot Fight Mode via Terraform

**Approach:** Add a `cloudflare_bot_management` Terraform resource to disable Bot Fight Mode for the `soleur.ai` zone.

**Pros:**

- Eliminates the console error at the source
- Simple Terraform change

**Cons:**

- Loses Cloudflare's bot detection entirely (both client-side and the Bot Fight Mode server-side protections)
- May require Enterprise plan features to configure granularly (Bot Fight Mode is all-or-nothing on free/pro plans)
- Overkill -- disabling a security feature to suppress a harmless console error

**Risk:** Medium. Reduces security posture to fix a non-issue.

### Option 4: Add Cloudflare challenge domains to script-src

**Approach:** Add `https://challenges.cloudflare.com` and `'unsafe-inline'` to the `script-src` directive to allow Cloudflare's injected scripts.

**Pros:**

- Simple one-line change to `base.njk`

**Cons:**

- Adding `'unsafe-inline'` to `script-src` defeats the entire purpose of hash-based CSP -- any injected script would execute, making the CSP security theater (documented in learning `2026-03-20-nonce-based-csp-nextjs-middleware.md`)
- The external `.js` file could be allowlisted via domain, but the inline bootstrap script requires either `'unsafe-inline'` or an unpredictable hash -- no middle ground with `<meta>` tag CSP

**Risk:** High. Undermines the security value of the CSP.

## Proposed Solution

**Option 1: Accept as known limitation** is the recommended approach.

The implementation consists of three small changes:

1. **Add an HTML comment** in `base.njk` above the CSP meta tag documenting the known Cloudflare console error and why it is acceptable
2. **Update `validate-csp.sh`** to document the known limitation in its output (informational message, not a failure)
3. **Close issue #1149** with the rationale

### Why this is the right call

The CSP was added to protect against XSS, not to enable Cloudflare bot detection. The bot detection script being blocked is a side effect of correct CSP enforcement. Weakening the CSP (`unsafe-inline`, `strict-dynamic` via Worker) or removing bot protection (disable Bot Fight Mode) to suppress a harmless console error violates the principle of least privilege.

If Cloudflare's bot detection becomes critical in the future (e.g., DDoS attacks on the docs site), Option 2 (HTTP header via Transform Rule) becomes justified. Until then, the meta tag approach from #1145 is correct and should not be weakened.

### Implementation Steps

1. **Add documentation comment** in `plugins/soleur/docs/_includes/base.njk`:

   Add an HTML comment above the CSP meta tag explaining the known Cloudflare console error:

   ```html
   <!-- CSP: Cloudflare Bot Fight Mode injects an inline script with per-request
        tokens. This script is intentionally blocked by script-src (its hash is
        unpredictable). The blocked script has no user-facing impact -- see #1149. -->
   <meta http-equiv="Content-Security-Policy" content="...">
   ```

2. **Close #1149** with a comment explaining the decision and linking to this plan.

### Files Modified

| File | Change |
|------|--------|
| `plugins/soleur/docs/_includes/base.njk` | Add HTML comment documenting known Cloudflare CSP console error |

## Technical Considerations

### Cloudflare Bot Fight Mode behavior

Cloudflare's Bot Fight Mode operates at two levels:

1. **Server-side (unaffected by CSP):** IP reputation scoring, rate limiting, challenge page interstitials. These protections work at the Cloudflare edge before the HTML response reaches the browser.
2. **Client-side (blocked by CSP):** An inline script injected into HTML responses that fingerprints the browser environment and reports back to Cloudflare. This is the script being blocked.

Blocking the client-side script degrades Cloudflare's bot detection accuracy but does not disable it entirely. For a static documentation site with no sensitive data, server-side protections are sufficient.

### Future upgrade path

If HTTP-header-based CSP becomes necessary (for `frame-ancestors`, `report-to`, or if bot detection becomes critical), the archived plan `20260326-090444-2026-03-25-feat-add-csp-header-docs-site-plan.md` documents the Cloudflare Transform Rule approach. The upgrade path is:

1. Create a `docs-site/infra/` Terraform module with `cloudflare_ruleset` for `http_response_headers_transform`
2. Move the CSP policy from `<meta>` tag to HTTP header
3. Optionally add a Cloudflare Worker for nonce injection (enables `strict-dynamic`)

This is documented but not recommended until there is a concrete need.

### Why not report-only mode

`Content-Security-Policy-Report-Only` headers allow monitoring CSP violations without blocking scripts. However, `report-only` is not supported in `<meta>` tags (only as HTTP headers). This reinforces that the `<meta>` tag approach is limited but appropriate for the current use case.

## Acceptance Criteria

- [ ] HTML comment in `base.njk` documents the known Cloudflare CSP console error with a reference to #1149
- [ ] No functional regression -- all existing CSP protections remain unchanged
- [ ] `validate-csp.sh` continues to pass (no changes to CSP hashes or directives)
- [ ] Issue #1149 is closed with rationale

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** This is a documentation-only change. The CSP policy is not modified. The recommended approach (accept as known limitation) is the correct security posture -- weakening CSP to suppress a harmless console error would be a net negative. The HTML comment provides institutional memory for future developers who encounter the console error.

## Test Scenarios

- Given the docs site builds with the CSP meta tag, when viewing any page with DevTools Console open, then the Cloudflare challenge script CSP violation appears but all user-facing functionality works correctly (analytics, forms, styles)
- Given the HTML comment is added above the CSP meta tag, when a developer investigates the console error, then the comment explains the known limitation and references #1149
- Given the CSP meta tag is unchanged, when `validate-csp.sh` runs, then all checks pass (no hash changes, no directive changes)

## References & Research

### Internal References

- `plugins/soleur/docs/_includes/base.njk` -- template with CSP meta tag (line 24)
- `plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh` -- CSP validation CI script
- `knowledge-base/project/learnings/security-issues/2026-03-26-hash-based-csp-static-eleventy-site.md` -- learning from CSP implementation
- `knowledge-base/project/plans/archive/20260326-090444-2026-03-25-feat-add-csp-header-docs-site-plan.md` -- original CSP implementation plan (includes Cloudflare upgrade path)
- `.github/workflows/deploy-docs.yml` -- docs deployment pipeline
- PR #1145 -- added the CSP meta tag
- Issue #1149 -- this fix

### External References

- [Cloudflare Bot Fight Mode](https://developers.cloudflare.com/bots/get-started/free/) -- free-tier bot detection
- [MDN: Content-Security-Policy meta tag limitations](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy#csp_in_meta_tags) -- strict-dynamic, report-only not supported in meta tags
- [Cloudflare Community: CSP and challenge scripts](https://community.cloudflare.com/t/csp-and-cloudflare-challenge-platform-scripts/) -- community discussion of the same issue
