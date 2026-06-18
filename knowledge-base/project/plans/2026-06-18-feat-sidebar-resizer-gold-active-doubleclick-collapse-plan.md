---
title: "feat: Sidebar resizer — gold active state + double-click-to-collapse across all sidebars"
date: 2026-06-18
type: feat
branch: feat-one-shot-sidebar-resizer-gold-active-doubleclick-collapse
lane: cross-domain
brand_survival_threshold: none
status: draft
---

## Enhancement Summary

**Deepened on:** 2026-06-18
**Sections enhanced:** Overview/operator-decision, FR variants, Acceptance Criteria, Research Insights, Sharp Edges
**Agents used:** best-practices-researcher, code-simplicity-reviewer, architecture-strategist,
user-impact-reviewer, frontend-anti-slop scanner.

### Key Improvements
1. **FR3-Alternative (keep button + double-click accelerator) PROMOTED to plan-of-record.**
   Five independent agents (CPO, spec-flow, code-simplicity, architecture-strategist,
   user-impact) converged: removing the button + widening the resize gate (old FR3) creates
   an incoherent "resize handle that doesn't resize" in 3/4 sections, an a11y misnaming
   (`role=separator`+`aria-valuenow`+"Resize knowledge base sidebar" rendered in Settings),
   AND a persisted-collapse boot dead-end. FR3-literal is retained as opt-in but, if chosen,
   MUST use the architecture-recommended decomposition (a separate collapse-edge gesture, NOT
   a widened resize handle) and the FM-driven ACs below.
2. **Concrete implementation grounding** added (Research Insights): 5px drag threshold;
   **Enter/Space key must collapse** for AT parity (W3C Window Splitter pattern) — double-click
   alone strands keyboard users; gold `#c9a962` on `#141414` = **7.77:1** (passes 1.4.11 at full
   opacity — verify the /50 render or raise to /70); Tailwind v4 `bg-soleur-accent-gold-fill/50`
   is valid on CSS-var tokens.
3. **Failure-mode ACs** added from user-impact pass (cold-boot-collapsed expand test;
   keyboard collapse parity; fetch-independent chevron).

### New Considerations Discovered
- The collapse state **persists to localStorage** (`use-sidebar-collapse.ts`) → a regressed
  expand affordance strands the user collapsed across reloads (FM-1). The expand control MUST
  render unconditionally in the collapsed branch, independent of any data fetch.
- frontend-anti-slop baseline: `amber-500` trips NOTHING (no off-brand-color rule; it's a
  Tailwind builtin), and `bg-soleur-accent-gold-fill` trips nothing — the gold swap is
  scanner-neutral. Two pre-existing advisory BRAND-NONZERO-CORNER findings in
  kb-desktop-layout.tsx + c4-workspace.tsx are unrelated (rounded-* dots) and out of scope.

# ✨ feat: Sidebar resizer — gold active state + double-click-to-collapse (all sidebars)

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). This is in
> practice a single-domain web-platform frontend change; the default is conservative.

## Overview

Three coupled changes to the web-platform's resize-handle ("grip") controls, building on
the straight vertical grip-bar idiom shipped in **PR #5477** (KB sidebar grip bar, merged
2026-06-17):

1. **Gold on ACTIVE (drag), grey on hover.** Today the handle's drag/active wash is
   `amber-500` (Tailwind built-in orange `#f59e0b`) — an **off-palette** color that is not
   in the Soleur token system at all. Change the active/drag (and keyboard-focus) wash to
   **brand gold** `soleur-accent-gold-fill` (`#c9a962`). Hover stays grey
   (`soleur-text-secondary`). The grip turns gold **while you click/drag**, never on hover.
2. **Remove the dedicated collapse button; double-click the resizer to collapse.** The
   floated `PanelToggleIcon` button in the nav rail (`(dashboard)/layout.tsx:367`) is
   removed. A **double-click on the nav-rail resizer** collapses the sidebar.
3. **Apply consistently to ALL sidebars.** The gold-active change lands on all three
   resize handles (nav rail + two between-pane splitters). Double-click-to-collapse lands
   **only on the nav-rail resizer** — the two splitters have no collapsed-width state, so a
   double-click has no coherent target there (see Research Reconciliation, gap E).

