# Tasks: Server-Side T&C Consent Recording

## Phase 1: Database Migration

- [ ] 1.1 Create `apps/web-platform/supabase/migrations/007_server_side_tc_accepted.sql`
  - [ ] 1.1.1 Replace `handle_new_user()` trigger function to remove `raw_user_meta_data->>'tc_accepted'` conditional
  - [ ] 1.1.2 Remove `tc_accepted_at` from the trigger INSERT (let callback be the single writer)
  - [ ] 1.1.3 Add migration comment explaining tc_accepted_at is now set exclusively by the callback route

## Phase 2: Callback Route (Server-Side Consent)

- [ ] 2.1 Modify `apps/web-platform/app/(auth)/callback/route.ts`
  - [ ] 2.1.1 Remove `tcAccepted` extraction from `user.user_metadata` (lines 29-31)
  - [ ] 2.1.2 Remove `tcAccepted` parameter from `ensureWorkspaceProvisioned` call (line 33)
  - [ ] 2.1.3 Update `ensureWorkspaceProvisioned` signature to `(userId: string, email: string)`
  - [ ] 2.1.4 Add `tc_accepted_at` to the SELECT column list (currently only selects `workspace_status`)
  - [ ] 2.1.5 In first-time user (no row) path: set `tc_accepted_at: new Date().toISOString()` unconditionally; remove `ignoreDuplicates: true` from upsert options to handle trigger race
  - [ ] 2.1.6 In existing-row path: if `tc_accepted_at` is NULL, issue UPDATE to set it (handles trigger-created rows)
  - [ ] 2.1.7 Combine `tc_accepted_at` and workspace updates into a single UPDATE when both needed

## Phase 3: Signup Page Cleanup

- [ ] 3.1 Modify `apps/web-platform/app/(auth)/signup/page.tsx`
  - [ ] 3.1.1 Remove `data: { tc_accepted: tcAccepted }` from `signInWithOtp` options (line 24)
  - [ ] 3.1.2 Keep `tcAccepted` state and checkbox for button-disable UX enforcement
  - [ ] 3.1.3 Add comment explaining consent is recorded server-side in callback

## Phase 4: Type Safety

- [ ] 4.1 Add `tc_accepted_at: string | null` to `User` interface in `apps/web-platform/lib/types.ts`

## Phase 5: Testing and Verification

- [ ] 5.1 TypeScript type-check passes (`npx tsc --noEmit`)
- [ ] 5.2 Verify login flow is unaffected (no `tc_accepted` metadata read)
- [ ] 5.3 Verify existing migration chain applies cleanly (001-007)
- [ ] 5.4 Run existing test suite (`bun test`)
