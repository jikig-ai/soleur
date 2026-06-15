---
title: "fix: Concierge chat box layout — avatar left-align, bubble shrink-to-fit, debug Show toggle clickability"
date: 2026-06-15
type: fix
branch: feat-one-shot-concierge-box-layout
lane: single-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix: Concierge chat box layout (avatar alignment · bubble width · debug Show toggle) 🐛

## Overview

Three independent layout/interaction defects on the **full-variant Command Center chat surface**
(`apps/web-platform/components/chat/chat-surface.tsx` → `MessageBubble` + `DebugStreamPanel`):

1. **Avatar pushes the Concierge box inward.** The Soleur "S" avatar sits *inside* the bubble's flex
   row, to the left of the card, so the card's left edge is offset right of the row's start by the
   avatar width (`h-7 w-7` = 28px) + `gap-3` (12px) ≈ 40px. The Debug stream panel directly below
   renders at the wrapper's left edge (no avatar), so the two left edges are misaligned.
2. **Premature wrapping.** The Concierge bubble card has `max-w-[90%] md:max-w-[80%]` on the **flex
   row** but the inner card has no natural-width sizing — combined with the `flex-1`/`min-w-0`
   pressure it can wrap short content (`"Routing to the right experts..."`) onto two lines even
   when it fits on one at a sensible max width.
