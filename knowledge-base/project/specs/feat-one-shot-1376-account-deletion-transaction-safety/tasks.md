# Tasks: fix account deletion transaction safety

Source: [2026-04-02-fix-account-deletion-transaction-safety-plan.md](../../plans/2026-04-02-fix-account-deletion-transaction-safety-plan.md)
Issue: #1376

## Phase 1: Test Updates (TDD -- RED phase)

- [ ] 1.1 Update `apps/web-platform/test/account-delete.test.ts`: change cascade order test to expect `abort -> workspace -> auth` (no explicit `public.users` step)
- [ ] 1.2 Add new test: "when auth.admin.deleteUser fails, public.users is NOT deleted" -- mock `deleteUser` to reject, assert `from("users").delete()` is never called
- [ ] 1.3 Update auth failure test to verify `public.users` data remains intact (mock returns error, verify `from("users").delete()` not called)
- [ ] 1.4 Remove or update the "returns error when public.users deletion fails" test since explicit `public.users` deletion will be removed
- [ ] 1.5 Run tests -- confirm new/updated tests FAIL (RED phase)

## Phase 2: Implementation (GREEN phase)

- [ ] 2.1 In `apps/web-platform/server/account-delete.ts`: move `auth.admin.deleteUser()` call to execute before the `public.users` deletion
- [ ] 2.2 Remove the explicit `from("users").delete().eq("id", userId)` block -- FK cascade handles this
- [ ] 2.3 Update code comments to explain: auth deletion cascades to `public.users` via FK, and why auth-first ordering is critical for GDPR compliance
- [ ] 2.4 Run tests -- confirm all tests PASS (GREEN phase)

## Phase 3: Verification

- [ ] 3.1 Run full test suite: `cd apps/web-platform && npx vitest run test/account-delete.test.ts`
- [ ] 3.2 Verify no other files depend on the removed `public.users` deletion step (grep for callers)
- [ ] 3.3 Run TypeScript type check: `cd apps/web-platform && npx tsc --noEmit`
