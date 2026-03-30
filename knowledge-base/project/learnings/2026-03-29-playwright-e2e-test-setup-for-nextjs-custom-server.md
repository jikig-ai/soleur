# Learning: Playwright E2E Test Setup for Next.js Custom Server

## Problem

Adding Playwright E2E tests to a Next.js 15 app with a custom server (`tsx server/index.ts`)
that wraps Next.js with WebSocket handling, Supabase auth, and CSP nonce middleware.

## Solution

### Key Setup Decisions

1. **Use dev mode (`tsx`) not production mode** — the esbuild-bundled production server has
   ESM/CJS compatibility issues with `@anthropic-ai/claude-agent-sdk` (`ERR_REQUIRE_ESM`).
   Dev mode with `tsx` handles ESM/CJS seamlessly.

2. **Provide ALL server env vars** — the custom server creates Supabase clients at module
   load time in `session-sync.ts`, `ws-handler.ts`, and `api-messages.ts`. Missing
   `SUPABASE_SERVICE_ROLE_KEY` crashes the server before it starts. Use dummy values:

   ```ts
   env: {
     NEXT_PUBLIC_SUPABASE_URL: "https://test.supabase.co",  // must be URL-shaped
     NEXT_PUBLIC_SUPABASE_ANON_KEY: "test-anon-key",
     SUPABASE_SERVICE_ROLE_KEY: "test-service-role-key",
   }
   ```

3. **URL-shaped dummy values required** — `csp.ts:parseSupabaseHost()` calls `new URL()`
   which throws on non-URL strings in production mode. Even in dev mode, it must be parseable.

4. **Use `.e2e.ts` extension, not `.spec.ts`** — Bun's test runner discovers `.spec.ts`
   and `.test.ts` files recursively with no exclude option. Renaming to `.e2e.ts` prevents
   Bun from discovering Playwright files while Playwright finds them via `testMatch: "**/*.e2e.ts"`.

5. **Run from `apps/web-platform/` directory** — Playwright resolves `webServer.command`
   relative to the config file. Running `npx playwright test` from the worktree root fails
   because `tsx server/index.ts` can't find the server file.

### Nonce Verification Gotchas

- **`getAttribute("nonce")` returns empty string** — browsers clear the nonce content attribute
  after parsing to prevent CSS selector exfiltration. Use the `.nonce` IDL property instead:

  ```ts
  const scriptNonces = await page.evaluate(() => {
    const scripts = document.querySelectorAll("script[nonce]");
    return Array.from(scripts).map(
      (s) => (s as HTMLScriptElement).nonce || s.getAttribute("nonce"),
    );
  });
  ```

- **CSP nonce is generated BEFORE auth check** in middleware. Testing nonce propagation
  on public pages (e.g., `/login`) covers the pipeline completely without needing auth mocking.

- **Assert `scriptNonces.length > 0`** — a conditional `if (length > 0)` silently passes
  when nonce propagation breaks (the exact #1213 failure mode). Always assert presence.

## Key Insight

For E2E testing a Next.js app with a custom server, the test harness complexity comes from
server-side dependencies (Supabase clients created at module scope, ESM/CJS issues in bundled
builds), not from the tests themselves. Enumerate all `process.env` references in server code
before writing the Playwright config.

## Session Errors

- **ESM/CJS crash in production build** — `node dist/server/index.js` failed with
  `ERR_REQUIRE_ESM` for claude-agent-sdk. Recovery: switched to `tsx server/index.ts`.
  Prevention: test the production build command before prescribing it in plans.

- **Missing SUPABASE_SERVICE_ROLE_KEY** — server crashed at startup. Recovery: added to
  playwright.config.ts env. Prevention: grep all `process.env` in server/ directory
  before writing test config.

- **Bun discovers Playwright files** — `bun test` picked up `.spec.ts` and crashed on
  Playwright imports. Recovery: renamed to `.e2e.ts`. Prevention: use `.e2e.ts` extension
  for Playwright tests in projects that use Bun test runner.

- **getAttribute("nonce") returns empty** — browser security feature, not a bug.
  Recovery: used `.nonce` IDL property. Prevention: document in test patterns.

- **postcss ERR_INVALID_URL_SCHEME on page render** — pre-existing Tailwind v4 + Next.js
  dev server issue. Not introduced by this PR. Tests work around it by checking CSP headers
  via API requests instead of relying on page rendering.

## Tags

category: test-infrastructure
module: apps/web-platform