3. **"Show" toggle no longer clickable (regression from #5241).** Before #5241 the entire debug
   header was ONE `<button>` and the "Show/Hide · not saved" `<span>` lived inside it, so clicking
   the word "Show" toggled the panel. #5241 split the header into a `<div>` with the toggle
   `<button>` (wrapping only "Debug stream" + count) and a **sibling** `<div>` holding the Copy
   button and a now-inert `"Show/Hide · not saved"` `<span>`. The word "Show" — the affordance the
   user reads as the control — is no longer inside any button, so clicking it does nothing.

Scope is these three CSS/JSX adjustments plus regression tests. No backend, schema, infra, or
regulated-data surface is touched. This is a single-domain (frontend) fix.

## Premise Validation

All three target surfaces exist on the worktree and the bug reports are *fix*, not *build*, premises:
- `components/chat/message-bubble.tsx` — `MessageBubble`, avatar at L178-180, card at L182-189 (issues 1, 2).
- `components/leader-avatar.tsx` — `LeaderAvatar`, `md` size = `h-7 w-7` (28px), `shrink-0` (issue 1).
- `components/chat/debug-stream-panel.tsx` — header `<div>` at L175, toggle `<button>` L176-196, inert
  `Show/Hide` `<span>` L212-214 (issue 3).
- `components/chat/chat-surface.tsx` — message list + DebugStreamPanel share the same
  `widthWrapper = "mx-auto max-w-3xl"` container (L733, L924), so the panel's left edge IS the
  wrapper edge; the routing chip example renders at L898-909 with label `"Routing to the right
  experts..."` (issues 1, 2).

Issue 3's regression was confirmed by reading the #5241 diff (`git show 9b6541b08`): the header
`<button class="flex w-full ...">` (with the `Show/Hide` span inside) was replaced by a `<div>` +
`<button class="flex flex-1 ...">` (Debug-stream text only) + a sibling `<div>` holding Copy and the
now-orphaned `Show/Hide` span. The existing tests pass because they click
`getByRole("button", { name: /debug stream/i })` (the toggle's accessible name is its "Debug stream"
text) — they never exercised the "Show" affordance, so the regression is invisible to the suite.

No external premises (issue refs, ADRs) are cited by the feature description — nothing else to validate.

## Research Reconciliation — Spec vs. Codebase

| Claim (from description) | Reality (codebase) | Plan response |
|---|---|---|
| "avatar pushes the bubble inward; two left edges misaligned" | Avatar is `shrink-0` inside the same flex row as the card, left of it; Debug panel has no avatar (issue 1 confirmed) | Move avatar out of the card's left-edge flex flow on the assistant side (negative-margin / absolute) so the card's left edge = row left edge = wrapper edge. |
| "bubble wraps when it would fit on one line" | Card has no `w-fit`/natural-width; row caps at `max-w-[90%]/[80%]` (issue 2 confirmed) | Add `w-fit max-w-full` (or `max-w-fit`) to the card so it shrinks to content up to the row cap. |
| "Copy button's container intercepts clicks on Show (overlay/stacking/pointer-events)" | NOT an overlay/z-index/pointer-events issue. The "Show" text is in a non-interactive `<span>` outside the toggle button (issue 3 — different mechanism than the report hypothesized) | Move the `Show/Hide · not saved` text *inside* the toggle button (keep Copy a sibling). Restores clickability without any z-index/pointer-events change. |

## User-Brand Impact

**If this lands broken, the user experiences:** a visibly misaligned chat box (Concierge box left
edge not aligned to the Debug panel below it), text wrapping awkwardly mid-phrase, or a debug "Show"
control that still does nothing when clicked — cosmetic/interaction polish defects on a dev-cohort
surface, no data loss.

**If this leaks, the user's data is exposed via:** N/A — this change touches only presentational
layout (flex/margin classes) and which DOM node owns an existing `onClick`. No new data flow, no
new persistence, no new network call, no redaction-path change.

**Brand-survival threshold:** none — pure presentational fix; reason: only Tailwind layout classes
and the ownership of an existing toggle handler change; the redaction dual-gate, the Copy serializer,
and all WS/persistence paths are untouched.

## Implementation Phases

### Phase 1 — Issue 3: restore the "Show" toggle clickability (debug-stream-panel.tsx)

The "Show/Hide · not saved" label currently sits in the right-side sibling `<div>` (L212-214) as a
plain `<span>`, outside the toggle `<button>`. Move the toggle affordance text back inside the
toggle button so clicking "Show"/"Hide" toggles the panel, while keeping Copy a sibling button.

Chosen approach (minimal, preserves the #5241 "Copy is a sibling, never nested" invariant):
- Inside the toggle `<button>` (L176-196), after the existing children, append the `Show/Hide`
  text so it is part of the button's clickable area:
  ```tsx
  // inside the toggle <button>, after the disconnected span:
  <span className="ml-auto text-[10px] font-medium text-soleur-text-secondary">
    {expanded ? "Hide" : "Show"}
  </span>
  ```
  (`ml-auto` pushes it to the right end of the `flex-1` button so the visual position is preserved.)
- Remove the orphaned `<span>` at L212-214 from the right-side `<div>`. The "· not saved" hint moves
  with it OR is kept as a separate non-interactive `<span>` next to Copy — keep "· not saved" as a
  static caption beside Copy (it is informational, not a control), and let "Show/Hide" live in the
  button. Final right-side `<div>`: `[ Copy button ] [ "· not saved" span ]`.
- Net effect: the toggle button now contains `Debug stream` + count + (disconnected?) + `Show/Hide`;
  Copy + "· not saved" remain siblings. Clicking anywhere on the left ~flex-1 region (including the
  word "Show") toggles; clicking Copy copies and never toggles (unchanged).

Files to Edit:
- `apps/web-platform/components/chat/debug-stream-panel.tsx` — move `Show/Hide` text into the toggle
  button; keep Copy + "· not saved" as siblings.

### Phase 2 — Issue 1: align the Concierge box left edge with the Debug panel (message-bubble.tsx)

The assistant-side row is `flex min-w-0 max-w-[90%] gap-3 md:max-w-[80%]` (L177) with the avatar
(`LeaderAvatar`, `shrink-0`) as the first child and the card second. The avatar consumes 28px + 12px
gap at the row's start, offsetting the card's left edge.

Chosen approach — render the avatar so it does NOT consume left-edge flow on the assistant side, so
the card's left edge coincides with the row's (and wrapper's) left edge:
- Option A (preferred): position the avatar with a negative left margin / absolute offset so it sits
  in the gutter left of the card without pushing the card right. e.g. wrap the assistant card's
  positioning context and render the avatar with `absolute -left-9 top-1` (or `-ml-9`) so the card's
  left edge aligns to the wrapper edge while the avatar floats in the left margin.
- Option B (simpler, evaluate at /work): drop the avatar from the row for the Concierge/assistant
  full-variant and rely on the in-bubble header (`headerPrimary`, L207-219) for identity — but this
  removes the avatar entirely; only adopt if the design owner accepts no avatar.

Decision: implement Option A — keep the avatar visible (brand presence) but move it out of the
card's left-edge flow so the card aligns. Guard so the **user** side (`isUser`, right-aligned,
`flex-row-reverse`) is unaffected — the alignment requirement is assistant-side only.

Constraints to preserve:
- `LeaderAvatar` is `shrink-0` and only rendered when `leader` is truthy (L178). The alignment edit
  must not regress the user-bubble layout or the sidebar variant.
- The mobile narrow viewport must not clip the avatar into the scroll container's padding — verify
  the negative offset against `px-4` (16px) / `md:px-6` (24px) wrapper padding so the avatar does
  not overflow the viewport edge on mobile. If 36px (`-left-9`) exceeds available gutter on mobile,
  scope the offset to `md:` and keep the current in-flow avatar on mobile (mobile alignment is not
  in the bug report).

Files to Edit:
- `apps/web-platform/components/chat/message-bubble.tsx` — assistant-side avatar positioning.

### Phase 3 — Issue 2: shrink-to-fit the Concierge bubble card (message-bubble.tsx)

The card (`data-testid="message-bubble-card"`, L182-189) has no natural-width sizing, so flex
pressure can wrap short content prematurely.

Chosen approach:
- Add `w-fit max-w-full` to the card's className so it sizes to content up to the row cap
  (`max-w-[90%] md:max-w-[80%]` already lives on the parent row). `w-fit` = `width: fit-content`,
  `max-w-full` keeps it inside the row cap; `min-w-0` (already present) keeps long content wrapping
  correctly. This makes `"Routing to the right experts..."` render on one line at sensible widths.
- Verify this does not break: (a) long markdown / code blocks (must still wrap, not overflow —
  `min-w-0` + the inner `[overflow-wrap:anywhere]` handle this), (b) the user bubble (apply the
  width treatment to both sides or scope to assistant — evaluate at /work; the report is about the
  Concierge/assistant bubble, so scope to assistant if user-side regresses), (c) the streaming
  cursor + "Working"/"Streaming" absolute badges (positioned `right-3` — unaffected by `w-fit`).

Files to Edit:
- `apps/web-platform/components/chat/message-bubble.tsx` — card `w-fit max-w-full`.

> Phases 2 and 3 both edit `message-bubble.tsx`; land them in one pass. Phase 1 edits
> `debug-stream-panel.tsx` independently.

### Phase 4 — Regression tests

vitest component project includes ONLY `test/**/*.test.tsx` (happy-dom) — co-located
`components/**/*.test.tsx` is silently NOT run (see Sharp Edges). All new tests live under
`apps/web-platform/test/components/`.

- **Issue 3 (extend existing `test/components/debug-stream-panel.test.tsx`):** add a test asserting
  the `Show`/`Hide` text is INSIDE the toggle button and that clicking it toggles `aria-expanded`.
  Concretely: `const toggle = screen.getByRole("button", { name: /debug stream/i })` then
  `expect(toggle.textContent).toMatch(/Show/)` (before expand) and
  `fireEvent.click(within(toggle).getByText(/Show/)); expect(toggle.getAttribute("aria-expanded")).toBe("true")`.
  Keep the existing AC4/AC6 assertion that Copy is NOT a descendant of the toggle and does not toggle.
- **Issues 1 + 2 (new `test/components/message-bubble.test.tsx`):** render a Concierge/assistant
  `MessageBubble` and assert the card carries the width class (`w-fit`) and the assistant-side avatar
  offset class is present (assert the className tokens, not pixel geometry — happy-dom does not lay
  out). This is a class-presence guard, not a visual-geometry test; visual confirmation is the
  Playwright/manual step below.
- **Visual confirmation (Playwright MCP, not a unit test):** at /work QA, drive the full chat surface
  with the routing chip visible and screenshot to confirm (a) Concierge box left edge aligns with the
  Debug panel left edge, (b) `"Routing to the right experts..."` is one line, (c) clicking the word
  "Show" toggles the debug panel. Use `mcp__playwright__*` against the dev surface.

## Files to Edit

- `apps/web-platform/components/chat/debug-stream-panel.tsx` (issue 3)
- `apps/web-platform/components/chat/message-bubble.tsx` (issues 1, 2)
- `apps/web-platform/test/components/debug-stream-panel.test.tsx` (issue 3 regression test — extend)

## Files to Create

- `apps/web-platform/test/components/message-bubble.test.tsx` (issues 1, 2 class-presence guards)

## Open Code-Review Overlap

None — no open `code-review`-labeled issue references `message-bubble.tsx`, `debug-stream-panel.tsx`,
or `chat-surface.tsx` (checked at plan time; the planned files are presentational and were last
touched by #5241 / #5282 / #5208, all merged).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (issue 3):** In `debug-stream-panel.tsx`, the `Show`/`Hide` text is rendered inside the
  toggle `<button>` (the one with `aria-expanded`), not in the right-side sibling `<div>`. Verify:
  `grep -n "Show" apps/web-platform/components/chat/debug-stream-panel.tsx` shows the ternary within
  the toggle button's JSX block (between the `<button ... onClick={() => setExpanded` open tag and
  its close).
- [ ] **AC2 (issue 3):** `debug-stream-panel.test.tsx` asserts: (a) the toggle button's `textContent`
  contains "Show" when collapsed; (b) clicking the "Show" text flips `aria-expanded` false→true;
  (c) the existing AC4/AC6 invariant still holds — Copy is NOT a descendant of the toggle and clicking
  Copy does not change `aria-expanded`.
- [ ] **AC3 (issue 1):** In `message-bubble.tsx`, the assistant-side avatar is positioned so the
  card's left edge is not offset by the avatar (negative-margin / absolute offset on the assistant
  branch). The user-side (`isUser`) layout is unchanged.
- [ ] **AC4 (issue 2):** The card (`data-testid="message-bubble-card"`) className includes a
  shrink-to-fit width (`w-fit`) with `max-w-full`, so short content does not wrap.
- [ ] **AC5:** `message-bubble.test.tsx` asserts the card carries the `w-fit` token and the
  assistant-avatar offset token is present.
- [ ] **AC6 (typecheck):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] **AC7 (tests):** `cd apps/web-platform && ./node_modules/.bin/vitest run test/components/debug-stream-panel.test.tsx test/components/message-bubble.test.tsx` passes.
- [ ] **AC8 (no regression to Copy):** the existing debug-stream Copy tests (Copy→Copied affordance,
  serializer redaction) still pass.

