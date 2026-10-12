---
title: "fix: add security headers (CSP, X-Frame-Options, HSTS)"
type: fix
date: 2026-03-20
semver: patch
deepened: 2026-03-20
---

# fix: add security headers (CSP, X-Frame-Options, HSTS)

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sources consulted:** OWASP Secure Headers Project, Next.js v15 docs (Context7), Supabase browser client source analysis, codebase security learnings
**Review agents applied:** security-sentinel, code-simplicity-reviewer, infra-security, spec-flow-analyzer

### Key Improvements from Research

1. **Critical `connect-src` correction** -- original plan incorrectly stated Supabase client "runs server-side, not from browser directly." Verified 5 browser-side files import `@/lib/supabase/client` (login, signup, dashboard layout, billing, ws-client). CSP `connect-src` must include both `https://` and `wss://` for the Supabase URL (Supabase JS uses WebSocket for realtime subscriptions).
2. **Testability via extraction** -- extract header-building logic into `lib/security-headers.ts` (pure function, no Next.js deps) following the `resolveOrigin()` pattern from the open-redirect learning. Enables direct vitest testing without importing `next.config.ts`.
3. **OWASP compliance** -- add `X-XSS-Protection: 0` to explicitly disable the legacy XSS filter (OWASP recommendation: disable, do not omit). Omitting leaves the header at browser default which can introduce vulnerabilities in older browsers.
4. **`new URL()` crash guard** -- `new URL("")` throws a `TypeError`. The MVP code calls `new URL(supabaseUrl)` on a potentially empty string. Need a try/catch or guard.
5. **API route impact** -- confirmed that `source: '/(.*)'` applies security headers to API routes too (e.g., Stripe webhook at `/api/webhooks/stripe`). This is harmless -- CSP headers are browser-enforced and ignored on non-HTML responses.

### New Considerations Discovered

- Stripe checkout uses redirect (`window.location.href = data.url`), not iframe -- `frame-ancestors 'none'` is safe
- HSTS `preload` is an intentional commitment -- removal from the preload list takes months; document this decision
- Supabase browser client contacts `<project>.supabase.co` for both REST API (`https://`) and realtime subscriptions (`wss://`)
- `form-action 'self'` may block Supabase OAuth redirects if PKCE email magic links use form POST (verified: they use GET redirects, safe)

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

### Research Insights: Approach Validation

**Next.js v15 docs (Context7)** confirm the non-nonce CSP approach for apps without strict inline script requirements. The exact pattern from the official docs uses `headers()` in `next.config.js` with `source: '/(.*)'` and `'unsafe-inline'` in both `script-src` and `style-src`.

**OWASP Secure Headers Project** recommends this exact set of headers as baseline security posture. The project's proposed CSP value aligns with this plan: `default-src 'self'; form-action 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'none'; upgrade-insecure-requests`.

### Alternative Considered: Middleware-Based Nonce CSP

The Next.js docs recommend nonce-based CSP via middleware (or proxy.ts in v16) for apps that need strict `script-src` without `'unsafe-inline'`. This was rejected because:

- Requires `'unsafe-eval'` in development regardless
- Forces dynamic rendering on all pages (performance regression)
- The app has no inline scripts to protect against -- all scripts are bundled by Next.js
- Adds complexity to the existing auth middleware

The `'unsafe-inline'` in `script-src` is acceptable here because: (a) Next.js bundles all scripts into hashed files served from `_next/static/`, (b) there are no user-controlled inline script injection points, and (c) the primary risk (clickjacking) is addressed by `frame-ancestors` and `X-Frame-Options` regardless.

**If stricter CSP is desired later** (e.g., for SOC2 compliance), the nonce approach can be added to the existing middleware without changing this header foundation.

### Alternative Considered: Experimental SRI (Subresource Integrity)

Next.js v14+ offers experimental `sri: { algorithm: 'sha256' }` which adds `integrity` attributes to script tags, enabling hash-based CSP without nonces and without forcing dynamic rendering. Rejected because: (a) experimental/unstable API, (b) Webpack-only (not Turbopack), (c) App Router only, (d) cannot handle dynamically generated scripts. Revisit when the feature stabilizes.