This is UI chrome, brand-survival threshold `none` (matching #5477's own classification).

### ⚠️ Operator decision embedded in this plan (read before /work)

The literal request — *"remove the dedicated collapse button entirely"* — creates two hard
dead-ends if implemented naively, because **the nav-rail resizer only renders when drilled
into KB AND expanded** (`kbExpanded` gate, `layout.tsx:506`):

- **Dead-end A:** outside KB-expanded (Dashboard root, Settings, Chat), the resizer never
  renders, so removing the button leaves **no pointer affordance to collapse** — only ⌘B.
- **Dead-end C:** once collapsed, `kbExpanded` is false, so the resizer unmounts; a
  double-click-to-collapse gesture is **self-destroying** and there is **no pointer
  affordance to expand**.

Both spec-flow-analyzer and the CPO recommend KEEPING the button (add double-click as an
additive accelerator), citing a discoverability regression for the Phase-4 non-technical
ICP. **This plan honors the user's explicit instruction to remove the button**, and closes
the dead-ends by (i) rendering the resizer in **all expanded drill states** (not KB-only) so
double-click-collapse works everywhere, and (ii) adding a **persistent expand chevron on the
collapsed rail edge** so expand survives collapse. `requires_cpo_signoff` is NOT set
(threshold `none`), but the Domain Review records the CPO's dissent so the operator can
override to "keep the button" at sign-off if desired. **If the operator prefers the
additive-button approach, switch FR3 to the "Alternative (additive)" variant below before
/work.**

## Research Reconciliation — Spec vs. Codebase

| Spec/request claim | Codebase reality | Plan response |
|---|---|---|
| "Resizer shows grey on hover; should turn gold on active" | Hover already grey; active is `amber-500/50` (NOT gold) at `rail-resize-handle.tsx:104`, `kb-desktop-layout.tsx:20`, `c4-workspace.tsx:25` | Correct premise. Swap `amber-500` → `soleur-accent-gold-fill` on active + focus-visible. |
| "Remove the dedicated collapse button" | Button is the floated `PanelToggleIcon` at `(dashboard)/layout.tsx:367`; it is the ONLY pointer collapse/expand affordance and renders in ALL drill states | Remove it, but re-home collapse (double-click resizer) AND expand (collapsed-rail chevron) — see gaps A/C. |
| "Double-click the resizer to collapse" | Nav-rail resizer (`RailResizeHandle`) renders only when `kbExpanded` (`layout.tsx:506`) | Widen the render gate to all expanded drill states (FR3) so the gesture is universal. |
| "Apply to ALL sidebars" | 3 resize handles: nav rail (collapsible) + 2 react-resizable-panels Separators (NOT collapsible — binary mount/unmount, no collapsed width) | Gold → all 3. Double-click-collapse → nav rail only (gap E). Make asymmetry explicit in code comments. |
| (implicit) focus state is amber | `focus-visible:bg-amber-500/50` on the rail handle (`:104`) while the GLOBAL focus ring is already gold (`globals.css:168`) | Move focus-visible to gold too — aligns with the existing global focus token. |
| react-resizable-panels percentages | v4 treats numeric sizes as pixels; this repo uses string `"40%"` forms | No size changes in scope; do NOT introduce numeric sizes. |

## User-Brand Impact

**If this lands broken, the user experiences:** a sidebar they cannot collapse or re-expand
by pointer (if the button is removed without the resizer re-home + collapsed-rail chevron),
or an off-brand orange flash on drag — a visible polish defect on the primary nav chrome.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this is
client-side CSS/interaction chrome. No data, auth, network, or persistence boundary is
touched beyond the existing `localStorage` rail-width/collapse keys (no new data class).

**Brand-survival threshold:** none — UI chrome. Reason: matches PR #5477's classification;
no regulated-data or single-user-incident surface. (Threshold `none` + no sensitive-path
diff ⇒ no Check-6 scope-out bullet required; this section satisfies preflight.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (gold active, rail):** `apps/web-platform/components/dashboard/rail-resize-handle.tsx`
      contains NO `amber-500` token; the active AND focus-visible wash use
      `soleur-accent-gold-fill`. Verify: `! grep -q 'amber-500' apps/web-platform/components/dashboard/rail-resize-handle.tsx` returns true, and `grep -c 'soleur-accent-gold-fill' …` ≥ 2 (active + focus-visible).
- [ ] **AC2 (gold active, all 3 handles):** zero `amber-500` occurrences remain in any of the
      three handle files. Verify: `grep -rn 'amber-500' apps/web-platform/components/dashboard/rail-resize-handle.tsx apps/web-platform/components/kb/kb-desktop-layout.tsx apps/web-platform/components/kb/c4-workspace.tsx` returns no lines.
- [ ] **AC3 (hover stays grey):** the grip's hover class is still `group-hover:bg-soleur-text-secondary` (no gold on hover) in all three files. Verify: `grep -c 'group-hover:bg-soleur-text-secondary' …` per file unchanged from baseline; no `hover:bg-soleur-accent-gold` anywhere.
- [ ] **AC4 (button removed):** `(dashboard)/layout.tsx` no longer renders the floated
      `PanelToggleIcon` collapse button, and the now-unused `PanelToggleIcon` SVG is deleted.
      Verify: `! grep -q 'PanelToggleIcon' apps/web-platform/app/\(dashboard\)/layout.tsx`.
- [ ] **AC5 (double-click collapses, rail):** double-clicking the rail resizer toggles
      `collapsed` to true. Verified by a vitest test (RTL) firing `fireEvent.doubleClick` on
      `data-testid="kb-rail-resize-handle"` and asserting the `onCollapse` prop fires exactly once.
- [ ] **AC6 (double-click guard):** a double-click that immediately follows a drag of > **5px**
      total pointer travel does NOT collapse; and double-click does NOT persist a width when
      `latest === startWidth` (no no-op localStorage write). Covered by two vitest cases.
      (5px is the MDN/use-gesture canonical drag threshold. NOTE per code-simplicity: first
      verify empirically during RED whether `onDoubleClick` can even fire after a drag in this
      handle — `onDoubleClick` and pointer-drag are separate event streams; if a drag never
      produces a second same-target `click`, drop the travel guard and keep only the no-op-commit
      skip. Do not ship the guard unproven.)
- [ ] **AC-KBD (keyboard collapse parity, FR3-Literal only):** the collapse target exposes an
      Enter/Space key that fires collapse (W3C Window Splitter pattern). Double-click is
      pointer-only; without this, removing the button strands keyboard/AT users (FM-4).
      Verified by `fireEvent.keyDown` Enter. (FR3-Alternative keeps the labeled `<button>`, so
      keyboard parity is already satisfied — AC-KBD is N/A there.)
- [ ] **AC7 (resizer renders in all expanded drill states):** `RailResizeHandle` mounts when
      the rail is expanded in Dashboard root / Settings / Chat / KB (not KB-only), and does
      NOT mount when collapsed. Verify by the render-gate predicate in `layout.tsx` (no longer
      `kbExpanded`-only) + a vitest assertion on at least one non-KB expanded state.
- [ ] **AC8 (expand survives collapse):** the collapsed rail renders a visible, labeled
      expand affordance (chevron, `aria-label="Expand sidebar"`) that calls `toggleCollapsed`.
      Verify by a vitest case rendering the collapsed layout and asserting the control exists
      and fires expand on click.
- [ ] **AC9 (⌘B preserved):** the global ⌘B / Ctrl+B keydown handler (`layout.tsx:199`)
      still toggles collapse, unchanged. Verify the existing handler block is intact (grep).
- [ ] **AC10 (splitters: gold yes, double-click no):** `kb-desktop-layout.tsx` and
      `c4-workspace.tsx` Separators use gold active but have NO `onDoubleClick` collapse
      handler, and each carries a code comment stating double-click-collapse is intentionally
      out of scope (no collapsed-width semantics). Verify by grep for the comment marker +
      absence of `onDoubleClick` in those two files.
- [ ] **AC11 (contrast):** the active gold wash on the handle meets ≥ 3:1 non-text contrast
      against `--soleur-bg-surface-1`; if `#c9a962` at `/50` alpha fails, raise the alpha
      (document the chosen value in the component comment). ux-design-lead to confirm the
      value against the wireframe.
- [ ] **AC12 (typecheck):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] **AC13 (tests green):** `cd apps/web-platform && ./node_modules/.bin/vitest run test/rail-resize-handle.test.tsx` and any new/affected layout test pass. (New tests live under `apps/web-platform/test/**/*.test.tsx` to match the vitest jsdom include glob — NOT co-located.)
- [ ] **AC14 (no stray amber across resize/separator surfaces):** repo-wide,
      `grep -rn 'amber-500' apps/web-platform/components apps/web-platform/app --include='*.tsx' | grep -iE 'resize|separator|handle|drag'` returns no lines (the dashboard drag-over dropzone amber at `dashboard/page.tsx:480` is OUT of scope — it is a file-drop affordance, not a resize handle; confirm it is the only remaining match and leave it).

### Post-merge (operator / automatable)

- [ ] **AC15 (visual verify, Playwright):** drive the dashboard, drag the rail resizer →
      confirm gold (#c9a962) wash on active, grey on hover; double-click → collapse; collapsed
      chevron → expand. Automatable via Playwright MCP — fold into `/soleur:qa` or a
      `test-browser` run, not a manual checklist.

## Implementation Phases

> TDD order: write failing vitest cases first (RED), then implement (GREEN). Color/class
> swaps that no test asserts are verified by the AC greps + Playwright post-merge.

### Phase 1 — Gold active state on all three handles (lowest risk, ship-alone-able)

- `apps/web-platform/components/dashboard/rail-resize-handle.tsx:104` — replace
  `focus-visible:bg-amber-500/50` and `active:bg-amber-500/50` with the gold token form
  (`focus-visible:bg-soleur-accent-gold-fill/50 active:bg-soleur-accent-gold-fill/50`, or a
  higher alpha if AC11 contrast requires). Hover (`hover:bg-soleur-text-secondary/50`) unchanged.
- `apps/web-platform/components/kb/kb-desktop-layout.tsx:20` — replace
  `active:bg-amber-500/50 data-[resize-handle-active]:bg-amber-500/50` → gold token form.
- `apps/web-platform/components/kb/c4-workspace.tsx:25` — same swap.
- Add a one-line code comment on each Separator (kb-desktop-layout, c4-workspace) noting:
  double-click-to-collapse is intentionally NOT wired here — these are between-pane splitters
  with no collapsed-width state (AC10).

### Phase 2 — Double-click-to-collapse on the rail resizer (RED first)

- Extend `RailResizeHandleProps` with `onCollapse: () => void`.
- Add `onDoubleClick` to the handle `<div>` in `rail-resize-handle.tsx`. Guard: track total
  pointer travel during the gesture; only call `onCollapse()` when travel ≤ 4px (distinguish
  a genuine double-click from a drag-drag). Skip the no-op `onCommit` when
  `latest.current === startWidth.current` (avoid redundant localStorage writes — AC6).
- Tests (write first) in `apps/web-platform/test/rail-resize-handle.test.tsx`:
  double-click fires `onCollapse` once (AC5); drag-then-click does not collapse and does not
  persist a no-op width (AC6).

### Phase 3 — Remove the button; re-home collapse + expand in the layout

> **Contract-order note:** Phase 2 (handle exposes `onCollapse`) MUST precede this phase —
> the layout wires `onCollapse={toggleCollapsed}` and depends on the new prop existing.

- `apps/web-platform/app/(dashboard)/layout.tsx`:
  - Remove the floated `PanelToggleIcon` `<button>` (lines ~367–374) AND delete the now-unused
    `PanelToggleIcon` SVG component (lines ~709–726) (AC4).
  - **Widen the resizer render gate** from `kbExpanded` to "expanded in any drill state"
    (e.g., `const railExpanded = !collapsed;` gated to `md+` and the desktop rail). Pass
    `onCollapse={toggleCollapsed}` to `RailResizeHandle` (AC5, AC7). Note: outside KB the rail
    is fixed-width (`md:w-56`); the resizer there serves double-click-collapse, and width
    persistence stays KB-scoped (do NOT persist width for non-KB sections — keep the existing
    `kbExpanded` predicate for the `--kb-rail-w` style + `data-kb-rail-width` attribute; only
    the *mount* of the handle widens). This keeps Settings/Chat/Dashboard rail widths
    structurally untouched while still giving them a collapse gesture.
  - **Add a collapsed-rail expand chevron** (AC8): in the collapsed branch, render a visible,
    labeled control (`aria-label="Expand sidebar"`, `title="Expand sidebar (⌘B)"`) on the rail
    edge that calls `toggleCollapsed`. This replaces the floated button's expand role, which
    the resizer cannot serve when collapsed (the resizer is unmounted while collapsed). Reuse a
    chevron glyph; brand-gold outline per wireframe `04-collapsed-rail-expand-chevron.png`.
  - Tests: a non-KB expanded state mounts the resizer (AC7); collapsed state renders the expand
    chevron and click expands (AC8); ⌘B still toggles (AC9).

### Phase 4 — Verification sweep

- Run AC2 / AC14 greps; `tsc --noEmit`; vitest. Confirm no co-located test files (vitest jsdom
  glob is `test/**/*.test.tsx`).

## FR3 variants (operator choice) — DEFAULT CHANGED at deepen-plan

> **OPERATOR DECISION (2026-06-18): FR3-Alternative SELECTED.** The operator confirmed: keep the
> collapse/expand button everywhere, add double-click-to-collapse on the KB resizer as an
> accelerator, gold-on-active on all 3 handles. FR3-Literal is NOT in scope. Active ACs: AC1,
> AC2, AC3, AC5, AC6, AC9, AC10, AC11, AC12, AC13, AC14, AC15. Dropped: AC4, AC7, AC8.

> **Plan-of-record after deepen-plan: FR3-Alternative.** Five agents converged that the literal
> "remove the button" path (FR3-Literal) builds two compensating subsystems to fill the holes
> it creates, and yields an a11y-misnaming + persisted-collapse dead-end. FR3-Alternative
> delivers the identical user-visible value (gold-on-active everywhere + double-click-collapse
> on the KB rail) at ~half the surface. **Operator: the only real question is "must the visible
> button be gone?" If not load-bearing, ship FR3-Alternative.**

- **FR3-Alternative (plan-of-record — CPO/spec-flow/code-simplicity/architecture/user-impact
  recommended):** KEEP the floated `PanelToggleIcon` button as the universal collapse/expand
  affordance. Add guarded double-click-collapse to the **KB-only** resizer as a redundant
  accelerator (where it is coherent — the rail there genuinely resizes). Do NOT widen the
  render gate; do NOT add a separate expand chevron (the button already serves expand). Keeps
  the `kbExpanded` predicate single-meaning (ADR-047 singular-authority spirit). **Active ACs:
  AC1, AC2, AC3, AC5, AC6, AC9, AC10, AC11, AC12, AC13, AC14, AC15.** Drops AC4 (button kept),
  AC7 (no gate widening), AC8 (button expands). Lowest risk; no discoverability/a11y regression.

- **FR3-Literal (opt-in — honors "remove the button entirely"):** remove the floated button
  AND the `PanelToggleIcon` SVG. Because the resize handle and width-persistence are one
  KB-scoped subsystem, do NOT widen `RailResizeHandle`'s gate (that produces a resize handle
  with no resize semantics + `role=separator`/`aria-valuenow` misnaming in Settings/Chat —
  architecture-strategist HIGH). Instead **decompose**: keep `RailResizeHandle` strictly
  KB-scoped (add double-click there); introduce a **separate thin collapse-edge** component
  (`cursor-pointer`, NO `role=separator`, NO `aria-valuenow`, `aria-label="Collapse sidebar"`,
  double-click → `toggleCollapsed`) for non-KB expanded states; add the collapsed-rail expand
  chevron. **Adds ACs:** AC4 (button+SVG removed), AC7' (collapse-edge — NOT the resize
  separator — mounts non-KB; resize separator stays KB-only), AC8 (chevron expands), AC8b
  (cold-boot-collapsed: render with `localStorage["soleur:sidebar.main.collapsed"]="1"` →
  chevron present + fires `toggleCollapsed`; chevron is fetch-independent — FM-1/FM-2), AC-KBD
  (Enter/Space on the collapse target fires collapse — keyboard parity, FM-4). **Operator must
  also accept the discoverability regression for the Phase-4 non-technical ICP (CPO dissent).**

