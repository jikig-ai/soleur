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

## Enhancement Summary

**Deepened on:** 2026-06-15
**Agents:** architecture-strategist (CSS correctness), code-simplicity-reviewer (YAGNI).

### Key changes from deepen-pass
1. **Issue 1 — replaced the negative-margin/absolute avatar (old Option A) with moving the avatar
   INTO the existing card header row.** The negative-margin approach (P1) clips the avatar off-screen
   on viewports narrower than `max-w-3xl`+gutters (`-left-9`=36px vs `px-4`=16px), and the `md:`-only
   fallback would leave mobile unaligned. Rendering `<LeaderAvatar size="sm">` as the first child of
   the existing in-card header `div` (`flex items-center gap-2`, message-bubble.tsx L207-219) makes
   the card's left edge = row edge = wrapper edge = Debug-panel edge, with zero negative margins and
   no clipping on any viewport.
2. **Issue 2 — add a `min-w` floor alongside `w-fit`** so the absolute `-top-2.5 right-3`
   "Working"/"Streaming"/checkmark badges (L191/L197) don't overhang the left edge on very short
   (1-word / empty `done`) bubbles. Scope the width treatment to the assistant side; `max-w-full` is
   redundant-but-harmless.
3. **Cut the new `test/components/message-bubble.test.tsx`** — class-token presence assertions are
   tautological under happy-dom (no layout); Playwright QA (AC9) is the real verification for issues
   1+2. Dropped AC5 and AC1's grep-gate (ceremony). Net: 9 ACs → 6 meaningful ones; phases 2+3 merge.

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

### Phase 2 — Issues 1 + 2: Concierge box left-edge alignment + shrink-to-fit (message-bubble.tsx)

Both edits are in `message-bubble.tsx`; land in one pass. (Phase 1 edits `debug-stream-panel.tsx`
independently.)

**Issue 1 — align the card left edge with the Debug panel (avatar into the card header).**

The assistant-side row is `flex min-w-0 max-w-[90%] gap-3 md:max-w-[80%]` (L177) with the avatar
(`LeaderAvatar`, `shrink-0`) as the first child and the card second. The avatar consumes 28px + 12px
gap at the row's START, offsetting the card's left edge right of the wrapper (and thus right of the
Debug panel below it).

Chosen approach (revised at deepen-pass — rejected the negative-margin/absolute variant): **move the
avatar OUT of the row's left-edge flow and INTO the existing in-card header row.** The card already
renders a header `div` (`mb-1 flex items-center gap-2`, L207-219) holding `headerPrimary`. Prepend
`<LeaderAvatar size="sm" leaderId={leaderId!} customIconPath={customIconPath} />` as the first child
of that header `div`, and remove the row-level avatar (L178-180) on the assistant side. The card's
left edge then coincides with the row's (and wrapper's, and Debug panel's) left edge — no negative
margins, no off-screen clipping on any viewport.

- Use `size="sm"` (20px) so the avatar fits the header line height; `md` (28px) row avatar becomes
  the smaller in-header mark. Acceptable minor visual change, not a regression.
- Guard the **user** side (`isUser`, right-aligned, `flex-row-reverse`) — leave its layout untouched.
- The card already renders the header only `{leader && (...)}` (L207), which is exactly the
  Concierge/leader case — so the avatar moves cleanly into that conditional. Non-leader/system
  bubbles that today render no avatar are unaffected.
- **Why not negative-margin (rejected):** an `-left-9`/`-ml-9` (36px) offset clips the avatar
  off-screen on viewports narrower than `max-w-3xl`+gutters (wrapper hugs `px-4`=16px at L689); the
  `md:`-only fallback would leave mobile misaligned and create two avatar layouts. Moving into the
  header avoids all of this and reuses an existing flex container (no novel positioning precedent).

**Issue 2 — shrink-to-fit the card so short content does not wrap.**

The card (`data-testid="message-bubble-card"`, L182-189) has no natural-width sizing, so flex
pressure can wrap short content (`"Routing to the right experts..."`) prematurely.

