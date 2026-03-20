# Tasks: Nonce-Based CSP (#953)

## Phase 1: Setup

- [ ] 1.1 Read existing files: `middleware.ts`, `lib/security-headers.ts`, `next.config.ts`, `test/security-headers.test.ts`
- [ ] 1.2 Run existing test suite to establish baseline (`cd apps/web-platform && npx vitest run`)

## Phase 2: Core Implementation

- [ ] 2.1 Create `apps/web-platform/lib/csp.ts` -- pure function `buildCspHeader({ nonce, isDev, supabaseUrl })` returning CSP header string with nonce, strict-dynamic, and all directives
- [ ] 2.2 Update `apps/web-platform/lib/security-headers.ts` -- remove CSP directive from returned headers array (keep all other security headers)
- [ ] 2.3 Update `apps/web-platform/middleware.ts`:
  - [ ] 2.3.1 Add nonce generation at top of middleware function (`Buffer.from(crypto.randomUUID()).toString('base64')`)
  - [ ] 2.3.2 Import and call `buildCspHeader` with nonce
  - [ ] 2.3.3 Set `x-nonce` on request headers
  - [ ] 2.3.4 Set `Content-Security-Policy` on request and response headers
  - [ ] 2.3.5 Ensure CSP header is set on ALL response paths: public path early returns, health check, redirects (`redirectWithCookies`), and normal response
  - [ ] 2.3.6 Verify auth and T&C logic is unchanged

## Phase 3: Testing

- [ ] 3.1 Create `apps/web-platform/test/csp.test.ts` with unit tests for `buildCspHeader`:
  - [ ] 3.1.1 Nonce appears in script-src
  - [ ] 3.1.2 strict-dynamic present in script-src
  - [ ] 3.1.3 unsafe-inline present as CSP2 fallback
  - [ ] 3.1.4 Development-only directives only in dev mode
  - [ ] 3.1.5 connect-src includes Supabase host
  - [ ] 3.1.6 style-src includes unsafe-inline
  - [ ] 3.1.7 All required CSP directives present
  - [ ] 3.1.8 Supabase URL production guard (throws when missing in prod)
  - [ ] 3.1.9 Supabase wildcard fallback in dev
- [ ] 3.2 Update `apps/web-platform/test/security-headers.test.ts` -- remove CSP-specific assertions, keep non-CSP header assertions
- [ ] 3.3 Run full test suite (`cd apps/web-platform && npx vitest run`)
- [ ] 3.4 Browser verification: check no CSP violations on login, signup, dashboard, chat, billing pages (Playwright)

## Phase 4: Review & Ship

- [ ] 4.1 Run compound (`skill: soleur:compound`)
- [ ] 4.2 Commit and push
- [ ] 4.3 Create PR with `Closes #953` in body
