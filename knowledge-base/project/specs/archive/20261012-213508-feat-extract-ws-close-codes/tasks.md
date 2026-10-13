# Tasks: Extract shared WS_CLOSE_CODES constant

## Phase 1: Define Shared Constant

- [ ] 1.1 Add `WS_CLOSE_CODES` constant to `apps/web-platform/lib/types.ts`
  - Define after existing `WSErrorCode` type
  - Use `as const` for literal type narrowing
  - Include all 5 codes: AUTH_TIMEOUT (4001), SUPERSEDED (4002), AUTH_REQUIRED (4003), TC_NOT_ACCEPTED (4004), INTERNAL_ERROR (4005)

## Phase 2: Update Consumers

- [ ] 2.1 Update `apps/web-platform/server/ws-handler.ts`
  - Add `WS_CLOSE_CODES` to existing import from `@/lib/types`
  - Replace all 7 inline `ws.close(40xx, ...)` calls with `ws.close(WS_CLOSE_CODES.*, ...)`
- [ ] 2.2 Update `apps/web-platform/lib/ws-client.ts`
  - Add `WS_CLOSE_CODES` to existing import from `@/lib/types`
  - Replace inline numeric keys in `NON_TRANSIENT_CLOSE_CODES` with computed property keys `[WS_CLOSE_CODES.*]`
- [ ] 2.3 Update `apps/web-platform/test/accept-terms.test.ts`
  - Import `WS_CLOSE_CODES` from `../lib/types`
  - Remove local `CLOSE_CODES` constant
  - Update test assertions to use `WS_CLOSE_CODES`

## Phase 3: Verification

- [ ] 3.1 Run `bun test` from `apps/web-platform/` -- all tests pass
- [ ] 3.2 Grep for remaining inline close code literals (`\b40(0[1-5])\b`) -- only `types.ts` should contain them
