---
title: "fix: Concierge duplicate question box + Still-working-while-waiting"
date: 2026-07-06
type: fix
branch: feat-one-shot-concierge-web-duplicate-question-box
lane: cross-domain
brand_survival_threshold: none
status: draft
---

# 🐛 fix: De-duplicate the Concierge question prompt + suppress "Still working…" while awaiting operator input

## Overview

When the Concierge agent calls the SDK `AskUserQuestion` tool, the web chat renders the
question **twice**:

1. A plain, unstyled card at the top — the `ask_user` variant of `InteractivePromptCard`
   (`bg-soleur-bg-surface-1/60` box with the question + chip options).
2. The amber **"Confirm scope"** card below it — `ReviewGateCard` (styled amber card with the
   header badge, per-option descriptions, and a highlighted selection).

Both carry the *same* question text and the *same* options (e.g. "Continue implementing /
Investigate first / Abort"). The amber card is the intended, richer surface; the plain box is
redundant.

Separately, while the agent is **blocked** awaiting the operator's answer, the chat still shows
the bottom **"Still working…"** live-narration indicator — an in-progress/working signal that
contradicts the actual waiting-for-input state.

This plan fixes both with two small, well-precedented changes:

1. **De-duplicate** — stop emitting the `ask_user` `interactive_prompt` for `AskUserQuestion`,
   leaving the amber `review_gate` card as the single surface. This mirrors the existing `Bash`
   suppression (feat-concierge-stream-commands AC1), where the authoritative `review_gate` is
   already "the single gating surface."
2. **Suppress "Still working…" while awaiting input** — gate the live-narration slot so it never
   renders while an unresolved `review_gate` / `interactive_prompt` / `autonomous_disclosure`
   message is present (the agent is parked, not working).

### Root-cause trace (verified against `origin/main` working tree)

**Duplicate box — two producers for one tool call:**

- `apps/web-platform/server/permission-callback.ts:268-333` — the `canUseTool` callback intercepts
  `AskUserQuestion`, emits `{ type: "review_gate", question, header, options, descriptions,
  stepProgress }` via `sendToClient`, sets conversation status `waiting_for_user`, and awaits
  `abortableReviewGate`. This is the **amber card** path. Fires on **every** `AskUserQuestion`.
- `apps/web-platform/server/soleur-go-runner.ts:661-687` — `classifyInteractiveTool` maps the same
  `AskUserQuestion` SDK `tool_use` block to `{ kind: "ask_user", payload: { question, options,
  multiSelect } }`, which is registered in `pendingPrompts` and emitted as `{ type:
  "interactive_prompt" }` (emit site `soleur-go-runner.ts:1775`). This is the **plain box** path.
- The immediately-preceding `case "Bash"` (`soleur-go-runner.ts:646-660`) **already** `return null`
  for exactly this reason: "the authoritative `review_gate` (permission-callback.ts) is the single
  gating surface … an informational card is redundant spam." `AskUserQuestion` needs the identical
  treatment.

**"Still working…" while blocked — streamState never leaves "streaming":**

- `apps/web-platform/lib/ws-client.ts:935-957` — the WS message handler dispatches `review_gate`,
  `autonomous_disclosure`, and `interactive_prompt` all as `{ type: "stream_event" }`.
- `apps/web-platform/lib/ws-client.ts:320-355` — the `stream_event` reducer sets
  `nextStreamState = streamState === "idle" && isTurnActive ? "streaming" : streamState`. None of
  the three gate/prompt event types is in the `isTurnActive` set (`stream_start | stream | tool_use
  | tool_progress`), so `streamState` **stays "streaming"**. The same arm nulls `liveNarration`
  because `applyStreamEvent` clears `activeStreams` (the `review_gate` arm at
  `chat-state-machine.ts:674-707` returns `activeStreams: new Map()`).
- `apps/web-platform/components/chat/chat-surface.tsx:982-996` — the live-narration slot renders
  whenever `streamState === "streaming"`, with content `liveNarration ?? "Still working…"`. With
  `streamState="streaming"` + `liveNarration=null`, the operator sees "Still working…" while the
  turn is actually parked on the gate.

## Research Reconciliation — Spec vs. Codebase

| Claim (from bug report) | Reality (verified) | Plan response |
| --- | --- | --- |
| Two boxes render: plain top + amber "Confirm scope" | Confirmed: `interactive_prompt`/`ask_user` (`InteractivePromptCard`→`AskUserCard`) + `review_gate` (`ReviewGateCard`), both from one `AskUserQuestion` | Suppress the `ask_user` emission; keep `review_gate`. |
| "Still working…" shows while blocked | Confirmed: gate events keep `streamState="streaming"`; slot content falls back to "Still working…" | Gate the slot on a derived `awaitingUserInput` flag. |
| Fix belongs in one render component | Two distinct layers: server emit (`soleur-go-runner.ts`) for de-dup, client render (`chat-surface.tsx`) for the indicator | Two files (+ tests). |

## User-Brand Impact

**If this lands broken, the user experiences:** the same duplicate-question confusion (two boxes)
and/or a misleading "Still working…" spinner during a decision they are being asked to make — i.e.
no regression relative to today, plus wasted attention. A wrong de-dup that suppressed the *amber*
card instead would leave the operator with only the plain box (loss of option descriptions), or a
wrong narration gate could hide a genuine in-progress signal.

**If this leaks, the user's data is exposed via:** N/A — this change moves no user data. It removes
a redundant client render and gates a UI indicator; no new persistence, network, or auth surface.

**Brand-survival threshold:** none
- `threshold: none, reason:` this is a presentational de-duplication + indicator-visibility fix on
  an existing operator-facing surface; it introduces no data-movement, auth, or persistence change,
  and the `review_gate` response path (the authoritative gating channel) is unchanged.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (de-dup, server):** `classifyInteractiveTool("AskUserQuestion", …)` returns `null` — an
      `AskUserQuestion` `tool_use` no longer registers a pending prompt or emits an
      `interactive_prompt`. Verified by the updated
      `test/soleur-go-runner-interactive-prompt.test.ts` case (mirrors the `Bash` suppression
      assertion).
- [ ] **AC2 (single surface):** Given an `AskUserQuestion`, exactly one selectable question card
      renders — the amber `ReviewGateCard` (`review_gate`). No `data-prompt-kind="ask_user"` card is
      present. Verified in `test/cc-soleur-go-end-to-end-render.test.tsx`.
- [ ] **AC3 (no "Still working…" while awaiting input):** When `streamState === "streaming"` and an
      **unresolved** `review_gate` (or `autonomous_disclosure`) message from the current turn is
      present, the `data-testid="live-narration"` slot is **absent** (no "Still working…"). Verified
      by a new component render test (jsdom, `.test.tsx`) using the `test/mocks/use-websocket.ts`
      mock.
- [ ] **AC4 (narration still works otherwise):** With `streamState === "streaming"` and **no**
      unresolved gate, the live-narration slot still renders `liveNarration ?? "Still working…"`
      exactly as today (regression guard).
- [ ] **AC5 (resolved gate resumes narration):** After the gate is resolved (`resolved: true`) and
      the turn resumes streaming, the "Still working…" slot renders again (the suppression is
      awaiting-input-scoped, not permanent).
- [ ] **AC5b (informational prompt does NOT suppress — P1 regression guard):** With
      `streamState === "streaming"` and an **unresolved `interactive_prompt` (kind `diff` /
      `todo_write`)** card present but NO gate, the live-narration slot is **present**. Informational
      ack cards are emitted while the agent keeps working (they are auto-allowed in `canUseTool` and
      never flip `waiting_for_user`); gating on them would dark real narration. This is the coverage
      the plain AC4 (zero-prompt) case does not exercise.
- [ ] **AC5c (stale prior-turn gate does NOT suppress — P2a regression guard):** With
      `streamState === "streaming"`, an **unresolved `review_gate` that precedes the last `user`
      message** (abandoned/timed-out gate from a prior turn), the live-narration slot is **present**
      — the turn-scoping (`i > lastUserIdx`) excludes stale gates so a new turn is not darked by
      unresolved message residue.
- [ ] **AC6 (typecheck):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes — the
      kind-exhaustiveness assertion in `soleur-go-runner.ts` stays satisfied (the declared return
      type `InteractivePromptPayload | null` is unchanged, so removing the `ask_user` *return*
      branch does not break `_AssertClassifiedExhaustive`; `ask_user` stays a union member for
      replay back-compat, exactly like `bash_approval`).
- [ ] **AC7 (targeted suites green):** `cd apps/web-platform && ./node_modules/.bin/vitest run test/soleur-go-runner-interactive-prompt.test.ts test/cc-soleur-go-end-to-end-render.test.tsx test/reasoning-narration-frame.test.ts test/chat-surface-awaiting-input.test.tsx` all pass.

## Implementation Phases

### Phase 1 — Suppress the duplicate `ask_user` emission (server)

- **File:** `apps/web-platform/server/soleur-go-runner.ts`
- Change the `case "AskUserQuestion":` arm in `classifyInteractiveTool` (currently lines 661-687)
  to `return null`, with an explanatory comment mirroring the `Bash` precedent (646-660): the
  `review_gate` (permission-callback.ts) is the single, authoritative surface for `AskUserQuestion`;
  the `ask_user` card is redundant. Keep the `ask_user` variant in the `InteractivePromptPayload`
  union and in `InteractivePromptCard` for replay of already-persisted prompts (same rationale the
  Bash comment gives for keeping `bash_approval`).
- **Co-installation note (spec-flow P2b):** the comment MUST state that the `AskUserQuestion`
  `review_gate` (`permission-callback.ts:268` — unconditional interception in `canUseTool`, fires
  for subagent calls too) is the co-installed replacement surface. De-dup is only safe because
  `createCanUseTool` (review_gate) and the interactive-prompt bridge (`emitInteractivePrompt` /
  `pendingPrompts`) are always wired together in the cc path; the note guards a future refactor that
  splits the two wirings from silently reintroducing a no-question-surface state.
- **Do NOT** touch `permission-callback.ts` — the `review_gate` emit + `abortableReviewGate` +
  `buildReviewGateResponse` cycle is the surviving, correct path; the operator answers via
  `review_gate_response`. `bridgeInteractivePromptIfApplicable` returns on `null` from
  `classifyInteractiveTool` **before** `pendingPrompts.register` (soleur-go-runner.ts ~1746), so
  `AskUserQuestion` registers nothing and leaves no dangling registry entry (verified by spec-flow);
  other kinds classify/register/wire `respondToToolUse` unchanged.
- **Do NOT** delete `AskUserCard` from `interactive-prompt-card.tsx` — it remains for replay
  back-compat.

### Phase 2 — Suppress "Still working…" while awaiting operator input (client render)

- **File:** `apps/web-platform/components/chat/chat-surface.tsx`
- Derive, where `messages` and `streamState` are already in scope (before the JSX return of the
  message list, near the existing narration slot ~982):

  ```tsx
  // The agent is PARKED (not working) only while a review_gate or autonomous_disclosure
  // awaits the operator — these are the exact two surfaces whose canUseTool site flips the
  // server conversation status to `waiting_for_user` and pauses the runaway wall-clock
  // (cc-dispatcher.ts:2530-2534). Both keep streamState="streaming" (they aren't turn-active
  // events), so the live-narration slot would otherwise show "Still working…" while blocked.
  //
  // Deliberately NOT `interactive_prompt`: after Phase 1, the interactive_prompt kinds still
  // emitted (diff / todo_write / notebook_edit / plan_preview) are AUTO-ALLOWED in canUseTool —
  // the agent keeps streaming while they render, and diff/todo_write/notebook_edit are
  // informational "ack" cards the operator rarely clicks. Gating on them would suppress
  // "Still working…" for the rest of a genuinely-working turn (spec-flow/simplicity P1).
  //
  // Turn-scoped: only a gate AFTER the last user message counts. A gate left unresolved by a
  // prior turn (timeout / abort / operator ignored it and sent a new message) persists in
  // `messages` as resolved:false — nothing prunes it (stream_end prunes only tool_use_chip,
  // chat-state-machine.ts:646-648) — and would otherwise dark the narration on every later
  // streaming turn (spec-flow P2a).
  const lastUserIdx = messages.map((m) => m.role).lastIndexOf("user");
  const awaitingUserInput = messages.some(
    (m, i) =>
      i > lastUserIdx &&
      (m.type === "review_gate" || m.type === "autonomous_disclosure") &&
      !m.resolved,
  );
  ```

- Change the slot guard from `{streamState === "streaming" && (` to
  `{streamState === "streaming" && !awaitingUserInput && (`.
- Update the block's explanatory comment to note the awaiting-input suppression (keep the existing
  reconnect-null rationale).
