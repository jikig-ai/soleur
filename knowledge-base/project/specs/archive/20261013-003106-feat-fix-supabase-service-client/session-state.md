# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-04-06-fix-supabase-service-client-dns-resolution-plan.md
- Status: complete (deepen-plan skipped — subagent hit usage limit, plan is sufficient for focused bug fix)

### Errors

Subagent ran out of usage before running deepen-plan. Plan was created successfully.

### Decisions

- Introduce `SUPABASE_URL` env var (no `NEXT_PUBLIC_` prefix) for server-side direct Supabase URL
- Use `serverUrl()` helper in `lib/supabase/server.ts` with fallback to `NEXT_PUBLIC_SUPABASE_URL`
- Consolidate 4 duplicate service client instances into imports from `lib/supabase/server.ts`
- Keep cookie-based `createClient()` on custom domain for auth cookie alignment
- Add `SUPABASE_URL` to Doppler `prd` config only (local dev falls back)

### Components Invoked

- soleur:plan