## Domain Review

**Domains relevant:** Product (Engineering is the implementer, not a review domain).

### Product/UX Gate

**Tier:** blocking
**Decision:** auto-accepted (pipeline) — wireframes ready for async review at
`knowledge-base/product/design/dashboard/screenshots/`
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead
**Skipped specialists:** copywriter (no persuasive/marketing copy in scope) — none required
**Pencil available:** yes (`@pencil.dev/cli` auto-installed; `.pen` committed)

#### Findings

- **ux-design-lead** produced `knowledge-base/product/design/dashboard/sidebar-resizer-gold-doubleclick.pen`
  (6 frames): three handle states (idle/hover grey, active gold #c9a962); expanded rail with
  the toggle button removed; "Double-click to collapse" hover tooltip; collapsed rail with a
  gold expand chevron; a generic splitter showing gold active. Referenced in FR/AC above.
- **spec-flow-analyzer** flagged BLOCKER gaps A (no pointer collapse outside KB-expanded) and
  C (no pointer expand once collapsed) if the button is removed naively, plus SHOULD-FIX gaps
  D (double-click/drag conflict + no-op commit), E (splitter asymmetry — confirmed
  intentional), F (a11y — button removal strands AT/touch users; focus-visible color). This
  plan resolves A/C by widening the resizer render gate (FR3) and adding the collapsed-rail
  chevron, and D by the movement guard + no-op-commit skip.
- **cpo** verdict: ship the gold color (clean on-brand win — amber is off-palette); add
  double-click as an accelerator; **dissents on removing the visible button** for the Phase-4
  non-technical ICP (discoverability regression; ⌘B is not an equivalent fallback). Recorded
  as a non-blocking dissent — threshold is `none`. Operator may switch to FR3-Alternative.

## Architecture Decision (ADR/C4)

None. This is an interaction/visual change on existing UI chrome — no data-model, tenancy,
substrate, resolver, or trust-boundary decision. No ADR or C4 view changes. (ADR-047 already
governs the unified nav rail; this plan does not amend it.)

## Observability

Skip — pure client-side UI/CSS change. No new server code, route, Inngest function, or infra
surface (Files-to-Edit are all `apps/web-platform/components/**` + `app/(dashboard)/layout.tsx`,
client components). No new error path, log, or failure mode reachable from Sentry/Better Stack.

## Open Code-Review Overlap

One same-file match, no real scope overlap: **#2193** (unify past_due/unpaid banners,
extract `useDismissiblePersistent`) names `(dashboard)/layout.tsx` — but at lines **23-80,
283-298** (the `PaymentWarningBanner` + inline `unpaid` banner region), a different region
than this plan's edits (floated collapse button ~367-374, resizer render gate ~506,
`PanelToggleIcon` SVG ~709-726). **Disposition: Acknowledge** — different concern (billing
banner extraction), no shared lines; the scope-out remains open. The three handle files have
zero open code-review references. (Verified against `gh issue list --label code-review
--state open`, 63 issues.)

