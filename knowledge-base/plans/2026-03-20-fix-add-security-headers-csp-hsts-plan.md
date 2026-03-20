---
title: "fix: add security headers (CSP, X-Frame-Options, HSTS)"
type: fix
date: 2026-03-20
semver: patch
---

# fix: add security headers (CSP, X-Frame-Options, HSTS)

## Overview

The web platform at `apps/web-platform/` serves all pages without security response headers. No `Content-Security-Policy`, `X-Frame-Options`, `X-Content-Type-Options`, `Strict-Transport-Security`, `Referrer-Policy`, or `Permissions-Policy` headers are set. Any page can be embedded in an iframe by a malicious site (clickjacking), and there is no defense-in-depth against XSS or MIME-type sniffing.

Closes #946.

## Problem Statement / Motivation

The security review of #933 (PR #940) identified this as a pre-existing gap. While Cloudflare proxy provides some transport-layer protections, the application itself does not set any security headers. This leaves users vulnerable to:

1. **Clickjacking** -- any page (login, signup, setup-key, dashboard, billing) can be framed by a malicious site
2. **XSS amplification** -- no CSP restricts script sources; if an XSS vector is found, there is no second line of defense
3. **MIME-type confusion** -- without `X-Content-Type-Options: nosniff`, browsers may reinterpret response content types
4. **Referrer leakage** -- full URLs (including query parameters with potential tokens) may be sent to external sites

## Proposed Solution

Add security headers via the Next.js `headers()` config in `next.config.ts`. This approach is preferred over middleware-based CSP nonces because:

1. The app uses **no third-party client-side scripts** (no analytics, no tag managers) -- the CSP policy is simple
2. The app uses **Tailwind CSS v4** compiled at build time to external stylesheets -- no inline style injection in production
3. Nonce-based CSP requires **dynamic rendering for all pages**, disabling static optimization and CDN caching -- an unnecessary performance penalty for this app's threat model
4. The `next.config.ts` approach is simpler, testable, and does not require changes to the existing middleware (which handles auth)

### Alternative Considered: Middleware-Based Nonce CSP

The Next.js docs recommend nonce-based CSP via middleware (or proxy.ts in v16) for apps that need strict `script-src` without `'unsafe-inline'`. This was rejected because:

- Requires `'unsafe-eval'` in development regardless
- Forces dynamic rendering on all pages (performance regression)
- The app has no inline scripts to protect against -- all scripts are bundled by Next.js
- Adds complexity to the existing auth middleware

The `'unsafe-inline'` in `script-src` is acceptable here because: (a) Next.js bundles all scripts into hashed files served from `_next/static/`, (b) there are no user-controlled inline script injection points, and (c) the primary risk (clickjacking) is addressed by `frame-ancestors` and `X-Frame-Options` regardless.

**If stricter CSP is desired later** (e.g., for SOC2 compliance), the nonce approach can be added to the existing middleware without changing this header foundation.

## Technical Considerations

### Architecture

- **Delivery mechanism**: `next.config.ts` `headers()` function with `source: '/(.*)'` to cover all routes
- **No middleware changes**: The existing `middleware.ts` handles auth only -- security headers are orthogonal
- **Cloudflare interaction**: Cloudflare proxy (`proxied = true` in `dns.tf`) adds its own headers but does not set CSP, X-Frame-Options, or Referrer-Policy -- these must come from the origin
- **Custom server**: `server/index.ts` delegates to `app.getRequestHandler()` -- Next.js config headers are applied by the handler
- **WebSocket path**: The `/ws` path is handled by the custom server's WebSocket upgrade, not Next.js -- headers config does not apply to WebSocket upgrade requests (this is correct behavior)

### CSP Directives

