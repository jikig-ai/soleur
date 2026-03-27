---
title: "Sign-in broken: CSP nonce rendering, cookie/redirect semantics, and PromiseLike types"
date: 2026-03-27
category: runtime-errors
tags: [csp, nonce, strict-dynamic, next.js, dynamic-rendering, cookies, redirect, supabase, auth]
symptoms: "sign-in non-functional: JS blocked by CSP, magic link redirects back to login"
module: apps/web-platform
severity: critical
---

# Learning: Three interconnected sign-in bugs — CSP nonce rendering, cookie/redirect semantics, PromiseLike types

## Problem

Sign-in on app.soleur.ai was completely non-functional. Three distinct bugs compounded:

1. All JavaScript blocked by CSP — page was a dead shell
2. TypeScript build error in ws-handler.ts blocked deployment of fix
3. Auth callback exchanged code successfully but session cookies were silently dropped on redirect

## Root Causes

### Bug 1: CSP nonce not propagated to scripts (PR #1213)

Middleware generates per-request CSP nonce with `'strict-dynamic'` in `script-src`. With CSP Level 3, `'strict-dynamic'` overrides `'self'`, `'unsafe-inline'`, and `https:` — only nonce-bearing scripts execute. But the root layout was a **static** Server Component that never called `headers()`. Next.js only injects nonces during dynamic rendering. Result: all `<script>` tags rendered without `nonce` attributes, CSP blocked everything.

### Bug 2: `.catch()` on Supabase PromiseLike (PR #1214)

`abortActiveSession` chained `.catch()` on a Supabase query result. Supabase returns `PromiseLike` (not `Promise`), which has `.then()` but NOT `.catch()`. TypeScript in the Docker build (`next build`) is stricter than local dev, so this only failed in CI.

### Bug 3: Session cookies dropped on redirect (PR #1219 + #1220)

The callback route used `cookies()` from `next/headers` (via `createClient()`) to set session cookies during `exchangeCodeForSession`, then returned `NextResponse.redirect()`. **In Route Handlers, cookies set via `cookies()` do NOT carry over to `NextResponse.redirect()`.** Cookies must be set directly on the response object. The Supabase client's `setAll` wrote to the cookie store, but the redirect response was a new object without those cookies. Middleware on the next page saw no session → redirected to login.

## Solutions

**Bug 1:** Made root layout async, added `await headers()` to force dynamic rendering.

**Bug 2:** Used `.then(onFulfilled, onRejected)` two-argument form instead of `.then().catch()`.

**Bug 3:** Rewrote callback to create Supabase client with an accumulating cookie handler, then applied cookies directly to the `NextResponse.redirect()` object:

```typescript
const pendingCookies: { name: string; value: string; options: CookieOptions }[] = [];
const supabase = createServerClient(url, key, {
  cookies: {
    getAll() { return request.cookies.getAll(); },
    setAll(cookiesToSet) {
      cookiesToSet.forEach((cookie) => pendingCookies.push(cookie));
    },
  },
});
// ... exchange code, determine redirect path ...
const response = NextResponse.redirect(url);
pendingCookies.forEach(({ name, value, options }) => {
  response.cookies.set(name, value, options);
});
return response;
```

## Key Insights

1. **Generating a CSP nonce is only half the job** — the rendering pipeline must also be dynamic for the nonce to reach the HTML. Security middleware and rendering mode must agree.
2. **`cookies()` from `next/headers` and `NextResponse.redirect()` are independent cookie stores** — setting cookies on one does not propagate to the other. The Next.js auth callback docs explicitly show setting cookies on the response object.
3. **Supabase query builders return `PromiseLike`, not `Promise`** — `.catch()` and `.finally()` don't exist. Use `.then(ok, err)` or wrap with `Promise.resolve()`.
4. **Docker `next build` is stricter than local `tsc`** — implicit `any` types pass locally but fail in CI. This mismatch delays error discovery.
5. **A prior learning can be the root cause of a future bug** — the 2026-03-20 CSP learning documented "Next.js extracts nonces automatically" without the dynamic rendering prerequisite.

## Why Tests Didn't Catch It

- **Unit tests** verified each component in isolation — CSP header generation, middleware routing, cookie store operations — all correct individually
- **No E2E test** loads the page in a browser and checks for CSP violations or JS execution
- **No integration test** verifies the contract between middleware (generates nonce) and rendering (must apply it)
- **No smoke test** hits the deployed app to verify critical flows work
- **Silent error swallowing** in `setAll` catch block (`// Server component — can't set cookies`) hid the cookie failure
- These bugs live in **gaps between correct components** — only integration or E2E testing can cover them

## Session Errors

1. **`npx vitest run` MODULE_NOT_FOUND** — worktree needed `npm install`. **Prevention:** worktree script should run dependency install after checkout.
2. **TypeScript implicit `any` in #1219 only caught by CI** — local `tsc --noEmit` uses different strictness than Docker `next build`. **Prevention:** pre-push hook running `next build` or matching tsconfig strictness.
3. **SSH to app.soleur.ai timed out** — firewall blocks SSH from dev machine, preventing log inspection. **Prevention:** set up log forwarding service, add `HCLOUD_TOKEN` to Doppler for CLI fallback.
4. **Pre-existing `bun:test` import in `domain-router.test.ts`** — wrong test runner import. **Prevention:** lint rule flagging test runner import mismatches.
5. **4 PRs shipped without `/ship` or `/review`** — urgent hotfix mode bypassed review and compound gates. **Prevention:** even for hotfixes, /ship Phase 1.5 review gate should enforce at minimum a self-review pass.
6. **Incomplete CSP learning from 2026-03-20 omitted dynamic rendering prerequisite** — "Next.js extracts nonces automatically" was true but missing critical context. **Prevention:** learnings documenting "X happens automatically" should include a Prerequisites section and ideally a verification test.

## Prevention

- In Route Handlers that return `NextResponse.redirect()`, NEVER use `cookies()` from `next/headers` to set session cookies — always set them directly on the response object
- When adding CSP with `'strict-dynamic'` + nonce, always verify the root layout forces dynamic rendering
- Use `.then(ok, err)` instead of `.then().catch()` on Supabase query builders (they return `PromiseLike`, not `Promise`)
- Add E2E tests verifying scripts load without CSP violations (tracked in #1217)
- Add synthetic monitoring for critical auth flows (tracked in #1218)
- Match local TypeScript strictness to CI build settings

## References

- PRs: #1213, #1214, #1219, #1220
- GitHub issues filed: #1217 (frontend testing), #1218 (observability)
- Prior learning: `2026-03-20-nonce-based-csp-nextjs-middleware.md` (updated with dynamic rendering caveat)
- [Next.js CSP Guide](https://github.com/vercel/next.js/blob/canary/docs/01-app/02-guides/content-security-policy.mdx)
- [Next.js Auth Callback Pattern](https://github.com/vercel/next.js/blob/canary/docs/01-app/02-guides/backend-for-frontend.mdx)
