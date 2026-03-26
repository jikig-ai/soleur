---
title: "feat: add Content-Security-Policy header to docs site"
type: feat
date: 2026-03-25
deepened: 2026-03-25
---

# feat: add Content-Security-Policy header to docs site

## Enhancement Summary

**Deepened on:** 2026-03-25
**Sources consulted:** OWASP CSP Cheat Sheet, MDN CSP documentation, web.dev strict CSP guide, Plausible Analytics CSP docs, Eleventy CSP plugin ecosystem, codebase security learnings
**Review agents applied:** security-sentinel, code-simplicity-reviewer, infra-security

### Key Improvements from Research

1. **Critical `strict-dynamic` incompatibility** -- `strict-dynamic` is silently ignored in `<meta>` CSP tags (per MDN spec). The plan correctly avoids it, but this constraint must be documented to prevent future "improvements" that add it.
2. **Meta tag placement must precede the JSON-LD script** -- the current plan says "after charset/viewport meta tags, before base href" but the JSON-LD `<script type="application/ld+json">` at line 24 comes before `<base href="/">` at line 64. While JSON-LD is exempt from `script-src`, placing the CSP meta tag at line 23 (before the JSON-LD block) is the safest position per the spec: "the policy only applies to content processed after the meta tag."
3. **Hash computation must use exact byte content** -- trailing newlines, carriage returns, and leading/trailing whitespace inside `<script>` tags are part of the hash input. The CI validation script must extract content identically to how browsers parse it.
4. **Inline `style=` attributes are pervasive** -- 40+ instances across 10 templates (agents.njk, legal.njk, community.njk, pricing.njk, vision.njk, etc.). `style-src 'unsafe-inline'` is confirmed necessary.
5. **No inline event handlers found** -- no `onclick`, `onload`, etc. across the docs site, so `'unsafe-hashes'` is not needed.
6. **Eleventy CSP plugin exists** -- `@jackdbd/eleventy-plugin-content-security-policy` automates hash computation at build time. Noted as future enhancement to reduce hash maintenance.
7. **`sandbox` directive also unsupported in meta tags** -- in addition to `frame-ancestors` and `report-to/report-uri` (per OWASP and content-security-policy.com).

### New Considerations Discovered

- Chrome DevTools displays the exact required hash when a script is blocked by CSP, useful for debugging hash mismatches during development
- `base-uri 'self'` is compatible with the existing `<base href="/">` tag (relative URL resolves to same origin)
- The Eleventy build must run from the repo root (per learning `2026-03-15-eleventy-build-must-run-from-repo-root.md`) -- the CI validation script must also run from the repo root
- Plausible cloud-hosted analytics requires `script-src https://plausible.io` and `connect-src https://plausible.io` (confirmed via Plausible community docs)

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
- Cannot set `sandbox` (per CSP spec, ignored in meta tags)
- **`strict-dynamic` is silently ignored in meta tags** (per [MDN spec](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/script-src)). Do not add it in the future without migrating to HTTP headers via Cloudflare.
- These limitations are acceptable for a static documentation site with no user-generated content or sensitive data

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

- `script-src`: `'self'` for any future external JS files, `https://plausible.io` for the analytics script, two SHA-256 hashes for the two inline scripts. Note: `'unsafe-inline'` is **not** included -- when hash sources are present, browsers that support CSP Level 2+ ignore `'unsafe-inline'` automatically (per [OWASP CSP Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Content_Security_Policy_Cheat_Sheet.html)). CSP Level 1 browsers (IE Edge legacy, pre-2015 browsers) will block inline scripts entirely -- acceptable for a 2026 documentation site.
- `connect-src`: `https://buttondown.com` for newsletter/waitlist form submissions via `fetch()`, `https://plausible.io` for analytics event beacons (Plausible sends pageview and custom event data back to its servers via XHR/fetch)
- `style-src 'unsafe-inline'`: Required -- 40+ inline `style=` attributes across 10 templates (agents.njk, community.njk, legal.njk, vision.njk, pricing.njk, blog.njk, skills.njk, changelog.njk). CSS injection is not an XSS vector (per learning `2026-03-20-nonce-based-csp-nextjs-middleware.md`)
- `form-action`: `'self'` plus `https://buttondown.com` for newsletter form POST targets
- `object-src 'none'`: No plugins/Flash needed. OWASP recommends always setting this to `'none'` as a baseline.
- `img-src 'self' data:`: Self-hosted images plus `data:` URIs if any exist
- `base-uri 'self'`: Restricts `<base>` tag to same-origin URLs. Compatible with existing `<base href="/">` (relative URL, resolves to same origin).

