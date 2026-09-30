---
title: "fix: conversations rail does not show live in-progress status for the active conversation"
type: fix
date: 2026-09-30
slug: fix-conversations-rail-live-status
branch: feat-one-shot-conv-nav-active
priority: P2
domain: product
brand_survival_threshold: none
lane: cross-domain
---

# fix: conversations rail does not show live in-progress status for the active conversation

## Overview

In the Concierge chat UI, the left "RECENT CONVERSATIONS" rail shows a stale status badge for the conversation currently being viewed. While a session is actively running — the main pane shows a working indicator and the debug stream is streaming — the rail entry still displays the previous terminal state. Leaving the conversation and re-entering repaints the rail with the correct live state. The rail should reflect the active conversation's running status in real time.

## Problem Statement / Motivation

Operator report (2026-09-30, with screenshots): a conversation that is actively
running (`Working…` in the main pane, debug stream streaming) shows a `Done`
badge in the Recent Conversations rail. Exiting the conversation and
re-entering makes the rail show `In progress` correctly.

The badge reads `conversations.status` through `useConversations`
(`components/chat/conversations-rail.tsx` › `StatusBadge`). Two defects compose
into the reported symptom:

**Defect 1 — server: no `status='active'` write at turn start.** The write
inventory for `conversations.status` is exhaustive (grepped every
`updateConversationFor` / `updateConversationStatus` call site in `server/`):

| Write site | Value | When |
|---|---|---|
| `ws-handler.ts` › `createConversation` | `active` | row INSERT only |
| `permission-callback.ts` ×5 | `waiting_for_user` → `active` | tool/review gate open → resolve |
| `agent-runner.ts` › result branch | `waiting_for_user` (then inactivity sweep → `completed`) | legacy turn end |
| `cc-dispatcher.ts` › `updateConversationStatus` dep | passthrough for permission-callback | gate transitions |
| `ws-handler.ts` supersede / close_conversation | `completed` | session switch / close |
| `agent-runner.ts` reapers | `failed` / `completed` | orphan / stuck-active / inactivity |
| `conversations-tools.ts` › `conversation_update_status` | agent-driven | MCP tool |

A follow-up `chat` message on an existing `completed` / `waiting_for_user`
conversation flips **nothing** back to `active`: `dispatchSoleurGo`'s
turn-start write (`cc-dispatcher.ts` › `dispatchSoleurGo` ownership probe)
bumps `last_active` only; `sendUserMessage` (`agent-runner.ts`) writes no
status at all. The row keeps its terminal value for the whole run — the rail
faithfully renders a stale DB. The badge only reads `active` mid-run if a
permission gate happened to round-trip it, which is exactly why a refetch on
re-entry sometimes shows `In progress`: it catches the post-gate value.

