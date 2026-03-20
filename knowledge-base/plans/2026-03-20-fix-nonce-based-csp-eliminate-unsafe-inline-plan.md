---
title: "fix(sec): migrate to nonce-based CSP to eliminate unsafe-inline in script-src"
type: fix
date: 2026-03-20
semver: patch
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 7
**Research sources used:** Next.js 15.1.8 official docs (Context7), Next.js with-strict-csp example, MDN CSP spec, Tailwind v4 compatibility docs, 3 project learnings (middleware-prefix-matching, middleware-error-handling, csrf-defense)

### Key Improvements
1. Added concrete middleware implementation pattern with CSP helper function to cover all 6 response exit paths
2. Added `https: http:` CSP1 fallback from official Next.js example (missing from original plan)
3. Added critical implementation detail: middleware must set CSP on `NextResponse.next()` early returns, not just final response -- requires refactoring early returns to use a response wrapper
4. Added structural test for CSP coverage: a test that verifies every middleware exit path includes CSP headers (analogous to the CSRF coverage test pattern from project learnings)
5. Identified potential issue: the official Next.js middleware matcher excludes `api` routes from CSP, but our existing middleware runs on API routes for auth -- plan now clarifies the CSP helper runs on all paths our middleware already handles

### New Considerations Discovered
- The official Next.js with-strict-csp example includes `https: http:` as additional CSP1 fallback in script-src alongside `'unsafe-inline'` -- this provides broader backward compatibility
- Next.js 15 extracts the nonce from the CSP header automatically (documented in Context7 docs) -- no need to manually pass nonce to framework scripts, only to any future `<Script>` components
- The `style-src 'nonce-...'` approach from the official docs conflicts with Next.js inline style injection -- keeping `'unsafe-inline'` for style-src is the correct choice for this app

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

1. **Middleware, not proxy.ts** -- Next.js 16 introduces `proxy.ts` as the recommended CSP mechanism, but this project is on Next.js 15.3.x. The middleware approach is the documented pattern for Next.js 14/15. Context7 confirms this pattern is stable in v15.1.8.

2. **`strict-dynamic` with three-tier backward-compatible fallback** -- The `script-src` directive will be:
   ```
   script-src 'self' 'unsafe-inline' https: http: 'nonce-<value>' 'strict-dynamic'
   ```
   This follows the official Next.js with-strict-csp example and MDN's recommended backward-compatible deployment pattern:
   - **CSP3 browsers** (all modern browsers since 2016): `'strict-dynamic'` causes `'unsafe-inline'`, `'self'`, `https:`, and `http:` to be ignored -- only the nonce matters.
   - **CSP2 browsers**: `'strict-dynamic'` is ignored but the nonce still works. `https:` provides additional allowlisting.
   - **CSP1 browsers**: Only `'unsafe-inline'` and `https:` apply (same as or better than current behavior -- no regression).

3. **`style-src` keeps `'unsafe-inline'`** -- Tailwind v4 generates external CSS files at build time (confirmed via docs), but Next.js itself injects inline styles for layout shifts and hydration. The official Next.js docs show `style-src 'self' 'nonce-...'` but this causes console violations with Next.js inline style injection in practice. Keeping `'unsafe-inline'` for style-src is the pragmatic choice -- style injection is not an XSS vector (CSS cannot execute JavaScript).

4. **Nonce via `x-nonce` request header** -- Standard Next.js pattern confirmed by Context7 v15.1.8 docs. The middleware sets `x-nonce` on request headers; server components read it via `(await headers()).get('x-nonce')`. Next.js 15 automatically extracts the nonce from the CSP header's `'nonce-{value}'` pattern and applies it to framework scripts, page bundles, and inline scripts. No manual nonce passing needed for framework code.

5. **CSP header removed from `next.config.ts`** -- CSP moves entirely to middleware. Other security headers (HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy, COOP, CORP, X-XSS-Protection, X-DNS-Prefetch-Control) remain in `next.config.ts` `headers()` since they are static and do not need per-request values.

6. **Dynamic rendering forced for all pages** -- Nonce-based CSP requires dynamic rendering because the nonce changes per request. The app already uses dynamic rendering (auth checks in middleware redirect unauthenticated users), so this is not a new constraint. Static generation was not in use.

7. **API routes still get CSP** -- The current middleware matcher excludes `/api/webhooks` via `PUBLIC_PATHS`. CSP headers on API JSON responses are harmless (browsers only enforce CSP on document loads). No matcher change needed for API routes.

## Technical Considerations

### Performance

- **Per-request nonce generation**: `crypto.randomUUID()` + base64 encoding is sub-microsecond. No measurable overhead.
- **Dynamic rendering**: Already the case -- no regression. Pages are SSR'd per request for auth.
- **No CDN cache impact**: The app uses a custom Node.js server, not Vercel's edge CDN. No static page caching to invalidate.

