# Tasks: fix setup-key redirect on invalid API key

## Phase 1: Protocol Enhancement

- [ ] 1.1 Add `WSErrorCode` union type (`"key_invalid" | "workspace_missing" | "session_failed"`) to `apps/web-platform/lib/types.ts`
- [ ] 1.2 Add optional `errorCode?: WSErrorCode` field to the `error` variant of `WSMessage` in `apps/web-platform/lib/types.ts`
- [ ] 1.3 Update `startAgentSession` catch block in `apps/web-platform/server/agent-runner.ts` (~line 255-261) to include `errorCode: "key_invalid" as const` when the error message includes "No valid API key"

## Phase 2: Client-Side Redirect

- [ ] 2.1 In `apps/web-platform/lib/ws-client.ts`, modify the `case "error"` handler to check `msg.errorCode === "key_invalid"` (no string fallback -- typed codes only)
- [ ] 2.2 On key-invalidation detection: stop the reconnect loop (`mountedRef.current = false`, `clearTimeout(reconnectTimerRef.current)`, `wsRef.current.onclose = null`, `wsRef.current.close()`)
- [ ] 2.3 Redirect to `/setup-key` via `window.location.href = "/setup-key"` followed by `return` (not `break`) to prevent post-redirect state updates

## Phase 3: Testing

- [ ] 3.1 Add test in `apps/web-platform/test/ws-protocol.test.ts` for error messages with `errorCode: "key_invalid"` -- verify it parses and the field is accessible
- [ ] 3.2 Add test for error messages without `errorCode` (backward compatibility) -- verify `errorCode` is `undefined`
- [ ] 3.3 Add test that `errorCode` is optional (both with and without parse successfully)
- [ ] 3.4 Verify existing `ws-protocol.test.ts` tests still pass
- [ ] 3.5 Verify existing `middleware.test.ts` tests still pass
- [ ] 3.6 Verify existing `byok.test.ts` tests still pass
- [ ] 3.7 Run full test suite with `bun test`