| Directive | Value | Rationale |
|-----------|-------|-----------|
| `default-src` | `'self'` | Restrict all resource loading to same origin by default |
| `script-src` | `'self' 'unsafe-inline' 'unsafe-eval'` (dev) / `'self' 'unsafe-inline'` (prod) | Next.js bundles all scripts; `unsafe-eval` needed in dev for React error overlays |
| `style-src` | `'self' 'unsafe-inline'` | Tailwind compiles to external CSS, but Next.js/React may inject inline styles for hydration |
| `img-src` | `'self' blob: data:` | Allow self-hosted images, blob URLs, and data URIs |
| `font-src` | `'self'` | No external fonts used |
| `connect-src` | `'self' wss://*.soleur.ai` | API calls to self; WebSocket to same host (wss:// needs explicit allowance in CSP); Supabase JS client runs server-side, not from browser directly (client uses `createBrowserClient` which connects to the Supabase URL) |
| `object-src` | `'none'` | No Flash/Java plugins |
| `base-uri` | `'self'` | Prevent base tag injection |
| `form-action` | `'self'` | Forms only submit to same origin |
| `frame-ancestors` | `'none'` | Prevent all framing (clickjacking protection) |
| `upgrade-insecure-requests` | (directive) | Force HTTPS for all subresources |

**Note on `connect-src`**: The Supabase client (`@supabase/ssr`) in browser context makes API calls to the Supabase URL (injected via `NEXT_PUBLIC_SUPABASE_URL`). This is a build-time environment variable, so the CSP must include the Supabase domain. Since the URL varies between environments, the CSP should be constructed to include it.

### Other Security Headers

| Header | Value | Rationale |
|--------|-------|-----------|
| `X-Frame-Options` | `DENY` | Legacy clickjacking protection (superseded by CSP `frame-ancestors` but still needed for older browsers) |
| `X-Content-Type-Options` | `nosniff` | Prevent MIME-type sniffing |
| `Strict-Transport-Security` | `max-age=63072000; includeSubDomains; preload` | 2-year HSTS with subdomain coverage and preload eligibility |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Send origin only (not full URL) for cross-origin requests; full referrer for same-origin |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=(), browsing-topics=()` | Disable unnecessary browser APIs |
| `X-DNS-Prefetch-Control` | `on` | Allow DNS prefetching for performance |

### Supabase `connect-src` Consideration

The browser-side Supabase client creates fetch requests to `NEXT_PUBLIC_SUPABASE_URL`. Since this is a `NEXT_PUBLIC_` variable inlined at build time, the CSP `connect-src` must include it. Two approaches:

1. **Build-time injection**: Read `NEXT_PUBLIC_SUPABASE_URL` in `next.config.ts` and interpolate into the CSP string
2. **Wildcard**: Use `*.supabase.co` in `connect-src`

Option 1 is preferred -- it is precise and does not open the CSP to all Supabase projects. `next.config.ts` runs at build time and has access to `process.env`.

### Performance

- Zero runtime cost -- headers are set statically via Next.js config
- No middleware overhead -- no per-request nonce generation
- CDN-compatible -- static pages remain cacheable

### Security

- **Clickjacking**: Fully mitigated by `frame-ancestors 'none'` + `X-Frame-Options: DENY`
- **XSS defense-in-depth**: CSP restricts script sources to `'self'`; `'unsafe-inline'` is the weakest point but acceptable given no inline script injection vectors
- **MIME sniffing**: Mitigated by `X-Content-Type-Options: nosniff`
- **Downgrade attacks**: Mitigated by HSTS with 2-year max-age
- **Referrer leakage**: Mitigated by `strict-origin-when-cross-origin` policy

## Acceptance Criteria

- [ ] All HTML responses from the web platform include `Content-Security-Policy` header
- [ ] All HTML responses include `X-Frame-Options: DENY`
- [ ] All HTML responses include `X-Content-Type-Options: nosniff`
- [ ] All HTML responses include `Strict-Transport-Security: max-age=63072000; includeSubDomains; preload`
- [ ] All HTML responses include `Referrer-Policy: strict-origin-when-cross-origin`
- [ ] All HTML responses include `Permissions-Policy: camera=(), microphone=(), geolocation=(), browsing-topics=()`
- [ ] CSP `frame-ancestors 'none'` prevents iframe embedding
- [ ] CSP `connect-src` includes `'self'`, WebSocket (`wss:`), and the Supabase URL
- [ ] CSP allows Next.js scripts and Tailwind-compiled CSS to load without violations
- [ ] `unsafe-eval` is included in `script-src` only in development mode
- [ ] WebSocket connections to `/ws` continue to work (not affected by CSP headers on upgrade requests)
- [ ] Unit tests verify the header configuration structure
- [ ] Existing middleware tests continue to pass

## Test Scenarios

### Unit Tests (`apps/web-platform/test/security-headers.test.ts`)

- Given the `next.config.ts` headers function, when called, then it returns an array with a single entry matching `source: '/(.*)'`
- Given the headers array, when inspected, then `Content-Security-Policy` key is present with all required directives
- Given production mode (`NODE_ENV=production`), when CSP is constructed, then `unsafe-eval` is NOT present in `script-src`
- Given development mode (`NODE_ENV=development`), when CSP is constructed, then `unsafe-eval` IS present in `script-src`
- Given the headers array, when inspected, then `X-Frame-Options` value is `DENY`
- Given the headers array, when inspected, then `Strict-Transport-Security` value contains `max-age=63072000`
- Given the headers array, when inspected, then `X-Content-Type-Options` value is `nosniff`
- Given the headers array, when inspected, then `Referrer-Policy` value is `strict-origin-when-cross-origin`
- Given the CSP header, when `connect-src` is parsed, then it includes `'self'` and `wss:` protocol
- Given a `NEXT_PUBLIC_SUPABASE_URL` environment variable, when CSP is constructed, then `connect-src` includes the Supabase domain

### Integration Verification (Manual/Playwright)

- Given the deployed app, when navigating to `/login`, then response headers include all security headers
- Given the deployed app, when attempting to embed `/login` in an iframe on another domain, then the browser blocks it
- Given the deployed app, when opening the browser console, then no CSP violation errors appear during normal usage
- Given the deployed app, when the WebSocket connects for chat, then no CSP violation errors appear

## Non-Goals

- Nonce-based CSP (can be added later if compliance requires it)
- Report-URI / report-to CSP reporting (future enhancement)
- Subresource Integrity (SRI) -- experimental in Next.js, Webpack-only
- Cloudflare-level header configuration (managed separately via Cloudflare dashboard/API)

## Dependencies and Risks

- **Risk**: `'unsafe-inline'` in `style-src` -- Tailwind compiles to external CSS, but Next.js/React may use inline styles for hydration. If inline styles are not actually needed, this can be tightened later.
- **Risk**: `connect-src` must include the Supabase URL which varies by environment. If the env var is missing at build time, the CSP will be malformed. Mitigation: validate at build time.
- **Dependency**: No new packages required. Uses built-in `next.config.ts` headers API.

## MVP

### `apps/web-platform/next.config.ts`

```typescript
import type { NextConfig } from "next";

const isDev = process.env.NODE_ENV === "development";
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";

// Extract hostname from Supabase URL for CSP connect-src
const supabaseHost = supabaseUrl ? new URL(supabaseUrl).host : "";

const cspDirectives = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline'${isDev ? " 'unsafe-eval'" : ""}`,
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' blob: data:",
  "font-src 'self'",
  `connect-src 'self' wss://${supabaseHost || "*.supabase.co"} https://${supabaseHost || "*.supabase.co"}`,
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
  "upgrade-insecure-requests",
];

