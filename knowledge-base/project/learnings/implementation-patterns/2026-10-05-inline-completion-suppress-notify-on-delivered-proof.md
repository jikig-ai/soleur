# Suppress a notification only on delivered proof — evaluated at decision time, not sample time

**Date:** 2026-10-05
**Issue:** PR #9562 (feat-one-shot-session-completion-inline)
**Category:** implementation-patterns

## Problem

The Concierge chat surface showed no completion signal inline when a session
finished — the only artifact was an `inbox_item` row plus a push/email nudge,
forcing the operator out of the conversation to confirm the turn ended. The
operator-chosen fix ("inline + notify if unseen") renders a `task_completed`
card in the viewed conversation and suppresses the push/email only when the
operator's live socket is bound to that conversation AND the frame was
delivered.

The defect class that shipped (and the review seats then caught again): the
suppression predicate was sampled **before** an intervening `await` (the inbox
insert). A socket rebind during that window meant `viewing` read stale-true
while `delivered` read current-true — a suppressed nudge for a frame the
rebound client drops. **Any sampling of a decision predicate before the last
`await` in the sequence is a TOCTOU window — evaluate it at decision time, in
the same synchronous tick as the emit.**

## Solution

The suppression seam (`server/notifications.ts` `notifyTaskCompleted`):

1. Insert the `inbox_item` row `unread` (`dispatch: false`) — the durable
   record exists in BOTH paths, so a delivered-but-unrendered frame still
   leaves an honest unread row + badge.
2. Emit the `task_completed` frame via an **injected** `emit`
   (`sendToClient`-shaped, returns `boolean`) — injected because
   `notifications.ts → ws-handler.ts` would close an import cycle, and because
   the injection point is where sink confusion was caught: cc-dispatcher's
   per-call `sendToClient` is a **support SSE sink** on support turns
   (ADR-113), which neither ring-stamps nor reports real socket delivery —
   the call site must pass ws-handler's `defaultSendToClient`, and the drift
   pin must name the symbol (`emit: defaultSendToClient`), not just the
   `emit:` key (`emit: sendToClient` matches the SSE sink too).
3. `viewing = isConversationViewed(...)` read **post-emit**, same tick —
   `delivered && viewing` decides; emit-throw and predicate-throw both
   degrade to `viewing=false`/`delivered=false` → notify (never-throws
   contract for `void` callers).
4. `delivered` means "written to an OPEN socket's send buffer," not "seen" —
   the client-side read-mark therefore fires from the card's **mount
   `useEffect`** (painted ⇒ read), not from the ws-handler dispatch
   (dispatched ≠ painted; an unmount race would otherwise mark-read a card
   never shown → zero residual signal).

Client side, the companion bug the new frame exposed: `sendToClient` is
user-scoped, so seq-bearing buffered frames for conversation A land on the
socket bound to conversation B — and the replay-dedup gate advanced
`lastRenderedSeq` on the foreign seq, swallowing this surface's own later
frames. Drop convId-mismatched seq-bearing frames **before** the cursor
advances (`task_completed` is the first frame guaranteed to arrive
cross-conversation on every completion, making a pre-existing edge routine).

## Key Insight

- A suppression decision is only as honest as its proof — "the socket was
  OPEN and bound when the frame was written" is checkable server-side on the
  same synchronous tick as the emit; anything weaker (a predicate sampled
  earlier, a delivery that means "enqueued") is a silent-miss window.
- "Marked read at render" is only true if the mark literally fires in a
  mount effect — dispatch-time marking is receipt-anchored and can clear the
  badge for a card that never painted.
- Injected emitters must be pinned to the *symbol*, not the parameter name —
  `emit: sendToClient` passes a grep pin whether the binding is ws-handler's
  sender or a per-call SSE sink.

## Session Errors

1. Planning subagent lacked `skill`/`Task` tools → `plan`/`deepen-plan` ran
   in-process sequentially (disclosed in plan).
   **Prevention:** none needed — the sequential fallback is the prescribed
   path; record it in session-state as done.
2. Pencil `.pen` insert failures (quoted variable parents; stroke schema
   shape). **Prevention:** rebuild `.pen` wholesale rather than incremental
   `execute` inserts when parenting fails.
3. Plan cited `lib/swr-keys.ts` / a wrong learning dir / wrong mock path —
   all caught by §4.45 verify-the-negative and corrected.
   **Prevention:** the deepen-plan file-existence probes already cover this.
4. eslint `no-fallthrough` ratchet grew 5→6 — a comment-bearing empty `case`
   label counts as a fallthrough site; the fix was folding the annotation
   into the adjacent comment rather than adding a new comment-owning case.
   **Prevention:** when adding a case label to a grouped server→client-only
   block in `ws-handler`, keep the label bare (no preceding comment of its
   own) or the ratchet reds.
5. `gh issue create` refused three times — body-file must be written in a
   separate step first, referenced by ABSOLUTE path, and carry a filing exit
   (`User-Impact:`+`Fix-Size:` pair ≥101 lines/5 files, or a whole-line
   `Mandated-By: <rule-id>`).
   **Prevention:** the playbook is now in this learning; never paste `\n` in
   `--body` (literal backslash-n defeats the whole-line anchor).
6. A python file-rewrite sharing an `exec` with a hook-blocked `gh` call
   never ran — hook rejection kills the whole command, not just the gated
   subcommand. **Prevention:** write/edit files in a separate tool call from
   any gated command (`gh issue create`, prod writes); verify the file
   actually changed before re-running the gate.
7. CPO sign-off (`requires_cpo_signoff: true`) was reconciled as operator-
   confirmed scope via AskUserQuestion rather than a separate formal ack —
   recorded in tasks.md; implementation proceeded on the same conversation's
   explicit product decision.
   **Prevention:** when a plan declares `requires_cpo_signoff`, resolve the
   sign-off artifact BEFORE work begins (this session's AskUserQuestion is
   the sign-off; record it as such at plan time).

## Prevention

- Pattern guardrails now exist in-code: `task-completed-both-lineages.test.ts`
  pins the emitter symbol + no-`ws-handler`-import in `notifications.ts`;
  `task-completed-suppression.test.ts` pins all four suppression-matrix
  corners + emit-throw; `task-completed-inline.test.tsx` pins the convId
  drop, the seq-cursor ordering, and the mount-anchored read-mark (including
  the "dispatch alone must not POST" negative pin).
- Deferred residual filed as #9567 (client never learns resolved
  conversationId after a `context_path` 23505 rebind — convId-gated frames
  drop permanently; the honest-unread row remains).

## Tags

notifications, websocket, inbox, suppression, toctou, emit-injection,
render-anchored, replay-buffer, session-registry, adr-059, adr-067