**Defect 2 — client: no deterministic live-update path for the viewed
conversation.** The rail's realtime UPDATE subscription is the only in-place
update channel, and it is demonstrably lossy here (the same class the
`CONVERSATION_CREATED_EVENT` mechanism was built for — a server write lands in
the rail's navigation/re-subscribe window, or the channel dies unobserved). The
subscribe callback handles only `SUBSCRIBED`; `CHANNEL_ERROR` / `TIMED_OUT` /
`CLOSED` are silently ignored — no retry, no Sentry mirror, no fallback —
unlike `components/dashboard/leader-loop-status.tsx` which degrades to polling
on `isTerminalSubscribeStatus`.

## Proposed Solution

1. **Server — write `status: "active"` when a user turn starts on an existing
   conversation.** Two lineages, two chokepoints:
   - cc/soleur-go (Concierge, the reported path): add `status: "active"` to the
     `updateConversationFor` ownership write in `dispatchSoleurGo`
     (`cc-dispatcher.ts`) — it already writes `last_active` on every dispatch,
     so one statement covers all soleur-go turn starts (WS `chat` branches at
     `ws-handler.ts:1370` + `dispatchSoleurGoForConversation`, and
     `api/support/route.ts`).
   - legacy: `sendUserMessage` (`agent-runner.ts`) — after the ownership probe,
     `updateConversationFor(userId, conversationId, { status: "active",
     last_active: <now> }, { feature: "agent-runner", op:
     "turn-start-active", expectMatch: true })`. Covers both `ws-handler.ts`
     `chat` call sites.
   - Semantics: a user-initiated turn IS activity — unconditional flip
     (`completed`/`waiting_for_user`/`failed` → `active`) is correct;
     permission-gate writes remain consistent (`waiting_for_user` → `active`
     round-trips unchanged).
   - **Compensating write on cc dispatch failure (advisor P-finding, applied):**
     the `active` write precedes ~10 throw-eligible setup steps in
     `dispatchSoleurGo` (assertWriteScope, tenant mint, `convWsRow` select,
     message INSERT, `runner.dispatch`). On a throw the WS `chat` catch emits an
     error frame but writes no status — the row would stay `active`, and because
     the session heartbeat keeps `touchSlot` fresh, `find_stuck_active_…`
     never reaps it → permanent `In progress`. Mirror the legacy
     `handleSessionError` primitive (`agent-runner.ts` `updateConversationStatusIfActive`,
     #3463): a guarded `updateConversationFor(…, { status: "failed" },
     { onlyIfStatusIn: ["active"], expectMatch: false })` on the dispatch
     throw path — revert only when the turn-start flip is what set it.
   - **Existing semantic noted (advisor):** the cc lineage writes NO terminal
     `conversations.status` at normal turn end — `active` persists while the
     session stays bound; terminal values arrive via supersede / close /
     reapers / the MCP tool. This plan does not change that contract.
2. **Client — deterministic rail refresh on the viewed conversation's turn
   boundaries**, mirroring the `CONVERSATION_CREATED_EVENT` precedent in the
   same hook: new exported const `CONVERSATION_ACTIVITY_EVENT =
   "soleur:conversation-activity"` in `use-conversations.ts`; `chat-surface.tsx`
   dispatches it (CustomEvent, `detail: { conversationId }`) and the rail
   listener runs a quiet `fetchConversations({ background: true })`
   (debounced ~500 ms). Deliberately a refetch, not an optimistic patch — the
   terminal-status value (`waiting_for_user` vs `completed`) is server-owned.
   - **Trigger = derived state, not wire frames (advisor P-finding, applied):**
     `chat-surface` consumes `streamState` from `useWebSocket`, not raw frames;
     on the cc path `stream_start` is never emitted and `session_started` fires
     on socket bind (incl. resume-on-view — the exact false-positive the plan's
     own AC forbids). Dispatch on `streamState` entering/leaving `"streaming"`
     — lineage-agnostic and immune to per-leader frame multiplicity — plus on
     the `awaitingUserInput`/`review_gate` transition (the `waiting_for_user`
     → "Needs your decision" flip is the one badge demanding operator action;
     `chat-surface.tsx` already detects unresolved gate messages).

## Technical Considerations

- `updateConversationFor` is the single sanctioned write wrapper (R8 composite
  key + Sentry mirror) — both new writes route through it.
- Turn-start `active` is harmless under the reapers: a live turn holds a
  concurrency slot with a fresh heartbeat, so `find_stuck_active_conversations`
  does not match; a `waiting_for_user`-flipping gate mid-turn is followed by
  the gate-resolve `active` write — no new race introduced.
- `resume_session` deliberately does NOT get this write: binding a socket is
  not a running turn, and writing `active` there would flip a `completed`
  conversation to `In progress` on mere viewing — the inverse lie.
- Non-goal (filed for follow-through per `wg-when-deferring-a-capability-create-a`
  and CPO review): a dead-channel polling fallback in `useConversations`
  (the `leader-loop-status.tsx` `isTerminalSubscribeStatus` → `startPolling`
  pattern). The activity-event refetch covers the viewed conversation — the
  reported case — but a dead channel leaves NON-viewed rows stale too; that
  residual staleness class is tracked in a follow-up issue.
- Non-goal: migrating the rail to SWR (ADR-067 TR3, tracked by the still-open
  SWR-migration issue) — the fix works within the existing fetch + realtime
  design.

## Research Insights

- **Premise validation (Phase 0.6):** `conversations-rail.tsx`,
  `use-conversations.ts`, `nav-resume.ts`/`use-nav-resume.ts` all exist on the
  branch; the rail renders `conversation.status` via `StatusBadge` — the UI is
  built, not absent. ADR-067 explicitly deferred the rail's SWR migration
  (TR3), so a fix in the current fetch+realtime design is not
  architecture-conflicting. No cited issue/PR was stale.
- **Property list (Phase 0.6b):** (a) while a turn runs, the viewed
  conversation's rail badge shows the in-progress state; (b) the badge reaches
  that state without navigation; (c) no regression on terminal/needs-decision
  badges. The issue proposes no mechanism — nothing to cut.
- **Cut list:** none — the ask named no machinery; both fixes reuse existing
  mechanisms (`updateConversationFor`, the window-event precedent).
- **Status-write inventory:** the table in Problem Statement is the complete
  enumeration; `status: "active"` on an existing row is written only by
  permission-callback gate resolution.
- **Client precedents:** `CONVERSATION_CREATED_EVENT`
  (`use-conversations.ts`) is the established "realtime cannot be observed"
  deterministic signal; `leader-loop-status.tsx` › `isTerminalSubscribeStatus`
  is the dead-channel fallback precedent (deferred here, see Non-goal).
- **Realtime substrate:** `conversations` is in `supabase_realtime`
  (migration 034) with `REPLICA IDENTITY FULL` (migration 015); UPDATE events
  carry full rows.
- **Open code-review overlap (Phase 1.7.5):** `#3243` (cc-dispatcher
  decomposition) — acknowledge: a file-level refactor doesn't change this
  patch's two-line site. `#3242` (tool_use name field, cc-dispatcher +
  agent-runner) — acknowledge: unrelated event-field concern. `#3374`,
  `#2191` (ws-handler slot/jitter) — acknowledge: unrelated. No fold-ins.
