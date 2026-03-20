# Tasks: fix unawaited startAgentSession()

## Phase 1: Core Fix

### 1.1 Add .catch() to ws-handler.ts call site
- [ ] Open `apps/web-platform/server/ws-handler.ts`
- [ ] At line 130, chain `.catch()` onto `startAgentSession()` call
- [ ] In the catch handler: log error, extract message, send error to client via `sendToClient()`
- [ ] Import `KeyInvalidError` from `@/lib/types` if not already imported
- [ ] Attach `errorCode: "key_invalid"` when error is `KeyInvalidError` instance

### 1.2 Add .catch() to agent-runner.ts call site
- [ ] Open `apps/web-platform/server/agent-runner.ts`
- [ ] At line 296 in `sendUserMessage()`, chain `.catch()` onto `startAgentSession()` call
- [ ] In the catch handler: log error, extract message, send error to client via `sendToClient()`
- [ ] Call `updateConversationStatus(conversationId, "failed").catch(() => {})` for best-effort status update
- [ ] Attach `errorCode: "key_invalid"` when error is `KeyInvalidError` instance

## Phase 2: Testing

### 2.1 Verify existing tests pass
- [ ] Run `bun test` in `apps/web-platform/` to confirm no regressions

### 2.2 Verify TypeScript compiles
- [ ] Run `bunx tsc --noEmit` in `apps/web-platform/` to confirm type correctness
