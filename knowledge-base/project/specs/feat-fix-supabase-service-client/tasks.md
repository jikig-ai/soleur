# Tasks: fix server-side Supabase service client DNS resolution

## Phase 1: Setup

- [x] 1.1 Add `SUPABASE_URL` to Doppler `prd` config (`https://ifsccnjhymdmidffkzhl.supabase.co`)
  - `doppler secrets set SUPABASE_URL https://ifsccnjhymdmidffkzhl.supabase.co -p soleur -c prd`
- [x] 1.2 Verify the secret is stored: `doppler secrets get SUPABASE_URL -p soleur -c prd --plain`

## Phase 2: Core Implementation

- [x] 2.1 Add `serverUrl()` helper to `apps/web-platform/lib/supabase/server.ts`
  - Returns `SUPABASE_URL` with fallback to `NEXT_PUBLIC_SUPABASE_URL`
  - Export for use by other server modules
- [x] 2.2 Update `createServiceClient()` in `apps/web-platform/lib/supabase/server.ts` to use `serverUrl()`
- [x] 2.3 Update health check in `apps/web-platform/server/health.ts` to use `serverUrl()`
- [x] 2.4 Update `apps/web-platform/server/ws-handler.ts` to use `createServiceClient()` from centralized module
- [x] 2.5 Update `apps/web-platform/server/agent-runner.ts` to use `createServiceClient()` from centralized module
- [x] 2.6 Update `apps/web-platform/server/api-messages.ts` to use `createServiceClient()` from centralized module
- [x] 2.7 Update `apps/web-platform/server/session-sync.ts` to use `createServiceClient()` from centralized module

## Phase 3: Testing

- [x] 3.1 Add unit tests for `serverUrl()` helper (prefers `SUPABASE_URL`, falls back to `NEXT_PUBLIC_SUPABASE_URL`)
- [x] 3.2 Update existing health test if needed
- [x] 3.3 Run full test suite: 503 tests pass, 0 failures
- [x] 3.4 Run TypeScript check: clean, no errors

## Phase 4: Verification

- [ ] 4.1 Deploy to production (merge triggers CI release)
- [ ] 4.2 Verify `/health` returns `supabase: "connected"`: `curl -s https://app.soleur.ai/health | jq '.supabase'`
- [ ] 4.3 Verify `/api/repo/install` works (POST with valid auth)
- [ ] 4.4 Verify `/api/repo/create` works (POST with valid auth)