- **Waiting-for-input surface:** the amber `ReviewGateCard` (and the other prompt cards) already
  *is* the waiting-for-input UI — the operator sees the question + options. Suppressing the
  contradictory spinner is sufficient; no new "Waiting for your input" element is required. (An
  explicit label is called out as an Alternative below and deferred unless plan-review/UX asks for
  it.)

### Phase 3 — Tests

- **`test/soleur-go-runner-interactive-prompt.test.ts`** — replace the existing case at ~231
  ("AskUserQuestion tool_use → emit interactive_prompt with kind ask_user") with a suppression
  assertion: an `AskUserQuestion` `tool_use` produces **no** `interactive_prompt` emit / no pending
  prompt. Mirror the Bash-suppression assertion shape already in the suite.
- **`test/cc-soleur-go-end-to-end-render.test.tsx`** — update/relax any assertion that expects an
  `ask_user` card from the `AskUserQuestion` path; assert the amber `review_gate` card is the sole
  question surface (no `data-prompt-kind="ask_user"`).
- **New `test/chat-surface-awaiting-input.test.tsx`** (jsdom via `.test.tsx`) — render `ChatSurface`
  with the `use-websocket` mock returning `streamState: "streaming"`, `liveNarration: null`, and a
  `messages` array; assert `queryByTestId("live-narration")` across five cases:
  - unresolved current-turn `review_gate` present → slot **null** (AC3);
  - no gate present → slot **present** (AC4);
  - resolved `review_gate` + streaming → slot **present** (AC5);
  - unresolved `interactive_prompt` (`diff` / `todo_write`) card, no gate → slot **present** (AC5b —
    P1 regression guard: informational cards must NOT suppress);
  - unresolved `review_gate` positioned BEFORE the last `user` message (stale prior-turn gate) →
    slot **present** (AC5c — P2a regression guard: turn-scoping excludes stale gates).

  (Confirm the exact mock shape and existing chat-surface `.test.tsx` harness before authoring;
  reuse `test/mocks/use-websocket.ts`.)

