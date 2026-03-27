# Tasks: fix race condition on session.conversationId with concurrent start_session

## Phase 1: Core Fix

### 1.1 Add abort-then-replace guard to start_session handler

- [ ] In `apps/web-platform/server/ws-handler.ts`, `start_session` case block (line 114), add a check before `createConversation` for an existing `session.conversationId`
- [ ] If `session.conversationId` is set, call `abortSession(userId, session.conversationId)`
- [ ] Update the old conversation status to `"completed"` via Supabase
- [ ] Clear `session.conversationId` before proceeding

### 1.2 Verify close_conversation parity

- [ ] Confirm the abort-then-replace guard mirrors the pattern in `close_conversation` (line 176-198)
- [ ] Ensure both handlers use `"completed"` status (not `"failed"`) for user-initiated transitions

## Phase 2: Testing

### 2.1 Add unit test for concurrent start_session

- [ ] In `apps/web-platform/test/ws-protocol.test.ts`, add a test verifying that `start_session` with a prior active conversationId triggers abort behavior
- [ ] Add a test verifying that `start_session` with no prior session works unchanged

### 2.2 Run existing tests

- [ ] Run `npx vitest run` in `apps/web-platform/` to verify no regressions

## Phase 3: Verification

### 3.1 Code review

- [ ] Verify the abort call happens before `createConversation` (ordering matters)
- [ ] Verify the `await` on the Supabase status update does not introduce a new race window
- [ ] Verify `abortSession` is a synchronous call (it is -- it calls `controller.abort()` which is sync)
