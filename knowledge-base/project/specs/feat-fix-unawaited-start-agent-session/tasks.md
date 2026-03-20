# Tasks: fix unawaited startAgentSession()

## Phase 1: Core Fix

### 1.1 Add .catch() to ws-handler.ts call site
- [ ] Open `apps/web-platform/server/ws-handler.ts`
- [ ] Add import: `import { KeyInvalidError } from "@/lib/types";` (alongside existing WSMessage import)
- [ ] At line 130, chain `.catch()` onto `startAgentSession()` call
- [ ] In the catch handler: log error with `console.error('[ws] startAgentSession error:', err)`
- [ ] Extract message: `err instanceof Error ? err.message : "Failed to start session"`
- [ ] Send to client with `sendToClient(userId, { type: "error", message, errorCode: err instanceof KeyInvalidError ? "key_invalid" : undefined })`

### 1.2 Add .catch() to agent-runner.ts call site
- [ ] Open `apps/web-platform/server/agent-runner.ts`
- [ ] At line 296 in `sendUserMessage()`, chain `.catch()` onto `startAgentSession()` call
- [ ] In the catch handler: log error with `console.error('[agent] sendUserMessage session error for ${userId}/${conversationId}:', err)`
- [ ] Extract message: `err instanceof Error ? err.message : "Agent session failed"`
- [ ] Send to client with `sendToClient(userId, { type: "error", message, errorCode: err instanceof KeyInvalidError ? "key_invalid" : undefined })`
- [ ] Call `updateConversationStatus(conversationId, "failed").catch(() => {})` for best-effort status update
- [ ] Note: `KeyInvalidError` is already imported on line 7

## Phase 2: Verification

### 2.1 Verify TypeScript compiles
- [ ] Run `bunx tsc --noEmit` in `apps/web-platform/` to confirm type correctness

### 2.2 Verify existing tests pass
- [ ] Run `bun test` in `apps/web-platform/` to confirm no regressions
