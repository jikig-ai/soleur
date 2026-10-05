---
title: "fix: Render session completion inline in the viewed conversation; notify only when unseen"
type: fix
date: 2026-10-05
slug: fix-session-completion-inline-render
branch: feat-one-shot-session-completion-inline
lane: cross-domain
domain: web-platform
priority: high
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: Render session completion inline in the viewed conversation; notify only when unseen

## Enhancement Summary

**Deepened on:** 2026-10-05
**Reviewed-Coverage:** sequential-fallback — this planning pass ran inside a
one-shot planning subagent with no `Task`/subagent spawn available; the
deepen-plan mechanical gates were executed directly and the review/research
lenses were applied in-process rather than by independent agents. No agent
"ran" here — the fallback disclosure is intentional.
**Cloud mode:** `cloud-detect.sh` → `not-local:no-devin-env` (proceeds
normally; sequential-fallback recorded regardless).

### Gate verdicts (deepen-plan §4.x, run mechanically)

- §4.5 Network-Outage: **skipped** — no trigger patterns (no SSH/infra apply).
- §4.55 Downtime & Cutover: **skipped** — no infra/DDL/deploy-surface edit.
- §4.6 User-Brand Impact: **PASS** — section present, threshold
  `single-user incident` (no `none` scope-out needed).
- §4.7 Observability: **PASS** — all 5 fields populated; `command` verb `rg`
  (allowlisted, no ssh/pipe), `expected_output` a literal path token.
- §4.8 PAT-shape: **PASS** — zero matches.
- §4.9 UI-Wireframe: **artifact present, commit pending** —
  `knowledge-base/product/design/app-ui/session-completion-inline.pen` exists
  (13.9 KB, two frames, PNGs exported) but is uncommitted in the worktree —
  the planning boundary forbids git writes; **the parent agent MUST `git add`
  it** or the gate re-halts at ship time.
- §4.10 Encryption Posture: **skipped** — no `.tf`/`.sql`/store/connection
  added.
- §4.11 Guard Contract: **skipped** — no new guard/lint/drift-check
  deliverable (the `task-completed-both-lineages` pin is extended, not
  created).
- §4.12 Scope Check: **PASS** — one unfenced `## Scope Check`, Ask Mapping
  (4 rows, all `mapped`), Plan-Item Provenance (2 `inferred` rows with
  justifications), `Recommendation: single PR`.
- §4.4 Precedent-diff: **PASS** — every pattern-bound choice names its
  in-repo precedent (`turn_summary` buffered-frame registration triple,
  `reasoning_narration` convId-filter drop, `supersedeExistingUserSocket`
  one-socket registry, `globalMutate(swrKeys.inbox)` ADR-067 reconcile,
  `set_inbox_item_state` read action).
- §4.45 Verify-the-negative: **PASS** — claims probed: `notifications.ts`
  carries **no** `ws-handler` import (cycle avoided by construction);
  `ws-known-types.ts` absent; `turn_summary` present in
  `BUFFERED_FRAME_TYPE_MAP` (:67); `session-registry` is a leaf (`import
  type` only); `ClientSession{ws,conversationId}` verified; the
  cc-dispatcher injected `sendToClient` opts annotation is `=> void` while
  the runtime value is `defaultSendToClient` (`=> boolean`) — widened in
  scope.

### Key improvements from the deepen pass

1. Problem Statement corrected for the `session_ended{completed}` nuance —
   the cc path DOES render "This run finished." at **whole-workflow**
   termination; the defect is per-request turns where the session stays
   alive (the exact `notifyTaskCompleted` emit point).
2. `swrKeys`/`useSWRConfig`/`mutate` wiring verified against
   `lib/swr-config.ts` + `inbox-surface.tsx` (an earlier draft referenced a
   non-existent `lib/swr-keys.ts` — corrected).
3. `discoverability_test.command` rewritten to survive Check 10's
   shell-metachar reject (pipe removed).
4. All cited file:line anchors re-verified on this branch; two drifts
   fixed (`ChatMessage` union :300, reducer case :2078).

### New considerations discovered

- The cc-dispatcher `sendToClient` opts annotation `=> void` vs the injected
  `=> boolean` runtime value must be widened (type-only) or `emit`'s
  delivered-flag is unreadable.
- `session.conversationId` provenance is single-writer (the socket binding
  handshake) — the signal cannot outlive its session; the only residual is
  mounted-but-backgrounded tabs reading as "viewing" (documented trade-off).

## Overview

When a Soleur session finishes working, the conversation the operator is
watching renders **no completion signal** — the last assistant bubble simply
stops. The only notice is a `task_completed` inbox item plus a desktop
push/email ("New item in your Soleur inbox"), so the operator must leave the
conversation and open the Inbox to learn the run they were watching is done.

