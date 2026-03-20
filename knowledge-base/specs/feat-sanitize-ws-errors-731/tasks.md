# Tasks: sanitize WebSocket error messages (#731)

## Phase 1: Setup

- [ ] 1.1 Create `apps/web-platform/server/error-sanitizer.ts` with `sanitizeErrorForClient` function
- [ ] 1.2 Create `apps/web-platform/test/error-sanitizer.test.ts` with unit tests

## Phase 2: Core Implementation

- [ ] 2.1 Update `apps/web-platform/server/agent-runner.ts` catch block (line 260-261) to use `sanitizeErrorForClient`
- [ ] 2.2 Update `apps/web-platform/server/ws-handler.ts` `start_session` catch (line 136-138) to use `sanitizeErrorForClient`
- [ ] 2.3 Update `apps/web-platform/server/ws-handler.ts` `chat` catch (line 162-163) to use `sanitizeErrorForClient`
- [ ] 2.4 Update `apps/web-platform/server/ws-handler.ts` `review_gate_response` catch (line 189-190) to use `sanitizeErrorForClient`
- [ ] 2.5 Update `apps/web-platform/server/ws-handler.ts` server-only type reflection (line 204-207) to use fixed string

## Phase 3: Testing

- [ ] 3.1 Run `bun test` to verify all existing tests pass
- [ ] 3.2 Run new `error-sanitizer.test.ts` tests pass
- [ ] 3.3 Verify `ws-protocol.test.ts` tests still pass
