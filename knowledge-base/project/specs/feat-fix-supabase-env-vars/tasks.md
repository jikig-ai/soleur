# Tasks: fix dev server crashes on missing Supabase env vars

## Phase 1: Doppler Configuration

- [ ] 1.1 Add `NEXT_PUBLIC_SUPABASE_URL` to Doppler `dev` config (`https://ifsccnjhymdmidffkzhl.supabase.co`)
- [ ] 1.2 Add `NEXT_PUBLIC_SUPABASE_ANON_KEY` to Doppler `dev` config (copy from `ci` config)
- [ ] 1.3 Add `SUPABASE_SERVICE_ROLE_KEY` to Doppler `dev` config (copy from `prd` config)
- [ ] 1.4 Verify all three secrets: `doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c dev --plain`

## Phase 2: Core Implementation -- Graceful Degradation

- [ ] 2.1 Update `apps/web-platform/lib/supabase/service.ts`
  - [ ] 2.1.1 Add dev-mode fallback in `serverUrl()` -- return placeholder URL with warning instead of throwing
- [ ] 2.2 Update `apps/web-platform/lib/supabase/client.ts`
  - [ ] 2.2.1 Add dev-mode fallback for missing `NEXT_PUBLIC_SUPABASE_URL`
- [ ] 2.3 Update `apps/web-platform/lib/supabase/server.ts`
  - [ ] 2.3.1 Add dev-mode fallback for missing `NEXT_PUBLIC_SUPABASE_URL` (line 13)
- [ ] 2.4 Update `apps/web-platform/middleware.ts`
  - [ ] 2.4.1 Guard `createServerClient()` with env var check in dev mode
  - [ ] 2.4.2 Skip Supabase auth when env vars are missing in dev -- allow unauthenticated access
- [ ] 2.5 Update `apps/web-platform/app/(auth)/callback/route.ts`
  - [ ] 2.5.1 Guard line 26 `NEXT_PUBLIC_SUPABASE_URL!` usage

## Phase 3: Testing

- [ ] 3.1 Update `apps/web-platform/test/lib/supabase/server-url.test.ts`
  - [ ] 3.1.1 Add test: dev mode returns placeholder when both vars missing
  - [ ] 3.1.2 Add test: production mode still throws when both vars missing
- [ ] 3.2 Run full test suite: `vitest run`
- [ ] 3.3 Verify dev server starts without Doppler: `npm run dev`
- [ ] 3.4 Verify dev server starts with Doppler: `doppler run -c dev -- npm run dev`
