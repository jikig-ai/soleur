# Tasks: fix stale key_invalid error card on remount

## Status

| Phase | Status |
|-------|--------|
| 1. Test | pending |
| 2. Implementation | pending |
| 3. Verification | pending |

## Phase 1: Test (TDD)

- [ ] 1.1 Add test case to `apps/web-platform/test/error-states.test.tsx`: verify that when the connection setup effect re-runs, `lastError` is cleared
- [ ] 1.2 Add test case: verify `conversationId` change clears `lastError`
- [ ] 1.3 Add test case: verify existing error display still works after fix (no regression)

## Phase 2: Implementation

- [ ] 2.1 Add `setLastError(null)` and `setDisconnectReason(undefined)` at the top of the connection setup `useEffect` in `apps/web-platform/lib/ws-client.ts` (line ~360, before `connect()` call)

## Phase 3: Verification

- [ ] 3.1 Run existing tests: `cd apps/web-platform && npx vitest run test/error-states.test.tsx`
- [ ] 3.2 Run full test suite to confirm no regressions
- [ ] 3.3 Verify TypeScript compilation: `npx tsc --noEmit`