- **Research execution note:** the pipeline's research subagents returned
  empty twice this session (Devin `run_subagent` spawned agents produced no
  output); local research above was performed inline by the planner — flagged
  for `compound` as a tooling-observation learning.

## Files to Edit

- `apps/web-platform/server/cc-dispatcher.ts` — `dispatchSoleurGo` ownership
  write gains `status: "active"` beside the existing `last_active` bump.
- `apps/web-platform/server/agent-runner.ts` — `sendUserMessage` writes
  `status: "active"` + `last_active` after the ownership probe.
- `apps/web-platform/hooks/use-conversations.ts` — export
  `CONVERSATION_ACTIVITY_EVENT`; add listener → debounced quiet refetch.
- `apps/web-platform/components/chat/chat-surface.tsx` — dispatch
  `CONVERSATION_ACTIVITY_EVENT` at `session_started`, `stream_start`,
  `session_ended`/`stream_end` with `detail.conversationId`.

## Files to Create

- `apps/web-platform/test/conversations-rail-activity-event.test.tsx` — rail
  refetches (and shows `In progress`) when the event fires for a listed id.
- `apps/web-platform/test/conversation-turn-start-status.test.ts` — asserts
  `updateConversationFor` receives `{ status: "active" }` on a `chat` dispatch
  to an existing `completed`/`waiting_for_user` conversation (both lineages,
  using the existing `ws-handler-cc-session-id-wiring` /
  `agent-runner-result-branch-finalization` harness seams).

## User-Brand Impact

- **If this lands broken, the user experiences:** the rail badge still shows a
  stale state while a session works — a cosmetic staleness regression, or
  (worst direction) a `completed` conversation reading `In progress` — pure
  display, no action is mis-gated (status is not a control input on this
  surface).
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  nothing — the write sets an existing status enum on an owner-scoped row the
  user already sees; no PII, no new reads, no cross-tenant surface.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the diff writes an existing enum field through the
  sanctioned owner-scoped wrapper and re-serves it on an already-visible
  badge; no credential, auth, payment, or data-access path is touched.`

## Observability

```yaml
liveness_signal:
  what: "conversations.status flips to 'active' on turn start; rail badge renders 'In progress' without navigation"
  cadence: "per user turn (event-driven); rail refresh on CONVERSATION_ACTIVITY_EVENT"
  alert_target: "Sentry web-platform (updateConversationFor mirrors write failures via reportSilentFallback, feature=cc-dispatcher/agent-runner)"
  configured_in: "apps/web-platform/server/conversation-writer.ts › updateConversationFor; apps/web-platform/hooks/use-conversations.ts"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN"
  fail_loud: "updateConversationFor returns ok:false + mirrors to Sentry on a failed status write; rail fetch failures already mirror via the hook's error path"

