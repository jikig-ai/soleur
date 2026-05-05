---
title: Fix Concierge idle-runaway on PDF summarize + duplicate "Concierge" header label
type: fix
date: 2026-05-05
requires_cpo_signoff: false
deepened: 2026-05-05
---

# Fix Concierge idle-runaway on PDF summarize + duplicate "Concierge" header label

## Enhancement Summary

**Deepened on:** 2026-05-05
**Sections enhanced:** Acceptance Criteria, Files to Edit, Context (Bug 1 + Bug 2 fix shapes), Risks, Test plan
**Research surface used:** repo-research (existing runaway tests, `MessageBubble` test patterns, all `DOMAIN_LEADERS` name/title pairs), call-site audit for `DEFAULT_WALL_CLOCK_TRIGGER_MS` / `wallClockTriggerMs`, learning carry-forward (`2026-05-04-cc-soleur-go-cutover-dropped-document-context-and-stream-end.md`).

### Key Improvements (deepening pass)

1. **Bug 1 fix shape clarified — preserve `firstToolUseAt` as turn-origin metadata.** The naive "reset on every block" reading would corrupt the user-facing `elapsedMs` field on `runner_runaway`. Correct shape: leave `state.firstToolUseAt` set on first tool_use only (turn origin), but call `clearRunaway(state)` + `armRunaway(state)` on every subsequent assistant block so the timeout window resets without changing the elapsed-measurement origin.
2. **Bug 2 fix shape generalized — substring rule, not cc_router-only.** Auditing all `DOMAIN_LEADERS`, the `name` is a strict prefix of `title` for both `cc_router` ("Concierge" / "Soleur Concierge") AND `system` ("System" / "System Process"). A generic rule (`title.includes(displayName)` → render `title` only) catches both and is safer than a hardcoded `cc_router` branch. The cc_router-specific branch is named as an acceptable fallback only if test churn is meaningful.
3. **Test target file corrected.** Bug 1 tests must land in `apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts` (the actual home of the runaway-timer test surface) NOT the generic `soleur-go-runner.test.ts`. Bug 2 tests should land in a new sibling file `apps/web-platform/test/message-bubble-header.test.tsx` modeled on `message-bubble-retry.test.tsx` (existing render harness — same `vi.mock("@/lib/client-observability")` setup needed).
4. **Existing runaway tests confirmed compatible.** AC7-regression, AC8, AC9, AC17, and the silent-fallback test all pass `wallClockTriggerMs: 30_000` explicitly per-test and emit a single tool_use, then advance past 30s with no further blocks. They remain green under both the raised default AND the new "any-block resets" semantic without change.
5. **Call-site audit complete.** `grep -rn "DEFAULT_WALL_CLOCK_TRIGGER_MS\|wallClockTriggerMs" apps/web-platform/` returns exactly 11 hits: 5 test references in `soleur-go-runner-awaiting-user.test.ts` (all explicit `30_000` overrides — unaffected by default change), 5 in `soleur-go-runner.ts` (the constant + dep + threading), and zero in `ws-handler.ts` / health-check paths. Safe to raise.

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
      Implementation invariant: `state.firstToolUseAt` is NOT reset on subsequent blocks — it
      remains the turn-origin timestamp so `armRunaway`'s `firedAtStart = state.firstToolUseAt`
      capture continues to report the user-facing `elapsedMs` as total turn elapsed time
      (not "time since last block").
- [ ] **Bug 1 — tests.** `apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts` adds:
      (a) a test asserting the timer DOES fire when `wallClockTriggerMs` elapses with no further
      assistant blocks AFTER the new default (90s); (b) a test asserting the timer does NOT
      fire when a second `tool_use` arrives 25s after the first (within the new 90s budget,
      and the second-block reset extends the window for another full 90s); (c) a test
      asserting the timer does NOT fire when a mid-turn `text` block arrives before the
      budget expires; (d) a test asserting `runner_runaway.elapsedMs` reports time-since-
      first-tool_use (turn-origin), not time-since-last-block; (e) the default-constant
      assertion (currently NO test asserts `DEFAULT_WALL_CLOCK_TRIGGER_MS === 30_000` — see
      audit; if a test author adds one in the work phase, it must read 90_000).