**Phase order note:** Phase 1 (server emit) and Phase 2 (client render) are independent; either can
land first. Phase 3 tests each phase.

## Alternative Approaches Considered

| Approach | Why not (default) |
| --- | --- |
| Suppress the `review_gate` and keep the plain `ask_user` box | Rejected — the amber card is the richer, intended surface (header, per-option descriptions, highlighted selection) and is the authoritative gating channel (`abortableReviewGate` + `buildReviewGateResponse`); the bug report explicitly says keep the amber card. |
| Introduce a new `streamState: "awaiting_input"` | Rejected (blast radius) — `streamState` gates the abort button (`chat-surface.tsx:450`) and `CohortMissingReplyMarker` (`isTurnInFlight = streamState !== "idle"`). A derived, message-scoped `awaitingUserInput` boolean is contained and does not disturb those consumers. Revisit only if a broader awaiting-input state is needed. |
| Reset `streamState` to `"idle"` on gate events | Rejected — would mark the turn "not in flight," breaking abort/lifecycle semantics while the operator is mid-decision. |
| Include `interactive_prompt` in `awaitingUserInput` | Rejected (plan-review P1, spec-flow + simplicity) — after Phase 1, the still-emitted kinds (`diff`/`todo_write`/`notebook_edit`/`plan_preview`) are auto-allowed and stream while the agent works; gating on them darks real narration mid-work. The server's authoritative parked set is exactly `review_gate` + `autonomous_disclosure`. |
| Whole-array (non-turn-scoped) `.some()` | Rejected (plan-review P2a) — an abandoned/timed-out gate persists unresolved in `messages` (unpruned) and would dark narration on every later streaming turn. Scope to `i > lastUserIdx`. |
| Render an explicit "Waiting for your input" line in place of the spinner | Deferred — the prompt card already conveys the waiting state; adding a second waiting element risks visual redundancy. Left as a UX call for plan-review/wireframe review. |

