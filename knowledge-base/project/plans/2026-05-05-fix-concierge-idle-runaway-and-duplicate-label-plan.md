---
title: Fix Concierge idle-runaway on PDF summarize + duplicate "Concierge" header label
type: fix
date: 2026-05-05
requires_cpo_signoff: false
---

# Fix Concierge idle-runaway on PDF summarize + duplicate "Concierge" header label

Two regressions in the kb-concierge thread UI, both surfaced by a single user-reported screenshot
(`/home/jean/Pictures/Screenshots/Screenshot From 2026-05-05 10-23-37.png`).

1. Asking "can you summarize this document?" against an attached PDF (Au Chat Potan presentation) shows
   the assistant bubble in `Working` state with a `Read` tool chip, then dies with
   `Error: The agent went idle without finishing. Try sending another message to nudge it forward.`
   The `runner_runaway` 30s wall-clock fires before the SDK's PDF Read + summarize turn can complete
   — the 30s budget covers both tool-execution and post-Read inference, and a multi-page PDF
   legitimately exceeds it.
2. The Concierge bubble header shows `Concierge   Soleur Concierge` — `leader.name` ("Concierge") and
   `leader.title` ("Soleur Concierge") are both rendered side-by-side on first message of the
   conversation. For every other domain leader the pair is a useful disambiguation
   (`CMO Riley | Chief Marketing Officer`); for cc_router the name is a strict prefix of the title,
   producing pure duplication.

Both bugs live in `apps/web-platform`. Bug 1 is in `server/soleur-go-runner.ts` (the `/soleur:go`
runner that PR #2901 introduced); bug 2 is in `components/chat/message-bubble.tsx` (header render
for `showFullTitle`).

## User-Brand Impact

- **If this lands broken, the user experiences:** the kb-concierge "Ask about this document" panel
  cannot summarize PDFs — the only document type for which Concierge guidance is most useful — and
  the Concierge header looks like a label-rendering bug (which it is). Both surface on the first
  PDF turn most users try, so first-impression damage is high.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A — neither fix touches
  credentials, auth, data, payments, or user-owned resources. The runaway-timer change widens the
  upper bound on agent compute time per turn, not the security envelope.
- **Brand-survival threshold:** `none`