- [ ] **Bug 2 — header label.** The Concierge bubble header on first message shows ONLY
      `Soleur Concierge` (not `Concierge   Soleur Concierge`). Visually verified against the
      same kb-concierge panel post-fix; subsequent messages in the same thread continue to render
      no header (existing `isFirst` behavior preserved).
- [ ] **Bug 2 — header label.** `apps/web-platform/components/chat/message-bubble.tsx` renders
      `leader.title` ONLY (not `displayName` AND `leader.title`) when `displayName` is contained
      in `leader.title` (substring-match, case-sensitive). This is the recommended fix shape —
      generic, catches both `cc_router` ("Concierge" / "Soleur Concierge") and the latent
      `system` leader bug ("System" / "System Process"), and is safer for future leaders.
      Acceptable fallback: special-case `leaderId === CC_ROUTER_LEADER_ID` only — but only if
      the substring rule generates unexpected test churn for other leaders.
      Concretely: `showFullTitle && !leader.title.includes(displayName) && (
        <span className="text-xs text-neutral-500">{leader.title}</span>
      )` paired with `displayName ? (<span>{leader.title.includes(displayName) ? leader.title : displayName}</span>) : null` — the implementer picks the cleaner JSX shape; the acceptance test pins behavior, not structure.
- [ ] **Bug 2 — tests.** New file `apps/web-platform/test/message-bubble-header.test.tsx`
      (modeled on `message-bubble-retry.test.tsx` — same `vi.mock("@/lib/client-observability")`
      shim) adds:
      (a) for `leaderId="cc_router"` with `showFullTitle=true`, the header contains
      `"Soleur Concierge"` exactly once and does NOT contain the bare token
      `"Concierge "` (trailing-space) or `"Concierge   Soleur Concierge"`.
      (b) for `leaderId="system"` with `showFullTitle=true`, the header contains
      `"System Process"` exactly once and does NOT show `"System   System Process"` —
      regression guard for the latent prefix-collision pattern.
- [ ] **Regression guard.** A non-prefix leader (e.g., `cmo` with `name: "CMO"` /
      `title: "Chief Marketing Officer"`) with `showFullTitle=true` continues to render BOTH
      `displayName` ("CMO") AND `leader.title` ("Chief Marketing Officer") — the
      substring-suppression must NOT fire when displayName is not contained in title.
      Note: in production the team-naming UX often passes a richer `displayName` via
      `getDisplayName` (e.g., `"CMO Riley"`); the test should cover BOTH the bare-name path
      (no `getDisplayName` provided) AND a getDisplayName-supplied team-name path to lock
      the substring rule's behavior on both shapes.
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
- **Given** the runner has emitted a tool_use at t=0 and another tool_use at t=60s, **when**
  the timer fires at t≥150s with no further blocks, **then**
  `runner_runaway.elapsedMs` is approximately 150_000 (turn-origin = first tool_use), NOT
  90_000 (time-since-last-block). This pins `firstToolUseAt` as turn-origin metadata.
- **Given** a Concierge bubble with `leaderId="cc_router"` and `showFullTitle=true`, **when**
  the bubble renders, **then** the header text content equals `"Soleur Concierge"` (single
  rendering — no leading bare `"Concierge"` token).
- **Given** a System bubble with `leaderId="system"` and `showFullTitle=true`, **when** the
  bubble renders, **then** the header contains `"System Process"` exactly once and does NOT
  contain `"System   System Process"` — regression guard for the latent prefix-collision.
- **Given** a CMO bubble with `leaderId="cmo"` and `showFullTitle=true` and NO
  `getDisplayName` prop, **when** the bubble renders, **then** the header contains BOTH
  `"CMO"` (from `leader.name`) AND `"Chief Marketing Officer"` (from `leader.title`) — the
  substring-suppression rule must NOT fire when displayName is not contained in title.
