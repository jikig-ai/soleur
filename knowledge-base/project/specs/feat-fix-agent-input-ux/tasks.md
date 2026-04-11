# Tasks: Fix Agent Input UX (Review Gates)

Issue: #1873
Plan: `knowledge-base/project/plans/2026-04-10-fix-agent-input-ux-broken-review-gates-plan.md`

## Phase 0: Fix SDK schema mismatch (Critical -- root cause)

- [ ] 0.1 Fix question extraction in `agent-runner.ts` `canUseTool` callback
  - [ ] 0.1.1 Read `toolInput.questions[0].question` instead of `toolInput.question`
  - [ ] 0.1.2 Read `toolInput.questions[0].header` for card title
  - [ ] 0.1.3 Map `toolInput.questions[0].options[].label` for option strings
  - [ ] 0.1.4 Extract `toolInput.questions[0].options[].description` for richer UI
  - [ ] 0.1.5 Keep backward-compatible fallback if `toolInput.questions` is undefined
- [ ] 0.2 Fix response format in `canUseTool` return
  - [ ] 0.2.1 Return `{ questions, answers: { [questionText]: selection } }` as `updatedInput`
  - [ ] 0.2.2 Fall back to `{ ...toolInput, answer: selection }` for legacy calls
- [ ] 0.3 Extend `review_gate` WSMessage type in `types.ts`
  - [ ] 0.3.1 Add optional `header?: string` field
  - [ ] 0.3.2 Add optional `descriptions?: Record<string, string>` field

## Phase 1: Improve question display

- [ ] 1.1 Update `ReviewGateCard` props in `page.tsx`
  - [ ] 1.1.1 Accept `header` and `descriptions` props
  - [ ] 1.1.2 Display `header` as a tag/chip above the question
  - [ ] 1.1.3 Show option descriptions as subtext below each button label
  - [ ] 1.1.4 Add question mark SVG icon to card header
- [ ] 1.2 Update `ChatMessage` and `review_gate` handler in `ws-client.ts`
  - [ ] 1.2.1 Add `header` and `descriptions` fields to `ChatMessage`
  - [ ] 1.2.2 Map new fields from WSMessage in the `review_gate` handler

## Phase 2: Fix button click errors

- [ ] 2.1 Extend `WSMessage` error type with optional `gateId` field
  - [ ] 2.1.1 Update `apps/web-platform/lib/types.ts` -- add `gateId?: string` to error message type
  - [ ] 2.1.2 Update `apps/web-platform/server/ws-handler.ts` -- pass `gateId` in error response
- [ ] 2.2 Improve `ReviewGateCard` state management in `page.tsx`
  - [ ] 2.2.1 Replace `selected` state with state machine: `idle` | `pending` | `resolved` | `error`
  - [ ] 2.2.2 Show `SpinnerIcon` (from `components/icons/index.tsx`) on clicked button during `pending`
  - [ ] 2.2.3 On error, display inline error text and reset to `idle` after 3 seconds
- [ ] 2.3 Route gate-specific errors in `ws-client.ts`
  - [ ] 2.3.1 When receiving error with `gateId`, set `gateError` on matching message instead of appending error bubble

## Phase 3: Dismiss resolved review gates

- [ ] 3.1 Add resolved state to `ChatMessage` in `ws-client.ts`
  - [ ] 3.1.1 Add `resolved?: boolean` and `selectedOption?: string` fields
  - [ ] 3.1.2 After sending `review_gate_response`, optimistically mark message as resolved
- [ ] 3.2 Implement collapsed state in `ReviewGateCard`
  - [ ] 3.2.1 When `resolved === true`, render compact summary: check icon + "Selected: [option]"
  - [ ] 3.2.2 Add `transition-all duration-300` for smooth collapse
  - [ ] 3.2.3 Revert to full card if server sends error with matching `gateId`

## Phase 4: Server-side resilience (stretch)

- [ ] 4.1 Add `review_gate_expired` WSMessage type in `types.ts`
- [ ] 4.2 Send `review_gate_expired` from timeout handler in `agent-runner.ts`
- [ ] 4.3 Handle `review_gate_expired` in `ws-client.ts` to mark gates as expired
- [ ] 4.4 Render expired state in `ReviewGateCard` (dimmed, disabled buttons)

## Phase 5: Testing

- [ ] 5.1 Add unit tests for SDK schema extraction (correct fields, fallback)
- [ ] 5.2 Add unit test for correct `updatedInput` response format
- [ ] 5.3 Add test for `ReviewGateCard` state machine (idle, pending, resolved, error)
- [ ] 5.4 Add test for `gateId`-targeted error routing in `ws-client.ts`
- [ ] 5.5 Add test for collapsed review gate rendering
- [ ] 5.6 Verify existing `review-gate.test.ts` tests pass unchanged
- [ ] 5.7 Verify existing `chat-page.test.tsx` tests pass unchanged
- [ ] 5.8 Update `agent-runner-tools.test.ts` mock for new response format