*Scope-out override:* `threshold: none, reason: this PR touches client-bundle UI rendering and
server-side wall-clock heuristics — no sensitive paths per preflight Check 6 (no credentials, auth,
data, payments).*

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **Bug 1 — runaway timer.** Asking "can you summarize this document?" against any PDF up to
      ~5 MB / ~50 pages in the kb-concierge panel produces a complete summary without surfacing
      `Error: The agent went idle without finishing.` Verified manually against the
      `Au Chat Potan - Presentation Projet-10.pdf` fixture from the screenshot (or the closest
      equivalent reproducible PDF in `knowledge-base/`).
- [ ] **Bug 1 — runaway timer.** `DEFAULT_WALL_CLOCK_TRIGGER_MS` is raised from 30s to 90s in
      `apps/web-platform/server/soleur-go-runner.ts`. The pre-existing comment
      ("measures 'no SDKResultMessage for wallClockTriggerMs'") is updated to reflect the new
      value AND the new "any-assistant-block resets the clock" semantics.
- [ ] **Bug 1 — runaway timer.** The runaway timer resets on EVERY assistant `tool_use` block
      and EVERY assistant `text` block during the active turn, not just the first `tool_use`.
      The clock is cleared by `SDKResultMessage` (turn boundary) as today. The semantic moves
      from "30s after first tool_use" to "90s of true silence (no assistant content at all)".
- [ ] **Bug 1 — tests.** `apps/web-platform/test/soleur-go-runner.test.ts` adds:
      (a) a test asserting the timer DOES fire when `wallClockTriggerMs` elapses with no further
      assistant blocks; (b) a test asserting the timer does NOT fire when a second `tool_use`
      arrives before the budget expires; (c) a test asserting the timer does NOT fire when a
      mid-turn `text` block arrives before the budget expires; (d) the existing 30s-default
      assertion is updated to 90s.
- [ ] **Bug 2 — header label.** The Concierge bubble header on first message shows ONLY
      `Soleur Concierge` (not `Concierge   Soleur Concierge`). Visually verified against the
      same kb-concierge panel post-fix; subsequent messages in the same thread continue to render
      no header (existing `isFirst` behavior preserved).
- [ ] **Bug 2 — header label.** `apps/web-platform/components/chat/message-bubble.tsx` renders
      `displayName` only — never both `displayName` and `leader.title` — when `displayName` is a
      substring of (or equal to) `leader.title` for that leader. Equivalent specific-case branch:
      special-case `leaderId === CC_ROUTER_LEADER_ID` to render `leader.title` only and skip
      `displayName`. Either approach is acceptable provided no other leader's header regresses.
- [ ] **Bug 2 — tests.** `apps/web-platform/test/` adds (or extends an existing message-bubble
      test) one render-time assertion: for `leaderId="cc_router"` with `showFullTitle=true`,
      the header contains `"Soleur Concierge"` exactly once and does NOT contain the bare token
      `"Concierge "` (trailing-space) or `"Concierge   Soleur Concierge"`.
- [ ] **Regression guard.** A non-cc leader (e.g., `cmo`) with `showFullTitle=true` continues
      to render BOTH `displayName` (e.g., `"CMO Riley"`) AND `leader.title`
      (e.g., `"Chief Marketing Officer"`) — the duplicate-suppression must NOT fire for
      leaders where name is not a prefix of title.
- [ ] **Type-check + full suite green.** `bun run --cwd apps/web-platform typecheck` clean and
      the web-platform vitest suite passes (≥ pre-PR baseline).

### Post-merge (operator)

- [ ] **Smoke verify in prod.** Open the Soleur Command Center kb-concierge panel against an
      attached PDF, ask "summarize this document". Confirm a complete reply renders and the
      header shows `Soleur Concierge` once. (Manual — Playwright MCP would require auth flow
      against prod; smoke is faster.)

## Test Scenarios

- **Given** the cc-soleur-go runner has dispatched a turn for a PDF summarize ask, **when** the
  SDK emits `tool_use(name="Read", input.file_path=…pdf)` followed by 60s of silence, **then**
  the runner does NOT fire `runner_runaway` (60s < new 90s budget).
- **Given** the runner has emitted one `tool_use`, **when** a second `tool_use` arrives 25s later
  (within the old 30s budget), **then** the runaway timer is reset to a fresh 90s window starting
  from the second tool_use timestamp.
- **Given** the runner has emitted one `tool_use`, **when** an assistant `text` block arrives
  25s later, **then** the runaway timer is reset to a fresh 90s window (text is a progress
  signal, not just tool_use).
- **Given** the runner has emitted one `tool_use`, **when** 95s elapse with no further assistant
  blocks AND no `SDKResultMessage`, **then** the runner fires
  `onWorkflowEnded({ status: "runner_runaway", elapsedMs: ≥90_000 })` exactly as today.
- **Given** the runner has emitted one `tool_use` and 25s later receives `SDKResultMessage`,
  **then** the runaway timer is cleared (existing semantics, unchanged).
- **Given** a Concierge bubble with `leaderId="cc_router"` and `showFullTitle=true`, **when**
  the bubble renders, **then** the header text content equals `"Soleur Concierge"` (single
  rendering — no leading bare `"Concierge"` token).
- **Given** a CMO bubble with `leaderId="cmo"` and `showFullTitle=true`, **when** the bubble
  renders, **then** the header contains BOTH the team-name token (`"CMO Riley"`) AND
  `leader.title` (`"Chief Marketing Officer"`) — regression guard against an over-broad
  duplicate-suppression rule.

## Context

### Bug 1 — root cause (verified)

`apps/web-platform/server/soleur-go-runner.ts:82`:

```ts
export const DEFAULT_WALL_CLOCK_TRIGGER_MS = 30 * 1000;
```

`apps/web-platform/server/soleur-go-runner.ts:694-713` (`armRunaway`) starts a 30s timer at
`firstToolUseAt` (set on first `tool_use`, line 803-806). `handleAssistantMessage` does NOT re-arm
on subsequent `tool_use` blocks (`if (state.firstToolUseAt === null) { ... armRunaway(state); }`).
The timer is cleared by `SDKResultMessage` only (`handleResultMessage` line 859 `clearRunaway`).

PR #2901 introduced the runaway as a 30s safeguard against a stuck SDK subprocess. PR #3213
restored PDF context (system prompt now contains a Read directive), so the runner correctly
asks the SDK to call `Read("…/foo.pdf")`. But:

1. PDF Read on a 50-page presentation = several seconds of file IO + base64-decode latency in
   the SDK subprocess.
2. After Read returns, the model has to digest the document and generate a multi-paragraph
   summary — additional inference latency.
3. The 30s clock covers BOTH (1) and (2) without any progress-signal reset.
4. There is no heartbeat-style WS event to keep the clock at bay during model inference.

The legacy `agent-runner.ts` path (pre-#2901) had no per-turn runaway timer, so this is a new
regression class introduced by the streaming-input cutover. PR #3213 fixed system-prompt PDF
parity but did not touch the timer.

### Bug 1 — chosen fix shape

Two adjustments in `soleur-go-runner.ts`:

1. **Raise the default from 30s to 90s.** Empirically PDF Read + summarize on a 5MB / 50-page
   presentation can hit ~45-60s on cold subprocess; 90s gives a 1.5x safety margin without
   leaving a truly stuck SDK process unbounded.
2. **Reset the timer on every assistant block, not just first tool_use.** New semantic:
   "90s of true silence (no assistant content at all)". When `handleAssistantMessage`
   processes a `text` or `tool_use` block AND `state.firstToolUseAt !== null` AND
   `!state.awaitingUser`, re-arm the timer with a fresh window. This treats any assistant
   content as a progress signal, which is the right invariant — the runaway should detect
   a hung subprocess, not a slow turn.

Both adjustments are in one function (`handleAssistantMessage`) plus the constant. ~10 LoC.

### Bug 2 — root cause (verified)

`apps/web-platform/components/chat/message-bubble.tsx:145-153`:

```tsx
{leader && (
  <div className="mb-1 flex items-center gap-2">
    <span className="text-xs font-semibold text-neutral-300">
      {displayName}
    </span>
    {showFullTitle && (
      <span className="text-xs text-neutral-500">{leader.title}</span>
    )}
  </div>
)}
```

`displayName` resolves via `getDisplayName?.(leaderId) ?? leader.name` (line 97). For
`leaderId="cc_router"`:

- `leader.name === "Concierge"` (`apps/web-platform/server/domain-leaders.ts:102`)
- `leader.title === "Soleur Concierge"` (line 104)

`displayName` ⇒ `"Concierge"`. With `showFullTitle=true` (true on first message of a leader,
see `chat-surface.tsx:494` `showFullTitle={!!isFirst}`), both render side-by-side:
`Concierge   Soleur Concierge`.

For other leaders (`cmo`, `cto`, etc.) the team-naming UX intentionally pairs the
display-name (e.g., `"CMO Riley"`) with the title (`"Chief Marketing Officer"`). For cc_router
the name is a strict prefix of the title, so the pair degenerates into duplication.

### Bug 2 — chosen fix shape

Special-case `leaderId === CC_ROUTER_LEADER_ID` (the same constant `LeaderAvatar` already
imports — `apps/web-platform/lib/cc-router-id.ts`) and skip the bare `displayName` span,
rendering only `leader.title` ("Soleur Concierge"). Other leaders unchanged.

Why a leader-specific branch (not a generic "if name is prefix of title, render title only"):

- The cc_router special-case is already an established pattern in the codebase
  (`LeaderAvatar` line 65 `isConcierge = leaderId === CC_ROUTER_LEADER_ID`,
  `chat-state-machine.ts:484-516` cc_router case for `stream_end`,
  `domain-leaders.ts:107` `internal: true`, `agentPath: ""`).
- A generic prefix rule would silently change rendering for any future leader where someone
  picks a `name`/`title` pair that happens to share a prefix — a less-surprising, more
  reviewable change is the explicit special-case.

### Open Code-Review Overlap

None. `gh issue list --label code-review --state open --json number,title,body --limit 200 |
jq -r '.[] | select(.body // "" | contains("soleur-go-runner.ts") or contains("message-bubble.tsx"))'`
returns zero matches against the planned files.

### Research Reconciliation — Spec vs. Codebase

| User-reported claim | Codebase reality | Plan response |
|---|---|---|
| "Recent PR #3213 restored PDF context for kb-concierge — verify whether that path is actually feeding PDF content into the model." | PR #3213 (`fix(kb-concierge): restore PDF context, soleur logo avatar, and markdown rendering`) DID restore PDF context via `kb-document-resolver.ts` + `buildSoleurGoSystemPrompt` (PDFs get a Read directive — text gets inlined up to 50KB). The system prompt is correct; the agent IS being instructed to Read the PDF. | Bug 1 is NOT a context-injection regression; it is a runaway-timer regression introduced by PR #2901 that PR #3213 did not touch. Plan scopes the fix to `soleur-go-runner.ts` runaway logic, not to context resolution. |
| "Bug surfaces in apps/web-platform — search for the thread/message renderer and the concierge agent runner." | Confirmed: thread/message renderer is `components/chat/message-bubble.tsx` (Bug 2 site); agent runner is `server/soleur-go-runner.ts` (Bug 1 site). | Plan's `## Files to Edit` lists both. |

### Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a localized two-file bug fix in the kb-concierge
thread UI runtime + render. Product domain is not engaged because no new user-facing surface,
flow, or page is being created — both fixes are corrective on existing surfaces. CMO/CRO/CFO/COO
have no signal in the diff. CTO sign-off lives in the runaway-timer Risk note below.

## Files to Edit

1. `apps/web-platform/server/soleur-go-runner.ts`
   - Raise `DEFAULT_WALL_CLOCK_TRIGGER_MS` from `30 * 1000` to `90 * 1000`.
   - In `handleAssistantMessage`, after the existing first-`tool_use` arm-runaway branch, add a
     re-arm path that fires for every `text` / `tool_use` block when `firstToolUseAt !== null`
     and `!state.awaitingUser`.
   - Update the comment block at lines ~798-803 ("Arm the wall-clock runaway timer on the FIRST
     tool_use…") to reflect the new "any-assistant-content resets the clock" semantic.
2. `apps/web-platform/components/chat/message-bubble.tsx`
   - Special-case `leaderId === CC_ROUTER_LEADER_ID`: when true, render `leader.title` only and
     skip the bare `displayName` span. Other leaders unchanged.
   - Import `CC_ROUTER_LEADER_ID` from `@/lib/cc-router-id` (matches existing `LeaderAvatar`
     import shape).
3. `apps/web-platform/test/soleur-go-runner.test.ts`
   - Update the existing 30s-default assertion to 90s.
   - Add four new tests per `## Test Scenarios` (no-fire on second tool_use within budget,
     no-fire on text block within budget, fire on 90s of true silence, default-90s assertion).
4. `apps/web-platform/test/message-bubble.test.tsx` (or extend existing if present; otherwise
   create alongside leader-avatar.test.tsx)
   - Add the cc_router header-render assertion.
   - Add the cmo regression-guard render assertion.

## Files to Create

None — all edits are in existing files. (The message-bubble test file may be created if no
existing test covers `MessageBubble` rendering — `grep -l "MessageBubble" apps/web-platform/test/`
to confirm during work-phase.)

## Risks

- **Runaway-timer relaxation.** Raising 30s → 90s widens the upper bound on per-turn agent
  compute time. A truly stuck SDK subprocess now wastes 90s of wall clock instead of 30s before
  the runaway fires. Acceptable: (a) the cost-ceiling circuit breaker still fires independently
  on `totalCostUsd >= cap` (`emitWorkflowEnded` line 882-890), so a runaway compute spend cannot
  exceed the per-workflow cap regardless of wall-clock; (b) the per-conversation idle reaper
  (`DEFAULT_IDLE_REAP_MS = 10 * 60 * 1000`) still tears down idle Queries; (c) the new
  reset-on-any-block semantic is the load-bearing change — without it, raising the budget alone
  would still be too tight on cold-subprocess multi-tool turns.
- **`leader.title` rename drift.** If a future change renames `cc_router.title` from
  `"Soleur Concierge"` to a different value, the test asserting
  `header.contains("Soleur Concierge")` would fail and force the renamer to update the test
  in the same commit. Acceptable — that is the desired pin.
- **Other leaders' `displayName === leader.title` future collisions.** Today no other leader's
  `name` equals (or is a strict prefix of) its `title`. Verified at plan time:
  `grep -A1 "name:" apps/web-platform/server/domain-leaders.ts | grep -B1 "title:"` (manual
  walk through `DOMAIN_LEADERS` at `apps/web-platform/server/domain-leaders.ts`). The
  `cc_router` special-case avoids over-fitting a generic prefix-match rule that would silently
  affect future leaders.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares
  `threshold: none` with the explicit scope-out rationale, so the gate passes.
- The `runner_runaway` user-facing copy
  (`apps/web-platform/server/cc-dispatcher.ts:144-145`, `"The agent went idle without finishing.
  Try sending another message to nudge it forward."`) is unchanged. The fix targets the
  trigger condition, not the message — once the timer no longer fires on legitimate slow turns,
  the message is correct for its actual use case (genuinely stuck SDK).
- After raising `DEFAULT_WALL_CLOCK_TRIGGER_MS`, ensure the `ws-handler.ts` and any container
  health-check paths that read this constant directly are not broken — `grep -n
  "DEFAULT_WALL_CLOCK_TRIGGER_MS" apps/web-platform/` should show only the runner + tests
  (verified at plan time: only `soleur-go-runner.ts:82` and the test file).

## References

- PR #2901 — Stage 2.12 cc-soleur-go cutover that introduced the runaway timer
  (`knowledge-base/project/learnings/best-practices/2026-04-27-widen-async-contract-instead-of-deferred-construction-proxy.md`)
- PR #3213 — kb-concierge PDF-context restoration that confirmed Bug 1 is NOT a context regression
  (`knowledge-base/project/plans/2026-05-04-fix-kb-concierge-pdf-context-and-logo-plan.md`)
- ADR-022 — SDK as router (the architecture that introduced streaming-input mode)
- Screenshot: `/home/jean/Pictures/Screenshots/Screenshot From 2026-05-05 10-23-37.png`