## Files to Edit

- `apps/web-platform/components/dashboard/rail-resize-handle.tsx` — gold active+focus; add `onCollapse` prop + guarded `onDoubleClick` (Phase 1, 2)
- `apps/web-platform/components/kb/kb-desktop-layout.tsx` — gold active; out-of-scope comment (Phase 1)
- `apps/web-platform/components/kb/c4-workspace.tsx` — gold active; out-of-scope comment (Phase 1)
- `apps/web-platform/app/(dashboard)/layout.tsx` — remove floated button + `PanelToggleIcon` SVG; widen resizer render gate; add collapsed-rail expand chevron; wire `onCollapse` (Phase 3)
- `apps/web-platform/test/rail-resize-handle.test.tsx` — new cases (AC5, AC6) (Phase 2)
- `apps/web-platform/test/<dashboard-layout>.test.tsx` — new/extended cases for AC7/AC8/AC9 if a layout test surface exists; else add one under `test/` (Phase 3)

## Files to Create

- `knowledge-base/product/design/dashboard/sidebar-resizer-gold-doubleclick.pen` — DONE (wireframe, committed with plan)
- `knowledge-base/product/design/dashboard/screenshots/*.png` — DONE (6 frames)
- Possibly `apps/web-platform/test/dashboard-collapse-affordances.test.tsx` — if no existing layout test surface covers AC7/AC8/AC9.

