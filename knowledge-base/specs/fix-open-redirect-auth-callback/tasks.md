# Tasks: fix open redirect via x-forwarded-host in auth callback

## Phase 1: Core Fix

- 1.1 Add `ALLOWED_ORIGINS` constant to `apps/web-platform/app/(auth)/callback/route.ts`
- 1.2 Replace raw `origin` variable with validated origin (allowlist check with fallback)
- 1.3 Verify all three `NextResponse.redirect()` calls use the validated origin

## Phase 2: Testing

- 2.1 Create `apps/web-platform/test/callback.test.ts` with origin validation tests
  - 2.1.1 Test: malicious `x-forwarded-host` is rejected
  - 2.1.2 Test: malicious proto + host combination is rejected
  - 2.1.3 Test: legitimate Cloudflare-proxied request is accepted
  - 2.1.4 Test: localhost development request is accepted
  - 2.1.5 Test: fallback to production when no headers present
  - 2.1.6 Test: port variants not in allowlist are rejected
- 2.2 Run `npx vitest run test/callback.test.ts` to verify all tests pass

## Phase 3: Verification

- 3.1 Run full test suite (`npx vitest run`) to verify no regressions
- 3.2 Run compound (`skill: soleur:compound`) before committing