### Implementation Steps

1. **Compute SHA-256 hashes** of the two inline scripts in `base.njk`:
   - The Plausible init script (line 70, content between `<script>` tags)
   - The form handler script (lines 119-168, content between `<script>` tags)
   - **Hash computation must match browser parsing exactly.** The hash input is the text content between `<script>` and `</script>` tags, including all whitespace, newlines, and indentation. Use `sed` to extract and `openssl` to hash:

   ```bash
   # Extract content between <script> and </script> (preserving exact whitespace)
   # Then compute SHA-256 and base64-encode
   echo -n '<exact script content>' | openssl dgst -sha256 -binary | openssl base64 -A
   ```

   - **Debugging tip:** If a hash doesn't match, open Chrome DevTools Console. Chrome displays the exact required hash in the CSP violation message: `Refused to execute inline script because it violates the following CSP directive: "script-src ...". Either the 'unsafe-inline' keyword, a hash ('sha256-XXXXX'), or a nonce...`

2. **Add `<meta>` tag** to `plugins/soleur/docs/_includes/base.njk` in the `<head>` section. **Critical placement: the meta tag must appear before the first `<script>` tag** (the JSON-LD block at line 24). Insert at line 23, immediately after the Twitter meta tags. Per the [CSP spec](https://content-security-policy.com/examples/meta/), the policy only applies to content processed after the meta tag.

   Example meta tag (with actual hashes substituted):

   ```html
   <meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self' https://plausible.io 'sha256-<hash1>' 'sha256-<hash2>'; connect-src 'self' https://buttondown.com https://plausible.io; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; base-uri 'self'; form-action 'self' https://buttondown.com; object-src 'none';">
   ```

3. **Build and verify locally**:
   - Run `npx @11ty/eleventy` **from the repo root** (per learning `2026-03-15-eleventy-build-must-run-from-repo-root.md`)
   - Open `_site/index.html` in a browser with DevTools Console open
   - Verify no CSP violation errors in the console
   - Test newsletter form submission (verify `connect-src` allows Buttondown `fetch()`)
   - Test Plausible analytics loads (verify `script-src` allows `https://plausible.io` and inline init script)
   - Test pricing page waitlist form (verify it works with CSP)
   - Check that JSON-LD structured data causes no errors (exempt from `script-src`)

4. **Add hash stability check to CI** (required, not optional -- hash breakage is silent in production):
   - A script that extracts inline scripts from the built HTML and verifies their hashes match the CSP meta tag
   - This prevents silent CSP breakage when someone edits an inline script without updating the hash
   - Location: `plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh` (alongside existing `validate-seo.sh`)
   - Add to `deploy-docs.yml` after the "Validate SEO" step and before "Verify build output"
   - The script must run from the repo root and accept `_site` as an argument (same pattern as `validate-seo.sh`)
   - Script logic: (a) extract the CSP meta tag from `_site/index.html`, (b) parse hash values from `script-src`, (c) extract each inline `<script>` block (excluding `type="application/ld+json"`), (d) compute SHA-256 hash of each, (e) verify every computed hash has a matching entry in the CSP, (f) verify no orphan hashes in CSP that match no script
   - Follow shell conventions: `#!/usr/bin/env bash`, `set -euo pipefail`

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

**Research insight (OWASP):** "Using hashes can be a risky approach -- if you change anything inside the script tag (even whitespace) by, e.g., formatting your code, the hash will be different, and the script won't render." This reinforces that the CI validation script is not optional -- it is a required safety net.

### Future Inline Script Growth

If more inline scripts are added to the docs site, each needs a new hash in the CSP. This scales poorly beyond 3-4 inline scripts.

**Mitigation for the future (not in scope):**

- **Preferred:** Move inline scripts to external `.js` files (covered by `'self'`). This eliminates hash management entirely and is the simplest long-term solution.
- **Alternative:** Use [`@jackdbd/eleventy-plugin-content-security-policy`](https://www.npmjs.com/package/@jackdbd/eleventy-plugin-content-security-policy) -- an Eleventy plugin that automatically computes SHA-256 hashes at build time for inline scripts/styles and injects them into the CSP. This would replace both the manual hash computation and the CI validation script.
- **Not recommended:** `strict-dynamic` -- even if the site migrated to HTTP headers (via Cloudflare), `strict-dynamic` with hashes only extends trust to dynamically loaded scripts, which is not needed for this site's static inline scripts.

### `<meta>` CSP Evaluation Order

Per the HTML spec, `<meta http-equiv="Content-Security-Policy">` must appear before any scripts or stylesheets. The CSP meta tag must be placed **before the JSON-LD `<script>` block at line 24** in `base.njk`. While `type="application/ld+json"` scripts are exempt from `script-src`, placing the CSP after them would leave any future executable script additions between lines 23-63 unprotected until they pass the CSP meta tag position.

### Buttondown Form Action

The newsletter and waitlist forms have `action="https://buttondown.com/api/emails/embed-subscribe/soleur"` but the JavaScript prevents default form submission and uses `fetch()` instead. The `form-action` directive is still set to include `https://buttondown.com` as defense-in-depth -- if JavaScript fails, the native form POST would still work.

### Browser Compatibility

Hash-based CSP is a CSP Level 2 feature, supported by all modern browsers (Chrome 40+, Firefox 31+, Safari 10+, Edge 15+). CSP Level 1 browsers (pre-2015) do not support hashes and will fall back to blocking all inline scripts -- this is acceptable for a 2026 documentation site.

No `'unsafe-inline'` fallback is added to `script-src` because it would negate the hash-based protection in CSP Level 2+ browsers (browsers that support both hashes and `'unsafe-inline'` in the same directive correctly ignore `'unsafe-inline'` when hashes are present, but adding it is misleading and creates confusion about the policy's intent).

### No Inline Event Handlers

The docs site uses no inline event handlers (`onclick`, `onload`, `onsubmit`, etc.) -- confirmed by grep across all `.njk` templates. This means `'unsafe-hashes'` is not needed. All interactivity is handled via the form handler script in `base.njk` which uses `addEventListener`.

### Cloudflare Upgrade Path

If HTTP-header-based CSP is needed in the future (for `frame-ancestors`, `report-to`, or `strict-dynamic`), the Cloudflare proxy can be used to inject headers via a Transform Rule (Terraform `cloudflare_ruleset` resource) or a Cloudflare Worker. This would require adding Terraform resources to the web-platform infra or a new docs-specific infra module. The `<meta>` tag approach is the right first step -- it covers the XSS defense use case without infrastructure changes.

## Acceptance Criteria

- [x] `<meta http-equiv="Content-Security-Policy">` present in built HTML pages, positioned before any `<script>` tags
- [x] No CSP violations in browser console when loading docs site pages (index, pricing, blog posts, agents, skills, community, vision, legal, changelog, getting-started)
- [x] Plausible analytics script loads from `https://plausible.io` and sends pageview events
- [ ] Newsletter form submission works -- `fetch()` to `https://buttondown.com` succeeds without CSP block
- [ ] Waitlist form submission works -- `fetch()` to `https://buttondown.com` succeeds without CSP block
- [x] `application/ld+json` structured data blocks render without CSP errors (JSON-LD is exempt from `script-src`)
- [x] Inline `style=` attributes render correctly (40+ instances across templates) -- `style-src 'unsafe-inline'` allows them
- [x] CI validation script (`validate-csp.sh`) detects hash mismatches when inline scripts are modified
- [x] CI validation script detects orphan hashes (hashes in CSP that match no inline script)
- [x] All existing pages build successfully with `npx @11ty/eleventy`
- [x] CSP meta tag does **not** contain `strict-dynamic`, `report-uri`, `report-to`, `frame-ancestors`, or `sandbox` (unsupported in meta tags)

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Straightforward security hardening. The hash-based approach is the correct choice for a static site. The main risk is hash fragility when inline scripts change -- mitigated by the CI validation script. No architectural concerns. The `<meta>` tag limitation (no `frame-ancestors`, no `report-to`) is acceptable for a documentation site with no sensitive user data. Consider extracting inline scripts to external files as a follow-up to reduce hash maintenance burden.

### Product/UX Gate

Not applicable -- no user-facing pages created or modified. The CSP header is invisible to users.

## Test Scenarios

### Functional Tests

- Given the docs site builds successfully, when viewing any page in a browser with DevTools Console open, then no CSP violation errors appear
- Given the Plausible analytics script is loaded, when a user visits a page, then the script executes and sends a pageview event to `plausible.io` (visible in Network tab as a POST to `plausible.io/api/event`)
- Given the newsletter form is submitted, when the user enters an email and clicks Subscribe, then the `fetch()` to `buttondown.com` succeeds without CSP block
- Given the waitlist form on the pricing page is submitted, when the user enters an email, then the `fetch()` to `buttondown.com` succeeds without CSP block
- Given a page contains `<script type="application/ld+json">` blocks, when rendered in the browser, then no CSP error occurs (JSON-LD is exempt from script-src)
- Given a page contains inline `style=` attributes (e.g., `style="background: var(--cat-legal)"`), when rendered in the browser, then styles apply correctly without CSP warnings

### CI Validation Tests

- Given a developer modifies an inline script in `base.njk`, when CI runs `validate-csp.sh`, then the script fails with a clear error indicating the hash mismatch and prints the new hash value
- Given a developer adds a new inline `<script>` to a template without updating the CSP, when CI runs `validate-csp.sh`, then the script fails indicating an unhashed inline script
- Given no inline scripts have changed, when CI runs `validate-csp.sh`, then the script passes with exit code 0

### Edge Cases

- Given the CSP meta tag is positioned at line 23 (before the JSON-LD block), when a new executable `<script>` is added between the meta tags and the JSON-LD block, then CSP enforcement applies to it
- Given a CSP Level 1 browser visits the site, when it encounters hash-based `script-src`, then inline scripts are blocked (acceptable degradation -- no security regression)

## References & Research

### Internal References

- `plugins/soleur/docs/_includes/base.njk` -- template with inline scripts (lines 69-70, 119-168)
- `plugins/soleur/docs/_includes/newsletter-form.njk` -- form template with Buttondown action
- `plugins/soleur/docs/pages/pricing.njk` -- waitlist forms and JSON-LD structured data
- `.github/workflows/deploy-docs.yml` -- deployment pipeline (GitHub Pages)
- `eleventy.config.js` -- Eleventy configuration
- `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` -- existing SEO validation script (pattern to follow for `validate-csp.sh`)
- `knowledge-base/project/learnings/2026-03-20-nonce-based-csp-nextjs-middleware.md` -- prior CSP learning (nonce approach for Next.js)
- `knowledge-base/project/learnings/2026-03-20-nextjs-static-csp-security-headers.md` -- prior CSP learning (static approach)
- `knowledge-base/project/learnings/2026-03-15-eleventy-build-must-run-from-repo-root.md` -- Eleventy CWD requirement
- `knowledge-base/project/learnings/2026-03-10-eleventy-build-fails-in-worktree.md` -- worktree path resolution issues

### External References

- [MDN: Content-Security-Policy meta tag](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy#csp_in_meta_tags)
- [MDN: CSP hash-based source](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/script-src#hash-based)
- [MDN: script-src strict-dynamic](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/script-src) -- documents strict-dynamic meta tag incompatibility
- [OWASP CSP Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Content_Security_Policy_Cheat_Sheet.html) -- hash fragility warnings, best practices
- [web.dev: Strict CSP Guide](https://web.dev/articles/strict-csp) -- hash-based policies for static sites
- [content-security-policy.com: Meta Tag Examples](https://content-security-policy.com/examples/meta/) -- meta tag limitations (frame-ancestors, sandbox, report-uri)
- [content-security-policy.com: CSP Hash Guide](https://content-security-policy.com/hash/) -- hash computation patterns
- [Plausible Analytics CSP Discussion](https://github.com/plausible/analytics/discussions/3714) -- required CSP directives for Plausible
- [`@jackdbd/eleventy-plugin-content-security-policy`](https://www.npmjs.com/package/@jackdbd/eleventy-plugin-content-security-policy) -- Eleventy plugin for automated hash generation (future enhancement)
- GitHub Issue: #1143
- Related PRs: #1140 (waitlist signup form, where gap was identified)