## Test Scenarios

1. Double-click rail resizer → `onCollapse` fires once; sidebar collapses (AC5).
2. Drag > 4px then quick second click → no collapse, no no-op width persist (AC6).
3. Resizer mounts in Settings/Chat/Dashboard expanded; unmounts when collapsed (AC7).
4. Collapsed rail → expand chevron present + click expands (AC8).
5. ⌘B toggles collapse in both directions (AC9).
6. All three handles: active class is gold, hover class is grey, zero `amber-500` (AC1–3, AC10).

## Research Insights

**Double-click vs drag (best-practices-researcher):** `onDoubleClick` and pointer-drag are
separate event streams; a `dblclick` fires only on two `click`s at the same target with no
intervening drag. Canonical drag threshold = **5px** (`Math.hypot(dx,dy) > 5`). Verify
empirically whether a drag can even produce `onDoubleClick` before writing the guard.

**Accessibility (W3C Window Splitter pattern):** a collapse action on a `role="separator"`
MUST also be bound to **Enter** (the canonical keyboard collapse). Double-click is mouse-only.
FR3-Alternative satisfies this for free (the kept `<button>` is Tab+Enter/Space activatable);
FR3-Literal must add Enter/Space to the collapse target (AC-KBD).

**Non-text contrast (WCAG 1.4.11):** `#c9a962` on `#141414` (`bg-surface-1`, dark theme) =
**7.77:1** — far above the 3:1 minimum at full opacity. At `/50` alpha the blended value is
lower; either test the render or use `/70` to stay safely above 3:1 (AC11). The existing global
focus ring already uses `--soleur-accent-gold-fill` (globals.css:168), so the focus-visible
swap aligns with established precedent.

