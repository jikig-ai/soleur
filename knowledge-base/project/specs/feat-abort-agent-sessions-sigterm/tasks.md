# Tasks: abort active agent sessions during SIGTERM shutdown

Source: `knowledge-base/project/plans/2026-04-06-feat-abort-agent-sessions-sigterm-plan.md`

## Phase 1: Core Implementation

### 1.1 Add `abortAllSessions()` to agent-runner.ts

- [ ] 1.1.1 Create `abortAllSessions()` function that iterates `activeSessions` and calls `session.abort.abort()` on each with reason "server_shutdown"
- [ ] 1.1.2 Export the function from `agent-runner.ts`
- [ ] 1.1.3 Verify existing abort patterns (disconnect, superseded, account_deleted) are not modified

### 1.2 Wire into SIGTERM handler

- [ ] 1.2.1 Import `abortAllSessions` in `server/index.ts`
- [ ] 1.2.2 Call `abortAllSessions()` before the WebSocket close loop in the SIGTERM handler
- [ ] 1.2.3 Verify conversation status flows to "failed" via existing catch block (no new DB calls needed)

## Phase 2: Testing

### 2.1 Unit tests

- [ ] 2.1.1 Create `apps/web-platform/test/abort-all-sessions.test.ts`
- [ ] 2.1.2 Test: `abortAllSessions()` calls abort on all active sessions
- [ ] 2.1.3 Test: `abortAllSessions()` is a no-op when no sessions exist
- [ ] 2.1.4 Test: abort reason includes "server_shutdown"
- [ ] 2.1.5 Test: "server_shutdown" reason does NOT trigger isSuperseded skip (catch block writes "failed")

## Phase 3: Verification

### 3.1 Type check and lint

- [ ] 3.1.1 Run `npx tsc --noEmit` in `apps/web-platform/`
- [ ] 3.1.2 Run markdownlint on changed `.md` files
