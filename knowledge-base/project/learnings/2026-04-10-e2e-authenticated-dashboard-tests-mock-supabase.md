# Learning: E2E Testing Authenticated Dashboard Pages with Mock Supabase

## Problem

The web platform dashboard requires Supabase SSR authentication — the Next.js middleware calls `supabase.auth.getUser()` from cookies and redirects to `/login` if unauthenticated. Playwright's `page.route()` only intercepts browser-originated requests, not server-side HTTP calls. Existing E2E tests only covered public pages (login, signup, CSP) and avoided the auth boundary entirely.

## Solution

A three-layer mock architecture that handles both server-side and client-side auth:

### Layer 1: Mock Supabase HTTP Server (`e2e/mock-supabase.ts`)

Lightweight Node.js HTTP server responding to Supabase API endpoints:

- `GET /auth/v1/user` → returns mock user (consumed by middleware and API routes)
- `POST /auth/v1/token` → returns session for refresh, 400 for PKCE code exchange
- `GET /rest/v1/users?select=...` → returns appropriate data based on `select` param (T&C check, workspace lookup, onboarding state)
- `GET /rest/v1/conversations?*` → returns empty array

PostgREST `.single()` compatibility: checks `Accept: application/vnd.pgrst.object+json` header to return single objects vs arrays.

### Layer 2: Auth Cookie via Storage State

Playwright `globalSetup` writes a storage state JSON file containing the Supabase session cookie (`sb-localhost-auth-token`) directly — no browser launch needed. The authenticated project uses this `storageState` so all tests start with valid auth cookies.

### Layer 3: `page.route()` for Per-Test State Control

Each test intercepts `/api/kb/tree` to return controlled KB tree data, controlling which dashboard state renders (first-run, foundations, command-center). This avoids filesystem manipulation and allows parallel-safe state control.

### Playwright Config Structure

Two projects: `chromium` (public pages, no auth) and `authenticated` (dashboard tests, with storageState). `testMatch`/`testIgnore` globs separate the projects. The `webServer` env points both `NEXT_PUBLIC_SUPABASE_URL` and `SUPABASE_URL` at the mock.

## Key Insight

For Next.js + Supabase SSR apps, the auth boundary spans both server and client. A mock HTTP server pointed at by env vars handles both sides uniformly — the middleware's `createServerClient` and the browser's `createBrowserClient` both talk to the same mock. This avoids test-only production code (auth bypass env vars) while keeping the test setup self-contained.

## Session Errors

1. **Worktree creation not persisted** — Worktree-manager reported success but worktree vanished from `git worktree list`. Recovery: re-created the worktree. Prevention: verify worktree existence with `git worktree list` after creation.

2. **Playwright testMatch regex matched worktree path** — `/start-fresh/` regex matched directory name `feat-start-fresh-e2e` in the full path, causing all tests to run in the authenticated project. Recovery: switched to glob pattern `"**/start-fresh-*.e2e.ts"`. **Prevention:** Always use glob patterns (not regex) for `testMatch`/`testIgnore` when the pattern could match parent directory names — especially in worktree environments where feature names appear in paths.

3. **PostgREST `.single()` returns object, not array** — Mock returned arrays for all queries; `.single()` sends `Accept: application/vnd.pgrst.object+json` expecting a single object. Recovery: added Accept header detection to mock's `sendRows()` helper. **Prevention:** When mocking PostgREST, always check the Accept header for `pgrst.object+json` and respond with object vs array accordingly.

4. **Mock PKCE token exchange succeeded for invalid codes** — Mock's `/auth/v1/token` always returned success, so the callback route tried workspace provisioning (crashed with 500). Recovery: return 400 for `grant_type=pkce` requests. **Prevention:** Mock auth endpoints should fail by default for code exchange (PKCE) and only succeed for session refresh.

5. **globalSetup required browser binaries** — `chromium.launch()` needed Playwright browsers installed. Recovery: write storage state JSON directly with `fs.writeFileSync`. **Prevention:** For storage state that only needs cookies (no actual login flow), write the JSON file directly instead of launching a browser.

6. **Mock server port not freed between runs** — EADDRINUSE when re-running tests after interrupted globalTeardown. Recovery: manual `lsof -ti:PORT | xargs kill -9`. **Prevention:** Accept this as a local dev friction; in CI each run is fresh.

7. **First test timeout (30s) on server cold start** — Next.js dev server compilation exceeded the default 30s test timeout on first request. Recovery: increased authenticated project timeout to 60s. **Prevention:** Set higher timeouts for authenticated projects that require server-side rendering with cold compilation.

## Tags

category: test-infrastructure
module: apps/web-platform/e2e