**Tailwind v4 token + opacity:** `bg-soleur-accent-gold-fill/50` is valid on CSS-var-backed
theme tokens in v4 (the `/opacity` shorthand works; the v3 `bg-[color:var(...)]/50` form is not
required). `soleur-accent-gold-fill` is a wired theme key already used across the app.

**Precedent diff (Phase 4.4):** the gold-active idiom has a direct in-repo precedent — PR #5477
established the grip-bar visual on this same `RailResizeHandle`; the global focus ring
(globals.css:168) already uses the gold token. The double-click-on-separator + collapse pattern
is NOVEL in this repo (no sibling precedent) — flagged for reviewer scrutiny. No SQL/atomic-write/
lock/RPC patterns in scope.

**frontend-anti-slop baseline:** scanner-neutral for the gold swap (verified). `amber-500`
trips nothing (no off-brand-color Tier-1 rule), `bg-soleur-accent-gold-fill` trips nothing.
Two pre-existing advisory `BRAND-NONZERO-CORNER` findings (rounded-* dots in kb-desktop-layout.tsx
+ c4-workspace.tsx) are unrelated and out of scope.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder, or omits
  the threshold will fail `deepen-plan` Phase 4.6. This section is filled (threshold `none`).
- **Both toggle states must be verified** (learning `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`):
  test/verify the rail in BOTH collapsed and expanded — the gold/active, the resizer mount, and
  the expand chevron each render different DOM per state.