## Observability

```yaml
liveness_signal:
  what: Existing per-conversation WS session logs (soleur-go-runner dispatch + permission-callback
        "canUseTool-review-gate" decision log) already record every AskUserQuestion → review_gate.
  cadence: per AskUserQuestion tool call
  alert_target: none (no new failure mode introduced)
  configured_in: apps/web-platform/server/permission-callback.ts (logPermissionDecision), server logs
error_reporting:
  destination: no new error path; existing Sentry mirroring in permission-callback / ws-handler unchanged
  fail_loud: n/a (removal of a redundant client emit; no new catch/fallback)
failure_modes:
  - mode: AskUserQuestion still emits a duplicate ask_user card (regression)
    detection: test/cc-soleur-go-end-to-end-render.test.tsx (AC2) + test/soleur-go-runner-interactive-prompt.test.ts (AC1)
    alert_route: CI (vitest) — fails the PR
  - mode: live-narration wrongly suppressed during a genuine working turn (over-broad gate — informational interactive_prompt or stale prior-turn gate)
    detection: chat-surface-awaiting-input.test.tsx AC4 (no gate) + AC5b (informational diff/todo_write card) + AC5c (stale prior-turn gate) + reasoning-narration-frame.test.ts
    alert_route: CI (vitest) — fails the PR
  - mode: "Still working…" still shows while a gate is unresolved (under-fix)
    detection: chat-surface-awaiting-input.test.tsx (AC3)
    alert_route: CI (vitest) — fails the PR
logs:
  where: existing server logs (permission-callback decisions); no new log lines added
  retention: unchanged
discoverability_test:
  command: cd apps/web-platform && ./node_modules/.bin/vitest run test/soleur-go-runner-interactive-prompt.test.ts test/cc-soleur-go-end-to-end-render.test.tsx test/chat-surface-awaiting-input.test.tsx
  expected_output: all suites pass; no ask_user emission for AskUserQuestion; live-narration absent while an unresolved gate is present
```

