# Learning: CSRF Three-Layer Defense for Next.js Custom Route Handlers

## Problem
Next.js custom API route handlers (`app/api/*/route.ts`) receive no built-in CSRF protection. Server Actions get Origin-vs-Host comparison automatically, but custom route handlers are explicitly documented as requiring manual CSRF protection. Our web platform had 3 state-mutating POST routes with zero server-side CSRF enforcement, relying entirely on implicit browser SameSite cookie defaults.

## Solution
Three-layer defense applied to all state-mutating routes:

**Layer 1: Origin/Referer Validation** — `validateOrigin(request)` checks the Origin header against an allowlist Set (O(1) lookup). Falls back to Referer header. Fails closed when neither header is present. Applied per-route (not in middleware) to avoid blocking Stripe webhook which has no Origin header.

**Layer 2: Explicit Cookie Hardening** — `cookieOptions: { sameSite: "lax", secure: process.env.NODE_ENV === "production", path: "/" }` on both `createServerClient` call sites (middleware.ts and lib/supabase/server.ts). Inline `// SECURITY:` comments prevent accidental removal during refactors.

**Layer 3: serverActions.allowedOrigins** — Zero-cost defense-in-depth config in next.config.ts for future Server Action adoption.

**Integration pattern (2 lines per route):**
```typescript
const { valid, origin } = validateOrigin(request);
if (!valid) return rejectCsrf("api/checkout", origin);
```

## Key Insight
**Structural enforcement beats documentation.** The negative-space test (`csrf-coverage.test.ts`) scans all `route.ts` files, finds POST handlers, and fails if they don't call `validateOrigin` or aren't in `EXEMPT_ROUTES`. This turns CSRF protection from a code-review checklist item into a CI-enforced invariant. New routes cannot be merged without protection.

This pattern generalizes: any security property that should be "always present" belongs in a build-time test, not documentation.

## Session Errors
1. `npx vitest` failed with rolldown native binding error — worktree had no node_modules. Fix: `npm install` then use `./node_modules/.bin/vitest`.
2. TypeScript `valid` variable name collision in keys/route.ts — both CSRF and API key validation used `const valid`. Fix: rename to `originValid`.
3. Next.js `serverActions` config initially placed under `experimental:` — Next.js 15 moved it to top-level. Fix: move to top-level config.

## Tags
category: security-issues
module: web-platform/api-routes
