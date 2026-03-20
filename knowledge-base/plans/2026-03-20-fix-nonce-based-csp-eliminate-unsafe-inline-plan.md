---
title: "fix(sec): migrate to nonce-based CSP to eliminate unsafe-inline in script-src"
type: fix
date: 2026-03-20
semver: patch
---

# fix(sec): migrate to nonce-based CSP to eliminate unsafe-inline in script-src

## Overview

The web platform's Content-Security-Policy currently uses `'unsafe-inline'` in `script-src`, which means CSP provides zero protection against XSS -- any injected `<script>` tag executes freely. Migrating to nonce-based CSP generates a cryptographic nonce per request in middleware, sets it on the CSP header, and lets Next.js propagate it to its own inline scripts. Only scripts bearing the correct nonce execute; injected scripts are blocked.

Closes #953.

## Problem Statement / Motivation

Issue #946 (PR #951) added static security headers via `next.config.ts` `headers()`. The CSP necessarily included `'unsafe-inline'` in `script-src` because Next.js injects inline scripts for hydration and the static header approach cannot add per-request nonces. This was filed as a known follow-up in #953.

The current CSP `script-src` is:

```
script-src 'self' 'unsafe-inline'
```

With `'unsafe-inline'`, if an attacker finds an XSS vector (e.g., reflected input, DOM mutation), their injected inline script runs unimpeded. The CSP becomes security theater -- present but not protective.

## Proposed Solution

Move CSP header generation from `next.config.ts` static `headers()` into the existing `middleware.ts`, generating a fresh nonce per request. Use `'strict-dynamic'` alongside the nonce for forward-compatible trust propagation.

### Architecture

**Current flow (static CSP):**
```
next.config.ts headers() -> static CSP on all routes
middleware.ts -> auth/T&C checks only (no CSP involvement)
```

**Proposed flow (nonce-based CSP):**
```
middleware.ts -> generate nonce -> build CSP with nonce -> set on request + response headers
                                                       -> also run auth/T&C checks
next.config.ts headers() -> non-CSP security headers only (HSTS, X-Frame-Options, etc.)
```

The middleware already runs on every non-static request and handles auth. Adding nonce generation there is natural -- no new middleware file needed.

### Key Design Decisions

1. **Middleware, not proxy.ts** -- Next.js 16 introduces `proxy.ts` as the recommended CSP mechanism, but this project is on Next.js 15.3.x. The middleware approach is the documented pattern for Next.js 14/15.

2. **`strict-dynamic` with backward-compatible fallback** -- The `script-src` directive will be:
   ```
   script-src 'self' 'unsafe-inline' 'nonce-<value>' 'strict-dynamic'
   ```
   In CSP3 browsers (all modern browsers since 2016), `'strict-dynamic'` causes `'unsafe-inline'` and `'self'` to be ignored -- only the nonce matters. In CSP2 browsers, `'strict-dynamic'` is ignored but the nonce still works. In CSP1 browsers, only `'unsafe-inline'` applies (same as current behavior -- no regression).

3. **`style-src` keeps `'unsafe-inline'`** -- Tailwind v4 generates external CSS files at build time, but Next.js itself injects some inline styles for layout. Adding nonces to `style-src` requires more invasive changes and provides marginal security benefit (style injection is not an XSS vector). The Next.js docs also recommend `'unsafe-inline'` for `style-src` unless you have specific needs.

4. **Nonce via `x-nonce` request header** -- Standard Next.js pattern. The middleware sets `x-nonce` on request headers; server components read it via `headers().get('x-nonce')`. Next.js 15 automatically extracts the nonce from the CSP header and applies it to framework scripts.

5. **CSP header removed from `next.config.ts`** -- CSP moves entirely to middleware. Other security headers (HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy, COOP, CORP, X-XSS-Protection, X-DNS-Prefetch-Control) remain in `next.config.ts` `headers()` since they are static and do not need per-request values.

6. **Dynamic rendering forced for all pages** -- Nonce-based CSP requires dynamic rendering because the nonce changes per request. The app already uses dynamic rendering (auth checks in middleware redirect unauthenticated users), so this is not a new constraint. Static generation was not in use.

7. **API routes still get CSP** -- The current middleware matcher excludes `/api/webhooks` via `PUBLIC_PATHS`. CSP headers on API JSON responses are harmless (browsers only enforce CSP on document loads). No matcher change needed for API routes.

## Technical Considerations

### Performance

