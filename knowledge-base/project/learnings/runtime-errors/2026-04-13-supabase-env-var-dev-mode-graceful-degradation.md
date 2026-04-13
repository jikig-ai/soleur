# Learning: Dev-mode graceful degradation for missing Supabase env vars

## Problem

The dev server (`npm run dev`) crashed on startup when `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` were missing from the environment. The Doppler `dev` config had no Supabase secrets, and no `.env.local` existed. Three call sites used non-null assertions (`process.env.NEXT_PUBLIC_SUPABASE_URL!`) that evaluated during module load or middleware execution, causing immediate crashes before any page could render.

## Solution

Two-part fix:

1. **Doppler config**: Added `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` to the Doppler `dev` config so `doppler run -c dev -- npm run dev` works out of the box.

2. **Graceful degradation**: Added dev-mode fallbacks to all five Supabase entry points:
   - `service.ts`, `client.ts`, `server.ts`: Return placeholder URL in development, throw in production
   - `middleware.ts`: Skip entire Supabase auth block when `NODE_ENV=development` and vars missing
   - `callback/route.ts`: Redirect to login when vars missing in development

Key pattern:

```typescript
if (!process.env.NEXT_PUBLIC_SUPABASE_URL) {
  if (process.env.NODE_ENV === "production") {
    throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL");
  }
  // warn once, then use placeholder
}
```

## Key Insight

When adding dev-mode env var fallbacks, the critical mistake is using `!== "production"` as the guard — this also fires during `NODE_ENV=test`, breaking test suites that mock at the SDK level (not the env var level). The correct guard is `=== "development"` for middleware/routes, which are exercised by tests with mocked Supabase clients. For utility functions like `serverUrl()` that tests call directly with explicit NODE_ENV setup, `=== "development"` is also correct to avoid masking misconfigured test environments.

Second insight: per-request functions (`createClient()` in server.ts) fire on every page load. `console.warn` inside them produces log spam. Always use a module-level `let warned = false` guard for once-per-process warnings.

Third insight: initial implementation of `client.ts`/`server.ts` used `const url = process.env.X || PLACEHOLDER` — an unconditional `||` that fires in ALL environments including production. If production somehow loses env vars, the app silently connects to a placeholder domain instead of failing hard. Always handle production first (throw), then dev (fallback).

## Session Errors

**Billing enforcement test failure (200 instead of 403)** — Middleware guard with `!== "production"` skipped auth during NODE_ENV=test, causing billing enforcement to return 200 instead of 403. Recovery: Changed to `=== "development"`. Prevention: When adding early-return guards to middleware, always consider the test environment — tests mock at SDK level, not env var level.

**TypeScript TS2540 readonly NODE_ENV** — `process.env.NODE_ENV = "production"` in test file rejected by TypeScript. Recovery: Used `process.env = { ...originalEnv, NODE_ENV: "production" }` spread pattern. Prevention: Always use spread assignment for NODE_ENV in vitest tests.

**TypeScript TS2704 delete readonly** — `delete process.env.NODE_ENV` rejected by TypeScript. Recovery: Used destructuring `const { NODE_ENV: _, ...envWithout } = originalEnv`. Prevention: Use destructuring to exclude readonly properties from process.env.

**Review P1: Unconditional production fallback** — client.ts/server.ts `||` fallback worked in all environments including production. Recovery: Added explicit production throw before fallback assignment. Prevention: When adding env var fallbacks, always handle production case first (throw), then development case (fallback). Never use unconditional `||` for env vars that must exist in production.

**Review P1: Log spam per-request** — console.warn in createClient() fired on every request in dev. Recovery: Added module-level `warnedMissing` flag. Prevention: Per-request functions must use warn-once patterns for dev-mode warnings.

## Tags

category: runtime-errors
module: web-platform/supabase