No SSH is required to verify — the change is exercised entirely by the vitest suites above.

## Architecture Decision (ADR/C4)

No architectural decision. This is a presentational bug fix on an existing surface: it changes which
of two already-modeled client cards renders and gates an existing UI indicator. No ownership/tenancy
boundary, substrate, resolver/dispatch, or trust boundary changes; no existing ADR is reversed or
extended. **C4 impact: none** — the change touches no external human actor, no external system/vendor,
no container/data-store, and no actor↔surface access relationship; the Concierge chat surface and its
WS event flow are already modeled and unchanged (checked model.c4 / views.c4 / spec.c4 for the
Concierge chat container and its `review_gate`/`interactive_prompt` WS events — the edit is internal
to the already-modeled web client). Skip.

## Domain Review

**Domains relevant:** Product (UI surface)

### Product/UX Gate

**Tier:** blocking (mechanical UI-surface override — `components/chat/chat-surface.tsx` matches
`components/**/*.{tsx,jsx,vue,svelte}`)
**Decision:** auto-accepted (pipeline / headless)
**Agents invoked:** ux-design-lead (wireframe of the corrected single-card + no-spinner state)
**Skipped specialists:** none
**Pencil available:** yes

#### Findings

The change is a de-duplication + indicator-suppression fix, not a new design. Wireframe captures the
corrected end state: a single amber "Confirm scope" card as the sole selectable question surface,
with no plain duplicate box above it and no "Still working…" spinner below while awaiting the
operator's selection. See `## Wireframes` reference below.

