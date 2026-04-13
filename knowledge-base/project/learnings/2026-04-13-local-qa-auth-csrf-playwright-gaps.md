# Learning: Local QA auth flow gaps — magic link redirect, CSRF port mismatch, missing test fixtures

## Problem

Running Playwright-based QA on the chat feature required authenticating as a test
user. Four sequential blockers emerged:

1. **Vitest from bare root** — `npx vitest` at the bare repo root fails with
   native binding errors. Must run from `apps/web-platform/` with `npm install`.
2. **Magic link redirect** — Supabase `generate_link` API ignores the
   `redirect_to` parameter and always redirects to the Site URL configured in the
   Supabase dashboard (`https://app.soleur.ai`), not `http://localhost:3847`.
3. **CSRF port mismatch** — `validate-origin.ts` hardcodes `DEV_ORIGINS` to
   `http://localhost:3000`. Any dev server on a different port (e.g., 3847 used
   by Playwright to avoid port conflicts) gets a 403 Forbidden on all POST routes.
4. **Chat route requires conversationId** — No index route at `/dashboard/chat`,
   so navigating there returns 404. Must create a conversation via API first.

## Solution

Workarounds used in the session:

- Extracted access token from magic link, set it as a browser cookie directly
- Updated `tc_accepted_version` via Supabase admin API (bypassing the 403'd
  accept-terms endpoint)
- Created a conversation via Supabase REST API, then navigated to
  `/dashboard/chat/<id>`

## Key Insight

The local QA auth flow has no automated path. Each manual workaround is fragile
and session-specific. The CSRF port restriction is a real code gap — any developer
on a non-3000 port is silently blocked. The test setup needs a dedicated seed
script or fixture that creates a fully provisioned test user with accepted terms,
valid API key stub, and a conversation with sample messages.

## Session Errors

1. **npx vitest native binding error from bare root** — Recovery: ran from
   worktree `apps/web-platform/`. Prevention: always run test commands from the
   app directory, not the bare root.
2. **Supabase magic link redirects to production** — Recovery: extracted token
   and set cookie manually. Prevention: use password-based sign-in for test
   accounts (already done in this session) or create a seed script.
3. **CSRF 403 on port 3847** — Recovery: bypassed accept-terms via admin API.
   Prevention: make `DEV_ORIGINS` dynamic using `NEXT_PUBLIC_APP_URL` env var.
4. **Chat page 404 at /dashboard/chat** — Recovery: created conversation via API.
   Prevention: QA seed script should create a conversation with sample messages.

## Tags

category: integration-issues
module: web-platform
