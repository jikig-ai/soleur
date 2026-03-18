# Tasks: fix setup-key redirect on invalid API key

## Phase 1: Protocol Enhancement

- [ ] 1.1 Add optional `errorCode` field to the `error` variant of `WSMessage` in `apps/web-platform/lib/types.ts`
- [ ] 1.2 Update `startAgentSession` catch block in `apps/web-platform/server/agent-runner.ts` to include `errorCode: "key_invalid"` when the error originates from `getUserApiKey`

## Phase 2: Client-Side Redirect

- [ ] 2.1 In `apps/web-platform/lib/ws-client.ts`, modify the `case "error"` handler to detect key-invalidation errors (via `errorCode` or message string fallback)
- [ ] 2.2 On key-invalidation detection: stop the reconnect loop (`mountedRef.current = false`, clear timeout, null out `onclose`, close WebSocket)
- [ ] 2.3 Redirect to `/setup-key` via `window.location.href`

## Phase 3: Testing

- [ ] 3.1 Add test in `apps/web-platform/test/ws-protocol.test.ts` for error messages with `errorCode: "key_invalid"`
- [ ] 3.2 Add test for error messages without `errorCode` (backward compatibility)
- [ ] 3.3 Verify existing `ws-protocol.test.ts` tests still pass
- [ ] 3.4 Verify existing `middleware.test.ts` tests still pass
- [ ] 3.5 Verify existing `byok.test.ts` tests still pass
- [ ] 3.6 Run full test suite with `bun test`
