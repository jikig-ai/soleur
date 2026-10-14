---
title: "fix: dev server crashes on missing SUPABASE_URL and NEXT_PUBLIC_SUPABASE_URL"
type: fix
date: 2026-04-13
---

# fix: Dev server crashes on missing SUPABASE_URL and NEXT_PUBLIC_SUPABASE_URL

## Overview

The dev server (`npm run dev` / `tsx server/index.ts`) crashes immediately on startup when `SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_URL` environment variables are missing. The Doppler `dev` config contains no Supabase secrets, and no `.env.local` file exists in the worktree. This blocks all browser-based test scenarios (progress indicator visual verification, PDF upload flow) that require a running server.

## Problem Statement

Three call sites use `process.env.NEXT_PUBLIC_SUPABASE_URL!` with non-null assertions that evaluate during module load or middleware execution:

1. **`lib/supabase/service.ts:serverUrl()`** -- throws `"Missing SUPABASE_URL and NEXT_PUBLIC_SUPABASE_URL"` when both are absent
2. **`middleware.ts:60`** -- passes `process.env.NEXT_PUBLIC_SUPABASE_URL!` to `createServerClient()`, which crashes the Supabase client constructor
3. **`lib/supabase/client.ts:5`** / **`lib/supabase/server.ts:13`** -- same non-null assertion pattern

The `lib/csp.ts:buildCspHeader()` already handles missing `NEXT_PUBLIC_SUPABASE_URL` gracefully (falls back to `*.supabase.co` in dev mode), but the Supabase client constructors do not.

### Root Cause

The Doppler `dev` config does not contain `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, or `SUPABASE_SERVICE_ROLE_KEY`. These exist only in `ci` and `prd` configs. Without a `.env.local` file, the dev server has no way to obtain these values.

### Environment Inventory

| Variable | `dev` | `ci` | `prd` |
|---|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | missing | `https://ifsccnjhymdmidffkzhl.supabase.co` | `https://api.soleur.ai` |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | missing | present | present |
| `SUPABASE_URL` | missing | missing | `https://ifsccnjhymdmidffkzhl.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | missing | missing | present |

## Proposed Solution

Two-part fix: add Supabase env vars to Doppler `dev` config AND make the dev server resilient to missing env vars for local development without Doppler.

### Part 1: Add Supabase secrets to Doppler `dev` config

Add the three required Supabase env vars to the Doppler `dev` config so that `doppler run -- npm run dev` works out of the box:

```bash
doppler secrets set NEXT_PUBLIC_SUPABASE_URL "https://ifsccnjhymdmidffkzhl.supabase.co" -p soleur -c dev
doppler secrets set NEXT_PUBLIC_SUPABASE_ANON_KEY "<value-from-ci-config>" -p soleur -c dev
doppler secrets set SUPABASE_SERVICE_ROLE_KEY "<value-from-prd-config>" -p soleur -c dev
```

This is the primary fix. Local dev should use `doppler run` to inject secrets, matching the pattern already used for other env vars in the `dev` config.

### Part 2: Graceful degradation for bare `npm run dev` (without Doppler)

Make the dev server startable without Supabase credentials, using placeholder values that produce clear runtime errors on actual Supabase API calls rather than crashing on startup:

1. **`lib/supabase/service.ts:serverUrl()`** -- In development mode, return a placeholder URL instead of throwing. Log a warning.
2. **`middleware.ts`** -- Guard the `createServerClient()` call with a check; if `NEXT_PUBLIC_SUPABASE_URL` is missing in dev mode, skip Supabase auth and allow unauthenticated access (the middleware already has public path handling).
3. **`lib/supabase/client.ts`** and **`lib/supabase/server.ts`** -- Use a fallback placeholder URL in dev mode with a console warning.

The key principle: **fail at point of use, not at startup**. The dev server should boot and serve pages; Supabase-dependent features should fail gracefully with clear error messages when env vars are missing.

## Technical Considerations

- **`NEXT_PUBLIC_` prefix semantics**: Variables with this prefix are inlined at build time by Next.js for client-side code. In dev mode (no build step), they are read at runtime. The placeholder approach works for dev but would break a production build.
- **Cookie-domain alignment**: The `createClient()` functions in `server.ts` and `middleware.ts` use `NEXT_PUBLIC_SUPABASE_URL` because auth cookies are scoped to this domain. In dev, this is irrelevant since there is no real auth session.
- **Existing tests**: Test files already set `process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co"` as a fallback pattern. The dev server should follow the same pattern.
- **CSP already handled**: `lib/csp.ts` already falls back to `*.supabase.co` in dev mode when the URL is empty. No changes needed there.
- **Playwright config**: The `playwright.config.ts` already provides env vars to its webServer configs. No changes needed there.

