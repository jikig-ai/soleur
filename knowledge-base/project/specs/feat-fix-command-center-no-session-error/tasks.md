# Tasks: fix Command Center chat race condition

## Phase 1: Test Setup (TDD)

- [ ] 1.1 Write failing test: `sendMessage` is NOT called until `session_started` event is received
  - File: `apps/web-platform/test/chat-page.test.tsx`
  - Extend mock to include `sessionConfirmed` in `wsReturn`
  - Test that when `sessionConfirmed` is `false`, `sendMessage` is not called even with `msg` param
  - Test that when `sessionConfirmed` flips to `true`, `sendMessage` is called with the `msg` param value

- [ ] 1.2 Write failing test: `sessionConfirmed` resets on new `startSession` call
  - File: `apps/web-platform/test/chat-page.test.tsx`
  - Verify that calling `startSession` resets `sessionConfirmed` to `false`

## Phase 2: Core Implementation

- [ ] 2.1 Add `sessionConfirmed` state to `useWebSocket` hook
  - File: `apps/web-platform/lib/ws-client.ts`
  - Add `const [sessionConfirmed, setSessionConfirmed] = useState(false)`
  - Handle `session_started` message type explicitly: set `sessionConfirmed = true`
  - Reset `sessionConfirmed` to `false` in `startSession` callback
  - Add `sessionConfirmed` to the hook's return value
  - Update `UseWebSocketReturn` interface

- [ ] 2.2 Update chat page to gate initial message on `sessionConfirmed`
  - File: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
  - Destructure `sessionConfirmed` from `useWebSocket`
  - Rename `sessionStarted` to `startRequested` (clarity: it tracks whether we sent the request, not whether server confirmed)
  - Change second `useEffect` dependency from `sessionStarted` to `sessionConfirmed`
  - Remove `status === "connected"` check from second effect (redundant -- `sessionConfirmed` implies connected)

## Phase 3: Test Verification

- [ ] 3.1 Run test suite and verify all tests pass
  - Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/chat-page.test.tsx`
  - Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/ws-protocol.test.ts`

- [ ] 3.2 Verify no regressions in existing test files
  - Run: `cd apps/web-platform && ./node_modules/.bin/vitest run`
