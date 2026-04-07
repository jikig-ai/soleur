# Tasks: Wire ConversationContext for KB "Chat about this" Flow

## Phase 1: Setup

- [ ] 1.1 Read and understand existing ConversationContext flow end-to-end
  - `lib/types.ts` (interface), `ws-client.ts` (startSession), `ws-handler.ts` (start_session), `agent-runner.ts` (system prompt injection)

## Phase 2: Core Implementation

- [ ] 2.1 Add `?context=` param to KB viewer chat URL
  - File: `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx`
  - Add `&context=${encodeURIComponent(joinedPath)}` to `chatUrl`

- [ ] 2.2 Add context fetching to chat page
  - File: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
  - Read `?context=` param from `searchParams`
  - Add `useState` for `kbContext` and `contextLoading`
  - Add `useEffect` to fetch `/api/kb/content/<path>` when context param present
  - Construct `ConversationContext` with `{ path, type: "kb-viewer", content }`

- [ ] 2.3 Wire ConversationContext into startSession call
  - File: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
  - Modify session-start `useEffect` to wait for context fetch
  - Pass `kbContext` as second argument to `startSession`

## Phase 3: Testing

- [ ] 3.1 Add unit tests for context-param flow
  - File: `apps/web-platform/test/chat-page.test.tsx`
  - Test: startSession called with ConversationContext when `?context=` present
  - Test: graceful degradation when KB API returns 404
  - Test: no regression when no `?context=` param
  - Test: session waits for context fetch before starting

- [ ] 3.2 Add protocol test for start_session with context
  - File: `apps/web-platform/test/ws-protocol.test.ts`
  - Test: start_session message with context field is valid

- [ ] 3.3 Run existing test suite to verify no regressions
  - Run `npx vitest run` in `apps/web-platform/`
