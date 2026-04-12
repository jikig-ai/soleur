# Tasks: fix: send resume\_session when opening existing conversations

## Phase 1: Setup

- [ ] 1.1 Read existing test files for patterns
  (`apps/web-platform/test/ws-deferred-creation.test.ts`,
  `apps/web-platform/test/ws-protocol.test.ts`)

## Phase 2: Core Implementation

- [ ] 2.1 Add `resumeSession` callback to `useWebSocket` hook
  (`apps/web-platform/lib/ws-client.ts`)
  - Add `resumeSession` callback that sends `resume_session` message
  - Add to the return object of the hook

- [ ] 2.2 Wire `resumeSession` into the chat page component
  (`apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`)
  - Destructure `resumeSession` from `useWebSocket`
  - Modify session initialization `useEffect` to call `resumeSession` for
    existing conversations (non-"new" conversationId)
  - Add `useEffect` to reset `sessionStarted` on reconnection
    (`status === "reconnecting"`)

## Phase 3: Testing

- [ ] 3.1 Add test: `resume_session` is sent when connecting to an existing
  conversation
- [ ] 3.2 Add test: `start_session` is still sent for new conversations
  (regression guard)
- [ ] 3.3 Add test: `resume_session` is re-sent after transient reconnection
- [ ] 3.4 Run existing test suite to verify no regressions
  (`cd apps/web-platform && npm test`)
