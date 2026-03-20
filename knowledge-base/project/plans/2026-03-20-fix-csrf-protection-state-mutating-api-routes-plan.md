---
title: "fix: add CSRF protection to state-mutating API routes"
type: fix
date: 2026-03-20
semver: patch
---

# fix: add CSRF protection to state-mutating API routes

## Overview

The web platform has four API route handlers and a WebSocket endpoint, three of which accept POST requests that mutate state (checkout, keys, workspace). None of these routes validate the request Origin header, and the Supabase SSR cookie configuration uses library defaults (`sameSite: "lax"`, `secure: false`, `httpOnly: false`) without explicit overrides. This leaves the application reliant on implicit browser defaults for CSRF protection rather than explicit server-side enforcement.

Closes #945

## Problem Statement

Next.js does **not** provide built-in CSRF protection for custom API route handlers (`route.ts`). The official Next.js security guide explicitly states: "When Custom Route Handlers are used instead, extra auditing can be necessary since CSRF protection has to be done manually there."

Currently:

1. **No Origin header validation** -- Any cross-origin site can submit POST requests to `/api/checkout`, `/api/keys`, and `/api/workspace`. While `SameSite=Lax` cookies provide partial protection (browsers do not send cookies on cross-site POST from `<form>` or `fetch`), this relies on browser behavior rather than server enforcement.
2. **Implicit cookie defaults** -- `@supabase/ssr` defaults to `sameSite: "lax"`, `secure: false`, `httpOnly: false`. The `secure: false` default means cookies are sent over plaintext HTTP in production if HTTPS terminates upstream (e.g., at Cloudflare). The code never explicitly sets these values.
3. **No defense-in-depth** -- A single layer (browser SameSite enforcement) is the entire CSRF defense. If a browser bug, misconfigured proxy, or subdomain compromise bypasses SameSite, there is no fallback.

### Attack Surface Enumeration

**State-mutating API routes (need CSRF protection):**

| Route | Method | Auth | Mutation |
|-------|--------|------|----------|
| `app/api/checkout/route.ts` | POST | Supabase cookie | Creates Stripe checkout session |
| `app/api/keys/route.ts` | POST | Supabase cookie | Stores encrypted API key in DB |
| `app/api/workspace/route.ts` | POST | Supabase cookie | Provisions user workspace |

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

## Proposed Solution

Three-layer CSRF defense:

### Layer 1: Origin Header Validation Middleware

Create a reusable `validateOrigin` function and apply it at the top of every mutating API route handler. The function:

1. Reads the `Origin` header from the request (falls back to `Referer` header for older clients)
2. Compares against the same allowlist used by `resolveOrigin` (`PRODUCTION_ORIGINS` / `DEV_ORIGINS`)
3. Returns 403 if the origin does not match

This mirrors what Next.js Server Actions do internally (compare Origin to Host/X-Forwarded-Host) but applied to custom route handlers.

**Why middleware-level vs. per-route:** The existing `middleware.ts` runs for all routes but bypasses public paths including `/api/webhooks`. A per-route utility function is simpler and avoids accidentally blocking the Stripe webhook (which must accept cross-origin POSTs from Stripe servers with no Origin header).

### Layer 2: Explicit SameSite Cookie Configuration

Add `cookieOptions` to both `createServerClient` call sites:

```typescript
cookieOptions: {
  sameSite: "lax",
  secure: process.env.NODE_ENV === "production",
  path: "/",
}
```

This makes the security posture explicit and ensures `secure: true` in production (cookies only sent over HTTPS).

**Why not `httpOnly: true`:** Supabase SSR needs JavaScript access to the auth token for client-side operations. Setting `httpOnly: true` would break the Supabase client.

**Why not `sameSite: "strict"`:** Strict blocks cookies on all cross-site navigations including top-level GET navigations (e.g., clicking a link from email to the dashboard). `Lax` is the correct setting for auth cookies that need to survive navigation.

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

### Edge Cases

1. **Missing Origin header** -- Some legitimate requests (older browsers, privacy extensions) may omit the Origin header. The implementation should fall back to the `Referer` header. If neither is present, reject the request (fail-closed).
2. **Stripe webhook** -- Must NOT have Origin validation (Stripe sends no Origin header). The webhook route is already excluded from auth middleware via `PUBLIC_PATHS` and uses its own signature verification.
3. **WebSocket connections** -- Authenticated via explicit token in the first message, not cookies. No Origin validation needed on the WebSocket upgrade itself (the WS handler already requires a valid Supabase token).
4. **Development mode** -- Must accept `http://localhost:3000` as a valid origin (already handled by `DEV_ORIGINS` in `resolve-origin.ts`).

### Performance

