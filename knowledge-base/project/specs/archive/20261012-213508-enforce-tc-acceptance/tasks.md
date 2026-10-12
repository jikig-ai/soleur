# Tasks: enforce tc_accepted_at in middleware

**Plan:** `knowledge-base/project/plans/2026-03-20-security-enforce-tc-acceptance-middleware-plan.md`
**Branch:** `enforce-tc-acceptance`
**Issues:** Closes #933, Closes #931

## Phase 1: Setup

- [ ] 1.1 Read all files to be modified (`middleware.ts`, `ws-handler.ts`, `lib/types.ts`, `test/middleware.test.ts`)
- [ ] 1.2 Verify `tc_accepted_at` column exists via migration 005 review

## Phase 2: Core Implementation

- [ ] 2.1 Update `lib/types.ts` -- add `tc_accepted_at: string | null` to `User` interface
- [ ] 2.2 Update `middleware.ts` -- add `/accept-terms` and `/api/accept-terms` to `PUBLIC_PATHS`, add `tc_accepted_at` check after auth
  - [ ] 2.2.1 Query `public.users` for `tc_accepted_at` using the existing Supabase client
  - [ ] 2.2.2 Redirect to `/accept-terms` if `tc_accepted_at` is NULL
- [ ] 2.3 Create `app/api/accept-terms/route.ts` -- POST endpoint using service role to set `tc_accepted_at`
  - [ ] 2.3.1 Authenticate via `createClient()` / `getUser()`
  - [ ] 2.3.2 Use `createServiceClient()` for the UPDATE (bypasses column-level grant)
  - [ ] 2.3.3 Use `.is("tc_accepted_at", null)` guard for immutability
- [ ] 2.4 Create `app/(auth)/accept-terms/page.tsx` -- clickwrap acceptance page
  - [ ] 2.4.1 Checkbox with T&C and Privacy Policy links (same URLs as signup page)
  - [ ] 2.4.2 Submit handler POSTs to `/api/accept-terms`
  - [ ] 2.4.3 Redirect to `/dashboard` on success
  - [ ] 2.4.4 Match existing auth page visual style (dark theme, centered card, max-w-sm)
- [ ] 2.5 Update `server/ws-handler.ts` -- add `tc_accepted_at` check after WebSocket auth
  - [ ] 2.5.1 Query `tc_accepted_at` after user validation (line ~300)
  - [ ] 2.5.2 Close with code 4004 and reason "T&C not accepted" if NULL

## Phase 3: Testing

- [ ] 3.1 Update `test/middleware.test.ts`
  - [ ] 3.1.1 Add `/accept-terms` to PUBLIC_PATHS in test
  - [ ] 3.1.2 Add `/api/accept-terms` to PUBLIC_PATHS in test
  - [ ] 3.1.3 Test: `/accept-terms` is a public path
  - [ ] 3.1.4 Test: `/api/accept-terms` is a public path
- [ ] 3.2 Create `test/accept-terms.test.ts`
  - [ ] 3.2.1 Test: unauthenticated POST returns 401
  - [ ] 3.2.2 Test: authenticated user with NULL tc_accepted_at gets timestamp set
  - [ ] 3.2.3 Test: authenticated user with existing tc_accepted_at is not re-stamped
- [ ] 3.3 Run `bun test` to verify all tests pass
- [ ] 3.4 Run compound before commit
