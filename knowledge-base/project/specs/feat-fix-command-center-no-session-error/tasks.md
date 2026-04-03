# Tasks: fix Command Center chat race condition

## Phase 1: Test Setup (TDD)

- [x] 1.1 Write failing test: `sendMessage` is NOT called until `session_started` event is received
  - File: `apps/web-platform/test/chat-page.test.tsx`
  - Extend mock to include `sessionConfirmed` in `wsReturn`
  - Test that when `sessionConfirmed` is `false`, `sendMessage` is not called even with `msg` param
  - Test that when `sessionConfirmed` flips to `true`, `sendMessage` is called with the `msg` param value

- [x] 1.2 Write failing test: `sessionConfirmed` resets on reconnection
  - File: `apps/web-platform/test/chat-page.test.tsx`
  - Verify that after a reconnection (status transitions through `reconnecting` to `connected`), `sessionConfirmed` starts as `false`

## Phase 2: Core Implementation

- [x] 2.1 Add `sessionConfirmed` state to `useWebSocket` hook
  - File: `apps/web-platform/lib/ws-client.ts`
  - Add `const [sessionConfirmed, setSessionConfirmed] = useState(false)`
  - Handle `session_started` message type explicitly in `onmessage` switch: set `sessionConfirmed = true`
  - Reset `sessionConfirmed` to `false` in `startSession` callback (before sending)
  - Reset `sessionConfirmed` to `false` at the top of `connect()` (reconnection path)
  - Reset `sessionConfirmed` to `false` in `teardown()` (non-transient close path)
  - Add `sessionConfirmed` to the `UseWebSocketReturn` interface and hook return value

- [x] 2.2 Update chat page to gate initial message on `sessionConfirmed`
  - File: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
  - Destructure `sessionConfirmed` from `useWebSocket`
  - Keep `sessionStarted` naming unchanged (per review: minimize diff noise in bug fix)
  - Change second `useEffect` dependency from `sessionStarted` to `sessionConfirmed`
  - Remove `status === "connected"` check from second effect (redundant -- `sessionConfirmed` implies connected)

## Phase 3: Test Verification

- [x] 3.1 Run test suite and verify all tests pass
  - Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/chat-page.test.tsx`
  - Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/ws-protocol.test.ts`

- [x] 3.2 Verify no regressions in existing test files
  - Run: `cd apps/web-platform && ./node_modules/.bin/vitest run`
