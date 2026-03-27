# Tasks: fix race condition on session.conversationId with concurrent start_session

## Phase 1: Core Fix

### 1.1 Extract `abortActiveSession` helper in ws-handler.ts

- [x] Create `abortActiveSession(userId, session)` function in `apps/web-platform/server/ws-handler.ts`
- [x] Guard: return early if `session.conversationId` is falsy
- [x] Call `abortSession(userId, oldConvId)` synchronously (fires AbortController.abort())
- [x] Fire-and-forget Supabase update to set old conversation status to `"completed"` with `.then()` error logging
- [x] Clear `session.conversationId = undefined` before returning
- [x] Add `console.log` for tracing aborted sessions

### 1.2 Apply guard to `start_session` handler

- [x] Add `abortActiveSession(userId, session)` call at the top of the `start_session` case block, before `createConversation`
- [x] Verify the rest of the handler is unchanged

### 1.3 Apply guard to `resume_session` handler

- [x] Add `abortActiveSession(userId, session)` call at the top of the `resume_session` case block, before the ownership check
- [x] Verify the rest of the handler is unchanged

### 1.4 Optionally refactor `close_conversation` to reuse helper

- [x] Evaluate whether `close_conversation` can use `abortActiveSession` or should keep its existing inline `await` pattern
- [x] If refactored, verify `session_ended` message still sends correctly

## Phase 2: Testing

### 2.1 Add unit tests for abort-before-replace behavior

- [x] In `apps/web-platform/test/ws-abort.test.ts`, add describe blocks for "abortActiveSession" and "concurrent session abort scenarios"
- [x] Test: `start_session` with prior active conversationId triggers abort logic
- [x] Test: `resume_session` with prior active conversationId triggers abort logic
- [x] Test: `start_session` with no prior session works unchanged (guard is no-op)
- [x] Test: `close_conversation` after prior abort returns early (conversationId already undefined)

### 2.2 Run existing tests

- [x] Run vitest in `apps/web-platform/` to verify no regressions (244 passed, 0 failures)

## Phase 3: Verification

### 3.1 Code review checklist

- [x] Verify `abortSession()` fires synchronously before any `await` (ordering critical)
- [x] Verify `abortActiveSession` is called before `createConversation` in `start_session`
- [x] Verify `abortActiveSession` is called before ownership check in `resume_session`
- [x] Verify fire-and-forget DB update has `.then()` error logging (not `.catch(() => {})`)
- [x] Verify no import changes needed -- `abortSession` is already imported in ws-handler.ts
- [x] Verify `supabase` is accessible in the helper scope (module-level const, already accessible)
