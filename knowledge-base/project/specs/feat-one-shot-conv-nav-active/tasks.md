# Tasks — fix: conversations rail live status

Derived from `knowledge-base/project/plans/2026-09-30-fix-conversations-rail-live-status-plan.md` (post-review, incl. advisor P-findings).
Branch: `feat-one-shot-conv-nav-active`. Draft PR: #9270. Follow-up: #9293.

## Phase 1 — Tests first (failing)

- 1.1 Create `apps/web-platform/test/conversation-turn-start-status.test.ts`:
  - existing `completed` conversation + `chat` via `dispatchSoleurGo` →
    `updateConversationFor` invoked with `{ status: "active" }`.
  - legacy `sendUserMessage` → same assertion before `startAgentSession`.
  - `dispatchSoleurGo` setup throw after the write → guarded revert called
    with `{ status: "failed" }`, `onlyIfStatusIn: ["active"]`,
    `expectMatch: false`.
  - harness seams: reuse `ws-handler-cc-session-id-wiring.test.ts` /
    `agent-runner-result-branch-finalization.test.ts` mock shapes.
- 1.2 Create `apps/web-platform/test/conversations-rail-activity-event.test.tsx`:
  - mounted rail listing conversation C receives `CONVERSATION_ACTIVITY_EVENT`
    (`detail.conversationId = C`) → background `fetchConversations` runs again
    (no loading flash) and the row shows the updated status without remount.
  - negative: no dispatch happens on socket bind/resume alone.

## Phase 2 — Server: turn-start `status='active'` + guarded revert

- 2.1 `apps/web-platform/server/cc-dispatcher.ts` — in `dispatchSoleurGo`, add
  `status: "active"` to the existing `updateConversationFor` ownership write
  that bumps `last_active` (~line 3269).
- 2.2 `apps/web-platform/server/cc-dispatcher.ts` — on the dispatch throw
  path after that write, revert via
  `updateConversationFor(…, { status: "failed" }, { onlyIfStatusIn: ["active"],
  expectMatch: false, feature: "cc-dispatcher", op: "turn-start-revert" })`
  — mirrors `agent-runner.ts` `updateConversationStatusIfActive` (#3463).
- 2.3 `apps/web-platform/server/agent-runner.ts` — in `sendUserMessage`, after
  the ownership probe, write `{ status: "active", last_active }` via
  `updateConversationFor` (`feature: "agent-runner"`, op `turn-start-active`,
  `expectMatch: true`). Both `ws-handler.ts` `chat` call sites covered.
- 2.4 Do NOT touch `resume_session` / `start_session` status — viewing is not a
  turn (plan Technical Considerations).

## Phase 3 — Client: deterministic rail refresh on derived state

- 3.1 `apps/web-platform/hooks/use-conversations.ts` — export
  `CONVERSATION_ACTIVITY_EVENT = "soleur:conversation-activity"`; add a window
  listener that runs a debounced (~500 ms) `fetchConversations({ background:
  true })`; cleanup removes listener + clears the timer.
- 3.2 `apps/web-platform/components/chat/chat-surface.tsx` — dispatch the
  event (CustomEvent, `detail: { conversationId }`) when `streamState`
  enters/leaves `"streaming"` and on the `awaitingUserInput`/gate transition
  — derived state only; do NOT key on raw frames (`stream_start` is
  legacy-only; `session_started` fires on socket bind/resume — a forbidden
  false-positive per plan AC).

## Phase 4 — Verify

- 4.1 Run new tests + existing rail/handler suites:
  `cd apps/web-platform && ./node_modules/.bin/vitest run test/conversation-turn-start-status.test.ts test/conversations-rail-activity-event.test.tsx test/conversations-rail.test.tsx test/conversations-rail-insert.test.tsx test/conversations-rail-connect-race.test.tsx test/conversations-active-repo-scope.test.tsx test/use-conversations-limit.test.tsx test/ws-handler-cc-session-id-wiring.test.ts`
- 4.2 Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- 4.3 Browser QA (playwright): open a `completed` conversation in the
  Concierge, send a message, observe the rail badge flip to `In progress`
  while `Working…` shows — without leaving the route. Before/after
  screenshots.
- 4.4 Re-entry regression: navigate away and back — badge still correct.
