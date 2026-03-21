# Session State

## Plan Phase

- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/enforce-tc-acceptance/knowledge-base/project/plans/2026-03-20-security-enforce-tc-acceptance-middleware-plan.md
- Status: complete

### Errors

None

### Decisions

- Middleware uses anon key, not service role — the existing Supabase client after getUser() has the user's auth context and can query public.users via the SELECT RLS policy. No elevated privileges needed for the read path.
- /api/accept-terms added to PUBLIC_PATHS — without this, the middleware would intercept the POST, find tc_accepted_at IS NULL, and redirect to /accept-terms, breaking the acceptance flow. The API route has its own auth check internally.
- WebSocket close code 4004 chosen to avoid collision with existing 4003 ("Auth required"). Close code table documented for future reference.
- getClaims() + custom access token hook documented as v2 optimization — eliminates both the getUser() server round-trip and the public.users DB query by injecting tc_accepted_at into JWT claims at token issuance time.
- Service role required for the POST /api/accept-terms write — migration 006 revoked UPDATE on tc_accepted_at from the authenticated role.

### Components Invoked

- soleur:plan (skill)
- soleur:deepen-plan (skill)
- context7 MCP (Next.js, Supabase docs)
- gh issue view (issues #933, #928, #925, #931, #934)
- Codebase research: middleware.ts, callback/route.ts, signup/page.tsx, ws-handler.ts, migrations, lib/types.ts, lib/supabase/server.ts