## Wireframes

Wireframe artifact (corrected awaiting-input chat state) generated at plan time by `ux-design-lead`:

- `.pen`: `knowledge-base/product/design/concierge/concierge-confirm-scope-single-card.pen`
  (21,251 bytes, non-empty; committed on this branch)
- Screenshot: `knowledge-base/product/design/concierge/screenshots/04-confirm-scope-single-card.png`

It shows the corrected end state: a single amber "Confirm scope" card (badge + question + three
options with "Continue implementing" highlighted) as the sole question surface, no duplicate plain
box above, and no "Still working…" spinner below. `snapshot_layout(problemsOnly=true)` reported no
layout problems. Headless pipeline: ready for async review; the visual delta is a strict subtraction
from today's surface.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder-only fails `deepen-plan` Phase
  4.6. This plan fills it (threshold `none` + reason bullet).
- Removing the `ask_user` *return* branch must NOT change the declared return type of
  `classifyInteractiveTool` (`InteractivePromptPayload | null`) — the kind-exhaustiveness assertion
  keys off the annotation, not the inferred returns. Verify with `tsc --noEmit` (AC6). `ask_user`
  stays a union member for replay back-compat (identical to how `bash_approval` was kept when Bash
  stopped emitting).
- The `awaitingUserInput` `.some()` must match the SERVER's authoritative parked set — exactly
  `review_gate` + `autonomous_disclosure` (the only two `canUseTool` sites that flip conversation
  status to `waiting_for_user` and pause the runaway wall-clock, `cc-dispatcher.ts:2530-2534`). Do
  **NOT** add `interactive_prompt`: its still-emitted kinds (`diff` / `todo_write` /
  `notebook_edit` / `plan_preview`) are auto-allowed and stream while the agent works —
  `diff`/`todo_write`/`notebook_edit` are informational "ack" cards the operator rarely clicks, so
  gating on them darks real narration for the rest of the turn (spec-flow + simplicity P1). A future
  interactive kind that genuinely parks would set `waiting_for_user` server-side and should be added
  there, not by blanket-including the informational-prompt channel.
- The `.some()` must be **turn-scoped** (`i > lastUserIdx`): an unresolved gate is durable in
  `messages` (nothing prunes it — `stream_end` prunes only `tool_use_chip`,
  `chat-state-machine.ts:646-648`), so a gate abandoned by a prior turn (timeout / abort / operator
  sent a new message) would otherwise dark narration on every later streaming turn (spec-flow P2a).
- New render test path must satisfy vitest's `include` globs: component tests live at
  `test/**/*.test.tsx` (happy-dom). A co-located `components/**/*.test.tsx` is never collected — put
  the new test under `test/`.

## Open Code-Review Overlap

None (checked at plan draft time — file this section's query at Step 1.7.5 once Files-to-Edit is
frozen; the three edit targets are `soleur-go-runner.ts`, `chat-surface.tsx`, and the three test
files).

## Files to Edit

- `apps/web-platform/server/soleur-go-runner.ts` — `AskUserQuestion` case → `return null`.
- `apps/web-platform/components/chat/chat-surface.tsx` — derive `awaitingUserInput`; gate the
  live-narration slot.
- `apps/web-platform/test/soleur-go-runner-interactive-prompt.test.ts` — flip the AskUserQuestion
  case to a suppression assertion.
- `apps/web-platform/test/cc-soleur-go-end-to-end-render.test.tsx` — assert single amber surface.

## Files to Create

- `apps/web-platform/test/chat-surface-awaiting-input.test.tsx` — narration-suppression render test.
