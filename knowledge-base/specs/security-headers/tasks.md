# Tasks: Add Security Headers (CSP, X-Frame-Options, HSTS)

## Phase 1: Setup

- [ ] 1.1 Read existing `apps/web-platform/next.config.ts`
- [ ] 1.2 Read existing `apps/web-platform/middleware.ts` to confirm no header conflicts
- [ ] 1.3 Verify `NEXT_PUBLIC_SUPABASE_URL` is available at build time in `next.config.ts`

## Phase 2: Core Implementation

- [ ] 2.1 Create `apps/web-platform/lib/security-headers.ts` with `buildSecurityHeaders()` pure function
  - [ ] 2.1.1 Build `connect-src` dynamically from `NEXT_PUBLIC_SUPABASE_URL` with both `https://` and `wss://` protocols
  - [ ] 2.1.2 Add try/catch guard around `new URL()` for malformed/empty Supabase URL (fall back to `*.supabase.co`)
  - [ ] 2.1.3 Conditionally include `'unsafe-eval'` in `script-src` for development only
- [ ] 2.2 Include all 8 headers: CSP, X-Frame-Options, X-Content-Type-Options, HSTS, Referrer-Policy, Permissions-Policy, X-DNS-Prefetch-Control, X-XSS-Protection (set to `0`)
- [ ] 2.3 Update `apps/web-platform/next.config.ts` to import `buildSecurityHeaders()` and add `async headers()` for `source: '/(.*)'`
- [ ] 2.4 Verify CSP does not break WebSocket connections (WebSocket upgrade is handled by custom server, not Next.js routes)

## Phase 3: Testing

- [ ] 3.1 Create `apps/web-platform/test/security-headers.test.ts`
  - [ ] 3.1.1 Test CSP contains `frame-ancestors 'none'`
  - [ ] 3.1.2 Test CSP does not contain `unsafe-eval` when `NODE_ENV=production`
  - [ ] 3.1.3 Test CSP contains `unsafe-eval` when `NODE_ENV=development`
  - [ ] 3.1.4 Test `connect-src` includes Supabase host (both `https://` and `wss://`) from env var
  - [ ] 3.1.5 Test `connect-src` falls back to `*.supabase.co` when env var empty
  - [ ] 3.1.6 Test no throw on malformed Supabase URL
  - [ ] 3.1.7 Test `X-Frame-Options` value is `DENY`
  - [ ] 3.1.8 Test `Strict-Transport-Security` value contains `max-age=63072000`
  - [ ] 3.1.9 Test `X-Content-Type-Options` value is `nosniff`
  - [ ] 3.1.10 Test `Referrer-Policy` value is `strict-origin-when-cross-origin`
  - [ ] 3.1.11 Test `X-XSS-Protection` value is `0`
  - [ ] 3.1.12 Test `Permissions-Policy` disables camera, microphone, geolocation
  - [ ] 3.1.13 Test all 8 required header keys are present
- [ ] 3.2 Run existing tests (`vitest`) to verify no regressions
- [ ] 3.3 Run `next build` to verify config compiles without errors

## Phase 4: Verification

- [ ] 4.1 Run `skill: soleur:compound` before commit
- [ ] 4.2 Commit and push
- [ ] 4.3 Create PR with `Closes #946` in body