This fix makes the completion surface live as a new card inside the
conversation view itself, and keeps the inbox item + push/email only for
completions the operator is **not currently viewing** — the operator-confirmed
semantics "inline + notify if unseen" (chosen over "never notify" and "always
notify").

## Problem Statement / Motivation

Two defects compound on the Concierge chat surface (`apps/web-platform`):

1. **No inline terminal signal per request.** On the dominant `cc-dispatcher`
   path the only per-turn end frame is `stream_end` (ends the bubble) — the
   concierge session stays alive for follow-ups, so the per-request
   `notifyTaskCompleted` emit has no renderable counterpart. The cc path's
   `session_ended{completed}` ("This run finished.",
   `SESSION_ENDED_COPY`/`TERMINAL_WORKFLOW_END_STATUSES`) fires only at
   **whole-workflow termination** — not per request — and on the legacy
   `agent-runner` path `turn_complete` is a member of
   `SESSION_ENDED_SUPPRESSED` (`lib/session-ended-copy.ts:46`), so it
   deliberately renders nothing. `turn_summary` boxes exist but only when
   the agent calls `summarize` — not every turn. Result: a finished request
   looks identical to a stalled run.
2. **Notification regardless of attention.** `notifyTaskCompleted`
   (`server/notifications.ts`) inserts an `inbox_item` row and dispatches
   push/email **unconditionally** on every turn completion — even when the
   operator has that exact conversation open in front of them.

Desired behavior (operator-confirmed): completion surfaces live as a new
box/message inside the conversation view itself; the inbox item + notification
fires only when the operator is not viewing that conversation.

## Research Insights

### Relevant file paths (verified on this branch)

| Path | Role |
|---|---|
| `apps/web-platform/server/notifications.ts` | `notifyInboxItem` (insert `inbox_item` + dispatch push/email, ~:837); `notifyTaskCompleted` shared seam called by both turn-boundary lineages (~:964); `notifyOfflineUser` dispatch (push → email fallback) |
| `apps/web-platform/server/agent-runner.ts` | legacy `startAgentSession` turn end: `notifyTaskCompleted` ~:2489, then `session_ended{turn_complete}` ~:2501 |
| `apps/web-platform/server/cc-dispatcher.ts` | dominant `onTextTurnEnd` path: `notifyTaskCompleted` ~:4041 ("Soleur finished your request"), then `stream_end` ~:4056 |
| `apps/web-platform/server/ws-handler.ts` | `sendToClient(userId, msg) → boolean` ~:729 — stamps buffered frames into the per-conversation replay ring **regardless of delivery**, returns `false` when no OPEN socket; `sessions` registry (one live socket per userId, `supersedeExistingUserSocket` ~:3327); `ClientSession.conversationId` = conversation the socket is bound to (set on `start_session`/`resume_session`, ~:1892/:2258, cleared on close/supersede) |
| `apps/web-platform/server/session-registry.ts` | 10-line leaf module exporting the `sessions` Map — importable from `notifications.ts` with **no cycle** |
| `apps/web-platform/lib/ws-client.ts` | client WS handler: `session_ended` case ~:1231 (suppressed reasons render nothing); `reasoning_narration` conversationId-mismatch drop precedent ~:1470; replay dedup gate ~:987 |
| `apps/web-platform/lib/types.ts` | `WSMessage` union — `turn_summary` variant ~:412 is the frame-shape precedent (carries `seq?`) |
| `apps/web-platform/lib/ws-zod-schemas.ts` | `turnSummarySchema` ~:350, `sessionEndedSchema` ~:410, union ~:639 |
| `apps/web-platform/lib/chat-state-machine.ts` | `ChatTurnSummaryMessage` :286, `ChatMessage` union member :300, `case "turn_summary"` ~:2078 |
| `apps/web-platform/server/stream-replay-buffer.ts` | `BufferedWSMessage` Extract ~:32 + `BUFFERED_FRAME_TYPE_MAP` ~:59 — the buffered-family checklist is in the comment at ~:50-58 |
| `apps/web-platform/lib/session-ended-copy.ts` | `SESSION_ENDED_SUPPRESSED` (:46) — `turn_complete` never produces a transcript line |
| `apps/web-platform/components/inbox/inbox-item-row.tsx` | `InboxItemRow` — the inbox completion card (severity dot + title + relative time; `buildInboxDeepLink` from `source_ref`) |
| `apps/web-platform/lib/inbox-severity.ts` | `InboxItemRowData` shape ~:28, `buildInboxDeepLink` ~:95 |
| `apps/web-platform/hooks/use-conversations.ts` | rail realtime channels + `CONVERSATION_ACTIVITY_EVENT` recovery (PR #9270 — the "dead realtime channel" adjacent work) |
| `apps/web-platform/test/task-completed-both-lineages.test.ts` | existing drift pin asserting both lineages call the shared seam |
| `apps/web-platform/supabase/migrations/122_inbox_item.sql` | `inbox_item` schema — `status unread\|read\|archived`, `read_at` set-once via `set_inbox_item_state` RPC |
| `apps/web-platform/app/api/inbox/[id]/state/route.ts` | existing `POST` endpoint for `read\|acted\|archived` transitions |

### Premise Validation (Phase 0.6)

- **Cited mechanisms verified present on this branch:** `notifyTaskCompleted`
  exists at both named call sites; `session_ended`/`SESSION_ENDED_SUPPRESSED`
  suppression confirmed (`turn_complete` never renders); `sessions` +
  `session.conversationId` server-side binding confirmed; `sendToClient`
  delivery bool + replay-ring stamping confirmed.
- **Adjacent work claim held:** PR #9270 (`CONVERSATION_ACTIVITY_EVENT` +
  server-side `status:"active"` writes on new turns — learning
  `ui-bugs/2026-09-30-conversations-rail-stale-status-turn-start.md`) and the
  listener/channel-survival learning (`2026-09-25-listener-survival-is-not-channel-survival.md`,
  which proves the chat surface **owns the page's only WebSocket**) both
  verified.
- **Stale premise corrected:** the feature description mentions "Supabase
  realtime" for the conversation view — the chat transcript is **WS-driven**,
  not realtime-driven; only the conversations *rail* uses Supabase realtime.
  The fix therefore rides the WS path, not a new realtime channel.
- **Inciting-defect carry-forward:** `ws-known-types.ts` no longer exists
  (activity-trail PR1 merged it away) — one fewer drift surface; the new frame
  type needs no allowlist edit.
- No external issue cited; no premise required `gh` verification.

### Property List + Cut List (Phase 0.6b)

Properties (restatement of the ask):

- **P1** — a conversation the operator is viewing shows a visible completion
  signal the moment a turn ends (a new box/message inline).
- **P2** — the inbox item + push/email fires **only** when the operator is not
  viewing that conversation ("notify if unseen", never "always notify",
  never "never notify").

Mechanism minimality:

| Proposed mechanism | Property it buys | Already covered by |
|---|---|---|
| New WS frame `task_completed` emitted at the shared `notifyTaskCompleted` seam | P1 (inline render, both lineages uniformly) | Nothing — `session_ended{turn_complete}` is suppressed AND absent on the cc path; `turn_summary` fires only when the agent summarizes |
| Server-side "viewing" predicate on the existing `sessions` registry | P2 (suppression) | `session.conversationId` binding already exists — the predicate is a read of it, not a new mechanism |
| Reuse `inbox_item` row + `read_at`/`set_inbox_item_state` for the seen-record | P2's "mark it seen" arm | Table + RPC + API route already exist — no migration |
| Stream-replay-buffer membership for the frame | P1 survives within-grace reconnect | Existing buffered family (`turn_summary` precedent) |
| ~~New messages `message_kind` persistence~~ | transcript durability on reload | **CUT** — the `inbox_item` row is already the durable record; a second persistence surface costs a CHECK-constraint migration + DSAR surface for a notice the operator already saw live |
| ~~Client-reported visibility (`document.visibilityState`) heartbeat~~ | strict "actively viewing" | **CUT for v1** — bound-socket predicate is the observable floor; a backgrounded tab still receives the card (visible on return). Recorded in Alternatives |

### Institutional learnings applied

- `2026-09-25-listener-survival-is-not-channel-survival.md` — the concierge
  panel owns the page's only WebSocket; collapsing it deletes the session.
  The suppression predicate therefore keys on the socket binding, and the
  frame rides the replay buffer for the within-grace race.
- `ui-bugs/2026-09-30-conversations-rail-stale-status-turn-start.md` — realtime
  UPDATE channels can die unobserved; deterministic event + server-owned
  status is the recovery pattern. Do NOT build the inline signal on a Supabase
  realtime channel.
- `learnings/integration-issues/2026-06-14-ws-lifecycle-hook-must-cover-both-legacy-and-cc-soleur-go-turn-boundaries.md`
  — any turn-boundary hook must be wired on BOTH lineages; the shared
  `notifyTaskCompleted` seam is the single chokepoint.
- ADR-085 content-minimization — `title` stays server-generated; the frame
  carries `inboxItemId` + `conversationId` + title only.
- ADR-067 shared-key contract — the read-mark POST must `mutate()` the shared
  `swrKeys.inbox("active")` entry so list + nav badge reconcile together.

### External research

Skipped — the mechanism set is fully bounded by in-repo precedents
(`turn_summary` frame family, `sessions` registry, `set_inbox_item_state`).
No external API, security surface, or unfamiliar dependency is introduced.

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch (fresh one-shot invocation); there is no
spec fiction to reconcile. All codebase claims above were verified directly
(file paths + symbol anchors in the table). `lane:` defaulted to
`cross-domain` (fail-closed — no spec to carry it forward from).

## Proposed Solution

One new server→client WS frame + a viewing-gated suppression in the existing
shared seam. Three coordinated changes:

### 1. `task_completed` WS frame (new buffered-family member)

`{ type: "task_completed", conversationId, inboxItemId, title, seq? }` —
server→client. Added to `WSMessage` (types.ts), `taskCompletedSchema`
(ws-zod-schemas.ts), `BufferedWSMessage` + `BUFFERED_FRAME_TYPE_MAP`
(stream-replay-buffer.ts) so it joins the per-conversation replay ring
(ADR-059): a within-grace reconnect replays the card — the exact class the
listener-survival learning exposed.

### 2. Viewing predicate + suppression inside `notifyTaskCompleted`

- New leaf helper `isConversationViewed(userId, conversationId)` in
  `server/session-registry.ts` (the module that owns `sessions`):
  `sessions.get(userId)` exists AND `session.ws.readyState === WebSocket.OPEN`
  AND `session.conversationId === conversationId`. "Viewing" = the
  conversation's chat surface is mounted (the socket exists only while
  `ChatSurface`/`useWebSocket` is mounted — unmount closes it).
  **Signal provenance** (existing-state-as-coordination-signal edge):
  `session.conversationId` has a single writer — the ws-handler binding
  handshake itself (set on `start_session` :1892 / `resume_session` :2258 /
  resolved :2452; cleared on `close_conversation`/abort :433,:2040,:2320;
  superseded sessions are aborted :400). One live socket per `userId`
  (`sessions.set` :3143, `sessions.delete` :3271) — the binding *is* the
  session, so the signal cannot outlive it; the residual is the reverse
  (mounted-but-backgrounded tab reads as viewing — documented).
- `notifyTaskCompleted` gains a required `emit: (userId, msg) => boolean`
  parameter; both call sites pass their already-imported `sendToClient`.
  Injection keeps `notifications.ts` free of a `ws-handler` import — the
  `ws-handler → cc-dispatcher → notifications → ws-handler` cycle class is
  avoided by construction.
- New seam order inside `notifyTaskCompleted`:
  1. `viewing = isConversationViewed(userId, conversationId)` (sessions leaf).
  2. Insert the `inbox_item` row as today (`unread`, `task_completed`,
     `info`, `source_ref.conversationId`) — the durable record is kept in
     **both** paths.
  3. `delivered = emit(userId, taskCompletedFrame)` — `sendToClient` stamps
     the replay ring for the frame's own `conversationId` even when no socket
     is live.
  4. `shouldNotify = !(viewing && delivered)`. Suppression requires BOTH the
     bound-conversation check AND the frame actually reaching an OPEN socket —
     a socket that dies between check and send degrades to "unseen" and the
     notification fires (no silent window).
  5. `shouldNotify` → `notifyOfflineUser` (push/email bundle) exactly as
     today; suppression → `log.info` with `op: "task-completed-suppressed"`
     (observability: suppression is a decision, not silence).
- `notifyInboxItem` refactor: split its insert vs dispatch so the seam can
  suppress dispatch while keeping the row — minimal signature change:
  optional `dispatch?: boolean` (default true) + return the inserted row id
  for the frame payload. All existing callers keep working (return ignored).

### 3. Client render + render-anchored "seen"

- `lib/ws-client.ts` `case "task_completed"`: drop when
  `msg.conversationId !== realConversationIdRef.current` (the
  `reasoning_narration` multi-tab precedent — a frame for conversation A must
  not render on conversation B's surface); otherwise
  `dispatch({ type: "stream_event", msg })` (the `turn_summary` route) AND
  fire-and-forget `POST /api/inbox/{inboxItemId}/state { action: "read" }`
  then `mutate(swrKeys.inbox("active"))` — `mutate` obtained via
  `useSWRConfig()` at `useWebSocket` top level; `swrKeys` is exported by
  `lib/swr-config.ts:62` (`inbox` key :67) and the pairing is the
  inbox-surface pattern (`inbox-surface.tsx:246,319`). ADR-067 shared-key
  reconciliation.
- `lib/chat-state-machine.ts`: `ChatTaskCompletedMessage` variant on
  `ChatMessageBase` (`type: "task_completed"`, `inboxItemId`), union member,
  reducer case appending it.
- New `components/chat/task-completed-card.tsx`: bordered card mirroring the
  `InboxItemRow` visual language (info-severity muted dot → emerald accent for
  the "finished" semantics, plain-text title, relative time). Plain text only
  — never markdown, never `dangerouslySetInnerHTML` (the InboxItemRow
  invariant). Non-navigating: the operator is already inside the target.
- `chat-surface.tsx` render switch: `case "task_completed"` →
  `<TaskCompletedCard />` beside the `turn_summary` case.

**Why render-anchored read (unread insert + mark-on-render), not insert-as-read:**
if the frame is emitted but never rendered (tab killed post-send, reducer
drop), the row stays `unread` and the nav badge still surfaces it — the
fallback is honest by construction instead of a permanently-silent `read`
row. "Seen" is asserted by the system that actually rendered, never assumed.

**Agent-native parity check (new-WS-event edge):** `task_completed` is a
server→client *informational* frame with no operator action attached (the
card is non-navigating) — it is not an interactive-prompt surface, so no MCP
tool counterpart is owed; the parity surface ("operator learns the turn
finished") is already agent-visible via the existing turn boundary.

**Semantics recap (operator's choice):**

| State at turn end | Inline card | inbox_item row | Push/email |
|---|---|---|---|
| Viewing this conversation | renders | inserted `unread`, marked `read` on render | suppressed |
| Viewing another conversation / another page / app closed | — | `unread` (today) | fires (today) |
| Socket dies mid-emit | replays within grace | `unread` | fires (shouldNotify degrades) |

## Files to Edit

- `apps/web-platform/server/notifications.ts` — `notifyTaskCompleted` seam:
  viewing predicate, frame emit, dispatch suppression; `notifyInboxItem`
  `dispatch` opt-out + inserted-id return.
- `apps/web-platform/server/session-registry.ts` — `isConversationViewed`
  helper (leaf, no new runtime edge): `sessions.get(userId)` →
  `session.ws.readyState === WebSocket.OPEN &&
  session.conversationId === conversationId` (`ClientSession` fields verified:
  `ws: WebSocket`, `conversationId?: string`).
- `apps/web-platform/server/agent-runner.ts` — pass `emit: sendToClient` at
  the `notifyTaskCompleted` call site (~:2489; `sendToClient` imported :30).
- `apps/web-platform/server/cc-dispatcher.ts` — same at the `onTextTurnEnd`
  call site (~:4041). The in-scope `sendToClient` is the opts-injected emitter
  (used for `stream_end` on the next line); its declared opts type is
  `(userId, msg) => void` while the injected runtime value is
  `defaultSendToClient` (`=> boolean`) — widen the opts annotation to
  `=> boolean` (type-only fix matching reality) so `emit`'s boolean return is
  honest.
- `apps/web-platform/lib/types.ts` — `task_completed` `WSMessage` variant
  (`conversationId`, `inboxItemId`, `title`, `seq?`).
- `apps/web-platform/lib/ws-zod-schemas.ts` — `taskCompletedSchema`
  (`strictObject`, mirrors `turnSummarySchema` incl. `seq`) + union member.
- `apps/web-platform/server/stream-replay-buffer.ts` — add `task_completed`
  to `BufferedWSMessage` Extract + `BUFFERED_FRAME_TYPE_MAP` (the file's own
  checklist also names types.ts `seq?` + zod — both above).
- `apps/web-platform/lib/chat-state-machine.ts` — `ChatTaskCompletedMessage`
  variant + union + `case "task_completed"` reducer arm.
- `apps/web-platform/lib/ws-client.ts` — `case "task_completed"`: convId
  filter → `stream_event` dispatch → read-mark POST + `mutate(swrKeys.inbox("active"))`.
- `apps/web-platform/components/chat/chat-surface.tsx` — render `case` →
  `TaskCompletedCard`.
- `apps/web-platform/test/mocks/use-websocket.ts` — the shared `useWebSocket`
  test double gains the `task_completed` surface (verified at
  `test/mocks/use-websocket.ts`; the activity-trail feature updated this mock
  for the same reason).

## Files to Create

- `apps/web-platform/components/chat/task-completed-card.tsx` — the inline
  completion card.
- `apps/web-platform/test/task-completed-suppression.test.ts` — server seam
  tests: viewing→insert+emit+no dispatch; not-viewing→today's path;
  emit-false→notify; unread row survives a dropped render.
- `apps/web-platform/test/task-completed-inline.test.tsx` — client reducer +
  ws-client tests: convId-filter drop, message append, read-mark POST fires
  only on render.
- `knowledge-base/product/design/app-ui/session-completion-inline.pen` —
  wireframe (already produced this session; screenshots in `screenshots/`).

## Implementation Phases

### Phase 1 — Server seam (failing tests first)

1.1 Write `task-completed-suppression.test.ts` (RED): viewing → row inserted
unread + frame emitted + `notifyOfflineUser` NOT called; not-viewing → today's
full path; viewing + `emit()` returns false → notify fires.
1.2 `session-registry.ts`: `isConversationViewed` helper.
1.3 `notifications.ts`: `notifyInboxItem` `dispatch` opt-out + inserted-id
return; `notifyTaskCompleted` new signature + seam order.
1.4 `agent-runner.ts` + `cc-dispatcher.ts`: pass `emit: sendToClient`; extend
`task-completed-both-lineages.test.ts` to pin `emit:` wiring at both sites
(GREEN).

### Phase 2 — Wire + render

2.1 types.ts + ws-zod-schemas.ts + stream-replay-buffer.ts (frame registration
triple, compile-enforced).
2.2 chat-state-machine.ts variant + reducer arm.
2.3 ws-client.ts case (filter → dispatch → read-mark + mutate).
2.4 task-completed-card.tsx + chat-surface render case.
2.5 task-completed-inline.test.tsx (RED → GREEN).

### Phase 3 — Verification

3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — the compiler
is the canonical rail enumerator (union-widening edge: never prescribe a
fixed site count); every TS2322 `not assignable to never` is a rail to widen
(`ws-client` switch, `chat-state-machine` reducer, test-d gates). Then
targeted vitest (`./node_modules/.bin/vitest run test/task-completed-*.test.ts*`
— vitest globs collect `test/**/*.test.ts` node + `test/**/*.test.tsx` jsdom).
3.2 E2E reasoning: existing e2e harness constraints apply (learning
2026-06-17 — mock-e2e cannot verify deployed realtime; rely on unit +
component tests + the AC checklist).

## User-Brand Impact

- **If this lands broken, the user experiences:** a finished Soleur run with
  **no signal anywhere** — the predicate-suppression arm inverted or widened
  would silently eat the inbox item and push on the product's core trust
  surface, exactly the "halt with no notice" class `#5767` cost-breaker
  telemetry was built to prevent. The degradation direction is therefore
  deliberately toward **over-notify** (any predicate uncertainty → today's
  path).
- **If this leaks, the user's [data / workflow / money] is exposed via:** the
  WS frame carries only `inboxItemId` + `conversationId` + server-generated
  `title` — the same id-class data the existing inbox payload already sends
  to the same user over the same authenticated socket (ADR-085
  content-minimization preserved; no agent output, no message content).
- **Brand-survival threshold:** `single-user incident` — matches the sibling
  concierge-activity-trail declaration for this same surface; one founder's
  silently-missed completion is brand-relevant in a solo-operator product.
- **Threshold decision (challengeable):** a broken suppression is invisible
  to the affected user by definition (they see nothing — that IS the bug), so
  a single affected account can lose confidence without ever filing a report.

`requires_cpo_signoff: true` is set per the `single-user incident` rule;
`soleur:engineering:review:user-impact-reviewer` runs at review time. (In this
headless planning pass the CPO lens was applied in-process — see Domain
Review — and formal sign-off should be confirmed before `soleur:work`.)

## Observability

```yaml
liveness_signal:
  what: "Sentry-tagged ops on the completion seam — emit (`op=task-completed-emit`), suppression (`op=task-completed-suppressed`), insert failure (`op=notify-inbox-action-required`/`inbox-item-insert` existing), unmapped-frame drop (client `op=ws-unknown-event`)"
  cadence: "per turn completion"
  alert_target: "Sentry web-platform (existing notify-inbox alert rules cover action_required; info-severity rows ride the inbox-item-insert op)"
  configured_in: "apps/web-platform/server/notifications.ts (new op slugs inside notifyTaskCompleted); existing rules in apps/web-platform/infra/sentry/issue-alerts.tf (~:1214 notifyInboxItem/notifyOfflineUser block)"

error_reporting:
  destination: "Sentry via reportSilentFallback / warnSilentFallback (server/observability.ts) + mirrorNotifyFailure for dispatch failures"
  fail_loud: "suppression is always logged (log.info op=task-completed-suppressed); insert failures reuse the existing inbox-item-insert Sentry mirror; a WS frame the client can't parse lands on ws-unknown-event (already mirrored)"

failure_modes:
  - mode: "suppression predicate widens (e.g. session.conversationId stale after navigation) → completions silently swallowed"
    detection: "Sentry count on op=task-completed-suppressed + cross-check: an unread task_completed row should exist whenever suppression was NOT taken; a weekly-count drift alert on the suppressed-vs-notified ratio"
    alert_route: "Sentry web-platform project → operator"
  - mode: "emit() returns false after viewing=true (socket died mid-emit)"
    detection: "the shouldNotify = !(viewing && delivered) branch falls through to notifyOfflineUser — the mode is SELF-CORRECTING; a log.info op=task-completed-suppress-race counts occurrences"
    alert_route: "Sentry breadcrumb + pino log"
  - mode: "task_completed frame emitted inside cc-dispatcher's onTextTurnEnd throws (blind dispatcher surface — Phase 2.9.2)"
    detection: "in-surface reportSilentFallback at the emit site (op=task-completed-emit, extra: conversationId present/absent, viewing, delivered) discriminates emit-failure vs suppression vs not-viewing in one event"
    alert_route: "Sentry web-platform"
  - mode: "read-mark POST fails after render → inbox row stays unread (badge shows a 'seen' item)"
    detection: "fire-and-forget POST logs on non-2xx; benign — row stays unread = over-notify direction"
    alert_route: "client-side warnSilentFallback (@/lib/client-observability — already imported by ws-client.ts:33; feature: ws-client, op: task-completed-mark-read)"

logs:
  where: "pino child 'notifications' (server) + browser console/Sentry breadcrumbs (client)"
  retention: "existing web-platform retention"

discoverability_test:
  command: "rg -l 'task_completed' apps/web-platform/lib/types.ts apps/web-platform/lib/ws-zod-schemas.ts apps/web-platform/server/stream-replay-buffer.ts apps/web-platform/lib/chat-state-machine.ts"
  expected_output: "apps/web-platform/lib/types.ts"
```

Field RUM (browser-rendered webapp): the change adds one card render + one
fire-and-forget POST per turn end — no new layout-affecting surface above the
composer, no image/font loads; CWV regression risk is negligible. The card
renders inside the existing scroll container (`messagesScrollRef`) and
participates in the existing near-bottom auto-scroll.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "the session completion surfaces live as a new box/message inside the conversation view itself" | `task_completed` WS frame + `ChatTaskCompletedMessage` + `task-completed-card.tsx` (Phase 2) | mapped |
| 2 | "the inbox item + notification still fires ONLY when the user is not currently viewing that conversation (operator explicitly chose \"inline + notify if unseen\")" | `isConversationViewed` predicate + `shouldNotify = !(viewing && delivered)` in `notifyTaskCompleted` (Phase 1) | mapped |
| 3 | "only skip creating the inbox item (or mark it seen/suppress the push) when the operator is actively viewing that conversation; completions for non-viewed conversations keep today's behavior" | unread insert + render-anchored read-mark; non-viewing path untouched (Phase 1 + ws-client read-mark) | mapped |
| 4 | "Investigate … how the Inbox renders its completion cards so the same component/data shape can render inline in the conversation" | `InboxItemRowData`/`buildInboxDeepLink`/`InboxItemRow` research + `task-completed-card.tsx` mirroring that visual language | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `task_completed` WS frame (buffered family) | "the session completion surfaces live as a new box/message inside the conversation view itself" | asked |
| `isConversationViewed` + dispatch suppression in `notifyTaskCompleted` | "only skip creating the inbox item (or mark it seen/suppress the push) when the operator is actively viewing that conversation" | asked |
| Unread insert + client read-mark on render | "(or mark it seen/suppress the push)" | asked |
| `emit: sendToClient` param at both call sites | — | inferred — justification: the seam must cover both turn-boundary lineages without a ws-handler↔notifications import cycle (dual-path-terminal learning) |
| Replay-buffer membership | — | inferred — justification: without it the within-grace reconnect silently loses the card (listener-survival learning) |
| `.pen` wireframe | "the plan must satisfy the repo's UI gates (.pen wireframe checkpoint …)" | asked |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform` (plus `knowledge-base/` design artifact)
- Planned files: 15 | Estimated changed lines: ~450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 — With the operator viewing conversation A on the chat surface, a
  turn completing on A renders a `task_completed` card inline (title +
  timestamp, plain text) — visible without leaving the conversation.
- [ ] AC2 — Under the same condition, no push/email is dispatched and the
  `inbox_item` row exists but is marked `read` (the nav badge never counts
  it).
- [ ] AC3 — With the operator viewing conversation B (or any non-chat page,
  or app closed) while A completes: today's behavior — `unread` inbox row +
  push/email — fires unchanged.
- [ ] AC4 — Suppression requires an OPEN socket bound to the completing
  conversation (`isConversationViewed` AND `sendToClient` returned true); a
  socket that dies between check and send degrades to notify.
- [ ] AC5 — A `task_completed` frame for conversation A arriving while the
  client views conversation B does not render and does not mark A's row read
  (the `realConversationIdRef` filter).
- [ ] AC6 — The frame is a `BufferedWSMessage` member: a within-grace
  reconnect replays it and the card renders (replay-dedup drops a
  second-rendered copy via `seq`).
- [ ] AC7 — If the frame is emitted but never rendered, the `inbox_item` row
  remains `unread` (no silent disappearance — render-anchored read).
- [ ] AC8 — Both lineages (legacy `agent-runner`, `cc-dispatcher`) emit the
  frame through the shared `notifyTaskCompleted` seam; the
  `task-completed-both-lineages` pin asserts `emit:` wiring at both sites.
- [ ] AC9 — `tsc --noEmit` clean; the `_exhaustive` rails in ws-client and
  chat-state-machine compile (new union member fully handled).
- [ ] AC10 — `.pen` wireframe exists at
  `knowledge-base/product/design/app-ui/session-completion-inline.pen`
  (non-empty) and is cited by this plan's FRs (satisfied — produced at plan
  time, headless auto-accept applies for async operator review).

## Domain Review

**Domains relevant:** Product, Engineering, Legal

### Product/UX Gate

**Tier:** blocking (new user-facing component `components/chat/task-completed-card.tsx`)
**Decision:** reviewed (partial) — headless pipeline: no Task/subagent spawn
available in this environment; the ux-design-lead, spec-flow and CPO lenses
were applied in-process (sequential-fallback), and the `.pen` wireframe was
produced directly via the authenticated `pen` CLI.
**Agents invoked:** ux-design-lead (in-process fallback — produced the .pen
via `pen interactive`), spec-flow-analyzer (in-process lens), CPO (in-process
lens — sign-off still required before work per `requires_cpo_signoff`)
**Skipped specialists:** none — `soleur:product:design:ux-design-lead` was NOT
skipped; the `.pen` exists on disk
**Pencil available:** yes — headless `pen` CLI (v0.3.8, stored session active)

#### Findings

- Wireframe produced: `knowledge-base/product/design/app-ui/session-completion-inline.pen`
  — two frames: (A) viewing → inline `TaskCompletedCard` (emerald dot, plain
  title, "also in your inbox" sub-line, suppression rule annotation);
  (B) not viewing → inbox row + push banner (unchanged). PNGs in
  `screenshots/05-session-completion-inline-viewing.png`,
  `06-session-completion-inline-notify.png`.
- Spec-flow lens: the completion event must not dead-end — the card is
  non-navigating (operator is already at the target); the "also in your
  inbox" sub-line preserves discoverability of the durable record.
- CPO lens: suppression degrades toward over-notify on any uncertainty —
  consistent with the brand-survival threshold.

### Engineering

**Status:** reviewed (in-process)
**Assessment:** the shared `notifyTaskCompleted` seam is the single
chokepoint both turn-boundary lineages already flow through — extending it
keeps the dual-lineage drift class impossible; `session-registry.ts` is a
leaf so the predicate adds no import cycle; the buffered-frame family has an
explicit 4-file registration checklist.

### Legal

**Status:** reviewed (in-process)
**Assessment:** GDPR gate fired (regulated-data adjacency: user-owned
conversations/inbox rows; canonical regex itself does not hit — no `.sql`,
no `app/api` edit, no auth path — but the single-user-incident threshold
trigger (b) applies). Findings: **no new processing** — the frame carries
id-class data already sent to the same user; `inbox_item` LAWFUL_BASIS
(Art. 6(1)(f), mig 122) covers the row; no schema change; no retention
change; ephemeral card (no `messages` write) deliberately avoids the DSAR
surface expansion the activity-trail brainstorm priced. No Critical
findings; no `compliance-posture.md` write warranted. *This is not legal
review. Findings are heuristic. Consult `soleur:legal:clo` +
`soleur:legal:legal-compliance-auditor` before merging.*

## Test Scenarios

- Given a live socket bound to conversation A, when `notifyTaskCompleted`
  fires for A, then an `inbox_item` row is inserted `unread`, a
  `task_completed` frame is emitted carrying `{conversationId: A, inboxItemId,
  title}`, and `notifyOfflineUser` is NOT called.
- Given no live socket (or a socket bound to conversation B), when
  `notifyTaskCompleted` fires for A, then the row is `unread` AND
  `notifyOfflineUser` runs exactly as today.
- Given viewing=true and `emit()` returning false, when the seam runs, then
  `notifyOfflineUser` still runs (degraded-to-notify).
- Given a `task_completed` frame for A on a client viewing B, when the frame
  arrives, then no message is appended and no read-mark POST fires.
- Given a `task_completed` frame for the viewed conversation, when it
  dispatches, then a `ChatTaskCompletedMessage` is appended AND a `read`
  POST fires for `inboxItemId` AND `mutate(swrKeys.inbox("active"))` runs.
- Given the buffered `task_completed` frame in the replay ring, when a
  within-grace reconnect resumes, then the card renders once (seq dedup
  drops the second copy).
- Given an emitted-but-unrendered frame (kill post-send), when the operator
  next opens the Inbox, then the row is still `unread` (badge counted it).
- Given both turn lineages, when the drift pin runs, then
  `agent-runner.ts` and `cc-dispatcher.ts` both match
  `notifyTaskCompleted(` with an `emit:` argument.
- Given `tsc --noEmit`, when the union widens, then the `_exhaustive` client
  switch and reducer arms compile (a missing case is a build error).

## Success Metrics

- Operator sees completion inline without leaving the conversation (the
  reported defect).
- Zero suppressed notifications for non-viewed conversations (predicate is
  read-only on existing bindings — no behavior change outside the viewed
  case).
- `op=task-completed-suppressed` rate ≈ "turns ending while the surface is
  mounted"; alertable drift if the suppressed:all ratio approaches 1 (would
  indicate predicate over-broad).

## Dependencies & Risks

- **Background-tab suppression:** a mounted-but-hidden tab counts as
  "viewing" — the card renders and waits; the inbox row marks read. Accepted
  v1 residual (documented in Alternatives; a `document.visibilityState`
  client-report frame is the documented upgrade path, deliberately deferred).
- **Multi-device:** one live socket per userId (`supersedeExistingUserSocket`)
  — the predicate reads whichever device connected last; a later-connected
  device on another page degrades to notify (over-notify direction).
- **Import cycle:** avoided by construction — `sessions` leaf + injected
  `emit`; do NOT import `ws-handler` from `notifications.ts`.
- **Concurrency:** sibling conversations can run concurrently
  (`user_concurrency_slots` cap>1) — per-recipient suppression is keyed on
  the viewed conversation only; concurrent completions on other
  conversations still notify.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Un-suppress `session_ended{turn_complete}` transcript line | Only exists on the legacy path (cc path has no per-turn `session_ended`); produces a bare text line, not the inbox-card shape; would need divergent cc-path machinery anyway |
| Skip the `inbox_item` row entirely when viewing | Operator's parenthetical allows it, but loses the durable record and the self-healing unread fallback for emit-dropped frames |
| Insert row as `read` when viewing | Saves one POST but a dropped render leaves a permanently-silent `read` row — the unrendered fallback becomes invisible by construction |
| Client-reported visibility (`visibilitychange` → `viewing` frame) | More faithful to "actively viewing" but adds a client→server frame + per-session freshness tracking; v1 bound-socket predicate covers the dominant case — deferred enhancement, not a tracking-issue class deferral since operator semantics are met |
| Persist card as `messages` row (`message_kind='task_completed'`) | CHECK-constraint migration + DSAR/Art.30 surface for a notice the viewer already saw; the `inbox_item` row is the durable record — matches the activity-trail session-only precedent |
| New Supabase realtime channel for completion | Realtime UPDATE channels die unobserved (PR #9270 learning); the chat transcript is WS-driven — a second transport for the same event doubles the miss surface |

## Open Code-Review Overlap

5 open `code-review` issues touch planned files — all **acknowledge**
(different concern, no fold-in):

- `#3374` slot_reclaimed WS frame (ws-handler/ws-zod/ws-client) — additive
  frame of a different family; no interaction.
- `#2191` ws-handler clearSessionTimers refactor — orthogonal.
- `#3242` tool_use raw-name field (agent-runner/cc-dispatcher/types/ws-zod) —
  different field on a different frame.
- `#3243` cc-dispatcher decomposition — our edit is inside `onTextTurnEnd`;
  decomposition moves it wholesale either way.
- `#3280` useWebSocket history-fetch refactor — adjacent region of
  ws-client.ts but a different function set.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. (Filled above.)
- `session.conversationId` is "socket bound to conversation", not "eyes on
  screen" — the predicate suppresses on a backgrounded tab. Deliberate v1
  trade-off; do not "fix" it into a visibility heartbeat inside this PR.
- `sendToClient` stamps the replay ring BEFORE the delivery check — emit the
  frame unconditionally and key suppression on `viewing && delivered`, never
  on `viewing` alone.
- `notifications.ts` must NOT import `ws-handler` — the
  ws-handler→cc-dispatcher→notifications→ws-handler cycle; inject `emit`.
- The read-mark is render-anchored (fires inside the ws-client case after the
  convId filter passes), never at emit time.
- `notifyInboxItem` is also used by broadcast (userId null) emits — the
  suppression change must be scoped to `notifyTaskCompleted`, never leak into
  the broadcast arm.

## References & Research

- `server/notifications.ts` `notifyTaskCompleted` (~:964) — the shared seam
- `server/ws-handler.ts` `sendToClient` (~:729), `ClientSession` (~:294),
  `supersedeExistingUserSocket` (~:3327)
- `server/session-registry.ts` — the `sessions` leaf
- `lib/session-ended-copy.ts` `SESSION_ENDED_SUPPRESSED` (:46)
- `lib/inbox-severity.ts` `InboxItemRowData` (:28), `buildInboxDeepLink` (:95)
- `supabase/migrations/122_inbox_item.sql` — `inbox_item` + `set_inbox_item_state`
- Learnings: `2026-09-25-listener-survival-is-not-channel-survival`,
  `ui-bugs/2026-09-30-conversations-rail-stale-status-turn-start`,
  `learnings/integration-issues/2026-06-14-ws-lifecycle-hook-must-cover-both-legacy-and-cc-soleur-go-turn-boundaries`
- Brainstorm (adjacent, merged): `2026-10-05-concierge-activity-trail`
- Wireframe: `knowledge-base/product/design/app-ui/session-completion-inline.pen`