### Research Insights: Performance

- The official Next.js middleware matcher config excludes prefetches to avoid unnecessary nonce generation on navigation prefetches. The existing middleware matcher already excludes static assets. Consider adding the `missing` clause to skip `next-router-prefetch` headers if profiling shows middleware latency on navigation.
- `crypto.randomUUID()` uses the V8 built-in CSPRNG -- no extra crypto module import needed. It is available in Node.js 19+ and all modern edge runtimes.

### Security

- **Nonce entropy**: `crypto.randomUUID()` produces 122 bits of entropy (UUID v4), base64-encoded to 24 characters. This exceeds the CSP spec's recommendation of 128 bits -- effectively unguessable.
- **`strict-dynamic` trust propagation**: Scripts loaded by nonce-bearing scripts inherit trust. This is correct for Next.js's bundle loading pattern (a nonce-bearing bootstrap script loads code-split chunks).
- **Development mode**: Development-only directives preserved from current behavior -- React dev tools need them for server-side error stack reconstruction. Not present in production.

### Research Insights: Security

**Best Practices (MDN, OWASP):**
- The `'strict-dynamic'` + nonce approach is CSP Level 3 and is the recommended pattern for modern web applications. It eliminates the need to maintain domain allowlists in `script-src`.
- The backward-compatible fallback chain (`'unsafe-inline' https: 'nonce-...' 'strict-dynamic'`) is explicitly recommended by MDN for gradual CSP deployment. In CSP3 browsers, `'strict-dynamic'` overrides all other source expressions in `script-src` -- the fallbacks only activate in older browsers.
- Nonces must never be exposed to client-side JavaScript. The `x-nonce` header is a request header only (set by middleware on the incoming request) and is not accessible to client-side code. Next.js does not expose request headers to the browser.

**Edge Cases to Handle:**
- **Error pages**: Next.js error pages (`_error`, `not-found`) are rendered server-side and will receive the nonce from the middleware-set headers. No special handling needed.
- **Streaming/Suspense boundaries**: Next.js 15's streaming SSR respects the nonce set during the initial render. Suspense fallbacks and streamed content use the same nonce from the original request.
- **Hot Module Replacement (HMR)**: In dev mode, Next.js HMR uses WebSocket (`connect-src`) and dynamic script loading. The `'strict-dynamic'` directive + nonce covers dynamically loaded scripts. HMR WebSocket is covered by `connect-src 'self'`.

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

### Research Insights: Middleware Response Coverage

**Critical implementation detail:** The existing middleware has **6 distinct response exit paths** that must all carry the CSP header:

1. `NextResponse.next()` for public paths (line 16-17 in current middleware)
2. `NextResponse.next()` for health check (line 21)
3. `NextResponse.next()` with request headers (line 24-26, the main response object)
4. `NextResponse.redirect()` for unauthenticated users (via `redirectWithCookies`)
5. `NextResponse.redirect()` for T&C non-acceptance (via `redirectWithCookies`)
6. Final `response` return (line 100)

**Implementation pattern:** Rather than adding CSP header setting to each exit point, use a helper function that wraps response creation:

```typescript
function withCspHeaders(response: NextResponse, cspValue: string): NextResponse {
  response.headers.set("Content-Security-Policy", cspValue);
  return response;
}
```

Apply this wrapper at every return statement. This is more maintainable than scattering `response.headers.set()` calls and ensures new exit paths cannot forget CSP.

**Learnings applied:**
- From `middleware-prefix-matching-bypass`: The existing `pathname === p || pathname.startsWith(p + "/")` pattern is already correct. No changes needed to path matching.
- From `middleware-error-handling-fail-open-vs-closed`: The T&C query error handling already fails open correctly. CSP header setting should happen before the T&C query, so even if the query fails, the response carries CSP.
- From `csrf-three-layer-defense`: The structural test pattern (scanning for invariant presence) should be applied to CSP -- a test that verifies every middleware response path includes CSP headers.

### Attack Surface Enumeration

All code paths that touch `script-src` or inline script execution:

1. **Next.js framework scripts** -- Hydration bootstrap, code-split chunks. Next.js 15 auto-applies nonce from CSP header (confirmed by Context7 docs: "Next.js extracts the nonce from the Content-Security-Policy header and applies it to framework scripts, page-specific JavaScript bundles, and inline styles/scripts").
2. **No `<Script>` components** -- The app does not use `next/script` or any third-party script tags.
3. **No unsafe innerHTML patterns** -- Grep confirms no raw HTML injection in components.
4. **No inline `<script>` tags in components** -- Grep confirms none.
5. **WebSocket upgrade on `/ws`** -- Not affected by CSP (WebSocket is `connect-src`, already covered).
6. **Supabase JS client** -- Loaded from `node_modules` as a bundled dependency, not via `<script src>`. Under `'strict-dynamic'`, scripts loaded by nonce-bearing bootstrap scripts inherit trust, so bundled code continues to work.