- **Per-request nonce generation**: `crypto.randomUUID()` + base64 encoding is sub-microsecond. No measurable overhead.
- **Dynamic rendering**: Already the case -- no regression. Pages are SSR'd per request for auth.
- **No CDN cache impact**: The app uses a custom Node.js server, not Vercel's edge CDN. No static page caching to invalidate.

### Security

- **Nonce entropy**: `crypto.randomUUID()` produces 122 bits of entropy (UUID v4), base64-encoded to 24 characters. This exceeds the CSP spec's recommendation of 128 bits -- effectively unguessable.
- **`strict-dynamic` trust propagation**: Scripts loaded by nonce-bearing scripts inherit trust. This is correct for Next.js's bundle loading pattern (a nonce-bearing bootstrap script loads code-split chunks).
- **Development mode**: Development-only directives preserved from current behavior -- React dev tools need them for server-side error stack reconstruction. Not present in production.

### Migration Risk

- **Low**: The middleware already exists and handles all non-static requests. Adding nonce generation is additive.
- **CSP Report-Only option**: Could deploy as `Content-Security-Policy-Report-Only` first to detect breakage without blocking. However, given the app uses only first-party scripts and Supabase (connect-src, not script-src), the risk of breakage is minimal.
- **Rollback**: Revert the middleware changes and restore CSP to `next.config.ts`. One-commit revert.

### Interaction with Existing Middleware

The existing middleware handles:
1. Public path bypass (login, signup, callback, webhooks, ws)
2. Health check bypass
3. Supabase auth session refresh
4. T&C acceptance check

The nonce generation and CSP header setting must happen on **every response**, including early returns for public paths and health checks. The nonce must be set on the response headers even when the middleware returns early (redirects, public paths), otherwise those pages would have no CSP at all.

### Attack Surface Enumeration

All code paths that touch `script-src` or inline script execution:

1. **Next.js framework scripts** -- Hydration bootstrap, code-split chunks. Next.js 15 auto-applies nonce from CSP header.
2. **No `<Script>` components** -- The app does not use `next/script` or any third-party script tags.
3. **No unsafe innerHTML patterns** -- Grep confirms no raw HTML injection in components.
4. **No inline `<script>` tags in components** -- Grep confirms none.
5. **WebSocket upgrade on `/ws`** -- Not affected by CSP (WebSocket is `connect-src`, already covered).
6. **Supabase JS client** -- Loaded from `node_modules` as a bundled dependency, not via `<script src>`. Covered by `'self'`.

## Acceptance Criteria

- [ ] `script-src` in production CSP contains `'nonce-<value>'` and `'strict-dynamic'`, does NOT contain `'unsafe-inline'` as effective policy (may be present as CSP2 fallback but ignored by CSP3 browsers)
- [ ] `script-src` in development CSP additionally contains development-only directives
- [ ] Every response (including redirects and public pages) carries the CSP header with a fresh nonce
- [ ] Nonce is available to server components via `headers().get('x-nonce')` (even though no components currently need it)
- [ ] `style-src` retains `'unsafe-inline'` (no change)
- [ ] `connect-src` retains Supabase host allowlist (no change)
- [ ] All other security headers (HSTS, X-Frame-Options, etc.) still present on responses
- [ ] CSP header removed from `next.config.ts` `headers()` (only set in middleware)
- [ ] Existing auth and T&C middleware behavior unchanged
- [ ] All existing tests pass; new tests cover nonce generation and CSP content
- [ ] No CSP violations in browser console on login, signup, dashboard, chat, billing pages

## Test Scenarios

### Acceptance Tests

- Given a production request, when the response headers are inspected, then `Content-Security-Policy` contains `'nonce-<base64>'` in `script-src` and does not contain `'unsafe-inline'` without an accompanying nonce
- Given a development request, when the response headers are inspected, then `script-src` contains development-only directives in addition to the nonce
- Given two sequential requests, when their CSP headers are compared, then the nonce values differ (per-request uniqueness)
- Given a request to a public path (`/login`), when the response is returned, then it still contains the CSP header with a nonce
- Given a request that triggers a redirect (unauthenticated user to `/login`), when the redirect response is inspected, then it contains the CSP header with a nonce

### Regression Tests

