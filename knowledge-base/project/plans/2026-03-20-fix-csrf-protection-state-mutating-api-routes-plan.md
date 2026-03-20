---
title: "fix: add CSRF protection to state-mutating API routes"
type: fix
date: 2026-03-20
semver: patch
---

# fix: add CSRF protection to state-mutating API routes

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 7
**Research sources used:** Next.js v15 docs (Context7), Supabase SSR docs (Context7), 4 institutional learnings, 3 web research sources

### Key Improvements
1. Added `next.config.ts` `serverActions.allowedOrigins` configuration for future-proofing (Next.js built-in CSRF for Server Actions)
2. Strengthened `validateOrigin` with log sanitization pattern from existing `resolveOrigin` (prevents log injection via crafted Origin headers)
3. Added explicit SECURITY comments on cookie config options per learning from adjacent-config-audit pattern (prevents accidental removal during refactors)
4. Added `workspace/route.ts` request parameter fix -- currently `POST()` takes no `request` argument, needs signature change to access headers
5. Added negative-space test for attack surface enumeration per institutional learning

### New Considerations Discovered
- `app/api/workspace/route.ts` has `POST()` with no `request` parameter -- it cannot read headers without a signature change
- Next.js `serverActions.allowedOrigins` config should be set as defense-in-depth even though no Server Actions exist yet
- The `console.warn` in origin rejection should sanitize the logged origin value (same pattern as `resolve-origin.ts` line 14)
- Config block diff verification needed when touching cookie options (learning: adjacent config options are collateral damage in refactors)

## Overview

The web platform has four API route handlers and a WebSocket endpoint, three of which accept POST requests that mutate state (checkout, keys, workspace). None of these routes validate the request Origin header, and the Supabase SSR cookie configuration uses library defaults (`sameSite: "lax"`, `secure: false`, `httpOnly: false`) without explicit overrides. This leaves the application reliant on implicit browser defaults for CSRF protection rather than explicit server-side enforcement.

Closes #945

## Problem Statement

Next.js does **not** provide built-in CSRF protection for custom API route handlers (`route.ts`). The official Next.js security guide explicitly states: "When Custom Route Handlers are used instead, extra auditing can be necessary since CSRF protection has to be done manually there."

Currently:

1. **No Origin header validation** -- Any cross-origin site can submit POST requests to `/api/checkout`, `/api/keys`, and `/api/workspace`. While `SameSite=Lax` cookies provide partial protection (browsers do not send cookies on cross-site POST from `<form>` or `fetch`), this relies on browser behavior rather than server enforcement.
2. **Implicit cookie defaults** -- `@supabase/ssr` defaults to `sameSite: "lax"`, `secure: false`, `httpOnly: false`. The `secure: false` default means cookies are sent over plaintext HTTP in production if HTTPS terminates upstream (e.g., at Cloudflare). The code never explicitly sets these values.
3. **No defense-in-depth** -- A single layer (browser SameSite enforcement) is the entire CSRF defense. If a browser bug, misconfigured proxy, or subdomain compromise bypasses SameSite, there is no fallback.

### Research Insights

**Next.js Server Actions CSRF mechanism (for reference):**
Next.js Server Actions compare the `Origin` header to the `Host` header (or `X-Forwarded-Host`). If they don't match, the request is aborted. This is the pattern we replicate for custom route handlers. Next.js also supports `serverActions.allowedOrigins` in `next.config.ts` for reverse proxy scenarios -- we should set this as future-proofing even though no Server Actions exist yet.