const securityHeaders = [
  { key: "Content-Security-Policy", value: cspDirectives.join("; ") },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  {
    key: "Strict-Transport-Security",
    value: "max-age=63072000; includeSubDomains; preload",
  },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  {
    key: "Permissions-Policy",
    value: "camera=(), microphone=(), geolocation=(), browsing-topics=()",
  },
  { key: "X-DNS-Prefetch-Control", value: "on" },
];

const nextConfig: NextConfig = {
  output: undefined,
  serverExternalPackages: ["@anthropic-ai/claude-agent-sdk", "ws"],
  async headers() {
    return [
      {
        source: "/(.*)",
        headers: securityHeaders,
      },
    ];
  },
};

export default nextConfig;
```

### `apps/web-platform/test/security-headers.test.ts`

```typescript
import { describe, test, expect, beforeAll } from "vitest";

// Extract the security headers config for testing
// We test the header values directly rather than importing next.config.ts
// (which has side effects and Next.js type dependencies)

describe("security headers", () => {
  test("CSP includes frame-ancestors 'none'", () => {
    // Verify in the actual config
  });

  test("X-Frame-Options is DENY", () => {
    // Verify header value
  });

  test("HSTS max-age is at least 1 year", () => {
    // Verify header value
  });

  test("CSP does not include unsafe-eval in production", () => {
    // Verify with NODE_ENV=production
  });
});
```

## References

- Issue: #946
- Found during: Security review of #933 (PR #940)
- Next.js headers docs: [nextjs.org/docs/app/api-reference/config/next-config-js/headers](https://nextjs.org/docs/app/api-reference/config/next-config-js/headers)
- Next.js CSP guide: [nextjs.org/docs/app/guides/content-security-policy](https://nextjs.org/docs/app/guides/content-security-policy)
- OWASP Secure Headers: [owasp.org/www-project-secure-headers](https://owasp.org/www-project-secure-headers/)
- Related learning: `knowledge-base/learnings/2026-03-20-open-redirect-allowlist-validation.md`