- **Class-assertion sweep uses the bare token** (learning `2026-06-02-test-class-assertion-sweep-must-use-bare-token-not-bracketed.md`):
  when sweeping for `amber-500`/`gold` in tests, grep the bare substring, not the bracketed
  regex-literal form, and run the full affected suite green — not just the first grep match.
- **brand-hex-commit-gate does NOT catch `amber-500`** (it scans raw hex, not Tailwind builtins),
  which is exactly why the off-brand color shipped. Using the `soleur-accent-gold-fill` token
  utility is gate-compliant; never introduce the literal `#c9a962` in a component (the gate
  WILL block that — use the token).
- **react-resizable-panels numeric size = pixels** (learning `2026-04-16-react-resizable-panels-v4-numeric-size-is-pixels.md`):
  do not introduce numeric panel sizes; the repo uses string `"40%"` forms and this plan
  changes no sizes.
- **Floating-control clearance in both branches** (learning `2026-06-08-floating-absolute-control-needs-clearance-in-both-render-branches.md`):
  the new collapsed-rail expand chevron is an absolute control — reserve clearance in BOTH the
  collapsed and expanded branches and match its `aria-label` with a regex (`/^(Expand|Collapse) sidebar$/`) in any VRT locator since the label flips with state.
- **Double-click vs single-click-drag**: `onDoubleClick` and pointer drag are separate event
  streams, but the movement-threshold guard (≤4px) is load-bearing to avoid a drag-drag being
  read as a collapse.

## Resume prompt (copy-paste after /clear)

```text
/soleur:work knowledge-base/project/plans/2026-06-18-feat-sidebar-resizer-gold-active-doubleclick-collapse-plan.md. Branch: feat-one-shot-sidebar-resizer-gold-active-doubleclick-collapse. Worktree: .worktrees/feat-one-shot-sidebar-resizer-gold-active-doubleclick-collapse/. Plan + wireframes done (6 .pen frames committed). Decision pending: FR3 (remove button, this plan) vs FR3-Alternative (keep button, CPO-recommended) — pick before implementing.
```
