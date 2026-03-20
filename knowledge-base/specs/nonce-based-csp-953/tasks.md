# Tasks: Nonce-Based CSP (#953)

## Phase 1: Setup

- [ ] 1.1 Read existing files: `middleware.ts`, `lib/security-headers.ts`, `next.config.ts`, `test/security-headers.test.ts`
- [ ] 1.2 Run `npm install` in `apps/web-platform/` (worktrees do not share node_modules)
- [ ] 1.3 Run existing test suite to establish baseline (`cd apps/web-platform && npx vitest run`)

## Phase 2: Core Implementation

- [ ] 2.1 Create `apps/web-platform/lib/csp.ts` -- pure function `buildCspHeader({ nonce, isDev, supabaseUrl })` returning CSP header string with nonce, strict-dynamic, https:/http: fallbacks, and all 13 directives. Use `.replace(/\s{2,}/g, " ").trim()` for whitespace normalization.
- [ ] 2.2 Update `apps/web-platform/lib/security-headers.ts` -- remove CSP directive from returned headers array (keep all other 9 security headers). The function no longer needs to build CSP directives.
- [ ] 2.3 Update `apps/web-platform/middleware.ts`:
  - [ ] 2.3.1 Add nonce generation at top of middleware function: `const nonce = Buffer.from(crypto.randomUUID()).toString("base64")`
  - [ ] 2.3.2 Import and call `buildCspHeader` with nonce, isDev, supabaseUrl
  - [ ] 2.3.3 Set up request headers: create `new Headers(request.headers)`, set `x-nonce` and `Content-Security-Policy`
  - [ ] 2.3.4 Create `withCspHeaders(response, cspValue)` helper to set CSP on any NextResponse
  - [ ] 2.3.5 Wrap ALL 6 response exit paths with `withCspHeaders`:
    - Public path early return (`NextResponse.next()`)
    - Health check early return (`NextResponse.next()`)
    - Main response object (`NextResponse.next({ request: { headers } })`)
    - Redirect for unauthenticated users (via `redirectWithCookies`)
    - Redirect for T&C non-acceptance (via `redirectWithCookies`)
    - Final response return
  - [ ] 2.3.6 Verify auth and T&C logic is unchanged (run tests)

## Phase 3: Testing

- [ ] 3.1 Create `apps/web-platform/test/csp.test.ts` with unit tests for `buildCspHeader`:
  - [ ] 3.1.1 Nonce appears in script-src
  - [ ] 3.1.2 `strict-dynamic` present in script-src
  - [ ] 3.1.3 `unsafe-inline` present as CSP2 fallback in script-src
  - [ ] 3.1.4 `https:` present as CSP1 fallback in script-src
  - [ ] 3.1.5 Development-only directives only in dev mode
  - [ ] 3.1.6 connect-src includes Supabase host (both https and wss)
  - [ ] 3.1.7 style-src includes unsafe-inline
  - [ ] 3.1.8 All 13 required CSP directives present
  - [ ] 3.1.9 Output has no double spaces or newlines
  - [ ] 3.1.10 Supabase URL production guard (throws when missing in prod)
  - [ ] 3.1.11 Supabase wildcard fallback in dev
  - [ ] 3.1.12 Nonce format validation (valid base64 regex)
- [ ] 3.2 Update `apps/web-platform/test/security-headers.test.ts`:
  - [ ] 3.2.1 Remove CSP-specific assertions (nonce, script-src, connect-src directive tests)
  - [ ] 3.2.2 Keep all non-CSP header assertions (HSTS, X-Frame-Options, etc.)
  - [ ] 3.2.3 Add assertion that CSP is NOT in the returned headers (verify separation)
- [ ] 3.3 Run full test suite (`cd apps/web-platform && npx vitest run`)
- [ ] 3.4 Browser verification: check no CSP violations on login, signup, dashboard, chat, billing pages (Playwright)

## Phase 4: Review & Ship

- [ ] 4.1 Run compound (`skill: soleur:compound`)
- [ ] 4.2 Commit and push
- [ ] 4.3 Create PR with `Closes #953` in body