## Acceptance Criteria

- [x] `script-src` in production CSP contains `'nonce-<value>'` and `'strict-dynamic'`, does NOT contain `'unsafe-inline'` as effective policy (may be present as CSP2 fallback but ignored by CSP3 browsers)
- [x] `script-src` in development CSP additionally contains development-only directives
- [x] Every response (including redirects and public pages) carries the CSP header with a fresh nonce
- [x] Nonce is available to server components via `(await headers()).get('x-nonce')` (even though no components currently need it)
- [x] `style-src` retains `'unsafe-inline'` (no change)
- [x] `connect-src` retains Supabase host allowlist (no change)
- [x] All other security headers (HSTS, X-Frame-Options, etc.) still present on responses
- [x] CSP header removed from `next.config.ts` `headers()` (only set in middleware)
- [x] Existing auth and T&C middleware behavior unchanged
- [x] All existing tests pass; new tests cover nonce generation and CSP content
- [ ] No CSP violations in browser console on login, signup, dashboard, chat, billing pages

## Test Scenarios

### Acceptance Tests

- Given a production request, when the response headers are inspected, then `Content-Security-Policy` contains `'nonce-<base64>'` in `script-src` and `'strict-dynamic'`
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

### Research Insights: Additional Test Scenarios

**Structural coverage test (inspired by csrf-coverage.test.ts learning):**
- Given the middleware source code, when scanned for all `NextResponse.next()`, `NextResponse.redirect()`, and `return response` statements, then every exit path is wrapped with CSP header setting. This test prevents future middleware changes from accidentally omitting CSP on new response paths.

**CSP header parsing test:**
- Given a CSP header string from `buildCspHeader`, when parsed directive-by-directive, then each directive is semicolon-separated, properly trimmed, and contains no newlines or double spaces.

**Nonce format test:**
- Given the nonce generation function, when called, then the result matches `/^[A-Za-z0-9+/]+=*$/` (valid base64) and has length >= 22 (sufficient entropy).

## Non-Goals

- Removing `'unsafe-inline'` from `style-src` -- marginal security benefit, higher migration risk. Next.js inline style injection would break.
- Adding `Content-Security-Policy-Report-Only` header -- can be a follow-up if desired
- CSP reporting endpoint (`report-uri` / `report-to`) -- separate infrastructure concern
- Migrating to Next.js 16's `proxy.ts` pattern -- upgrade path, not security fix
- Hash-based CSP (experimental SRI) -- requires Webpack (not Turbopack) and is still experimental in Next.js
- Adding `block-all-mixed-content` -- deprecated in favor of `upgrade-insecure-requests` (already present)

## MVP

### `apps/web-platform/middleware.ts`

The existing middleware gains nonce generation at the top, CSP header construction, and header setting on all response paths (early returns for public paths, redirects, and normal responses).

Key changes:
- Import `buildCspHeader` from a new `lib/csp.ts` module
- Generate nonce via `Buffer.from(crypto.randomUUID()).toString('base64')`
- Build CSP header string once at top of middleware function
- Set `x-nonce` on request headers
- Create helper function `withCspHeaders(response, cspValue)` to avoid repetition
- Ensure ALL 6 response exit paths carry the CSP header
- Set `Content-Security-Policy` on request headers (for Next.js nonce extraction) and on every response

### Research Insights: Middleware Implementation Pattern

The official Next.js v15 pattern (from Context7) sets CSP on both request and response:

```typescript
// On request headers (for Next.js to extract nonce during SSR)
const requestHeaders = new Headers(request.headers);
requestHeaders.set("x-nonce", nonce);
requestHeaders.set("Content-Security-Policy", cspValue);

// On response (for browser enforcement)
const response = NextResponse.next({
  request: { headers: requestHeaders },
});
response.headers.set("Content-Security-Policy", cspValue);
```

For our middleware with multiple exit paths, the request header setup happens once at the top. Each response path then gets CSP via the `withCspHeaders` wrapper.

### `apps/web-platform/lib/csp.ts` (new)

Pure function that builds the CSP header string given a nonce and options (isDev, supabaseUrl). Extracted for testability, following the pattern established by `lib/security-headers.ts`.

```typescript
export function buildCspHeader(options: {
  nonce: string;
  isDev: boolean;
  supabaseUrl: string;
}): string
```

### Research Insights: CSP Directive Construction

Based on the official Next.js with-strict-csp example and current app requirements, the full directive set should be:

```
default-src 'self';
script-src 'self' 'unsafe-inline' https: http: 'nonce-<value>' 'strict-dynamic' [+ dev-only directives];
style-src 'self' 'unsafe-inline';
img-src 'self' blob: data:;
font-src 'self';
connect-src 'self' https://<supabase-host> wss://<supabase-host>;
object-src 'none';
frame-src 'none';
worker-src 'self';
base-uri 'self';
form-action 'self';
frame-ancestors 'none';
upgrade-insecure-requests;
```

Key differences from current static CSP:
- `script-src` gains `'nonce-<value>'`, `'strict-dynamic'`, `https:`, `http:` and loses effective `'unsafe-inline'` (kept only as CSP2 fallback)
- All other directives unchanged

The function should use template literal with `.replace(/\s{2,}/g, " ").trim()` to normalize whitespace (matches official Next.js pattern).

### `apps/web-platform/lib/security-headers.ts`

Remove the CSP directive from the returned headers array. CSP is now middleware-owned. The function continues to return all other security headers for `next.config.ts`.

### `apps/web-platform/next.config.ts`

No changes needed to the `headers()` call -- `buildSecurityHeaders` simply stops returning the CSP header.

### `apps/web-platform/test/csp.test.ts` (new)

Unit tests for `buildCspHeader`:
- Nonce appears in `script-src`
- `'strict-dynamic'` present in `script-src`
- `'unsafe-inline'` present as CSP2 fallback in `script-src`
- `https:` present as CSP1 fallback in `script-src`
- Development-only directives present only in dev
- `connect-src` includes Supabase host (both https and wss)
- `style-src` retains `'unsafe-inline'`
- All required directives present (same 13 directives as current CSP)
- Output string has no double spaces or newlines (whitespace normalization)
- Supabase URL production guard (throws when missing in prod)
- Supabase wildcard fallback in dev
- Nonce format validation (valid base64)

### `apps/web-platform/test/security-headers.test.ts`

Update existing tests: CSP-specific assertions removed or moved to `csp.test.ts`. Non-CSP header assertions remain. Verify the function no longer returns a `Content-Security-Policy` header.

## Dependencies & Risks

- **Dependency**: None -- uses only Node.js built-in `crypto` and existing Next.js middleware APIs.
- **Risk**: Browser console CSP violations on pages with unexpected inline scripts. **Mitigation**: The app has no inline scripts or third-party script tags; grep confirms this. Run browser verification before merging.
- **Risk**: Middleware performance regression from nonce generation. **Mitigation**: `crypto.randomUUID()` is sub-microsecond; negligible.
- **Risk**: Future middleware changes adding new response paths may forget CSP. **Mitigation**: Structural coverage test (see Test Scenarios) catches this at CI time.

## References & Research

### Internal References

- `apps/web-platform/lib/security-headers.ts` -- Current static CSP implementation
- `apps/web-platform/middleware.ts` -- Existing middleware (auth + T&C)
- `apps/web-platform/test/security-headers.test.ts` -- Existing CSP tests
- `knowledge-base/learnings/2026-03-20-nextjs-static-csp-security-headers.md` -- Learning from #946 implementation
- `knowledge-base/learnings/2026-03-20-middleware-prefix-matching-bypass.md` -- Middleware path matching security
- `knowledge-base/learnings/2026-03-20-middleware-error-handling-fail-open-vs-closed.md` -- Middleware error handling patterns
- `knowledge-base/learnings/2026-03-20-csrf-three-layer-defense-nextjs-api-routes.md` -- Structural test pattern for security invariants
- PR #951 -- Original security headers implementation
- Issue #946 -- Parent issue (static CSP)

### External References

- [Next.js CSP Guide (v14/15)](https://nextjs.org/docs/14/app/building-your-application/configuring/content-security-policy) -- Official middleware-based nonce pattern
- [Next.js v15.1.8 CSP docs (Context7)](https://github.com/vercel/next.js/blob/v15.1.8/docs/01-app/02-building-your-application/07-configuring/15-content-security-policy.mdx) -- Verified v15-specific implementation
- [Next.js CSP Guide (v16)](https://nextjs.org/docs/app/guides/content-security-policy) -- Shows proxy.ts (future migration path)
- [MDN: CSP script-src strict-dynamic](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/script-src) -- Backward compatibility matrix for strict-dynamic
- [Next.js with-strict-csp example](https://github.com/vercel/next.js/tree/canary/examples/with-strict-csp) -- Reference implementation (includes `https: http:` fallback)

### Related Work

- Issue #953 -- This issue
- Issue #946 / PR #951 -- Static security headers (predecessor)
- Issue #954 -- HSTS preload list submission (unrelated follow-up)