- **Given** a CMO bubble with a custom `getDisplayName` returning `"CMO Riley"` and
  `showFullTitle=true`, **when** the bubble renders, **then** the header contains BOTH
  `"CMO Riley"` AND `"Chief Marketing Officer"` — the team-name path is unaffected by the
  substring rule.

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
   - Raise `DEFAULT_WALL_CLOCK_TRIGGER_MS` from `30 * 1000` to `90 * 1000` (line 82).
   - In `handleAssistantMessage` (line ~766), refactor the runaway-arm logic. Today
     (lines 803-806) the timer arms ONCE on first `tool_use`. Replace with: on every
     assistant block (`text` and `tool_use`), if `firstToolUseAt === null` set
     `firstToolUseAt = now()` (turn-origin), then unconditionally call
     `clearRunaway(state)` + `armRunaway(state)` to reset the timeout window.
     **Critical:** do NOT reset `firstToolUseAt` on subsequent blocks — `armRunaway`
     captures `firedAtStart = state.firstToolUseAt` (line 702), and the user-facing
     `elapsedMs` field on `runner_runaway` must report total turn elapsed time, not
     "time since last block".
   - Update the comment block at lines ~798-803 ("Arm the wall-clock runaway timer on the FIRST
     tool_use…") to reflect the new "any assistant block resets the timeout window; turn-origin
     `firstToolUseAt` is preserved" semantic.
2. `apps/web-platform/components/chat/message-bubble.tsx`
   - In the header render block (lines ~145-153), gate the `leader.title` span on
     `showFullTitle && !leader.title.includes(displayName)` — when displayName is a substring
     of title, skip the bare `displayName` span and render `leader.title` instead. This is
     a generic substring rule; no per-leader special-case needed.
   - Acceptable fallback if the substring rule generates unexpected churn: special-case
     `leaderId === CC_ROUTER_LEADER_ID` only. Either path must satisfy ALL acceptance
     criteria including the system-leader regression guard.
   - If the substring rule is chosen, no additional import is needed. If the cc_router
     fallback is chosen, import `CC_ROUTER_LEADER_ID` from `@/lib/cc-router-id` (matches
     existing `LeaderAvatar` import shape).
3. `apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts`
   - Add four new tests per `## Test Scenarios` (no-fire on second tool_use within new 90s
     budget, no-fire on text block within budget, fire on 90s of true silence, elapsedMs
     reports turn-origin not last-block).
   - Existing AC7-regression / AC8 / AC9 / AC17 / silent-fallback tests are confirmed
     compatible (each passes `wallClockTriggerMs: 30_000` explicitly + emits one tool_use
     + advances past 30s — green under both old and new semantics).

## Files to Create

1. `apps/web-platform/test/message-bubble-header.test.tsx`
   - New test file modeled on `apps/web-platform/test/message-bubble-retry.test.tsx`
     (same `vi.mock("@/lib/client-observability")` shim required to keep Sentry initialization
     out of the bundle under test). See that file for the render harness.
   - Tests per `## Test Scenarios`: cc_router shows "Soleur Concierge" once; system leader
     shows "System Process" once; cmo (or another non-prefix leader) shows BOTH "CMO" and
     "Chief Marketing Officer"; team-name path (`getDisplayName="CMO Riley"`) renders both
     "CMO Riley" and "Chief Marketing Officer".

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
- **Other leaders' `displayName === leader.title` future collisions.** Verified at deepen
  time via `grep -n "name:\|title:" apps/web-platform/server/domain-leaders.ts`: TWO leaders
  today have `name` as a strict prefix of `title` — `cc_router` ("Concierge" /
  "Soleur Concierge") and `system` ("System" / "System Process"). The `system` leader is
  documented as not-user-visible-as-a-conversational-bubble (see line 95-100 of
  `domain-leaders.ts`), but the bug surface exists if it ever does render with
  `showFullTitle`. The recommended substring rule fixes BOTH; the cc_router-only fallback
  fixes only one and leaves the latent system-leader case untouched. Other leaders
  (`cmo`/CMO, `cto`/CTO, `cfo`/CFO, etc.) all have orthogonal name/title pairs where neither
  is a substring of the other, so the substring rule is no-op for them.
- **Substring-rule false positives for future leaders.** If a future leader is added with
  `name: "Acme"` / `title: "Acme Engineering"`, the substring rule would silently render only
  the title. This is the same UX as `cc_router` today (after the fix) and is design-intent —
  showing both creates the duplication this PR is fixing. If a future case wants explicit
  side-by-side rendering despite substring, the path forward is to override `displayName`
  via `getDisplayName` (e.g., `"Acme Bot"`) so the substring rule no longer matches. This
  escape hatch is documented in the Bug 2 fix-shape commentary.

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
