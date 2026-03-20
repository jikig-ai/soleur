# Tasks: sanitize WebSocket error messages (#731)

## Phase 1: Setup

- [x] 1.1 Create `apps/web-platform/server/error-sanitizer.ts` with `sanitizeErrorForClient` function
- [x] 1.2 Create `apps/web-platform/test/error-sanitizer.test.ts` with unit tests (including interpolated error and byok config leak tests)

## Phase 2: Core Implementation

- [x] 2.1 Update `apps/web-platform/server/agent-runner.ts` catch block (line 260-261) to use `sanitizeErrorForClient`
- [x] 2.2 Update `apps/web-platform/server/ws-handler.ts` `start_session` catch (line 136-138) to use `sanitizeErrorForClient`
- [x] 2.3 Update `apps/web-platform/server/ws-handler.ts` `chat` catch (line 161-164) to use `sanitizeErrorForClient` and add `console.error` logging
- [x] 2.4 Update `apps/web-platform/server/ws-handler.ts` `review_gate_response` catch (line 188-191) to use `sanitizeErrorForClient` and add `console.error` logging
- [x] 2.5 Update `apps/web-platform/server/ws-handler.ts` server-only type reflection (line 204-207) to use fixed string
- [x] 2.6 Add `import { sanitizeErrorForClient } from "./error-sanitizer"` to both files

## Phase 3: Testing

- [x] 3.1 Run `bun test` to verify all existing tests pass
- [x] 3.2 Verify new `error-sanitizer.test.ts` tests pass
- [x] 3.3 Verify `ws-protocol.test.ts` tests still pass
