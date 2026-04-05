# Tasks: Graceful SIGTERM Drain

## Phase 1: Setup

- [x] 1.1 Add `SERVER_GOING_AWAY: 1001` to `WS_CLOSE_CODES` in `apps/web-platform/lib/types.ts`
- [x] 1.2 Verify code 1001 is not in `NON_TRANSIENT_CLOSE_CODES` in `apps/web-platform/lib/ws-client.ts` (it should not be -- this ensures client auto-reconnects)

## Phase 2: Core Implementation

- [x] 2.1 In `apps/web-platform/server/index.ts`, capture the return value of `setupWebSocket(server)` into a `wss` variable
- [x] 2.2 Add `import { WebSocket } from "ws"` to `apps/web-platform/server/index.ts`
- [x] 2.3 Add `import { WS_CLOSE_CODES } from "@/lib/types"` to `apps/web-platform/server/index.ts`
- [x] 2.4 Replace the SIGTERM handler (lines 74-78) with the graceful shutdown implementation:
  - [x] 2.4.1 Define `SHUTDOWN_TIMEOUT_MS = 8_000` constant
  - [x] 2.4.2 Add `let shuttingDown = false` re-entrancy guard
  - [x] 2.4.3 Add re-entrancy check at handler entry: `if (shuttingDown) return; shuttingDown = true;`
  - [x] 2.4.4 Start a hard-deadline timer that force-exits after 8s with `server.closeAllConnections()` before `process.exit(1)` (`.unref()` the timer)
  - [x] 2.4.5 Call `server.close()` to stop accepting new connections
  - [x] 2.4.6 Call `server.closeIdleConnections()` to immediately release idle keep-alive connections
  - [x] 2.4.7 Iterate `wss.clients` and close each open WebSocket with code `WS_CLOSE_CODES.SERVER_GOING_AWAY` and reason `"Server shutting down"`
  - [x] 2.4.8 Call `await Sentry.flush(2_000)` (preserve existing behavior)
  - [x] 2.4.9 Log completion and call `process.exit(0)`

## Phase 3: Testing

- [x] 3.1 Create `apps/web-platform/test/server/shutdown.test.ts` with tests:
  - [x] 3.1.1 Test that `SERVER_GOING_AWAY` close code equals 1001
  - [x] 3.1.2 Test that code 1001 is not in `NON_TRANSIENT_CLOSE_CODES` (client will auto-reconnect)
  - [x] 3.1.3 Test that all `WS_CLOSE_CODES` values remain unique (regression guard)
- [x] 3.2 Run existing test suite to verify no regressions: `cd apps/web-platform && npx vitest run`
- [x] 3.3 Verify TypeScript compiles cleanly: `cd apps/web-platform && npx tsc --noEmit`

## Phase 4: Verification

- [x] 4.1 Run markdownlint on changed `.md` files
- [x] 4.2 Verify no new dependencies added to `package.json`
