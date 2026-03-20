# Tasks: feat: add T&C version tracking

## Phase 1: Database Migration

- [ ] 1.1 Create `apps/web-platform/supabase/migrations/007_add_tc_accepted_version.sql`
  - [ ] 1.1.1 Add `tc_accepted_version text` column to `public.users` (nullable, no default)
  - [ ] 1.1.2 Add column comment documenting the purpose
  - [ ] 1.1.3 Update `handle_new_user()` trigger to record `tc_accepted_version` from `raw_user_meta_data->>'tc_version'` (conditional on `tc_accepted = 'true'`)
  - [ ] 1.1.4 Verify column is NOT added to GRANT in migration 006 (auto-protected by existing whitelist model)

## Phase 2: Application Constants & Types

- [ ] 2.1 Create `apps/web-platform/lib/legal/tc-version.ts`
  - [ ] 2.1.1 Export `TC_VERSION = "1.0.0"` constant

## Phase 3: Core Implementation

- [ ] 3.1 Update auth callback (`apps/web-platform/app/(auth)/callback/route.ts`)
  - [ ] 3.1.1 Extract `tc_version` from `user.user_metadata` alongside existing `tc_accepted`
  - [ ] 3.1.2 Pass `tcVersion` to `ensureWorkspaceProvisioned`
  - [ ] 3.1.3 Update fallback upsert to include `tc_accepted_version` (conditional on `tcAccepted`, mirroring trigger logic)
- [ ] 3.2 Update middleware (`apps/web-platform/middleware.ts`)
  - [ ] 3.2.1 Import `TC_VERSION` from `lib/legal/tc-version`
  - [ ] 3.2.2 After auth check, query `tc_accepted_version` from `public.users` for the authenticated user
  - [ ] 3.2.3 If `tc_accepted_version !== TC_VERSION` (including NULL), redirect to `/accept-terms`
  - [ ] 3.2.4 Add `/accept-terms` to `PUBLIC_PATHS` if not already present (dependency on #940)
  - [ ] 3.2.5 Fail open on Supabase query errors (consistent with existing pattern)
- [ ] 3.3 Update accept-terms API route (dependency on #940 -- `apps/web-platform/app/api/accept-terms/route.ts`)
  - [ ] 3.3.1 Import `TC_VERSION`
  - [ ] 3.3.2 Write `tc_accepted_version: TC_VERSION` alongside `tc_accepted_at` on acceptance
- [ ] 3.4 Update signup form to include `tc_version: TC_VERSION` in user metadata

## Phase 4: Testing

- [ ] 4.1 Add middleware version check tests to `apps/web-platform/test/middleware.test.ts`
  - [ ] 4.1.1 Test: matching version proceeds normally
  - [ ] 4.1.2 Test: NULL version redirects to `/accept-terms`
  - [ ] 4.1.3 Test: stale version redirects to `/accept-terms`
  - [ ] 4.1.4 Test: fail-open on query error
- [ ] 4.2 Add version recording tests
  - [ ] 4.2.1 Test: signup with T&C accepted records version
  - [ ] 4.2.2 Test: signup without T&C does not record version
  - [ ] 4.2.3 Test: re-acceptance updates version and timestamp
- [ ] 4.3 Run full test suite (`bun test`)