- Add `w-fit max-w-full` to the assistant-side card className. `w-fit` = `width: fit-content` sizes
  the card to content up to the row cap (`max-w-[90%] md:max-w-[80%]` on the parent row, which still
  applies transitively); `min-w-0` (already present) keeps LONG content wrapping correctly (no
  conflict with `w-fit` — `min-w-0` lowers the flex floor, `fit-content` resolves above it).
  `max-w-full` is redundant-but-harmless (parent row already caps width) — keep as a cheap guard.
- **Add a `min-w` floor** (e.g. `min-w-[7rem]` on the assistant card, or scope to active/done state)
  so `fit-content` never collapses the card narrower than the absolutely-positioned
  `-top-2.5 right-3` badges ("Working"/"Streaming" L191, done-checkmark L197). Without a floor, a
  1-word `done` bubble or the `Used:` chip-list (L394-405) shrinks the card below badge width and the
  `right-3`-anchored badge overhangs the left card edge. The exact floor value is tuned at /work
  against the widest badge; the QA matrix MUST screenshot a short `done` bubble, not only the wide
  routing chip.
- Scope the width treatment to the assistant side (the report is about the Concierge bubble); leave
  the user bubble unchanged unless QA shows it benefits.

Files to Edit:
- `apps/web-platform/components/chat/message-bubble.tsx` — avatar into card header (issue 1); card
  `w-fit max-w-full min-w-[…]` on the assistant side (issue 2).

### Phase 3 — Regression test (issue 3) + visual QA (issues 1, 2, 3)

vitest component project includes ONLY `test/**/*.test.tsx` (happy-dom) — co-located
`components/**/*.test.tsx` is silently NOT run (see Sharp Edges).

