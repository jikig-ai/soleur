# Learning: CSP appHost resolution and x-forwarded-host validation in Next.js middleware

## Problem

Production CSP `connect-src` contained `wss://localhost:3000` instead of `wss://app.soleur.ai`. This could block WebSocket connections on strict CSP-enforcing browsers. Additionally, Sentry error reporting was silently failing because the CSP only allowed `*.ingest.sentry.io` but the Sentry EU region uses `*.ingest.de.sentry.io`.

### Root Cause

`request.nextUrl.host` in Next.js middleware running behind a reverse proxy (Cloudflare) returns the custom server's bind address (`localhost:3000`), not the client-facing hostname. The auth callback route already solved this via `resolveOrigin()` in `lib/auth/resolve-origin.ts`, but the middleware was not using that validated pattern.

## Solution

Three changes applied:

1. **Middleware host resolution:** Replace `request.nextUrl.host` with `resolveOrigin()` which validates the forwarded host against an allowlist, preventing CSP injection via spoofed `x-forwarded-host` headers.

2. **Sentry EU region:** Add `https://*.ingest.de.sentry.io` to CSP `connect-src`. The `*` wildcard only matches one subdomain level, so `*.ingest.sentry.io` does not match `*.ingest.de.sentry.io`.

3. **Negative E2E test:** Added test confirming spoofed `x-forwarded-host: evil.com` is rejected and does not appear in CSP.

## Key Insight

When reusing a validated pattern (`resolveOrigin`) in a new location, always reuse the function itself rather than reimplementing the logic inline. The inline version in this case omitted the allowlist validation, creating a defense-in-depth gap that the existing function already addressed. CSP header values constructed from user-controllable headers are injection vectors.

## Session Errors

1. **`bun install --frozen-lockfile` failed in worktree** — The lockfile had changes from dependency updates. Recovery: ran `bun install` without `--frozen-lockfile`. Prevention: worktree-manager should detect lockfile drift and run without frozen flag automatically.

2. **Supabase `generateLink` admin API produces implicit grant, not PKCE** — The API always strips the path from `redirect_to`, producing `#access_token` hash fragments instead of `?code=` PKCE flow. This prevented workspace provisioning during E2E testing because the `/callback` route never ran. Recovery: bypassed callback by setting cookies directly and updating DB status. Prevention: document that `generateLink` is not suitable for E2E tests that need workspace provisioning; use Supabase test OTP or a dedicated provisioning endpoint instead.

3. **Playwright MCP tool parameter errors** — `browser_fill_form` requires a `fields` array, `browser_wait_for` requires `text`/`textGone`/`time` (not `url` event type), and `setTimeout` is not available in `browser_run_code`. Recovery: used correct parameter formats. Prevention: check tool schemas via ToolSearch before first use in a session.

## Tags

category: security-issue
module: web-platform
tags: [csp, x-forwarded-host, reverse-proxy, sentry, defense-in-depth, next-js-middleware]

## See Also

- `knowledge-base/project/learnings/2026-03-20-open-redirect-allowlist-validation.md` -- Original `resolveOrigin()` implementation that this fix extends to middleware
- #1075 -- Production verification issue
- #1291 -- Session persistence missing feature (AC5)