## Technical Considerations

### Architecture

- **Delivery mechanism**: `next.config.ts` `headers()` function with `source: '/(.*)'` to cover all routes
- **Testability**: Extract header-building into `apps/web-platform/lib/security-headers.ts` as a pure function (no Next.js imports). Import from both `next.config.ts` and test files. This follows the `resolveOrigin()` extraction pattern proven in the open-redirect fix (#932).
- **No middleware changes**: The existing `middleware.ts` handles auth only -- security headers are orthogonal
- **Cloudflare interaction**: Cloudflare proxy (`proxied = true` in `dns.tf`) adds its own headers but does not set CSP, X-Frame-Options, or Referrer-Policy -- these must come from the origin. Cloudflare may add `Strict-Transport-Security` if configured in the dashboard, but application-level HSTS provides defense-in-depth regardless.
- **Custom server**: `server/index.ts` delegates to `app.getRequestHandler()` -- Next.js config headers are applied by the handler. The `/health` endpoint at line 16-19 responds directly without the Next.js handler, so it will NOT receive security headers. This is acceptable -- health checks are not browser-navigable.
- **WebSocket path**: The `/ws` path is handled by the custom server's WebSocket upgrade, not Next.js -- headers config does not apply to WebSocket upgrade requests (this is correct behavior)
- **API routes**: The `source: '/(.*)'` pattern applies headers to API routes (e.g., `/api/webhooks/stripe`). Security headers on JSON API responses are harmless -- they are browser-enforced directives that have no effect on non-HTML responses.

### CSP Directives

| Directive | Value | Rationale |
|-----------|-------|-----------|
| `default-src` | `'self'` | Restrict all resource loading to same origin by default |
| `script-src` | `'self' 'unsafe-inline' 'unsafe-eval'` (dev) / `'self' 'unsafe-inline'` (prod) | Next.js bundles all scripts; `unsafe-eval` needed in dev for React error overlays ([Next.js docs](https://nextjs.org/docs/app/guides/content-security-policy)) |
| `style-src` | `'self' 'unsafe-inline'` | Tailwind compiles to external CSS, but Next.js/React may inject inline styles for hydration |
| `img-src` | `'self' blob: data:` | Allow self-hosted images, blob URLs, and data URIs |
| `font-src` | `'self'` | No external fonts used |
| `connect-src` | `'self' https://<supabase-host> wss://<supabase-host>` | Browser-side Supabase client (`lib/supabase/client.ts`) makes REST API calls (`https://`) and realtime subscriptions (`wss://`) to `NEXT_PUBLIC_SUPABASE_URL`. WebSocket to same host (`/ws`) is covered by `'self'`. |
| `object-src` | `'none'` | No Flash/Java plugins |
| `base-uri` | `'self'` | Prevent base tag injection |
| `form-action` | `'self'` | Forms only submit to same origin. Supabase magic link auth uses GET redirects, not form POSTs -- safe. |
| `frame-ancestors` | `'none'` | Prevent all framing (clickjacking protection). Stripe checkout uses redirect, not iframe -- safe. |
| `upgrade-insecure-requests` | (directive) | Force HTTPS for all subresources |

### Research Insights: CSP `connect-src` Deep Dive

**Browser-side Supabase usage verified in 5 files:**

- `app/(auth)/login/page.tsx` -- `supabase.auth.signInWithOtp()` (REST call to Supabase auth endpoint)
- `app/(auth)/signup/page.tsx` -- `supabase.auth.signInWithOtp()` (REST call)
- `app/(dashboard)/layout.tsx` -- `supabase.auth.signOut()` (REST call)
- `app/(dashboard)/dashboard/billing/page.tsx` -- `supabase.auth.getUser()` + `.from("subscriptions")` (REST calls)
- `lib/ws-client.ts` -- `supabase.auth.getSession()` (REST call to get token for app WebSocket)

The Supabase JS client also opens a WebSocket connection to `wss://<project>.supabase.co/realtime/v1/` for realtime subscriptions. While the current app may not use realtime features, the client library opens the connection by default. Including `wss://` for the Supabase host prevents future CSP violations if realtime is enabled.

### Other Security Headers

| Header | Value | Rationale |
|--------|-------|-----------|
| `X-Frame-Options` | `DENY` | Legacy clickjacking protection (superseded by CSP `frame-ancestors` but still needed for older browsers) |
| `X-Content-Type-Options` | `nosniff` | Prevent MIME-type sniffing |
| `Strict-Transport-Security` | `max-age=63072000; includeSubDomains; preload` | 2-year HSTS with subdomain coverage and preload eligibility. **Note**: `preload` is an intentional commitment -- removal from the HSTS preload list takes months. This is appropriate for a production SaaS app served exclusively over HTTPS via Cloudflare. |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Send origin only (not full URL) for cross-origin requests; full referrer for same-origin. OWASP recommends `no-referrer` for maximum privacy, but `strict-origin-when-cross-origin` is the pragmatic choice -- it preserves same-origin referrer data while protecting cross-origin URLs containing tokens. |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=(), browsing-topics=()` | Disable unnecessary browser APIs |
| `X-DNS-Prefetch-Control` | `on` | Allow DNS prefetching for performance |
| `X-XSS-Protection` | `0` | **Explicitly disable** the legacy XSS filter. OWASP recommends `0` (not omission) because the default browser behavior varies and the filter itself can introduce vulnerabilities in older browsers. Modern protection comes from CSP, not this header. |

### Research Insights: Deprecated Headers

Per OWASP Secure Headers Project, these headers should NOT be used:

- **`X-XSS-Protection`**: Set to `0` to disable (we add this). Using `1; mode=block` is actively harmful.
- **`Feature-Policy`**: Replaced by `Permissions-Policy` (we use the modern header).
- **`Expect-CT`**: Obsolete, becoming deprecated.
- **`Public-Key-Pins` (HPKP)**: Risk of domain unavailability. Do not use.

### Supabase `connect-src` Consideration

The browser-side Supabase client (`lib/supabase/client.ts` via `createBrowserClient`) creates fetch requests to `NEXT_PUBLIC_SUPABASE_URL`. Since this is a `NEXT_PUBLIC_` variable inlined at build time, the CSP `connect-src` must include it. Two approaches:

1. **Build-time injection**: Read `NEXT_PUBLIC_SUPABASE_URL` in the header-building function and interpolate into the CSP string
2. **Wildcard**: Use `*.supabase.co` in `connect-src`

Option 1 is preferred -- it is precise and does not open the CSP to all Supabase projects.

**Edge case**: If `NEXT_PUBLIC_SUPABASE_URL` is not set at build time, `new URL("")` throws a `TypeError`. The header-building function must guard against this with a try/catch or conditional, falling back to `*.supabase.co` as a safe default.

### Performance

- Zero runtime cost -- headers are set statically via Next.js config at build time
- No middleware overhead -- no per-request nonce generation
- CDN-compatible -- static pages remain cacheable
- Headers add ~500 bytes to each response (negligible vs. page size)

### Security

- **Clickjacking**: Fully mitigated by `frame-ancestors 'none'` + `X-Frame-Options: DENY`
- **XSS defense-in-depth**: CSP restricts script sources to `'self'`; `'unsafe-inline'` is the weakest point but acceptable given no inline script injection vectors. Future nonce-based CSP can tighten this.
- **MIME sniffing**: Mitigated by `X-Content-Type-Options: nosniff`
- **Downgrade attacks**: Mitigated by HSTS with 2-year max-age + Cloudflare Always Use HTTPS
- **Referrer leakage**: Mitigated by `strict-origin-when-cross-origin` policy
- **Legacy XSS filter**: Explicitly disabled via `X-XSS-Protection: 0` per OWASP guidance

### Research Insights: Attack Surface Verification

**Framing attack surface (all browser-navigable routes):**

- `/login` -- auth form, frameable by default (FIXED by `frame-ancestors 'none'`)
- `/signup` -- auth form with T&C checkbox (FIXED)
- `/setup-key` -- Anthropic API key entry form (FIXED)
- `/dashboard` -- authenticated content (FIXED)
- `/dashboard/billing` -- payment management with Stripe link (FIXED)
- `/dashboard/chat/[id]` -- WebSocket chat (FIXED)
- `/callback` -- auth callback, redirects only -- low framing risk but still protected

**Not browser-navigable (API routes) -- headers applied but inert:**

- `/api/webhooks/stripe` -- Stripe webhook
- `/api/checkout` -- Stripe checkout session creation
- `/api/keys` -- API key management
- `/api/workspace` -- workspace provisioning
- `/health` -- health check (served by custom server, NOT covered by Next.js headers -- acceptable)

## Acceptance Criteria

- [x] All HTML responses from the web platform include `Content-Security-Policy` header
- [x] All HTML responses include `X-Frame-Options: DENY`
- [x] All HTML responses include `X-Content-Type-Options: nosniff`
- [x] All HTML responses include `Strict-Transport-Security: max-age=63072000; includeSubDomains; preload`
- [x] All HTML responses include `Referrer-Policy: strict-origin-when-cross-origin`
- [x] All HTML responses include `Permissions-Policy: camera=(), microphone=(), geolocation=(), browsing-topics=()`
- [x] All HTML responses include `X-XSS-Protection: 0`
- [x] CSP `frame-ancestors 'none'` prevents iframe embedding
- [x] CSP `connect-src` includes `'self'`, and both `https://` and `wss://` for the Supabase host
- [x] CSP allows Next.js scripts and Tailwind-compiled CSS to load without violations
- [x] `unsafe-eval` is included in `script-src` only in development mode
- [x] WebSocket connections to `/ws` continue to work (covered by `'self'` in `connect-src`)
- [x] Header-building logic is extracted to `lib/security-headers.ts` for testability
- [x] Unit tests verify the header configuration structure via the extracted function
- [x] Existing middleware tests continue to pass
- [x] Build-time failure is graceful when `NEXT_PUBLIC_SUPABASE_URL` is not set (falls back to `*.supabase.co`)

## Test Scenarios

### Unit Tests (`apps/web-platform/test/security-headers.test.ts`)

Test the pure `buildSecurityHeaders()` function from `lib/security-headers.ts`:

- Given production mode (`NODE_ENV=production`), when `buildSecurityHeaders()` is called, then the CSP `script-src` does NOT contain `unsafe-eval`
- Given development mode (`NODE_ENV=development`), when `buildSecurityHeaders()` is called, then the CSP `script-src` contains `unsafe-eval`
- Given `NEXT_PUBLIC_SUPABASE_URL=https://abc.supabase.co`, when `buildSecurityHeaders()` is called, then CSP `connect-src` contains `https://abc.supabase.co` and `wss://abc.supabase.co`
- Given `NEXT_PUBLIC_SUPABASE_URL` is empty/undefined, when `buildSecurityHeaders()` is called, then CSP `connect-src` falls back to `https://*.supabase.co` and `wss://*.supabase.co`
- Given the returned headers array, when inspected, then `Content-Security-Policy` contains all required directives: `default-src`, `script-src`, `style-src`, `img-src`, `font-src`, `connect-src`, `object-src`, `base-uri`, `form-action`, `frame-ancestors`, `upgrade-insecure-requests`
- Given the returned headers array, when inspected, then `X-Frame-Options` value is `DENY`
- Given the returned headers array, when inspected, then `Strict-Transport-Security` value contains `max-age=63072000`
- Given the returned headers array, when inspected, then `X-Content-Type-Options` value is `nosniff`
- Given the returned headers array, when inspected, then `Referrer-Policy` value is `strict-origin-when-cross-origin`
- Given the returned headers array, when inspected, then `X-XSS-Protection` value is `0`
- Given the returned headers array, when inspected, then `Permissions-Policy` disables `camera`, `microphone`, `geolocation`, and `browsing-topics`
- Given a malformed `NEXT_PUBLIC_SUPABASE_URL` (e.g., `not-a-url`), when `buildSecurityHeaders()` is called, then it does not throw and falls back to `*.supabase.co`

### Integration Verification (Manual/Playwright)

- Given the deployed app, when navigating to `/login`, then response headers include all 8 security headers
- Given the deployed app, when attempting to embed `/login` in an iframe on another domain, then the browser blocks it
- Given the deployed app, when opening the browser console, then no CSP violation errors appear during normal usage (login, signup, dashboard, chat, billing)
- Given the deployed app, when the WebSocket connects for chat, then no CSP violation errors appear
- Given the deployed app, when Supabase auth calls fire (login via magic link), then no `connect-src` CSP violations appear

## Non-Goals

- Nonce-based CSP (can be added later if compliance requires it)
- Report-URI / report-to CSP reporting (future enhancement -- would enable monitoring violations in production)
- Subresource Integrity (SRI) -- experimental in Next.js, Webpack-only, revisit when stable
- Cloudflare-level header configuration (managed separately via Cloudflare dashboard/API)
- Removing `X-Powered-By` header (Next.js sets this by default; can be disabled with `poweredByHeader: false` in a follow-up)

## Dependencies and Risks

- **Risk**: `'unsafe-inline'` in `style-src` -- Tailwind compiles to external CSS, but Next.js/React may use inline styles for hydration. If inline styles are not actually needed, this can be tightened later by testing without `'unsafe-inline'` and checking for CSP violations.
- **Risk**: `connect-src` must include the Supabase URL which varies by environment. If the env var is missing at build time, the function falls back to `*.supabase.co` (wider but safe).
- **Risk**: HSTS `preload` commits the domain to HTTPS-only for years. Removal from the preload list requires submission to hstspreload.org and takes months. This is the correct choice for a production SaaS app.
- **Dependency**: No new packages required. Uses built-in `next.config.ts` headers API.

## MVP

### `apps/web-platform/lib/security-headers.ts`

Extract header-building into a pure, testable function:

```typescript
/**
 * Build security response headers for the web platform.
 *
 * Pure function with no Next.js dependencies -- importable by both
 * next.config.ts and vitest test files.
 */

interface SecurityHeader {
  key: string;
  value: string;
}

function parseSupabaseHost(url: string): string {
  if (!url) return "";
  try {
    return new URL(url).host;
  } catch {
    return "";
  }
}

export function buildSecurityHeaders(options: {
  isDev: boolean;
  supabaseUrl: string;
}): SecurityHeader[] {
  const { isDev, supabaseUrl } = options;
  const supabaseHost = parseSupabaseHost(supabaseUrl);

  // Use precise host when available, wildcard fallback when not
  const supabaseConnect = supabaseHost
    ? `https://${supabaseHost} wss://${supabaseHost}`
    : "https://*.supabase.co wss://*.supabase.co";

  const cspDirectives = [
    "default-src 'self'",
    `script-src 'self' 'unsafe-inline'${isDev ? " 'unsafe-eval'" : ""}`,
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' blob: data:",
    "font-src 'self'",
    `connect-src 'self' ${supabaseConnect}`,
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "upgrade-insecure-requests",
  ];

  return [
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
    { key: "X-XSS-Protection", value: "0" },
  ];
}
```

### `apps/web-platform/next.config.ts`

```typescript
import type { NextConfig } from "next";
import { buildSecurityHeaders } from "./lib/security-headers";

const securityHeaders = buildSecurityHeaders({
  isDev: process.env.NODE_ENV === "development",
  supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
});

const nextConfig: NextConfig = {
  // Custom server handles HTTP -- disable standalone output
  output: undefined,
  // Allow WebSocket upgrade on the same port
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
import { describe, test, expect } from "vitest";
import { buildSecurityHeaders } from "../lib/security-headers";

function findHeader(headers: { key: string; value: string }[], key: string) {
  return headers.find((h) => h.key === key)?.value ?? "";
}

function parseCspDirective(csp: string, directive: string): string {
  const match = csp.match(new RegExp(`${directive}\\s+([^;]+)`));
  return match?.[1]?.trim() ?? "";
}

describe("buildSecurityHeaders", () => {
  const prodHeaders = buildSecurityHeaders({
    isDev: false,
    supabaseUrl: "https://abc.supabase.co",
  });
  const devHeaders = buildSecurityHeaders({
    isDev: true,
    supabaseUrl: "https://abc.supabase.co",
  });
  const noUrlHeaders = buildSecurityHeaders({
    isDev: false,
    supabaseUrl: "",
  });
  const badUrlHeaders = buildSecurityHeaders({
    isDev: false,
    supabaseUrl: "not-a-url",
  });

  test("CSP contains frame-ancestors 'none'", () => {
    const csp = findHeader(prodHeaders, "Content-Security-Policy");
    expect(csp).toContain("frame-ancestors 'none'");
  });

  test("CSP does not include unsafe-eval in production", () => {
    const csp = findHeader(prodHeaders, "Content-Security-Policy");
    expect(csp).not.toContain("unsafe-eval");
  });

  test("CSP includes unsafe-eval in development", () => {
    const csp = findHeader(devHeaders, "Content-Security-Policy");
    expect(csp).toContain("unsafe-eval");
  });

  test("connect-src includes Supabase host when URL is provided", () => {
    const csp = findHeader(prodHeaders, "Content-Security-Policy");
    const connectSrc = parseCspDirective(csp, "connect-src");
    expect(connectSrc).toContain("https://abc.supabase.co");
    expect(connectSrc).toContain("wss://abc.supabase.co");
  });

  test("connect-src falls back to wildcard when URL is empty", () => {
    const csp = findHeader(noUrlHeaders, "Content-Security-Policy");
    const connectSrc = parseCspDirective(csp, "connect-src");
    expect(connectSrc).toContain("https://*.supabase.co");
    expect(connectSrc).toContain("wss://*.supabase.co");
  });

  test("does not throw on malformed Supabase URL", () => {
    expect(badUrlHeaders.length).toBeGreaterThan(0);
    const csp = findHeader(badUrlHeaders, "Content-Security-Policy");
    expect(csp).toContain("*.supabase.co");
  });

  test("X-Frame-Options is DENY", () => {
    expect(findHeader(prodHeaders, "X-Frame-Options")).toBe("DENY");
  });

  test("HSTS max-age is 2 years", () => {
    expect(findHeader(prodHeaders, "Strict-Transport-Security")).toContain(
      "max-age=63072000",
    );
  });

  test("X-Content-Type-Options is nosniff", () => {
    expect(findHeader(prodHeaders, "X-Content-Type-Options")).toBe("nosniff");
  });

  test("Referrer-Policy is strict-origin-when-cross-origin", () => {
    expect(findHeader(prodHeaders, "Referrer-Policy")).toBe(
      "strict-origin-when-cross-origin",
    );
  });

  test("X-XSS-Protection is explicitly 0", () => {
    expect(findHeader(prodHeaders, "X-XSS-Protection")).toBe("0");
  });

  test("Permissions-Policy disables dangerous APIs", () => {
    const pp = findHeader(prodHeaders, "Permissions-Policy");
    expect(pp).toContain("camera=()");
    expect(pp).toContain("microphone=()");
    expect(pp).toContain("geolocation=()");
  });

  test("returns all required headers", () => {
    const keys = prodHeaders.map((h) => h.key);
    expect(keys).toContain("Content-Security-Policy");
    expect(keys).toContain("X-Frame-Options");
    expect(keys).toContain("X-Content-Type-Options");
    expect(keys).toContain("Strict-Transport-Security");
    expect(keys).toContain("Referrer-Policy");
    expect(keys).toContain("Permissions-Policy");
    expect(keys).toContain("X-DNS-Prefetch-Control");
    expect(keys).toContain("X-XSS-Protection");
  });
});
```

## References

- Issue: #946
- Found during: Security review of #933 (PR #940)
- Next.js headers docs: [nextjs.org/docs/app/api-reference/config/next-config-js/headers](https://nextjs.org/docs/app/api-reference/config/next-config-js/headers)
- Next.js CSP guide: [nextjs.org/docs/app/guides/content-security-policy](https://nextjs.org/docs/app/guides/content-security-policy)
- OWASP Secure Headers Project: [owasp.org/www-project-secure-headers](https://owasp.org/www-project-secure-headers/)
- Related learning: `knowledge-base/project/learnings/2026-03-20-open-redirect-allowlist-validation.md` (extraction pattern for testability)
- Related learning: `knowledge-base/project/learnings/2026-03-20-safe-tools-allowlist-bypass-audit.md` (defense-in-depth approach)
