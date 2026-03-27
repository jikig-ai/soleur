# Session State

## Plan Phase

- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-fix-chat-reconnecting/knowledge-base/project/plans/2026-03-27-fix-chat-reconnecting-loop-plan.md
- Status: complete

### Errors

None

### Decisions

- **Root cause identified**: The `ws.onclose` handler in `ws-client.ts` ignores the `CloseEvent.code` property and blindly reconnects for all close reasons, including non-transient server-initiated closes (auth failure 4001, T&C not accepted 4004, superseded 4002, internal error 4005). This creates an infinite reconnect loop.
- **Fix approach**: Add a `NON_TRANSIENT_CLOSE_CODES` routing map and a `teardown()` helper extracted from the existing `key_invalid` redirect pattern. Branch on close codes in `onclose` -- redirect for auth/T&C failures, disconnect quietly for superseded/error, and reconnect with backoff only for transient failures (1006, etc.).
- **No new types or server changes needed**: The fix adds one `useState` for `disconnectReason` and one constant map. No changes to `ConnectionStatus`, `WSMessage`, or server-side code. The server already sends correct close codes.
- **Teardown pattern consistency is critical**: The TOCTOU learning (2026-03-20) documents how phantom sessions cause reconnect loops. The new close code handler must use the exact same teardown sequence as the existing `key_invalid` handler (mountedRef, clearTimeout, onclose=null, close).
- **Domain review**: No cross-domain implications -- pure client-side bug fix in WebSocket reconnection logic.

### Components Invoked

- `soleur:plan` -- Created initial plan with root cause analysis, proposed fix, acceptance criteria, test scenarios
- `soleur:deepen-plan` -- Enhanced plan with MDN CloseEvent documentation, concrete TypeScript implementation code, edge case analysis, security review, simplicity review
