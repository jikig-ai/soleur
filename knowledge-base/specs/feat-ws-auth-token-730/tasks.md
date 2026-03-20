# Tasks: security: move WebSocket auth token from URL query string to first message

## Phase 1: Protocol Types

- [ ] 1.1 Add `{ type: "auth"; token: string }` to `WSMessage` union in `apps/web-platform/lib/types.ts`
- [ ] 1.2 Add `{ type: "auth_ok" }` to `WSMessage` union in `apps/web-platform/lib/types.ts`

## Phase 2: Server-Side Auth Refactor

- [ ] 2.1 Use closure-scoped `authenticated` boolean and `authTimer` in the connection handler (not on `ClientSession`) to keep unauthenticated connections out of the `sessions` Map
- [ ] 2.2 Refactor `setupWebSocket` connection handler: accept connection without auth, start 5s auth timeout via `setTimeout`
- [ ] 2.3 Handle first message as auth: validate token via `supabase.auth.getUser()`, set `authenticated = true`, `clearTimeout(authTimer)`, register session, send `{ type: "auth_ok" }`
- [ ] 2.4 Guard all non-auth first messages: if not `{ type: "auth" }`, close with `4003 "Auth required"` and `clearTimeout(authTimer)`
- [ ] 2.5 Implement auth timeout: close with `4001 "Auth timeout"` only if `!authenticated` (race guard)
- [ ] 2.6 Remove `authenticateConnection` function and query-string token extraction
- [ ] 2.7 Clean up auth failure log line (`ws-handler.ts:250`) -- URL no longer contains token
- [ ] 2.8 Ensure `clearTimeout(authTimer)` in the `ws.on("close")` handler to prevent timer leak on early disconnect

## Phase 3: Client-Side Auth Refactor

- [ ] 3.1 Remove token from WebSocket URL in `getWsUrl()` -- return `${proto}://${window.location.host}/ws` in `apps/web-platform/lib/ws-client.ts`
- [ ] 3.2 Send `{ type: "auth", token }` in `ws.onopen` handler in `apps/web-platform/lib/ws-client.ts`
- [ ] 3.3 Handle `auth_ok` message in `ws.onmessage`: set status to `connected`, reset backoff
- [ ] 3.4 Set initial status to `connecting` (not `connected`) until `auth_ok` is received
- [ ] 3.5 Add `auth` and `auth_ok` to message type handling in `ws.onmessage` switch

## Phase 4: Tests

- [ ] 4.1 Update URL construction tests in `apps/web-platform/test/ws-protocol.test.ts` -- URL should not contain `?token=`
- [ ] 4.2 Add test: `auth` message is valid client message
- [ ] 4.3 Add test: `auth_ok` message is valid server message
- [ ] 4.4 Update `isClientMessage` and `isServerMessage` helpers for new types
- [ ] 4.5 Update middleware test case `/ws?token=abc` in `apps/web-platform/test/middleware.test.ts`
- [ ] 4.6 Add test: malformed JSON as first message results in close(4003), not a crash
- [ ] 4.7 Run full test suite: `cd apps/web-platform && npx vitest run`

## Phase 5: Verify

- [ ] 5.1 Verify no token appears in any `console.log`, `console.warn`, or `console.error` in ws-handler.ts
- [ ] 5.2 Verify exhaustive switch in `handleMessage` accounts for `auth` type
- [ ] 5.3 Verify exhaustive switch in client `onmessage` accounts for `auth_ok` type
- [ ] 5.4 Verify `KeyInvalidError` / `errorCode: "key_invalid"` path in `agent-runner.ts` still works (not broken by auth refactor)
- [ ] 5.5 Run `bun test` or `npx vitest run` and confirm all tests pass