### Post-merge (operator)

- [ ] **AC9 (visual QA):** via Playwright MCP against the dev chat surface (debug-mode cohort),
  confirm (a) Concierge box left edge aligns to the Debug panel left edge, (b)
  `"Routing to the right experts..."` renders on one line, (c) clicking the word "Show" toggles the
  panel. Automation: feasible via `mcp__playwright__*` — run at /work QA, not deferred to a human.

## Domain Review

**Domains relevant:** Product (UI surface — mechanical override fired)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none — no NEW user-facing page/flow/component file is created (only
existing components are modified and one co-located test file added), so the BLOCKING `.pen`
wireframe requirement does not fire (`wg-ui-feature-requires-pen-wireframe` applies to new UI
surfaces; this is a layout/interaction correction to existing surfaces).
**Pencil available:** N/A (no new UI surface)

#### Findings

Pure presentational + interaction-ownership fix to existing chat components. No new flows, no copy
changes, no new persuasive/emotional surfaces — ADVISORY tier, auto-accepted on the pipeline path.

## Observability

Skipped — this plan edits only client presentational components
(`apps/web-platform/components/chat/*.tsx`); no `apps/*/server/`, `apps/*/infra/`, or new
infrastructure surface. No new error path, log site, or failure mode is introduced. (The existing
`reportSilentFallback` redaction-fallthrough mirror in `message-bubble.tsx` is untouched.)

