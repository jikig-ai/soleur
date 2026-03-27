# Tasks: fix race condition on session.conversationId with concurrent start_session

## Phase 1: Core Fix

### 1.1 Extract `abortActiveSession` helper in ws-handler.ts

- [ ] Create `abortActiveSession(userId, session)` function in `apps/web-platform/server/ws-handler.ts`
- [ ] Guard: return early if `session.conversationId` is falsy
- [ ] Call `abortSession(userId, oldConvId)` synchronously (fires AbortController.abort())
- [ ] Fire-and-forget Supabase update to set old conversation status to `"completed"` with `.then()` error logging
- [ ] Clear `session.conversationId = undefined` before returning
- [ ] Add `console.log` for tracing aborted sessions

### 1.2 Apply guard to `start_session` handler

- [ ] Add `abortActiveSession(userId, session)` call at the top of the `start_session` case block, before `createConversation`
- [ ] Verify the rest of the handler is unchanged

### 1.3 Apply guard to `resume_session` handler

- [ ] Add `abortActiveSession(userId, session)` call at the top of the `resume_session` case block, before the ownership check
- [ ] Verify the rest of the handler is unchanged

### 1.4 Optionally refactor `close_conversation` to reuse helper

- [ ] Evaluate whether `close_conversation` can use `abortActiveSession` or should keep its existing inline `await` pattern
- [ ] If refactored, verify `session_ended` message still sends correctly

## Phase 2: Testing

### 2.1 Add unit tests for abort-before-replace behavior

- [ ] In `apps/web-platform/test/ws-protocol.test.ts`, add a describe block for "concurrent session abort"
- [ ] Test: `start_session` with prior active conversationId triggers abort logic
- [ ] Test: `resume_session` with prior active conversationId triggers abort logic
- [ ] Test: `start_session` with no prior session works unchanged (guard is no-op)
- [ ] Test: `close_conversation` after prior abort returns early (conversationId already undefined)

### 2.2 Run existing tests

- [ ] Run `npx vitest run` in `apps/web-platform/` to verify no regressions

## Phase 3: Verification

### 3.1 Code review checklist

- [ ] Verify `abortSession()` fires synchronously before any `await` (ordering critical)
- [ ] Verify `abortActiveSession` is called before `createConversation` in `start_session`
- [ ] Verify `abortActiveSession` is called before ownership check in `resume_session`
- [ ] Verify fire-and-forget DB update has `.then()` error logging (not `.catch(() => {})`)
- [ ] Verify no import changes needed -- `abortSession` is already imported in ws-handler.ts
- [ ] Verify `supabase` is accessible in the helper scope (module-level const, already accessible)