- Given the middleware processes a request, when the auth check runs, then Supabase cookies are still correctly refreshed (no regression from #951)
- Given a user who has not accepted T&C, when they visit a protected page, then they are redirected to `/accept-terms` (no regression from T&C enforcement)
- Given a request to `/health`, when the response is returned, then it returns 200 OK (no regression from health check)

### Edge Cases

- Given `NEXT_PUBLIC_SUPABASE_URL` is missing in production, when `buildSecurityHeaders` is called for non-CSP headers, then it throws (production guard preserved)
- Given the nonce contains base64 special characters (`+`, `/`, `=`), when it is embedded in the CSP header, then the header is syntactically valid

## Non-Goals

- Removing `'unsafe-inline'` from `style-src` -- marginal security benefit, higher migration risk
- Adding `Content-Security-Policy-Report-Only` header -- can be a follow-up if desired
- CSP reporting endpoint (`report-uri` / `report-to`) -- separate infrastructure concern
- Migrating to Next.js 16's `proxy.ts` pattern -- upgrade path, not security fix
- Hash-based CSP (experimental SRI) -- requires Webpack (not Turbopack) and is still experimental in Next.js

## MVP

### `apps/web-platform/middleware.ts`

The existing middleware gains nonce generation at the top, CSP header construction, and header setting on all response paths (early returns for public paths, redirects, and normal responses).

Key changes:
- Import `buildCspHeader` from a new `lib/csp.ts` module
- Generate nonce via `Buffer.from(crypto.randomUUID()).toString('base64')`
- Set `x-nonce` on request headers
- Set `Content-Security-Policy` on both request and response headers
- Ensure ALL response paths (public path early return, health check, redirect, normal) set the CSP header

### `apps/web-platform/lib/csp.ts` (new)

Pure function that builds the CSP header string given a nonce and options (isDev, supabaseUrl). Extracted for testability, following the pattern established by `lib/security-headers.ts`.

```typescript
export function buildCspHeader(options: {
  nonce: string;
  isDev: boolean;
  supabaseUrl: string;
}): string
```

### `apps/web-platform/lib/security-headers.ts`

Remove the CSP directive from the returned headers array. CSP is now middleware-owned. The function continues to return all other security headers for `next.config.ts`.

### `apps/web-platform/next.config.ts`

No changes needed to the `headers()` call -- `buildSecurityHeaders` simply stops returning the CSP header.

### `apps/web-platform/test/csp.test.ts` (new)

Unit tests for `buildCspHeader`:
- Nonce appears in `script-src`
- `'strict-dynamic'` present
- `'unsafe-inline'` present (as CSP2 fallback)
- Development-only directives present only in dev
- `connect-src` includes Supabase host
- `style-src` retains `'unsafe-inline'`
- All required directives present

### `apps/web-platform/test/security-headers.test.ts`

Update existing tests: CSP-specific assertions removed or moved to `csp.test.ts`. Non-CSP header assertions remain.

## Dependencies & Risks

- **Dependency**: None -- uses only Node.js built-in `crypto` and existing Next.js middleware APIs.
- **Risk**: Browser console CSP violations on pages with unexpected inline scripts. **Mitigation**: The app has no inline scripts or third-party script tags; grep confirms this. Run browser verification before merging.
- **Risk**: Middleware performance regression from nonce generation. **Mitigation**: `crypto.randomUUID()` is sub-microsecond; negligible.

## References & Research

### Internal References

- `apps/web-platform/lib/security-headers.ts` -- Current static CSP implementation
- `apps/web-platform/middleware.ts` -- Existing middleware (auth + T&C)
- `apps/web-platform/test/security-headers.test.ts` -- Existing CSP tests
- `knowledge-base/learnings/2026-03-20-nextjs-static-csp-security-headers.md` -- Learning from #946 implementation
- PR #951 -- Original security headers implementation
- Issue #946 -- Parent issue (static CSP)

### External References

- [Next.js CSP Guide (v14/15)](https://nextjs.org/docs/14/app/building-your-application/configuring/content-security-policy) -- Official middleware-based nonce pattern
- [Next.js CSP Guide (v16)](https://nextjs.org/docs/app/guides/content-security-policy) -- Shows proxy.ts (future migration path)
- [MDN: CSP script-src strict-dynamic](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/script-src) -- Backward compatibility matrix for strict-dynamic
- [Next.js with-strict-csp example](https://github.com/vercel/next.js/tree/canary/examples/with-strict-csp) -- Reference implementation

### Related Work

- Issue #953 -- This issue
- Issue #946 / PR #951 -- Static security headers (predecessor)
- Issue #954 -- HSTS preload list submission (unrelated follow-up)
