# Tasks: CSRF Protection for State-Mutating API Routes

## Phase 1: Setup -- Extract Shared Origin Allowlist

- [ ] 1.1 Create `apps/web-platform/lib/auth/allowed-origins.ts` with `getAllowedOrigins()` exporting the shared origin set
- [ ] 1.2 Refactor `apps/web-platform/lib/auth/resolve-origin.ts` to import from `allowed-origins.ts` instead of defining its own origin sets
- [ ] 1.3 Verify existing `test/callback.test.ts` tests still pass after refactor

## Phase 2: Core Implementation -- Origin Validation

- [ ] 2.1 Create `apps/web-platform/lib/auth/validate-origin.ts` with `validateOrigin(request)` function
  - [ ] 2.1.1 Read Origin header, fall back to Referer header
  - [ ] 2.1.2 Compare against allowlist from `allowed-origins.ts`
  - [ ] 2.1.3 Return `{ valid: boolean; origin: string | null }`
  - [ ] 2.1.4 Fail-closed: reject if neither Origin nor Referer present
  - [ ] 2.1.5 Log sanitization: truncate and strip control characters from logged origin (match `resolve-origin.ts` pattern)
- [ ] 2.2 Add Origin validation to `app/api/checkout/route.ts` POST handler (before auth check)
- [ ] 2.3 Add Origin validation to `app/api/keys/route.ts` POST handler (before auth check)
- [ ] 2.4 Fix `app/api/workspace/route.ts` POST handler: change `POST()` to `POST(request: Request)`, then add Origin validation (before auth check)
- [ ] 2.5 Verify Stripe webhook route (`app/api/webhooks/stripe/route.ts`) is NOT modified

## Phase 3: Core Implementation -- Cookie Hardening

- [ ] 3.1 Add `cookieOptions` to `createServerClient` in `middleware.ts` (`sameSite: "lax"`, `secure` based on NODE_ENV, `path: "/"`) with inline `SECURITY:` comments
- [ ] 3.2 Add `cookieOptions` to `createServerClient` in `lib/supabase/server.ts` (`sameSite: "lax"`, `secure` based on NODE_ENV, `path: "/"`) with inline `SECURITY:` comments
- [ ] 3.3 Add `serverActions.allowedOrigins: ["app.soleur.ai"]` to `next.config.ts` for defense-in-depth

## Phase 4: Testing

- [ ] 4.1 Create `test/validate-origin.test.ts`
  - [ ] 4.1.1 Test: valid Origin header is accepted
  - [ ] 4.1.2 Test: invalid Origin header is rejected
  - [ ] 4.1.3 Test: missing Origin with valid Referer is accepted
  - [ ] 4.1.4 Test: missing Origin with invalid Referer is rejected
  - [ ] 4.1.5 Test: neither Origin nor Referer is rejected (fail-closed)
  - [ ] 4.1.6 Test: localhost accepted in development mode
  - [ ] 4.1.7 Test: localhost rejected in production mode
  - [ ] 4.1.8 Test: case-insensitive origin comparison
  - [ ] 4.1.9 Test: subdomain spoofing rejected (e.g., `app.soleur.ai.evil.com`)
  - [ ] 4.1.10 Test: malformed Referer URL rejected gracefully
- [ ] 4.2 Create `test/allowed-origins.test.ts`
  - [ ] 4.2.1 Test: production returns production origins only
  - [ ] 4.2.2 Test: development returns dev origins including localhost
- [ ] 4.3 Negative-space enumeration test: every POST route handler either calls `validateOrigin` or is in an explicit exemption list
- [ ] 4.4 Verify existing `test/callback.test.ts` passes (no regressions from allowlist extraction)
- [ ] 4.5 Verify existing `test/middleware.test.ts` passes
- [ ] 4.6 Run full test suite: `bun test` from `apps/web-platform/`