- **Issue 3 — extend existing `test/components/debug-stream-panel.test.tsx`** (real behavioral
  regression guard for the #5241 defect): assert the `Show`/`Hide` text is INSIDE the toggle button
  and clicking it toggles the panel. Concretely:
  `const toggle = screen.getByRole("button", { name: /debug stream/i })`, then
  `expect(toggle.textContent).toMatch(/Show/)` (collapsed) and
  `fireEvent.click(within(toggle).getByText(/Show/)); expect(toggle.getAttribute("aria-expanded")).toBe("true")`.
  Keep the existing AC4/AC6 invariant (Copy is NOT a descendant of the toggle and does not toggle).
- **Issues 1 + 2 — NO new unit test.** Class-token presence assertions are tautological under
  happy-dom (no layout engine), so a `message-bubble.test.tsx` that greps for `w-fit` only restates
  the diff. The real verification is the Playwright visual step below — it owns issues 1 and 2.
- **Visual confirmation (Playwright MCP, automated at /work QA — AC9):** drive the full chat surface
  with the routing chip visible and screenshot to confirm (a) Concierge box left edge aligns with the
  Debug panel left edge, (b) `"Routing to the right experts..."` renders on one line, (c) a SHORT
  `done` bubble's badge does not overhang the left card edge, (d) clicking the word "Show" toggles the
  debug panel. Use `mcp__playwright__*` against the dev surface.

## Files to Edit

- `apps/web-platform/components/chat/debug-stream-panel.tsx` (issue 3)
- `apps/web-platform/components/chat/message-bubble.tsx` (issues 1, 2 — avatar into card header; card `w-fit min-w-[…]`)
- `apps/web-platform/test/components/debug-stream-panel.test.tsx` (issue 3 regression test — extend)

## Files to Create

None. (The deepen-pass cut the planned `test/components/message-bubble.test.tsx`: class-token
assertions are tautological under happy-dom; Playwright QA owns issues 1+2.)

## Precedent

- `w-fit` / `min-w-[…]`: Tailwind v4.1 (`apps/web-platform/package.json` → `tailwindcss: ^4.1.0`);
  utilities present. No existing `w-fit` usage in `components/chat/**` — pattern is novel here but
  trivial and framework-standard.
- Moving the avatar into the in-card header reuses the existing `flex items-center gap-2` header row
  (message-bubble.tsx L207-219) rather than inventing an absolute-positioning pattern — preferred
  precisely because no negative-margin-avatar precedent exists in the chat components.

## Open Code-Review Overlap

None — no open `code-review`-labeled issue references `message-bubble.tsx`, `debug-stream-panel.tsx`,
or `chat-surface.tsx` (checked at plan time; the planned files are presentational and were last
touched by #5241 / #5282 / #5208, all merged).

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 (issue 3):** `debug-stream-panel.test.tsx` asserts: (a) the toggle button's `textContent`
  contains "Show" when collapsed; (b) clicking the "Show" text (via `within(toggle).getByText(/Show/)`)
  flips `aria-expanded` false→true; (c) the existing invariant still holds — Copy is NOT a descendant
  of the toggle and clicking Copy does not change `aria-expanded`.
- [x] **AC2 (issue 1, production contract):** In `message-bubble.tsx`, the assistant-side avatar
  renders inside the in-card header `div` (not as a row-level sibling left of the card), so the card's
  left edge is not offset. The user-side (`isUser`) layout is unchanged. (Visual outcome verified by
  AC6.)
- [x] **AC3 (issue 2, production contract):** The assistant card (`data-testid="message-bubble-card"`)
  className includes `w-fit` and a `min-w-[…]` floor sized for the absolute `right-3` badges. (Visual
  no-overhang outcome verified by AC6.)
- [x] **AC4 (typecheck):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [x] **AC5 (tests):** `cd apps/web-platform && ./node_modules/.bin/vitest run test/components/debug-stream-panel.test.tsx` passes, including the existing Copy tests (Copy→Copied affordance, serializer redaction — no regression).

### Post-merge (operator)

- [ ] **AC6 (visual QA — automated):** via Playwright MCP against the dev chat surface (debug-mode
  cohort), confirm (a) Concierge box left edge aligns to the Debug panel left edge, (b)
  `"Routing to the right experts..."` renders on one line, (c) a SHORT `done` bubble's badge does not
  overhang the left card edge, (d) clicking the word "Show" toggles the panel. Automation: feasible
  via `mcp__playwright__*` — run at /work QA, not deferred to a human.

## Domain Review

**Domains relevant:** Product (UI surface — mechanical override fired)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none — no NEW user-facing page/flow/component file is created (only
existing components are modified; no files are created). The deepen-plan Phase 4.9 UI-wireframe
mechanical glob matches (`components/chat/*.tsx` is edited), but per the shared UI-surface term list
this change falls in the **Excluded** category ("Pure copy or style tweaks with no structural/layout
change" — here a layout/CSS correction + re-parenting an existing toggle handler, no new structural
surface, flow, screen, or persuasive copy). No `.pen` wireframe adds design value for moving an
avatar, shrink-to-fitting a card, and restoring a toggle's clickability; recording the determination
explicitly here rather than skipping silently (`wg-ui-feature-requires-pen-wireframe`).
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
- **vitest discovery:** the component project collects ONLY `test/**/*.test.tsx`. The extended
  `debug-stream-panel.test.tsx` already lives under `apps/web-platform/test/components/`. (No new
  message-bubble unit test — happy-dom cannot verify the layout outcomes that matter.)
- **Typecheck command:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — NOT
  `npm run -w apps/web-platform typecheck` (no root `workspaces` field; the `-w` form aborts).
- **happy-dom does not lay out.** This is why issues 1+2 are verified via Playwright MCP (AC6), not
  vitest — a class-token assertion would be tautological.
- **Alignment in both toggle states:** issue 3's toggle has collapsed/expanded states. Verify the
  "Show"↔"Hide" swap toggles correctly in BOTH states (the same `expanded` ternary now lives in the
  button); confirm clicking works after expanding too (clicking "Hide" collapses).
- **Avatar moves into the header — verify identity rendering.** Moving `LeaderAvatar` into the
  `{leader && (...)}` header block (L207) means non-leader/system assistant bubbles (which render no
  header today) still render no avatar — confirm that's acceptable (it matches today's behavior: the
  row-level avatar was also `{leader && ...}`-gated at L178). Confirm `customIconPath` is still
  threaded to the relocated avatar.
- **`w-fit` + absolute badges need a `min-w` floor.** The "Working"/"Streaming" badge and
  done-checkmark are `absolute right-3 -top-2.5` on the card — `w-fit` shrinks the card, so a 1-word
  `done` bubble (or the `Used:` chip-list) can collapse the card narrower than the `right-3`-anchored
  badge, which then overhangs the left card edge. The `min-w-[…]` floor (tuned at /work to the widest
  badge) prevents this; QA MUST screenshot a short `done` bubble, not only the wide routing chip.
