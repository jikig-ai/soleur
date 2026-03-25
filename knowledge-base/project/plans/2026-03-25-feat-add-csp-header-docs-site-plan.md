---
title: "feat: add Content-Security-Policy header to docs site"
type: feat
date: 2026-03-25
---

# feat: add Content-Security-Policy header to docs site

## Overview

The docs site at `soleur.ai` (Eleventy on GitHub Pages, proxied through Cloudflare) has no Content-Security-Policy. As the number of inline scripts grows (Plausible analytics init, newsletter form handler, waitlist form handler), adding a CSP provides defense-in-depth against XSS.

Closes #1143.

## Problem Statement / Motivation

Identified during security review of PR #1140 (waitlist signup form). The docs site serves multiple inline scripts and loads an external analytics script from Plausible, but has no CSP constraining which scripts can execute. Any XSS injection into a template would execute without restriction.

The web platform (`app.soleur.ai`) already has a nonce-based CSP (PRs #947, #960, learnings `2026-03-20-nonce-based-csp-nextjs-middleware.md` and `2026-03-20-nextjs-static-csp-security-headers.md`). The docs site is the remaining gap.

## Proposed Solution

Add a `<meta http-equiv="Content-Security-Policy">` tag to `plugins/soleur/docs/_includes/base.njk` with a hash-based policy for inline scripts.

### Why `<meta>` tag, not HTTP header

GitHub Pages does not support custom HTTP response headers. The site is deployed via `actions/deploy-pages` (see `.github/workflows/deploy-docs.yml`). While `soleur.ai` is proxied through Cloudflare (confirmed: DNS resolves to Cloudflare IPs 172.67.188.7, 104.21.7.210), adding a Cloudflare Transform Rule or Worker would require Terraform infrastructure changes and ongoing maintenance for a single header. The `<meta>` tag approach is self-contained in the repo and deploys with zero infrastructure changes.

**`<meta>` CSP limitations to accept:**

- Cannot set `frame-ancestors` (use X-Frame-Options instead, but that also requires HTTP headers -- not available on GitHub Pages)
- Cannot set `report-uri` or `report-to` (no CSP violation reporting)
- These limitations are acceptable for a static documentation site

### Why hash-based, not nonce-based

Nonces require per-request server-side generation. Eleventy produces static HTML -- every visitor gets the same file. A static nonce in HTML is equivalent to no nonce (attacker can read it from the page source). Hash-based CSP is the correct approach for static sites: the browser computes the SHA-256 hash of each inline script and compares it to the allowlisted hashes in the CSP.

### Why not `'unsafe-inline'`

`'unsafe-inline'` defeats the purpose of CSP for script-src -- any injected script would execute. The web platform learning (`2026-03-20-nonce-based-csp-nextjs-middleware.md`) explicitly documents this as "security theater."

## Technical Approach

### Inline Script Inventory

Scripts in `plugins/soleur/docs/_includes/base.njk` that need CSP coverage:

| Line(s) | Type | CSP Treatment |
|---------|------|---------------|
| 24-63 | `<script type="application/ld+json">` (structured data) | **Exempt** -- non-executable script type, not subject to `script-src` |
| 69 | `<script async src="https://plausible.io/js/...">` | Covered by `script-src https://plausible.io` |
| 70 | Inline Plausible init (1 line) | Needs `'sha256-<hash>'` |
| 119-168 | Inline form handler (`handleSignupForm` + event bindings) | Needs `'sha256-<hash>'` |

Other pages (pricing.njk, index.njk, blog posts, etc.) only contain `<script type="application/ld+json">` blocks, which are exempt.

### CSP Policy

```
default-src 'self';
script-src 'self' https://plausible.io 'sha256-<plausible-init-hash>' 'sha256-<form-handler-hash>';
connect-src 'self' https://buttondown.com https://plausible.io;
style-src 'self' 'unsafe-inline';
img-src 'self' data:;
font-src 'self';
base-uri 'self';
form-action 'self' https://buttondown.com;
object-src 'none';
```

**Directive rationale:**

- `script-src`: `'self'` for any future external JS files, `https://plausible.io` for the analytics script, two SHA-256 hashes for the two inline scripts
- `connect-src`: `https://buttondown.com` for newsletter/waitlist form submissions via `fetch()`, `https://plausible.io` for analytics event beacons
- `style-src 'unsafe-inline'`: The site uses `<link rel="stylesheet">` for main CSS but some inline styles exist (e.g., `style="text-align:center"` in pricing.njk line 324). `'unsafe-inline'` for style-src is acceptable -- CSS injection is not an XSS vector (per learning `2026-03-20-nonce-based-csp-nextjs-middleware.md`)
- `form-action`: `'self'` plus `https://buttondown.com` for newsletter form POST targets
- `object-src 'none'`: No plugins/Flash needed
- `img-src 'self' data:`: Self-hosted images plus `data:` URIs if any exist

### Implementation Steps

1. **Compute SHA-256 hashes** of the two inline scripts in `base.njk`:
   - The Plausible init script (line 70, content between `<script>` tags)
   - The form handler script (lines 119-168, content between `<script>` tags)
   - Use: `echo -n '<script content>' | openssl dgst -sha256 -binary | openssl base64 -A`

2. **Add `<meta>` tag** to `plugins/soleur/docs/_includes/base.njk` in the `<head>` section (after the existing meta tags, before the base href).

   Example meta tag (with actual hashes substituted):

   ```html
   <meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self' https://plausible.io 'sha256-<hash1>' 'sha256-<hash2>'; connect-src 'self' https://buttondown.com https://plausible.io; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; base-uri 'self'; form-action 'self' https://buttondown.com; object-src 'none';">
   ```

3. **Build and verify locally**:
   - Run `npx @11ty/eleventy` to build
   - Open `_site/index.html` in a browser
   - Verify no CSP violations in the browser console
   - Test newsletter form submission (verify `connect-src` allows Buttondown)
   - Test Plausible analytics loads (verify `script-src` allows Plausible)

4. **Add hash stability check to CI** (optional enhancement):
   - A script that extracts inline scripts from the built HTML and verifies their hashes match the CSP meta tag
   - This prevents silent CSP breakage when someone edits an inline script without updating the hash
   - Location: `plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh` (alongside existing `validate-seo.sh`)
   - Add to `deploy-docs.yml` after the build step

### Files Modified

| File | Change |
|------|--------|
| `plugins/soleur/docs/_includes/base.njk` | Add `<meta http-equiv="Content-Security-Policy">` tag in `<head>` |
| `plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh` | New: CI script to verify inline script hashes match CSP |
| `.github/workflows/deploy-docs.yml` | Add CSP validation step after build |

## Technical Considerations

### Hash Fragility

SHA-256 hashes are computed from the exact byte content of the inline script. Any change to the script (even whitespace) invalidates the hash and breaks the CSP. This is the primary maintenance risk.

**Mitigation:** The CI validation script (step 4) catches this at build time. If a developer edits an inline script, CI fails with a clear error message explaining how to recompute the hash.

### Future Inline Script Growth

If more inline scripts are added to the docs site, each needs a new hash in the CSP. This scales poorly beyond 3-4 inline scripts.

**Mitigation for the future (not in scope):**

- Move inline scripts to external `.js` files (covered by `'self'`)
- Or use an Eleventy plugin/shortcode that computes hashes at build time and injects them into the CSP meta tag

### `<meta>` CSP Evaluation Order

Per the HTML spec, `<meta http-equiv="Content-Security-Policy">` must appear before any scripts or stylesheets. The proposed placement (early in `<head>`, after charset/viewport meta tags) satisfies this requirement.

### Buttondown Form Action

The newsletter and waitlist forms have `action="https://buttondown.com/api/emails/embed-subscribe/soleur"` but the JavaScript prevents default form submission and uses `fetch()` instead. The `form-action` directive is still set to include `https://buttondown.com` as defense-in-depth -- if JavaScript fails, the native form POST would still work.

## Acceptance Criteria

- [ ] `<meta http-equiv="Content-Security-Policy">` present in built HTML pages
- [ ] No CSP violations in browser console when loading docs site pages (index, pricing, blog posts, agents, skills)
- [ ] Plausible analytics script loads and sends events
- [ ] Newsletter form submission works (Buttondown fetch succeeds)
- [ ] Waitlist form submission works (Buttondown fetch succeeds)
- [ ] `application/ld+json` structured data blocks render without CSP errors
- [ ] CI validation script detects hash mismatches when inline scripts are modified
- [ ] All existing pages build successfully with `npx @11ty/eleventy`

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Straightforward security hardening. The hash-based approach is the correct choice for a static site. The main risk is hash fragility when inline scripts change -- mitigated by the CI validation script. No architectural concerns. The `<meta>` tag limitation (no `frame-ancestors`, no `report-to`) is acceptable for a documentation site with no sensitive user data. Consider extracting inline scripts to external files as a follow-up to reduce hash maintenance burden.

### Product/UX Gate

Not applicable -- no user-facing pages created or modified. The CSP header is invisible to users.

## Test Scenarios

- Given the docs site builds successfully, when viewing any page in a browser, then no CSP violation errors appear in the console
- Given the Plausible analytics script is loaded, when a user visits a page, then the script executes and sends a pageview event to `plausible.io`
- Given the newsletter form is submitted, when the user enters an email and clicks Subscribe, then the `fetch()` to `buttondown.com` succeeds without CSP block
- Given the waitlist form on the pricing page is submitted, when the user enters an email, then the `fetch()` to `buttondown.com` succeeds without CSP block
- Given a developer modifies an inline script in `base.njk`, when CI runs, then the CSP validation script fails with a clear error indicating the hash mismatch
- Given a page contains `<script type="application/ld+json">` blocks, when rendered in the browser, then no CSP error occurs (JSON-LD is exempt from script-src)

## References & Research

### Internal References

- `plugins/soleur/docs/_includes/base.njk` -- template with inline scripts (lines 69-70, 119-168)
- `plugins/soleur/docs/_includes/newsletter-form.njk` -- form template with Buttondown action
- `plugins/soleur/docs/pages/pricing.njk` -- waitlist forms and JSON-LD structured data
- `.github/workflows/deploy-docs.yml` -- deployment pipeline (GitHub Pages)
- `eleventy.config.js` -- Eleventy configuration
- `knowledge-base/project/learnings/2026-03-20-nonce-based-csp-nextjs-middleware.md` -- prior CSP learning (nonce approach for Next.js)
- `knowledge-base/project/learnings/2026-03-20-nextjs-static-csp-security-headers.md` -- prior CSP learning (static approach)

### External References

- [MDN: Content-Security-Policy meta tag](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy#csp_in_meta_tags)
- [MDN: CSP hash-based source](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/script-src#hash-based)
- GitHub Issue: #1143
- Related PRs: #1140 (waitlist signup form, where gap was identified)
