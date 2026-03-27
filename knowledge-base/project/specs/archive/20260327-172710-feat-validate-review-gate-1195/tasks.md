# Tasks: validate review gate selection against offered options

Closes #1195

## Phase 1: Type Changes (`apps/web-platform/server/review-gate.ts`)

- [ ] 1.1 Add `ReviewGateEntry` interface with `resolve` and `options` fields
- [ ] 1.2 Export `MAX_SELECTION_LENGTH` constant (256)
- [ ] 1.3 Change `AgentSession.reviewGateResolvers` type from `Map<string, (selection: string) => void>` to `Map<string, ReviewGateEntry>`
- [ ] 1.4 Update `abortableReviewGate` signature to accept `options: string[]` parameter (5th param after `timeoutMs`)
- [ ] 1.5 Store `{ resolve, options }` in the resolver map instead of bare `resolve`
- [ ] 1.6 Update cleanup paths (abort handler, timeout handler) to work with new map value type -- `delete` calls are unchanged

## Phase 2: Validation Logic

- [ ] 2.1 Add `validateSelection(options, selection, maxLength?)` pure function to `apps/web-platform/server/review-gate.ts` -- throws on length > max or selection not in options
- [ ] 2.2 Import `validateSelection` in `apps/web-platform/server/agent-runner.ts`
- [ ] 2.3 Update `resolveReviewGate` to read `entry.options` from the map and call `validateSelection(entry.options, selection)` before `entry.resolve(selection)`
- [ ] 2.4 Pass `gateOptions` from `canUseTool` AskUserQuestion block to `abortableReviewGate` (5th argument)
- [ ] 2.5 Add Layer 1 transport-level guard in `apps/web-platform/server/ws-handler.ts` `review_gate_response` case -- reject if `typeof msg.selection !== "string"` or `msg.selection.length > 256` before calling `resolveReviewGate`
- [ ] 2.6 Add `"Invalid review gate selection"` to `KNOWN_SAFE_MESSAGES` in `apps/web-platform/server/error-sanitizer.ts`

## Phase 3: Tests

- [ ] 3.1 Update existing tests in `apps/web-platform/test/review-gate.test.ts` -- resolver access changes from `get("g1")!("Approve")` to `get("g1")!.resolve("Approve")`
- [ ] 3.2 Add `abortableReviewGate` test: stores options alongside resolver in the map
- [ ] 3.3 Add `validateSelection` unit tests: valid option passes, invalid option throws, oversized string throws, empty string throws, case mismatch throws, trailing whitespace throws
- [ ] 3.4 Add negative-space test: `resolveReviewGate` wires through to `validateSelection` (invalid selection through full function produces expected error)
- [ ] 3.5 Add test for error sanitizer mapping: `"Invalid review gate selection"` -> user-friendly message
- [ ] 3.6 Run full test suite (`cd apps/web-platform && npx vitest run`) and verify all tests pass
