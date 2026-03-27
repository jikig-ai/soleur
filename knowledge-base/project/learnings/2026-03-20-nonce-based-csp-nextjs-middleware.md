---
title: Nonce-based CSP migration in Next.js 15 middleware
date: 2026-03-20
category: security-issues
tags: [csp, nonce, middleware, next.js, security-headers, strict-dynamic]
symptoms: "'unsafe-inline' in script-src weakens XSS protection"
module: apps/web-platform
---

# Learning: Nonce-based CSP migration in Next.js 15 middleware

## Problem

The web platform's CSP used `'unsafe-inline'` in `script-src`, making the CSP header security theater -- any injected inline script would execute freely. Next.js injects inline scripts for hydration, so static CSP headers (via `next.config.ts headers()`) cannot use nonces.

## Solution

Moved CSP generation from `next.config.ts` static headers into `middleware.ts` with per-request nonce generation:

1. **New `lib/csp.ts` module** -- pure function `buildCspHeader({ nonce, isDev, supabaseUrl })` builds the complete CSP string with three-tier backward-compatible `script-src`:
   - CSP3: `'strict-dynamic'` ignores fallbacks, only nonce matters
   - CSP2: nonce works, `https:` provides allowlisting
   - CSP1: `'unsafe-inline'` and `https:` apply (no regression)

2. **Middleware generates nonce** -- `Buffer.from(crypto.randomUUID()).toString("base64")` per request. Sets `x-nonce` and `Content-Security-Policy` on request headers for Next.js SSR extraction. Sets `Content-Security-Policy` on response headers via `withCspHeaders()` wrapper.

3. **`withCspHeaders()` wrapper pattern** -- ensures all middleware exit paths carry CSP. A structural test scans the middleware source to verify every return statement calls `withCspHeaders` or `redirectWithCookies` (which wraps `withCspHeaders`).

4. **`security-headers.ts` simplified** -- no longer handles CSP or needs `isDev`/`supabaseUrl` params. Returns only static headers (HSTS, X-Frame-Options, etc.).

## Key Insights

- **Next.js 15 extracts nonces from the CSP header automatically, but ONLY during dynamic rendering** -- setting `Content-Security-Policy` with `'nonce-<value>'` on request headers is sufficient, but the root layout must call `await headers()` (or use another dynamic function) to force dynamic rendering. Static layouts skip nonce extraction entirely, causing `'strict-dynamic'` to block all scripts. See `2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md`.
- **`style-src` must keep `'unsafe-inline'`** -- Next.js injects inline styles that would break with nonce-only style-src. CSS injection is not an XSS vector.
- **`/health` should skip CSP** -- health endpoints return no HTML, so nonce generation is wasted computation for load balancer probes.
- **`http:` in CSP1 fallback is a security regression, not a fallback** -- CSP1 browsers don't support `upgrade-insecure-requests`, so `http:` would allow scripts from any HTTP origin. Use `https:` only.
- **Structural coverage tests prevent CSP gaps** -- regex-based source scanning catches new middleware exit paths that forget `withCspHeaders`. Filter by indentation depth to avoid false positives from nested callback returns.
- **`x-nonce` is a request-only header** -- must never be rendered into HTML or exposed in API responses. Document this constraint with a safety comment.

## Session Errors

1. `npx vitest run` failed due to stale npx cache (`@rolldown/binding-linux-x64-gnu` missing). Project uses `bun test`, not vitest via npx.
2. Structural coverage test regex `return .+` matched nested callback returns (`return request.cookies.getAll()`). Fixed by filtering to middleware-level indentation (2-4 spaces).

## Prevention

- When writing structural source-scanning tests, always account for nested functions and callbacks -- filter by indentation or use AST parsing
- When migrating CSP from static to dynamic, trace every response exit path in middleware before starting implementation
- Always verify which test runner a project uses before running tests (check `package.json` scripts, not assumptions)

## References

- Issue #953, PR #960
- [Next.js CSP Guide (v14/15)](https://nextjs.org/docs/14/app/building-your-application/configuring/content-security-policy)
- [MDN: CSP script-src strict-dynamic](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/script-src)
- Related learnings: `2026-03-20-nextjs-static-csp-security-headers.md`, `2026-03-20-middleware-prefix-matching-bypass.md`
