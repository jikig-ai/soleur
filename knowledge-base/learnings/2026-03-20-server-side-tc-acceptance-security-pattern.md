# Learning: Server-side consent recording prevents client-controlled metadata forgery

## Problem
The T&C acceptance mechanism trusted Supabase `user_metadata.tc_accepted` set client-side during `signInWithOtp()`. An attacker could call the Supabase auth API directly with `tc_accepted: true` without rendering the signup form, creating GDPR Article 7 non-compliant consent records.

Both the SQL trigger (`005_add_tc_accepted_at.sql`) and the TypeScript callback fallback (`callback/route.ts`) read this client-controlled field as the source of truth.

## Solution
Replaced the client-metadata-based consent recording with a three-layer server-side enforcement model:

1. **Trigger always sets NULL** — Migration 007 replaces `handle_new_user()` to always insert `tc_accepted_at = NULL`, ignoring `raw_user_meta_data`.
2. **Server-side acceptance route** — `POST /api/accept-terms` writes `tc_accepted_at` via service role client with `AND tc_accepted_at IS NULL` idempotency guard.
3. **Middleware enforcement** — Queries `users.tc_accepted_at` for authenticated users on non-exempt paths; redirects to `/accept-terms` if NULL.

Key implementation details:
- Separated PUBLIC_PATHS (no auth) from TC_EXEMPT_PATHS (auth required, T&C check skipped) for defense-in-depth
- Cookie preservation on all middleware redirects prevents Supabase session desync
- API route checks UPDATE row count to detect missing user rows (prevents silent redirect loops)
- Service role client in callback (bypasses RLS for race condition safety); session client in middleware (respects RLS for established sessions)
- Path matching uses exact match + slash boundary (`pathname === p || pathname.startsWith(p + "/")`) to prevent prefix collisions

## Key Insight
Never trust client-supplied data for legally significant actions, even when the data flows through an auth provider's metadata system. Supabase `user_metadata` is client-writable by design — it is not a secure channel for recording consent. The fix pattern is: (1) stop reading the untrusted field, (2) create a server-side write path with a privileged client, (3) enforce the requirement in middleware so no protected route is accessible without it.

## Session Errors
1. **Context7 recommended `getClaims()` but SDK doesn't support it** — The plan recommended migrating middleware from `getUser()` to `getClaims()` based on Supabase SSR docs via Context7. The installed SDK (`@supabase/supabase-js` v2.49 / `@supabase/ssr` v0.6) does not expose `getClaims()`. Verified via `grep` in `node_modules`. Always verify API availability against the installed SDK version, not just documentation.
2. **Next.js lint required interactive ESLint setup** — `npm run lint` triggered a first-run setup prompt. Used `npx tsc --noEmit` as fallback for type checking.

## Tags
category: security-issues
module: web-platform/auth