**Supabase SSR cookie defaults (confirmed via Context7 + GitHub issue #40):**

| Property | Default | Our Override |
|----------|---------|-------------|
| `sameSite` | `"lax"` | `"lax"` (explicit) |
| `secure` | `false` | `true` in production |
| `httpOnly` | `false` | `false` (required for Supabase JS client) |
| `path` | `"/"` | `"/"` (explicit) |
| `maxAge` | ~400 days | default (no change) |

### Attack Surface Enumeration

Per institutional learning "Enumerate full attack surface when fixing security boundaries" -- we list ALL code paths, not just the reported vector.

**State-mutating API routes (need CSRF protection):**

| Route | Method | Auth | Mutation | Origin Access |
|-------|--------|------|----------|---------------|
| `app/api/checkout/route.ts` | POST | Supabase cookie | Creates Stripe checkout session | Has `request` param |
| `app/api/keys/route.ts` | POST | Supabase cookie | Stores encrypted API key in DB | Has `request` param |
| `app/api/workspace/route.ts` | POST | Supabase cookie | Provisions user workspace | **No `request` param -- needs signature change** |

**Excluded from CSRF protection (different auth mechanism):**

| Route | Method | Auth | Reason |
|-------|--------|------|--------|
| `app/api/webhooks/stripe/route.ts` | POST | Stripe signature | Server-to-server; no cookies |
| `app/(auth)/callback/route.ts` | GET | OAuth code exchange | GET (read); already has origin validation via `resolveOrigin` |
| `server/ws-handler.ts` | WebSocket | Token in first message | Not HTTP; uses explicit token auth |

**Cookie configuration locations (need hardening):**

| File | Context |
|------|---------|
| `middleware.ts` | `createServerClient` in middleware -- no `cookieOptions` set |
| `lib/supabase/server.ts` | `createClient()` for route handlers -- no `cookieOptions` set |

**Allowlist bypass audit (per learning: audit allowlists when tightening deny-by-default):**

| Bypass | Status | Notes |
|--------|--------|-------|
| `PUBLIC_PATHS` in middleware | Safe | Skips auth check but does not affect CSRF; CSRF check is per-route, not in middleware |
| Stripe webhook signature | Safe | Uses its own signature verification; no cookies involved |
| WebSocket token auth | Safe | Explicit token in first message; not cookie-based |

## Proposed Solution

Three-layer CSRF defense:

### Layer 1: Origin Header Validation Utility

Create a reusable `validateOrigin` function and apply it at the top of every mutating API route handler. The function:

1. Reads the `Origin` header from the request (falls back to `Referer` header for older clients)
2. Compares against the same allowlist used by `resolveOrigin` (`PRODUCTION_ORIGINS` / `DEV_ORIGINS`)
3. Returns 403 if the origin does not match

This mirrors what Next.js Server Actions do internally (compare Origin to Host/X-Forwarded-Host) but applied to custom route handlers.

**Why per-route utility vs. middleware-level:** The existing `middleware.ts` runs for all routes but bypasses public paths including `/api/webhooks`. A per-route utility function is simpler and avoids accidentally blocking the Stripe webhook (which must accept cross-origin POSTs from Stripe servers with no Origin header).

### Research Insights

**Best Practices:**
- Next.js official proxy middleware example uses `request.headers.get('origin')` with an allowlist array and `includes()` check -- our `Set.has()` approach is equivalent but O(1) lookup instead of O(n)
- The Next.js authentication guide recommends cookie options: `httpOnly: true, secure: true, sameSite: 'lax', path: '/'` -- we match all except `httpOnly` which breaks Supabase client
- Log sanitization: the existing `resolveOrigin` sanitizes logged values with `.slice(0, 100).replace(/[\x00-\x1f]/g, "")` -- the new `validateOrigin` must use the same pattern to prevent log injection attacks via crafted Origin headers

**Edge Cases from Framework Docs:**
- Next.js `serverActions.allowedOrigins` accepts wildcard patterns (e.g., `*.my-proxy.com`) -- but our custom validation uses exact string matching, which is stricter and correct for our use case
- `@supabase/ssr` chunks large tokens across multiple cookies (named `key.0`, `key.1`, etc.) -- the `cookieOptions` apply to all chunks automatically via `setAll`

### Layer 2: Explicit SameSite Cookie Configuration

Add `cookieOptions` to both `createServerClient` call sites:

```typescript
cookieOptions: {
  // SECURITY: explicit SameSite prevents cross-site cookie transmission
  sameSite: "lax" as const,
  // SECURITY: secure flag prevents cookie leakage over HTTP
  secure: process.env.NODE_ENV === "production",
  path: "/",
},
```

This makes the security posture explicit and ensures `secure: true` in production (cookies only sent over HTTPS).

**Why not `httpOnly: true`:** Supabase SSR needs JavaScript access to the auth token for client-side operations. Setting `httpOnly: true` would break the Supabase client. The Supabase SSR docs explicitly show `httpOnly: false` as the intended pattern.

**Why not `sameSite: "strict"`:** Strict blocks cookies on all cross-site navigations including top-level GET navigations (e.g., clicking a link from email to the dashboard). `Lax` is the correct setting for auth cookies that need to survive navigation.

### Research Insights

**Institutional Learning: Adjacent config options are collateral damage in refactors** (from `2026-03-20-security-refactor-adjacent-config-audit.md`):

When adding `cookieOptions`, add inline `SECURITY:` comments on each option explaining its purpose. This prevents future refactors from accidentally removing security-critical configuration. The learning documents a case where `settingSources: []` was accidentally removed during a refactor because it was visually adjacent to the code being changed.

```typescript
// Pattern: mark security options with inline comments
cookieOptions: {
  sameSite: "lax" as const,  // SECURITY: blocks cross-site cookie transmission
  secure: process.env.NODE_ENV === "production",  // SECURITY: HTTPS-only in production
  path: "/",
},
```

**Pre-commit verification:** After implementing, run a diff comparison to verify no existing cookie behavior was accidentally changed:

```bash
git diff apps/web-platform/middleware.ts apps/web-platform/lib/supabase/server.ts
```

### Layer 2b: next.config.ts `serverActions.allowedOrigins`

As defense-in-depth for future Server Action adoption, add the `allowedOrigins` config:

```typescript
const nextConfig: NextConfig = {
  output: undefined,
  serverExternalPackages: ["@anthropic-ai/claude-agent-sdk", "ws"],
  serverActions: {
    allowedOrigins: ["app.soleur.ai"],
  },
};
```

This is a zero-cost config change that protects against future CSRF if Server Actions are introduced.

### Layer 3: CSRF Token (Defense-in-Depth) -- Deferred

After evaluating the trade-offs, a CSRF token mechanism is **not recommended for v1**:

- The application uses no `<form>` submissions -- all mutations go through `fetch()` with JSON bodies from same-origin React components
- Origin validation + SameSite=Lax provides strong protection for `fetch()`-based APIs
- CSRF tokens add complexity (token generation, storage, rotation, client distribution) with marginal benefit given the architecture
- Next.js Server Actions intentionally do not use CSRF tokens, relying on Origin validation instead

If the application later adds `<form>` POST submissions or Server Actions, CSRF tokens should be reconsidered.

## Technical Considerations

### Architecture

- The `resolveOrigin` module (`lib/auth/resolve-origin.ts`) already maintains the origin allowlist. The new `validateOrigin` function should reuse the same allowlist to avoid duplication.
- Extract the allowlist into a shared constant (e.g., `lib/auth/allowed-origins.ts`) imported by both `resolveOrigin` and `validateOrigin`.
- `app/api/workspace/route.ts` currently declares `POST()` with no parameters. It must be changed to `POST(request: Request)` to access headers for Origin validation. This is a safe change -- Next.js always passes the Request object; the route handler was simply not destructuring it.

### Edge Cases

1. **Missing Origin header** -- Some legitimate requests (older browsers, privacy extensions) may omit the Origin header. The implementation should fall back to the `Referer` header. If neither is present, reject the request (fail-closed).
2. **Stripe webhook** -- Must NOT have Origin validation (Stripe sends no Origin header). The webhook route is already excluded from auth middleware via `PUBLIC_PATHS` and uses its own signature verification.
3. **WebSocket connections** -- Authenticated via explicit token in the first message, not cookies. No Origin validation needed on the WebSocket upgrade itself (the WS handler already requires a valid Supabase token).
4. **Development mode** -- Must accept `http://localhost:3000` as a valid origin (already handled by `DEV_ORIGINS` in `resolve-origin.ts`).
5. **Malformed Referer URL** -- The `new URL(referer)` call in the Referer fallback path must be wrapped in try/catch to handle malformed Referer values gracefully (already present in the MVP code).
6. **Case sensitivity** -- Origin headers should be compared case-insensitively. The allowlist uses lowercase; the `validateOrigin` function calls `.toLowerCase()` on the incoming origin.

### Performance

- Origin validation is a string comparison against a Set -- O(1) lookup, zero measurable overhead.
- Cookie option changes are configuration-only -- no runtime cost.
- No external dependencies introduced.

### Security

- Fail-closed: missing Origin + missing Referer = 403
- Allowlist-based: only known origins are accepted (not a blocklist)
- Production `secure: true`: prevents cookie leakage over HTTP
- Log sanitization: origin values truncated and control characters stripped before logging (same pattern as `resolve-origin.ts`)

### Research Insights

**Institutional Learning: Defense-in-depth requires programmatic guards, not just documentation** (from `2026-03-15-env-var-post-guard-defense-in-depth.md`):

The CSRF protection follows the same two-key principle documented in the env var post guard learning: the browser must both send cookies AND pass Origin validation. Neither alone is sufficient. SameSite cookies are the "browser cooperates" layer; Origin validation is the "server verifies" layer. This is structurally equivalent to the `*_ALLOW_POST` pattern used in community scripts.

**Institutional Learning: Enumerate full attack surface** (from `2026-03-20-security-fix-attack-surface-enumeration.md`):

The attack surface table above was expanded to include ALL code paths, not just the three routes mentioned in the issue. The WebSocket handler and auth callback were explicitly evaluated and documented as excluded with justification. A negative-space test should verify that every POST route handler either includes origin validation or is documented as exempt.

## Acceptance Criteria

- [x] All three mutating API routes (`/api/checkout`, `/api/keys`, `/api/workspace`) validate the Origin header and return 403 for cross-origin requests
- [x] Origin validation falls back to Referer header when Origin is absent
- [x] Requests with neither Origin nor Referer header are rejected with 403
- [x] `app/api/workspace/route.ts` POST handler accepts `request: Request` parameter
- [x] Stripe webhook route (`/api/webhooks/stripe`) is NOT affected by Origin validation
- [x] Auth callback route (`/callback`) is NOT affected (GET-only, already has origin validation)
- [x] Supabase cookie configuration explicitly sets `sameSite: "lax"` and `secure: true` (production) in both `middleware.ts` and `lib/supabase/server.ts`
- [x] Cookie options include inline `SECURITY:` comments explaining each setting's purpose
- [x] `next.config.ts` includes `serverActions.allowedOrigins` for defense-in-depth
- [x] Logged origin values are sanitized (truncated, control characters stripped)
- [x] Existing tests continue to pass
- [x] New tests cover Origin validation (valid origin, invalid origin, missing origin, Referer fallback)
- [x] New tests verify cookie options are set correctly
- [x] Negative-space test: every POST route is either origin-validated or documented as exempt

## Test Scenarios

### Origin Validation

- Given a POST to `/api/checkout` with `Origin: https://app.soleur.ai`, when the user is authenticated, then the request proceeds normally (200)
- Given a POST to `/api/keys` with `Origin: https://evil.com`, when the user is authenticated, then the request is rejected (403)
- Given a POST to `/api/workspace` with no Origin header but `Referer: https://app.soleur.ai/dashboard`, when the user is authenticated, then the request proceeds normally (200)
- Given a POST to `/api/keys` with neither Origin nor Referer headers, when the user is authenticated, then the request is rejected (403)
- Given a POST to `/api/webhooks/stripe` with no Origin header, when a valid Stripe signature is present, then the request proceeds normally (200)
- Given a POST to `/api/checkout` with `Origin: http://localhost:3000` in development mode, when the user is authenticated, then the request proceeds normally (200)
- Given a POST to `/api/checkout` with `Origin: HTTP://LOCALHOST:3000` in development mode, when the user is authenticated, then the request proceeds normally (case-insensitive)
- Given a POST to `/api/keys` with `Origin: https://app.soleur.ai.evil.com`, when the user is authenticated, then the request is rejected (403, subdomain spoofing)
- Given a POST with `Referer: not-a-valid-url`, when neither Origin is present, then the request is rejected (403, malformed Referer)

### Research Insights: Additional Test Scenarios

- Given any POST route handler exists in `app/api/`, then it either calls `validateOrigin` or is in the explicit exemption list (negative-space enumeration test)
- Given the origin value contains control characters (`\x00-\x1f`), when logged, then control characters are stripped (log injection prevention)

### Cookie Configuration

- Given the middleware creates a Supabase server client, when cookies are set, then `sameSite` is `"lax"` and `secure` matches the production flag
- Given the route handler creates a Supabase server client via `createClient()`, when cookies are set, then `sameSite` is `"lax"` and `secure` matches the production flag

## Non-Goals

- CSRF token implementation (deferred -- see Layer 3 rationale)
- Changes to the WebSocket authentication mechanism
- Changes to the Stripe webhook verification
- Adding CORS headers (separate concern; the application is same-origin only)
- `httpOnly` cookie flag (breaks Supabase client-side auth)

## MVP

### `lib/auth/allowed-origins.ts` (new)

```typescript
const PRODUCTION_ORIGINS = new Set(["https://app.soleur.ai"]);
const DEV_ORIGINS = new Set(["https://app.soleur.ai", "http://localhost:3000"]);

export function getAllowedOrigins(): Set<string> {
  return process.env.NODE_ENV === "development" ? DEV_ORIGINS : PRODUCTION_ORIGINS;
}
```

### `lib/auth/validate-origin.ts` (new)

```typescript
import { getAllowedOrigins } from "./allowed-origins";

export function validateOrigin(request: Request): { valid: boolean; origin: string | null } {
  const origin = request.headers.get("origin");
  const referer = request.headers.get("referer");
  const allowed = getAllowedOrigins();

  if (origin) {
    return { valid: allowed.has(origin.toLowerCase()), origin };
  }

  if (referer) {
    try {
      const refererOrigin = new URL(referer).origin;
      return { valid: allowed.has(refererOrigin.toLowerCase()), origin: refererOrigin };
    } catch {
      return { valid: false, origin: referer };
    }
  }

  return { valid: false, origin: null };
}
```

### `lib/auth/resolve-origin.ts` (modified)

Refactor to import from `allowed-origins.ts` instead of defining its own `PRODUCTION_ORIGINS` / `DEV_ORIGINS`.

### `app/api/checkout/route.ts` (modified -- add at top of POST handler)

```typescript
import { validateOrigin } from "@/lib/auth/validate-origin";

// Inside POST handler, before auth check:
const { valid, origin } = validateOrigin(request);
if (!valid) {
  console.warn(`[api/checkout] CSRF: rejected origin ${(origin ?? "none").slice(0, 100).replace(/[\x00-\x1f]/g, "")}`);
  return NextResponse.json({ error: "Forbidden" }, { status: 403 });
}
```

Same pattern applied to `app/api/keys/route.ts` and `app/api/workspace/route.ts`.

### `app/api/workspace/route.ts` (modified -- add request parameter)

```typescript
// Before:
export async function POST() {

// After:
export async function POST(request: Request) {
```

### `middleware.ts` and `lib/supabase/server.ts` (modified)

Add `cookieOptions` to `createServerClient` / `createClient`:

```typescript
cookieOptions: {
  sameSite: "lax" as const,  // SECURITY: blocks cross-site cookie transmission
  secure: process.env.NODE_ENV === "production",  // SECURITY: HTTPS-only in production
  path: "/",
},
```

### `next.config.ts` (modified -- add allowedOrigins)

```typescript
const nextConfig: NextConfig = {
  output: undefined,
  serverExternalPackages: ["@anthropic-ai/claude-agent-sdk", "ws"],
  serverActions: {
    allowedOrigins: ["app.soleur.ai"],
  },
};
```

## Dependencies & Risks

- **Risk: False positives from Origin validation** -- Privacy-focused browsers or corporate proxies that strip Origin/Referer headers will get 403 errors. Mitigation: the fail-closed behavior is intentional and correct for security; such clients need to be configured to send Origin headers. All modern browsers (Chrome, Firefox, Safari, Edge) send the Origin header on POST requests.
- **Risk: Cookie option change breaks existing sessions** -- Changing cookie options (adding `secure: true`) could invalidate existing sessions if the server was previously setting cookies without the `secure` flag over HTTP. Mitigation: production traffic already goes through Cloudflare HTTPS termination, so cookies are already sent over HTTPS; the `secure` flag simply prevents accidental HTTP leakage.
- **Risk: Accidental removal during future refactors** -- Per institutional learning, inline `SECURITY:` comments on cookie options serve as speed bumps during refactoring. Without comments, a future developer might remove the options as "redundant" since they partially match defaults.

## References & Research

### Internal References

- `apps/web-platform/lib/auth/resolve-origin.ts` -- existing origin allowlist pattern and log sanitization
- `apps/web-platform/middleware.ts` -- current Supabase cookie handling
- `apps/web-platform/lib/supabase/server.ts` -- route handler Supabase client
- `apps/web-platform/app/api/checkout/route.ts` -- mutating route (no CSRF protection)
- `apps/web-platform/app/api/keys/route.ts` -- mutating route (no CSRF protection)
- `apps/web-platform/app/api/workspace/route.ts` -- mutating route (no CSRF protection, no request param)
- `apps/web-platform/app/api/webhooks/stripe/route.ts` -- excluded (Stripe signature auth)
- `apps/web-platform/test/callback.test.ts` -- existing origin validation test pattern
- `apps/web-platform/next.config.ts` -- needs `serverActions.allowedOrigins`

### Institutional Learnings Applied

- `2026-03-20-security-fix-attack-surface-enumeration.md` -- enumerate ALL code paths when fixing security boundaries; write negative-space tests
- `2026-03-20-security-refactor-adjacent-config-audit.md` -- mark security options with inline comments; run config diff before committing
- `2026-03-15-env-var-post-guard-defense-in-depth.md` -- defense-in-depth via two-key pattern (browser SameSite + server Origin validation)
- `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md` -- allowlist-based security (deny-by-default) pattern applied to origin validation

### External References

- [Next.js Security: How to Think About Security](https://nextjs.org/blog/security-nextjs-server-components-actions) -- confirms custom route handlers need manual CSRF protection; Server Actions compare Origin to Host
- [Next.js Data Security Guide](https://github.com/vercel/next.js/blob/canary/docs/01-app/02-guides/data-security.mdx) -- `serverActions.allowedOrigins` config for reverse proxy scenarios
- [Next.js Authentication Guide](https://github.com/vercel/next.js/blob/canary/docs/01-app/02-guides/authentication.mdx) -- recommended cookie options: `httpOnly: true, secure: true, sameSite: 'lax', path: '/'`
- [Supabase SSR Cookie Options](https://deepwiki.com/supabase/ssr/3-server-client-(createserverclient)) -- `cookieOptions` interface with defaults (`sameSite: "lax"`, `secure: false`, `httpOnly: false`)
- [Supabase SSR Issue #40](https://github.com/supabase/ssr/issues/40) -- confirms `sameSite: "lax"` default, `maxAge` override behavior
- [MakerKit CSRF Protection for Next.js + Supabase](https://makerkit.dev/docs/next-supabase-turbo/csrf-protection) -- reference implementation pattern with `useCsrfToken` hook
