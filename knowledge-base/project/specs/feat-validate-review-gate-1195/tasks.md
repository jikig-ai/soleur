# Tasks: validate review gate selection against offered options

Closes #1195

## Phase 1: Type Changes

- [ ] 1.1 Add `ReviewGateEntry` interface to `apps/web-platform/server/review-gate.ts`
- [ ] 1.2 Change `AgentSession.reviewGateResolvers` type from `Map<string, (selection: string) => void>` to `Map<string, ReviewGateEntry>`
- [ ] 1.3 Update `abortableReviewGate` to accept `options: string[]` parameter and store it with the resolver
- [ ] 1.4 Update cleanup paths (abort handler, timeout handler) to work with new map value type

## Phase 2: Validation Logic

- [ ] 2.1 Add `validateSelection` function to `apps/web-platform/server/review-gate.ts` (max length check + options inclusion check)
- [ ] 2.2 Update `resolveReviewGate` in `apps/web-platform/server/agent-runner.ts` to call `validateSelection` before resolving
- [ ] 2.3 Pass `gateOptions` from `canUseTool` AskUserQuestion block to `abortableReviewGate`
- [ ] 2.4 Add `"Invalid review gate selection"` to `KNOWN_SAFE_MESSAGES` in `apps/web-platform/server/error-sanitizer.ts`

## Phase 3: Tests

- [ ] 3.1 Update existing tests in `apps/web-platform/test/review-gate.test.ts` for `ReviewGateEntry` type
- [ ] 3.2 Add tests for `validateSelection`: valid option, invalid option, oversized string, empty string
- [ ] 3.3 Add test for `abortableReviewGate` storing options alongside resolver
- [ ] 3.4 Add test for error sanitizer mapping of new error message
- [ ] 3.5 Run full test suite and verify all tests pass
