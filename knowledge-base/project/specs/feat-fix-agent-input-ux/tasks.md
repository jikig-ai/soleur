# Tasks: Fix Agent Input UX (Review Gates)

Issue: #1873
Plan: `knowledge-base/project/plans/2026-04-10-fix-agent-input-ux-broken-review-gates-plan.md`

## Phase 1: Improve question display

- [ ] 1.1 Refactor `ReviewGateCard` visual hierarchy in `page.tsx`
  - [ ] 1.1.1 Add a header label ("Agent needs your input") as a small caps subtitle
  - [ ] 1.1.2 Display the `question` prop with larger text and better contrast
  - [ ] 1.1.3 Add a question/input icon to the card header
  - [ ] 1.1.4 When question equals generic fallback, show "The agent is waiting for your decision -- select an option below"

## Phase 2: Fix button click errors

- [ ] 2.1 Extend `WSMessage` error type with optional `gateId` field
  - [ ] 2.1.1 Update `apps/web-platform/lib/types.ts` -- add `gateId?: string` to error message type
  - [ ] 2.1.2 Update `apps/web-platform/server/ws-handler.ts` -- pass `gateId` in error response for `review_gate_response` handler
- [ ] 2.2 Improve `ReviewGateCard` state management in `page.tsx`
  - [ ] 2.2.1 Replace `selected` state with a state machine: `idle` | `pending` | `resolved` | `error`
  - [ ] 2.2.2 Show loading spinner on the clicked button during `pending` state
  - [ ] 2.2.3 On error, reset to `idle` state so buttons become clickable again
  - [ ] 2.2.4 Display gate-specific errors inline on the card
- [ ] 2.3 Route gate-specific errors in `ws-client.ts`
  - [ ] 2.3.1 When receiving an error with `gateId`, emit targeted error to matching gate message instead of generic error bubble

## Phase 3: Dismiss resolved review gates

- [ ] 3.1 Add `resolved` field to `ChatMessage` in `ws-client.ts`
  - [ ] 3.1.1 Extend `ChatMessage` interface with `resolved?: boolean` and `selectedOption?: string`
  - [ ] 3.1.2 After sending `review_gate_response`, optimistically mark the message as resolved
- [ ] 3.2 Implement collapsed state in `ReviewGateCard`
  - [ ] 3.2.1 When `resolved === true`, render a compact summary: "You selected: [option]"
  - [ ] 3.2.2 Add CSS transition for smooth collapse animation
  - [ ] 3.2.3 Style collapsed state with subtle visual treatment (smaller, dimmed)

## Phase 4: Server-side resilience (stretch)

- [ ] 4.1 Add `review_gate_expired` WSMessage type in `types.ts`
- [ ] 4.2 Send `review_gate_expired` from `agent-runner.ts` when timeout fires
- [ ] 4.3 Handle `review_gate_expired` in `ws-client.ts` to proactively expire cards
- [ ] 4.4 Add `review_gate_resolved` confirmation message from server to client

## Phase 5: Testing

- [ ] 5.1 Add unit tests for `ReviewGateCard` state machine (idle, pending, resolved, error)
- [ ] 5.2 Add test for gate-specific error routing in ws-client
- [ ] 5.3 Add test for collapsed review gate rendering
- [ ] 5.4 Verify existing `review-gate.test.ts` tests pass unchanged
- [ ] 5.5 Verify existing `chat-page.test.tsx` tests pass unchanged
- [ ] 5.6 Add test for expired gate UI state
