# Tasks: fix health check supabase connected

Source: [Plan](../../plans/2026-04-07-fix-health-check-supabase-connected-plan.md)
Issue: #1685

## Phase 1: Fix

- [x] 1.1 Update `checkSupabase()` in `apps/web-platform/server/health.ts` to query `/rest/v1/users?select=id&limit=1` instead of `/rest/v1/`

## Phase 2: Test

- [x] 2.1 Verify existing unit tests pass (`apps/web-platform/test/server/health.test.ts`)
- [x] 2.2 Run E2E smoke test to confirm `/health` returns 200 with expected JSON shape

## Phase 3: Deploy and Verify

- [ ] 3.1 Ship PR via `/soleur:ship`
- [ ] 3.2 After deploy, verify production: `curl -s https://app.soleur.ai/health | jq '.supabase'` returns `"connected"`
