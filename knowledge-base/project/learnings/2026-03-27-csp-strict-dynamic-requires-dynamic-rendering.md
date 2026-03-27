---
title: CSP strict-dynamic with nonce requires dynamic rendering in Next.js root layout
date: 2026-03-27
category: runtime-errors
tags: [csp, nonce, strict-dynamic, next.js, dynamic-rendering, middleware]
symptoms: "all JavaScript blocked on page load, 15+ CSP violation console errors, form submissions have no effect"
module: apps/web-platform
severity: critical
---

# Learning: CSP strict-dynamic with nonce requires dynamic rendering in Next.js root layout

## Problem

Sign-in on app.soleur.ai was completely non-functional. The login form rendered but submitting it had no effect — no magic link email sent, page appeared to reload. Playwright reproduction revealed 15 CSP violation console errors: every Next.js framework script and inline script was blocked.

## Root Cause

The middleware generates a per-request CSP nonce and includes `'strict-dynamic'` in `script-src`. With CSP Level 3 (all modern browsers), `'strict-dynamic'` overrides `'self'`, `'unsafe-inline'`, and `https:` — only scripts bearing the correct nonce can execute.

The root layout (`app/layout.tsx`) was a **static** Server Component — a synchronous function that never called `headers()`. Without dynamic rendering, Next.js cannot extract the nonce from the CSP header during SSR, so framework `<script>` tags are rendered without `nonce` attributes. Result: CSP blocks every script, React never hydrates, the page is a dead shell.

## Solution

Made the root layout async and added `await headers()` to force dynamic rendering:

```typescript
import { headers } from "next/headers";

export default async function RootLayout({ children }) {
  // Force dynamic rendering so Next.js extracts the CSP nonce from
  // the Content-Security-Policy header and applies it to all framework
  // scripts, inline scripts, and styles automatically.
  await headers();

  return (
    <html lang="en">
      <body className="bg-neutral-950 text-neutral-100 antialiased">
        {children}
      </body>
    </html>
  );
}
```

Next.js then automatically parses the `Content-Security-Policy` request header, extracts the nonce via the `'nonce-{value}'` pattern, and applies it to all framework scripts, page bundles, and inline scripts.

## Key Insight

**Generating a CSP nonce is only half the job — the rendering pipeline must also be dynamic for the nonce to reach the HTML.** This is an architectural mismatch bug: security middleware and rendering mode must agree. The existing learning (`2026-03-20-nonce-based-csp-nextjs-middleware.md`) documented "Next.js extracts nonces automatically" but omitted the critical prerequisite that the page must be dynamically rendered.

## Why Tests Didn't Catch It

- **Unit tests** verified CSP header generation (`lib/csp.ts`) and middleware routing in isolation — both were correct
- **Structural tests** verified every middleware exit path includes CSP headers — also correct
- **No E2E test** verified that rendered HTML actually has nonce attributes on script tags
- **No smoke test** hits the deployed app to check for console errors or JS execution
- The bug exists in the gap between "correct headers" and "correct rendering" — a gap only integration or E2E testing can cover

## Session Errors

1. **`npx vitest run` failed** with `MODULE_NOT_FOUND` for `rolldown-binding.linux-x64-gnu.node` — worktree needed `npm install`. **Prevention:** worktree creation script should verify dependencies are installed, not just copied.
2. **`node_modules/.bin/vitest` not found** — same root cause as above. **Prevention:** same as above.
3. **Pre-existing: `domain-router.test.ts` imports `bun:test`** — test file uses wrong test runner import. **Prevention:** add a lint rule or test runner check that flags `bun:test` imports in a vitest project.

## Prevention

- When adding CSP with `'strict-dynamic'` + nonce to Next.js, always verify the root layout forces dynamic rendering via `headers()` or equivalent
- Add E2E tests that verify scripts load without CSP violations (Playwright console error check)
- Add post-deploy smoke tests that detect "all JS blocked" scenarios before users hit them
- Consider synthetic monitoring for critical auth flows

## References

- Issue: sign-in non-functional on app.soleur.ai (CSP blocking all JS)
- Prior learning: `2026-03-20-nonce-based-csp-nextjs-middleware.md` (CSP nonce migration)
- [Next.js CSP Guide](https://github.com/vercel/next.js/blob/canary/docs/01-app/02-guides/content-security-policy.mdx): "To use a nonce, your page must be dynamically rendered"
