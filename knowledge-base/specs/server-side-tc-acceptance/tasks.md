# Tasks: Server-Side T&C Acceptance

Branch: `server-side-tc-acceptance`
Plan: `knowledge-base/plans/2026-03-20-security-server-side-tc-acceptance-plan.md`
Issue: #931

## Phase 1: Database Migration

- [ ] 1.1 Create `apps/web-platform/supabase/migrations/007_remove_tc_accepted_metadata_trust.sql`
  - [ ] 1.1.1 Replace `handle_new_user()` to always set `tc_accepted_at = NULL`
  - [ ] 1.1.2 Update column comment to reflect server-side acceptance route

## Phase 2: Server-Side Accept Terms Route

- [ ] 2.1 Create `apps/web-platform/app/api/accept-terms/route.ts`
  - [ ] 2.1.1 Validate auth session via `createClient()` + `getUser()`
  - [ ] 2.1.2 UPDATE `users SET tc_accepted_at = now()` via service role with `AND tc_accepted_at IS NULL` guard
  - [ ] 2.1.3 Return 401 for unauthenticated, 500 for DB errors, 200 for success

## Phase 3: Accept Terms Page

- [ ] 3.1 Create `apps/web-platform/app/(auth)/accept-terms/page.tsx`
  - [ ] 3.1.1 Render T&C checkbox with links to Terms & Conditions and Privacy Policy
  - [ ] 3.1.2 Submit button calls `POST /api/accept-terms`
  - [ ] 3.1.3 On success, redirect to `/setup-key` (or `/dashboard` if key exists)
  - [ ] 3.1.4 Match visual style of existing signup/login pages

## Phase 4: Callback Route Update

- [ ] 4.1 Modify `apps/web-platform/app/(auth)/callback/route.ts`
  - [ ] 4.1.1 Remove `tcAccepted` extraction from `user.user_metadata`
  - [ ] 4.1.2 Revert `ensureWorkspaceProvisioned` to `(userId, email)` signature
  - [ ] 4.1.3 Fallback INSERT always sets `tc_accepted_at: null`
  - [ ] 4.1.4 After provisioning, query `tc_accepted_at` and redirect to `/accept-terms` if NULL

## Phase 5: Signup Page Update

- [ ] 5.1 Modify `apps/web-platform/app/(auth)/signup/page.tsx`
  - [ ] 5.1.1 Remove `data: { tc_accepted: tcAccepted }` from `signInWithOtp` options
  - [ ] 5.1.2 Keep checkbox UI as client-side UX hint (disabled submit button)

## Phase 6: Middleware Enforcement

- [ ] 6.1 Modify `apps/web-platform/middleware.ts`
  - [ ] 6.1.1 Add `/accept-terms` and `/api/accept-terms` to `PUBLIC_PATHS`
  - [ ] 6.1.2 For authenticated users on protected routes, query `users.tc_accepted_at`
  - [ ] 6.1.3 Redirect to `/accept-terms` if `tc_accepted_at IS NULL`

## Phase 7: Verification

- [ ] 7.1 Type-check: `npx tsc --noEmit` passes
- [ ] 7.2 Verify attack scenario: direct Supabase auth API call with forged metadata results in middleware redirect to `/accept-terms`
- [ ] 7.3 Verify normal flow: signup -> magic link -> callback -> `/accept-terms` -> submit -> `/setup-key`
- [ ] 7.4 Verify returning user: login -> magic link -> callback -> `/dashboard` (no `/accept-terms` redirect)
- [ ] 7.5 Verify idempotency: double-submit on `/accept-terms` is safe
