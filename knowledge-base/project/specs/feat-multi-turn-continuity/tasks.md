# Tasks: Multi-Turn Conversation Continuity

## Phase 0: SDK Resume Spike

- [x] 0.1 Remove `persistSession: false` (SDK default is `true`)
- [x] 0.2 Complete session, capture `session_id` from first streamed message
- [x] 0.3 Locate session files on disk, verify inside persistent volume
- [x] 0.4 Kill process, restart, attempt resume
- [x] 0.5 Confirm resume works with full tool context in SDK 0.2.80
- [x] 0.6 Document spike findings

**Decision gate:** If resume fails across restarts, pivot to replay-primary.

## Phase 1: Core Session Resume

- [x] 1.1 Extend `AgentSession` type with `sessionId`
- [x] 1.2 Remove `persistSession: false` in query options
- [x] 1.3 Capture `session_id` from first streamed message (not init)
- [x] 1.4 Store `session_id` in `conversations.session_id` via Supabase
- [x] 1.5 Refactor `startAgentSession` to accept optional `sessionId` and `userMessage` (branch internally, don't duplicate setup)
- [x] 1.6 Refactor `sendUserMessage` to read `session_id` and route (add `user_id` auth check)
- [x] 1.7 First turn uses user's actual message, not hardcoded greeting
- [x] 1.8 Set status to `waiting_for_user` instead of `completed`

## Phase 2: Message Replay Fallback

- [x] 2.1 Add `loadConversationHistory` function
- [x] 2.2 Format messages as conversation context (last 20 messages, no tool call replay)
- [x] 2.3 Add resume-with-fallback logic
- [x] 2.4 Server startup cleanup for orphaned conversations
- [x] 2.5 REST endpoint for client-side message history loading

## Phase 3: WebSocket Reconnection

- [x] 3.1 Grace period before aborting session on disconnect
- [x] 3.2 Auto-resume conversation on reconnect
- [x] 3.3 TOCTOU guard: re-check `ws.readyState` after awaits
- [x] 3.4 Add typed error codes and WSMessage types for session transitions

## Phase 4: Lifecycle Management

- [x] 4.1 Inactivity timeout cleanup (24h)
- [x] 4.2 Explicit close mechanism (`close_conversation` WSMessage + handler)
- [x] 4.3 Work completion close trigger
- [x] 4.4 Orphan session file cleanup

## Phase 5: Testing

- [ ] 5.1 Multi-turn context retention test
- [ ] 5.2 WebSocket reconnection test
- [ ] 5.3 Fallback replay test
- [ ] 5.4 Session expiry test
- [ ] 5.5 Concurrent message handling test