failure_modes:
  - mode: "turn-start status write fails (RLS/pool drop)"
    detection: "Sentry issue on feature=cc-dispatcher op=verify-conversation-ownership / feature=agent-runner op=turn-start-active"
    alert_route: "Sentry web-platform project"
  - mode: "rail realtime channel dead (CHANNEL_ERROR/TIMED_OUT) while viewing"
    detection: "badge stays stale despite active turn; CONVERSATION_ACTIVITY_EVENT refetch is the in-place recovery"
    alert_route: "no new route — same silent-miss class as pre-existing rail; non-goal note recorded"

logs:
  where: "web-platform server pino logs (updateConversationFor error path)"
  retention: "existing platform log retention"

discoverability_test:
  command: rg -l 'CONVERSATION_ACTIVITY_EVENT' apps/web-platform/hooks/use-conversations.ts apps/web-platform/components/chat/chat-surface.tsx
  expected_output: "use-conversations.ts"
```

## Domain Review

**Domains relevant:** product

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

The diff modifies no component file structure — the rail's badge and row are
unchanged; the change fixes when `conversations.status` becomes `active` and
when the rail refetches. The mechanical UI-surface glob does not fire (no
`components/**/*.tsx` created; `chat-surface.tsx` gains only an event dispatch,
no visual change). Tier resolved to advisory (modifies user-facing behavior,
no new interactive surface) and auto-accepts under the pipeline arm.

## Acceptance Criteria

- [ ] A `chat` message dispatched via `dispatchSoleurGo` on an existing
      conversation whose `status` is `completed` or `waiting_for_user` results
      in `updateConversationFor` being invoked with `status: "active"`.
- [ ] A `chat` message routed to `sendUserMessage` (legacy engine) results in
      `updateConversationFor` being invoked with `status: "active"` +
      `last_active` before agent dispatch.
- [ ] A `dispatchSoleurGo` setup throw AFTER the turn-start write results in a
      guarded `updateConversationFor` with `{ status: "failed" }`,
      `onlyIfStatusIn: ["active"]`, `expectMatch: false` (no permanent
      `active` row on a turn that never started; does NOT stomp a row another
      writer moved to `waiting_for_user`/`completed`).
- [ ] `CONVERSATION_ACTIVITY_EVENT` is exported from `use-conversations.ts`
      and dispatched by `chat-surface.tsx` when `streamState` enters and
      leaves `"streaming"` and on the `awaitingUserInput`/gate transition,
      carrying `detail.conversationId`.
- [ ] The rail listener refetches quietly (no loading flash) on the event; a
      listed conversation whose turn starts shows `In progress` without the
      user leaving the route.
- [ ] `resume_session` and socket reconnects write NO status change (viewing a
      `completed` conversation must not flip it to `In progress`); the event
      must NOT dispatch on socket bind/resume alone.
- [ ] No existing rail test regresses
      (`test/conversations-rail*.test.tsx`, `use-conversations-limit.test.tsx`,
      `ws-handler-cc-session-id-wiring.test.ts`).

## Test Scenarios

- Given an existing conversation at `status='completed'`, when the user sends
  a `chat` message (soleur-go dispatch), then `updateConversationFor` is called
  with `{ status: "active", last_active }` and `expectMatch: true`.
- Given an existing conversation at `status='waiting_for_user'`, when
  `sendUserMessage` runs, then the same active-flip write fires before
  `startAgentSession`.
- Given the rail is mounted listing conversation C, when chat-surface
  dispatches `CONVERSATION_ACTIVITY_EVENT` with `detail.conversationId = C`,
  then a background `fetchConversations` refetch occurs (RPC called again) and
  the row shows the updated status — without a remount.
- Given a permission gate opens mid-turn (`waiting_for_user`), when the gate
  resolves, then the existing permission-callback `active` write is unchanged
  and consistent with the turn-start write.
- Given `dispatchSoleurGo` throws during post-write setup (e.g. `convWsRow`
  select fails), when the dispatch-failure path runs, then a guarded
  `{ status: "failed" }` revert fires — and with `onlyIfStatusIn: ["active"]`
  it does NOT stomp a row a concurrent writer already moved to
  `waiting_for_user`/`completed`.
- Given the viewed conversation's `streamState` transitions into `"streaming"`,
  when `CONVERSATION_ACTIVITY_EVENT` fires, then the mounted rail runs a
  background refetch; on transition out, the same — the badge lands on the
  server-owned terminal value.
- Given a gate opens mid-turn (`awaitingUserInput`), when the event fires,
  then the rail refetches and the badge can render `Needs your decision`
  without navigation.
- Given the user merely re-enters a `completed` conversation (resume_session,
  no message), then no status write occurs AND no event dispatch — badge
  stays `Done`.
- **Browser:** open a completed conversation in the Concierge, send a message,
  observe the rail badge flip to `In progress` while `Working…` shows in the
  main pane — without navigating away and back. Screenshot before/after.
- **API verify:** `<REDACTED_SECRET> run test/conversation-turn-start-status.test.ts test/conversations-rail-activity-event.test.tsx` (from `apps/web-platform/`) expects `passed`.

## Success Metrics

- Operator-visible: the active conversation's rail badge reads `In progress`
  during a live turn on first render, without route re-entry.
- Server: `updateConversationFor` op `verify-conversation-ownership` /
  `turn-start-active` shows `ok:true` for the active write on new turns.

## Dependencies & Risks

- **Race:** supersede-on-reconnect writes `completed` to the previous
  conversation — our write fires only inside a `chat` dispatch for the row it
  targets, so ordering is determined by actual turn vs. switch order.
- **Scope:** `dispatchSoleurGo` also serves `api/support/route.ts` and
  `api/repo/setup/route.ts` — both are turn-start dispatches where `active` is
  semantically correct.
- **Risk:** emitting the event on every `stream_start` could fire per-leader in
  multi-leader mode; debounce the rail's refetch handler.

## References & Research

- Status-write inventory: greps of `updateConversationFor(` /
  `updateConversationStatus(` across `apps/web-platform/server/` (see Problem
  Statement table).
- Precedents: `CONVERSATION_CREATED_EVENT` + bounded-retry listener
  (`use-conversations.ts`); `isTerminalSubscribeStatus` polling fallback
  (`components/dashboard/leader-loop-status.tsx`).
- Realtime substrate: `supabase/migrations/015` (REPLICA IDENTITY FULL),
  `034` (publication), `037`/`133` (reapers).
- ADR-067 (SWR adoption) §Conversations rail — TR3 deferred; fix stays in the
  fetch+realtime design.
- Follow-up filed: #9293 (dead-channel polling fallback for non-viewed rows).
- Plan Review: advisor (strong-model consult) + CPO ran; both returned
  findings, all applied above. Eng panel (DHH/Kieran/code-simplicity),
  spec-flow, UX, and CTO spawns were killed by the harness model rate limit —
  recorded as a partial panel; the two high-signal seats completed.
- Applied at review: (a) guarded `failed`-revert on cc dispatch throw
  (otherwise a falsely-`active` row is reaper-invisible — heartbeat stays
  fresh while the socket is bound); (b) event trigger moved from wire frames
  to derived `streamState` transitions + gate transitions (cc path never
  emits `stream_start`; `session_started` fires on socket bind — a forbidden
  resume-on-view false-positive); (c) `api/repo/setup/route.ts` removed from
  coverage claims (it does not call `dispatchSoleurGo`); (d) #9293 filed for
  the deferred dead-channel fallback; (e) gate-transition dispatch added so
  the action-demanding `Needs your decision` badge also refreshes.
