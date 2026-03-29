# Tasks: WebSocket Rate Limiting

Source: `knowledge-base/project/plans/2026-03-29-sec-websocket-rate-limiting-plan.md`
Issue: #1046

## Phase 1: Setup and Foundation

- [ ] 1.1 Create `apps/web-platform/server/rate-limiter.ts` with `SlidingWindowCounter` class
  - [ ] 1.1.1 Implement sliding window counter with `Map<string, number[]>` tracking timestamps
  - [ ] 1.1.2 Implement `isAllowed(key: string): boolean` method that checks and records
  - [ ] 1.1.3 Implement lazy eviction of expired entries (prune on each `isAllowed()` call)
  - [ ] 1.1.4 Implement `getClientIp(req: IncomingMessage): string` helper (cf-connecting-ip > x-forwarded-for > remoteAddress)
- [ ] 1.2 Add `RATE_LIMITED: 4008` to `WS_CLOSE_CODES` in `apps/web-platform/lib/types.ts`
- [ ] 1.3 Add `rate_limited` to `WSErrorCode` type in `apps/web-platform/lib/types.ts`
- [ ] 1.4 Add `RATE_LIMITED` to `NON_TRANSIENT_CLOSE_CODES` in `apps/web-platform/lib/ws-client.ts` with message "Too many requests. Please try again later."

## Phase 2: Core Implementation

- [ ] 2.1 Integrate Layer 1 -- IP connection throttle in `server.on("upgrade")` handler
  - [ ] 2.1.1 Extract client IP from upgrade request using `getClientIp()`
  - [ ] 2.1.2 Check against `SlidingWindowCounter` (20/min default, `WS_RATE_LIMIT_CONNECTIONS_PER_MIN` env var)
  - [ ] 2.1.3 Reject with 429 status + socket destroy if over limit
- [ ] 2.2 Integrate Layer 2 -- pending connection limit in `wss.on("connection")` handler
  - [ ] 2.2.1 Track pending (unauthenticated) connections per IP with a `Map<string, number>` counter
  - [ ] 2.2.2 Increment on connection, decrement on auth success or close
  - [ ] 2.2.3 Reject with close code 4008 if pending count exceeds 5 (default, `WS_RATE_LIMIT_MAX_PENDING_PER_IP` env var)
- [ ] 2.3 Integrate Layer 3 -- session creation rate limit in `handleMessage()` for `start_session`
  - [ ] 2.3.1 Add `SlidingWindowCounter` for session creation keyed by userId
  - [ ] 2.3.2 Check before `createConversation()` call
  - [ ] 2.3.3 Send error message `{ type: "error", message: "Rate limited..." }` if over limit (30/hour default, `WS_RATE_LIMIT_SESSIONS_PER_HOUR` env var)
- [ ] 2.4 Update `wss.on("connection")` handler signature to accept `req: IncomingMessage` as second parameter
  - The emit side already passes `req` (`wss.emit("connection", ws, req)`) but the handler only accepts `(ws: WebSocket)` -- add the second param to access IP headers

## Phase 3: Testing

- [ ] 3.1 Create `apps/web-platform/test/rate-limiter.test.ts`
  - [ ] 3.1.1 Test SlidingWindowCounter allows requests within limit
  - [ ] 3.1.2 Test SlidingWindowCounter rejects requests over limit
  - [ ] 3.1.3 Test window expiry allows new requests after window passes
  - [ ] 3.1.4 Test lazy eviction removes expired entries on next call
  - [ ] 3.1.5 Test getClientIp extracts cf-connecting-ip header
  - [ ] 3.1.6 Test getClientIp falls back to x-forwarded-for
  - [ ] 3.1.7 Test getClientIp falls back to remoteAddress
- [ ] 3.2 Add rate limit assertions to `apps/web-platform/test/ws-protocol.test.ts`
  - [ ] 3.2.1 Test rate limit close code 4008 is in WS_CLOSE_CODES
  - [ ] 3.2.2 Test RATE_LIMITED is treated as non-transient (no reconnect)
- [ ] 3.3 Verify existing tests pass
  - [ ] 3.3.1 Run `bun test` in apps/web-platform and confirm all existing tests pass
