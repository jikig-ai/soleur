# Tasks: fix open redirect via x-forwarded-host in auth callback

## Phase 1: Core Fix

- 1.1 Extract `resolveOrigin` as a named export in `apps/web-platform/app/(auth)/callback/route.ts`
- 1.2 Add `ALLOWED_ORIGINS` constant (Set with `https://app.soleur.ai` and `http://localhost:3000`)
- 1.3 Add `console.warn` for rejected origins (truncated to 100 chars, no auth code)
- 1.4 Replace inline origin construction in `GET` handler with `resolveOrigin()` call
- 1.5 Verify all three `NextResponse.redirect()` calls use the validated origin

## Phase 2: Testing

- 2.1 Create `apps/web-platform/test/callback.test.ts` importing `resolveOrigin` directly
  - 2.1.1 Test: malicious `x-forwarded-host` is rejected + warning logged
  - 2.1.2 Test: malicious proto + host combination is rejected
  - 2.1.3 Test: port variants not in allowlist are rejected
  - 2.1.4 Test: subdomain spoofing (`app.soleur.ai.evil.com`) is rejected
  - 2.1.5 Test: userinfo abuse (`app.soleur.ai@evil.com`) is rejected
  - 2.1.6 Test: case variation (`APP.SOLEUR.AI`) is rejected
  - 2.1.7 Test: legitimate Cloudflare-proxied request is accepted (no warning)
  - 2.1.8 Test: localhost development request is accepted
  - 2.1.9 Test: fallback to production when no headers present
- 2.2 Run `npx vitest run test/callback.test.ts` to verify all tests pass

## Phase 3: Verification

- 3.1 Run full test suite (`npx vitest run`) to verify no regressions
- 3.2 Run compound (`skill: soleur:compound`) before committing