- Origin validation is a string comparison -- zero measurable overhead.
- Cookie option changes are configuration-only -- no runtime cost.

### Security

- Fail-closed: missing Origin + missing Referer = 403
- Allowlist-based: only known origins are accepted (not a blocklist)
- Production `secure: true`: prevents cookie leakage over HTTP

## Acceptance Criteria

- [ ] All three mutating API routes (`/api/checkout`, `/api/keys`, `/api/workspace`) validate the Origin header and return 403 for cross-origin requests
- [ ] Origin validation falls back to Referer header when Origin is absent
- [ ] Requests with neither Origin nor Referer header are rejected with 403
- [ ] Stripe webhook route (`/api/webhooks/stripe`) is NOT affected by Origin validation
- [ ] Auth callback route (`/callback`) is NOT affected (GET-only, already has origin validation)
- [ ] Supabase cookie configuration explicitly sets `sameSite: "lax"` and `secure: true` (production) in both `middleware.ts` and `lib/supabase/server.ts`
- [ ] Existing tests continue to pass
- [ ] New tests cover Origin validation (valid origin, invalid origin, missing origin, Referer fallback)
- [ ] New tests verify cookie options are set correctly

## Test Scenarios

### Origin Validation

- Given a POST to `/api/checkout` with `Origin: https://app.soleur.ai`, when the user is authenticated, then the request proceeds normally (200)
- Given a POST to `/api/keys` with `Origin: https://evil.com`, when the user is authenticated, then the request is rejected (403)
- Given a POST to `/api/workspace` with no Origin header but `Referer: https://app.soleur.ai/dashboard`, when the user is authenticated, then the request proceeds normally (200)
- Given a POST to `/api/keys` with neither Origin nor Referer headers, when the user is authenticated, then the request is rejected (403)
- Given a POST to `/api/webhooks/stripe` with no Origin header, when a valid Stripe signature is present, then the request proceeds normally (200)
- Given a POST to `/api/checkout` with `Origin: http://localhost:3000` in development mode, when the user is authenticated, then the request proceeds normally (200)

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
  console.warn(`[api/checkout] CSRF: rejected origin ${origin?.slice(0, 100)}`);
  return NextResponse.json({ error: "Forbidden" }, { status: 403 });
}
```

Same pattern applied to `app/api/keys/route.ts` and `app/api/workspace/route.ts`.

### `middleware.ts` and `lib/supabase/server.ts` (modified)

Add `cookieOptions` to `createServerClient` / `createClient`:

```typescript
cookieOptions: {
  sameSite: "lax" as const,
  secure: process.env.NODE_ENV === "production",
  path: "/",
},
```

## Dependencies & Risks

- **Risk: False positives from Origin validation** -- Privacy-focused browsers or corporate proxies that strip Origin/Referer headers will get 403 errors. Mitigation: the fail-closed behavior is intentional and correct for security; such clients need to be configured to send Origin headers.
- **Risk: Cookie option change breaks existing sessions** -- Changing cookie options (adding `secure: true`) could invalidate existing sessions if the server was previously setting cookies without the `secure` flag over HTTP. Mitigation: production traffic already goes through Cloudflare HTTPS termination, so cookies are already sent over HTTPS; the `secure` flag simply prevents accidental HTTP leakage.

## References & Research

### Internal References

- `apps/web-platform/lib/auth/resolve-origin.ts` -- existing origin allowlist pattern
- `apps/web-platform/middleware.ts` -- current Supabase cookie handling
- `apps/web-platform/lib/supabase/server.ts` -- route handler Supabase client
- `apps/web-platform/app/api/checkout/route.ts` -- mutating route (no CSRF protection)
- `apps/web-platform/app/api/keys/route.ts` -- mutating route (no CSRF protection)
- `apps/web-platform/app/api/workspace/route.ts` -- mutating route (no CSRF protection)
- `apps/web-platform/app/api/webhooks/stripe/route.ts` -- excluded (Stripe signature auth)
- `apps/web-platform/test/callback.test.ts` -- existing origin validation test pattern

### External References

- [Next.js Security: How to Think About Security](https://nextjs.org/blog/security-nextjs-server-components-actions) -- confirms custom route handlers need manual CSRF protection
- [Supabase SSR Cookie Options](https://deepwiki.com/supabase/ssr/3-server-client-(createserverclient)) -- `cookieOptions` interface with defaults
- [Supabase SSR Issue #40](https://github.com/supabase/ssr/issues/40) -- confirms `sameSite: "lax"` default
- [MakerKit CSRF Protection for Next.js + Supabase](https://makerkit.dev/docs/next-supabase-turbo/csrf-protection) -- reference implementation pattern