## Test Scenarios

1. Collapsed debug panel → click the word "Show" → panel expands (`aria-expanded` true), label reads "Hide".
2. Click Copy → "Copied" affordance, panel does NOT toggle, `aria-expanded` unchanged.
3. Concierge routing chip ("Routing to the right experts...") → renders on one line, box left edge
   aligned with the Debug panel left edge below.
4. Long assistant markdown/code → still wraps inside the card (no horizontal overflow).
5. User bubble (right-aligned) → unchanged by the assistant-side avatar/width edits.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan`
  Phase 4.6 — this plan fills it (threshold: none, with reason).
- **vitest discovery:** the component project collects ONLY `test/**/*.test.tsx`. A co-located
  `components/chat/message-bubble.test.tsx` would be silently skipped. Both the new test and the
  extended test live under `apps/web-platform/test/components/`.
- **Typecheck command:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — NOT
  `npm run -w apps/web-platform typecheck` (no root `workspaces` field; the `-w` form aborts).
- **happy-dom does not lay out.** Unit tests can only assert class-token presence, not pixel
  alignment. The actual "left edges align" and "one line" outcomes are verified via Playwright MCP
  at QA, not in vitest.
- **Alignment in both toggle states:** issue 3's toggle has collapsed/expanded states. Verify the
  "Show"↔"Hide" swap toggles correctly in BOTH states (the same `expanded` ternary now lives in the
  button); confirm clicking works after expanding too (clicking "Hide" collapses).
- **Mobile gutter clip (issue 1):** a negative-margin/absolute avatar offset can push the avatar past
  the scroll container's `px-4` (16px) padding on mobile. Verify the offset against viewport padding;
  if it overflows, scope the alignment to `md:` and leave mobile avatar in-flow (mobile alignment is
  not in the bug report).
- **`w-fit` interaction with absolute badges:** the "Working"/"Streaming" badge and done-checkmark
  are `absolute right-3 -top-2.5` on the card — `w-fit` shrinks the card, so confirm the badges still
  sit inside the (now narrower) card and don't clip; very short content (e.g. a 1-word bubble) must
  still leave room for the `right-3` badge.
