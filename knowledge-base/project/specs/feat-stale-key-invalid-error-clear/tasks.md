# Tasks: fix stale key_invalid error card on remount

## Status

| Phase | Status |
|-------|--------|
| 1. Test | pending |
| 2. Implementation | pending |
| 3. Verification | pending |

## Phase 1: Test (TDD)

- [ ] 1.1 Add test case to `apps/web-platform/test/error-states.test.tsx`: verify that `reconnect()` clears `lastError` (contract test via mock)
- [ ] 1.2 Add test case: verify connection setup effect clears `lastError` on re-run (remount scenario)
- [ ] 1.3 Add test case: verify `conversationId` change clears `lastError`
- [ ] 1.4 Add test case: verify existing error display still works after fix (no regression)
- [ ] 1.5 Update `apps/web-platform/test/chat-page.test.tsx` mock to include `lastError: null` and `reconnect: vi.fn()` in `wsReturn` (test hygiene)

## Phase 2: Implementation

- [ ] 2.1 Add `setLastError(null)` and `setDisconnectReason(undefined)` at the top of the connection setup `useEffect` in `apps/web-platform/lib/ws-client.ts` (line ~360, before `connect()` call)

## Phase 3: Verification

- [ ] 3.1 Run existing tests: `cd apps/web-platform && ./node_modules/.bin/vitest run test/error-states.test.tsx`
- [ ] 3.2 Run full test suite to confirm no regressions
- [ ] 3.3 Verify TypeScript compilation: `npx tsc --noEmit`
