# Tasks: Server-Side T&C Consent Recording

## Phase 1: Database Migration

- [ ] 1.1 Create `apps/web-platform/supabase/migrations/007_server_side_tc_accepted.sql`
  - [ ] 1.1.1 Replace `handle_new_user()` trigger function to remove `raw_user_meta_data->>'tc_accepted'` conditional
  - [ ] 1.1.2 Remove `tc_accepted_at` from the trigger INSERT (let callback be the single writer) OR set `tc_accepted_at = now()` unconditionally
  - [ ] 1.1.3 Verify migration applies cleanly on existing schema

## Phase 2: Callback Route (Server-Side Consent)

- [ ] 2.1 Modify `apps/web-platform/app/(auth)/callback/route.ts`
  - [ ] 2.1.1 Remove `tcAccepted` extraction from `user.user_metadata` (lines 29-31)
  - [ ] 2.1.2 Remove `tcAccepted` parameter from `ensureWorkspaceProvisioned` call (line 33)
  - [ ] 2.1.3 Update `ensureWorkspaceProvisioned` signature to `(userId: string, email: string)`
  - [ ] 2.1.4 In first-time user path: set `tc_accepted_at: new Date().toISOString()` unconditionally
  - [ ] 2.1.5 Add UPDATE path for trigger-created rows with `tc_accepted_at = NULL` (service client updates to `now()`)

## Phase 3: Signup Page Cleanup

- [ ] 3.1 Modify `apps/web-platform/app/(auth)/signup/page.tsx`
  - [ ] 3.1.1 Remove `data: { tc_accepted: tcAccepted }` from `signInWithOtp` options (line 24)
  - [ ] 3.1.2 Keep `tcAccepted` state and checkbox for button-disable UX enforcement
  - [ ] 3.1.3 Add comment explaining consent is recorded server-side in callback

## Phase 4: Testing and Verification

- [ ] 4.1 TypeScript type-check passes (`npx tsc --noEmit`)
- [ ] 4.2 Verify login flow is unaffected (no `tc_accepted` metadata read)
- [ ] 4.3 Verify existing migration chain applies cleanly (001-007)
- [ ] 4.4 Run existing test suite (`bun test`)