## Acceptance Criteria

- [ ] `doppler run -c dev -- npm run dev` starts the dev server without errors (with Doppler `dev` config containing Supabase secrets)
- [ ] `npm run dev` (without Doppler, without `.env.local`) starts the dev server with warning messages about missing Supabase env vars
- [ ] Dev server serves pages at `http://localhost:3000/login` without crashing
- [ ] Supabase-dependent API routes return clear error responses (not stack traces) when env vars are missing
- [ ] Existing unit tests pass (`vitest run`)
- [ ] Existing `server-url.test.ts` tests continue to pass
- [ ] No changes to production behavior (production still throws on missing env vars)

## Test Scenarios

- Given Doppler `dev` config contains `NEXT_PUBLIC_SUPABASE_URL`, when `doppler run -c dev -- npm run dev` is executed, then the server starts on port 3000
- Given no `.env.local` and no Doppler, when `npm run dev` is executed, then the server starts with warning logs about missing Supabase env vars
- Given missing `NEXT_PUBLIC_SUPABASE_URL` in dev mode, when middleware processes a request to `/login`, then the page renders without crashing
- Given missing `NEXT_PUBLIC_SUPABASE_URL` in dev mode, when middleware processes a request to `/dashboard`, then the user is redirected to `/login` (not a 500 error)
- Given `NODE_ENV=production` and missing `NEXT_PUBLIC_SUPABASE_URL`, when the server starts, then it still throws (production behavior unchanged)
- Given missing `SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_URL` in dev mode, when `serverUrl()` is called, then it returns a placeholder and logs a warning (not throws)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change for local development ergonomics.

## Implementation Notes

### Files to modify

1. **`apps/web-platform/lib/supabase/service.ts`** -- Add dev-mode fallback in `serverUrl()` instead of throwing
2. **`apps/web-platform/lib/supabase/client.ts`** -- Add dev-mode fallback for missing URL
3. **`apps/web-platform/lib/supabase/server.ts`** -- Add dev-mode fallback for missing URL (line 13)
4. **`apps/web-platform/middleware.ts`** -- Guard Supabase client creation with env var check in dev mode
5. **`apps/web-platform/app/(auth)/callback/route.ts`** -- Guard line 26 `NEXT_PUBLIC_SUPABASE_URL!` usage

### Doppler config changes

```bash
# Copy NEXT_PUBLIC_SUPABASE_ANON_KEY from ci to dev
doppler secrets get NEXT_PUBLIC_SUPABASE_ANON_KEY -p soleur -c ci --plain | xargs -I{} doppler secrets set NEXT_PUBLIC_SUPABASE_ANON_KEY "{}" -p soleur -c dev

# Set NEXT_PUBLIC_SUPABASE_URL in dev (use direct Supabase URL, not custom domain)
doppler secrets set NEXT_PUBLIC_SUPABASE_URL "https://ifsccnjhymdmidffkzhl.supabase.co" -p soleur -c dev

# Copy SUPABASE_SERVICE_ROLE_KEY from prd to dev
doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c prd --plain | xargs -I{} doppler secrets set SUPABASE_SERVICE_ROLE_KEY "{}" -p soleur -c dev
```

### Fallback pattern

```typescript
// In lib/supabase/service.ts
const DEV_PLACEHOLDER = "https://placeholder.supabase.co";

export function serverUrl(): string {
  const url = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!url) {
    if (process.env.NODE_ENV !== "production") {
      console.warn(
        "[supabase] Missing SUPABASE_URL and NEXT_PUBLIC_SUPABASE_URL -- " +
        "Supabase calls will fail. Run with: doppler run -c dev -- npm run dev"
      );
      return DEV_PLACEHOLDER;
    }
    throw new Error("Missing SUPABASE_URL and NEXT_PUBLIC_SUPABASE_URL");
  }
  return url;
}
```

## References

- Prior fix for server-side Supabase URL: `knowledge-base/project/learnings/runtime-errors/docker-dns-supabase-custom-domain-20260406.md`
- Prior spec: `knowledge-base/project/specs/feat-fix-supabase-service-client/`
- Existing server-url tests: `apps/web-platform/test/lib/supabase/server-url.test.ts`
- Playwright config with env var patterns: `apps/web-platform/playwright.config.ts`
