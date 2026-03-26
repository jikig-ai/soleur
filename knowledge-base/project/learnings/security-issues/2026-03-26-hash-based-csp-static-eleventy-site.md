---
module: Docs Site
date: 2026-03-26
problem_type: security_issue
component: frontend_stimulus
symptoms:
  - "No Content-Security-Policy header on docs site"
  - "Inline scripts execute without restriction"
  - "XSS injection in templates would execute without CSP constraint"
root_cause: missing_validation
resolution_type: code_fix
severity: high
tags: [csp, content-security-policy, xss, static-site, eleventy, sha256, hash-based-csp]
synced_to: [seo-aeo]
---

# Hash-Based CSP for Static Eleventy Sites

## Problem

The docs site at `soleur.ai` (Eleventy on GitHub Pages, proxied through Cloudflare) had no Content-Security-Policy. Inline scripts (Plausible analytics init, newsletter/waitlist form handlers) executed without any CSP restriction. Any XSS injection into a template would execute without constraint.

## Solution

Added a `<meta http-equiv="Content-Security-Policy">` tag to `base.njk` with SHA-256 hashes for inline scripts.

### Why meta tag, not HTTP header

GitHub Pages does not support custom HTTP response headers. Cloudflare could inject headers via Transform Rule or Worker, but that requires Terraform infrastructure changes disproportionate to the task. The meta tag is self-contained in the repo.

### Why hash-based, not nonce-based

Nonces require per-request server-side generation. Eleventy produces static HTML — every visitor gets the same file. A static nonce in HTML is equivalent to no nonce. Hash-based CSP is the correct approach for static sites.

### Implementation

1. Compute SHA-256 hashes of inline scripts using Python (reliable multi-line extraction):

   ```python
   import hashlib, base64, re
   scripts = re.findall(r'<script(?![^>]*(?:type="application/ld\+json"|src=))[^>]*>(.*?)</script>', content, re.DOTALL)
   for script in scripts:
       h = hashlib.sha256(script.encode('utf-8')).digest()
       print(f"sha256-{base64.b64encode(h).decode()}")
   ```

2. Add CSP meta tag **before** the first `<script>` tag (CSP only applies to content after the meta tag).

3. Create `validate-csp.sh` CI script that scans all HTML pages, extracts inline scripts, computes hashes, and verifies they match the CSP.

### Key directives

- `script-src 'self' https://plausible.io 'sha256-...' 'sha256-...'` — only allowlisted scripts execute
- `connect-src 'self' https://buttondown.com https://plausible.io` — fetch() targets
- `style-src 'self' 'unsafe-inline'` — required for 40+ inline style attributes
- `upgrade-insecure-requests` — defense-in-depth for HTTPS
- `object-src 'none'` — block plugins/Flash

## Key Insight

Hash-based CSP on static sites is fragile by design — any whitespace change to an inline script silently breaks the hash and the browser blocks execution. The CI validation script is not optional; it is the critical safety net. Without it, a developer editing an inline script would unknowingly break the site in production with no error visible during local development (CSP violations only appear in the browser console).

## Meta Tag Limitations (Cannot Be Used)

- `strict-dynamic` — silently ignored in meta tags (per MDN spec)
- `frame-ancestors` — only works as HTTP header
- `report-uri` / `report-to` — CSP violations are silent in production
- `sandbox` — ignored in meta tags

## Session Errors

1. **Markdown lint failure on first commit** — `session-state.md` had missing blank lines around headings/lists. Recovery: reformatted file and re-committed. **Prevention:** Always validate markdown formatting when generating session-state files from subagent output.

## Review Findings Addressed

- **Code injection in validation script** — `$INDEX` was interpolated into Python heredoc; fixed by passing via `sys.argv[1]`
- **Single-page validation** — script only checked `index.html`; expanded to scan all HTML pages
- **Missing `upgrade-insecure-requests`** — added to CSP
- **GNU-specific `grep -oP`** — consolidated all HTML parsing into Python for portability
- **SKILL.md not updated** — added `validate-csp.sh` reference to seo-aeo skill

## Cloudflare Bot Fight Mode Conflict (#1149)

Cloudflare's Bot Fight Mode injects an inline `<script>` at the end of every HTML response with per-request tokens (`r`, `t` parameters). This script bootstraps `/cdn-cgi/challenge-platform/scripts/jsd/main.js` for client-side bot fingerprinting. Because the tokens change per request, the script's SHA-256 hash is unpredictable and will always be blocked by hash-based CSP.

**Decision:** Accept as known limitation. The blocked script has no user-facing impact — Cloudflare's server-side bot protections (IP reputation, rate limiting, challenge pages) remain active. Weakening the CSP to accommodate a cosmetic console error would be a net security loss.

**Why not migrate to HTTP header CSP?** Even with Cloudflare HTTP header CSP + nonces, community reports indicate Cloudflare sometimes fails to inject nonces into Bot Fight Mode scripts. The engineering effort (Terraform Transform Rule + Cloudflare Worker) is disproportionate and unreliable.

**Key constraints:**

- Cloudflare only parses nonces from CSP HTTP response headers, not `<meta>` tags
- Bot Fight Mode's JavaScript Detections cannot be independently disabled (all-or-nothing toggle)
- Bot Fight Mode cannot be scoped per-path on free/pro plans (only Super Bot Fight Mode supports WAF Skip actions)

**Generalizable pattern:** CDN-injected scripts (bot detection, analytics, A/B testing) will be blocked by strict hash-based CSP on static sites. This is usually correct behavior — the CSP's purpose is XSS protection, not CDN feature enablement. Accept the console error and document it.

## See Also

- [Nonce-based CSP for Next.js middleware](../2026-03-20-nonce-based-csp-nextjs-middleware.md) — nonce approach for server-rendered sites (contrast with hash approach for static sites)
