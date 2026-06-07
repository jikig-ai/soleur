---
title: "feat: Float the sidebar collapse toggle to reclaim top vertical space"
date: 2026-06-07
type: feat
branch: feat-one-shot-sidebar-top-space-float-toggle
status: planned
lane: single-domain
requires_cpo_signoff: false
brand_survival_threshold: none
---

# ✨ feat: Float the sidebar collapse toggle to reclaim top vertical space

## Enhancement Summary

**Deepened on:** 2026-06-07

### Key improvements from the deepen pass
1. **Precedent adopted (Phase 4.4 diff):** the floating-toggle classes were changed from the
   speculative `absolute top-3 right-2 z-40` to the repo's existing corner-control convention
   `absolute right-3 top-3 z-10` — verbatim from `components/ui/error-card.tsx:27`. Pattern is
   not novel; do not invent new offsets.
2. **z-index correction:** the original "toggle z-40 < dropdown z-50" framing was wrong — the
   two live in separate stacking contexts and the dropdown opens DOWNWARD (`top-full`) into a
   vertical band disjoint from the top-right toggle. `z-10` suffices; the VRT no-overlap
   assertion is the real guard.
3. **Wireframe produced:** Phase 4.9 (UI-Wireframe Halt) fired because `app/(dashboard)/layout.tsx`
   matches the UI-surface glob superset. A `.pen` wireframe was generated via Pencil CLI (auth
   from Doppler `soleur/dev` `PENCIL_CLI_KEY`) — see Domain Review.

### Verify-the-negative pass (Phase 4.45)
- "multi-workspace card has a chevron at the right edge" → confirmed `org-switcher.tsx:140` (`▾`).
- "`<aside>` is a positioned ancestor" → confirmed `layout.tsx:308` (`md:relative`).
- "mobile close button is `md:hidden` and unaffected" → confirmed `layout.tsx:331-337`.
- "dropdown opens below the card" → confirmed `org-switcher.tsx:146` (`top-full`).
- "vitest is the runner, not bun" → confirmed `package.json:15` (`"test": "vitest"`) +
  `bunfig.toml` `pathIgnorePatterns = ["**"]`.

## Overview

The web-platform desktop sidebar wastes ~45px of vertical space at its very top. A
dedicated "brand row" (`apps/web-platform/app/(dashboard)/layout.tsx:326`) once held the
"Soleur" wordmark, but that wordmark was removed in a prior PR (#4915 Phase 2). The row now
holds only two tiny controls — the mobile close button (`md:hidden`) and the desktop
collapse toggle (`hidden md:flex h-6 w-6`) — yet still occupies a full ~44px row on
desktop, stacked above ~28px of further padding before the workspace switcher card.

**Approach (chosen during investigation):** On desktop (md+), remove the dedicated toggle
row entirely so the workspace context band rises to the very top of the sidebar.
Absolutely-position the collapse toggle in the top-right corner of the sidebar so it costs
**zero vertical space**. Reclaims ~45px. The mobile close-button row is preserved unchanged.

This is a **CSS/layout-only** change. No data, no auth, no API, no schema. The only
non-CSS edits are the two test files that pin the current row geometry.

### Current geometry (verified against `origin`-state worktree, 2026-06-07)

| Element | File:line | Current classes | Notes |
|---|---|---|---|
| Brand/toggle row | `layout.tsx:326` | `flex items-center justify-between safe-top ${collapsed ? "px-2" : "px-3"} pt-3 pb-2` | Holds mobile close (`md:hidden`) + desktop toggle (`hidden md:flex`). `justify-between` pins toggle to the rail's right edge. |
| Mobile close button | `layout.tsx:331-337` | `... md:hidden`, `XIcon h-5 w-5` | **Must keep working on mobile.** |
| Desktop collapse toggle | `layout.tsx:344-351` | `hidden md:flex h-6 w-6 ... rounded`, `PanelToggleIcon h-4 w-4` | `onClick={toggleCollapsed}`, `aria-label` Expand/Collapse, `title` "...(⌘B)". |
| Workspace band wrapper | `layout.tsx:365` | `hidden md:block` (desktop), mobile band at `layout.tsx:268` (`variant="mobile"`, inside the `md:hidden` top bar) | Desktop band is the new top-most element after the row is removed. |
| Expanded band pill row | `workspace-context-band.tsx:151` | `flex items-center gap-2 px-3 pt-2` | mounts `OrgSwitcherContainer`. |
| Collapsed band column | `workspace-context-band.tsx:80-130` | `flex flex-col items-center gap-3 px-2 py-3` | icon-only; workspace tile is the **top** element. |
| OrgSwitcherContainer wrapper | `org-switcher-container.tsx:210` | `py-3` (no px — band supplies px-3) | |
| Workspace card (solo) | `org-switcher.tsx:84` | `... px-3 py-2.5`, no chevron | non-interactive identity chip. |
| Workspace card (multi) | `org-switcher.tsx:118` | `flex w-full ... px-3 py-2.5`, **chevron `▾` at right edge** (`org-switcher.tsx:140`, `ml-1 shrink-0`) | **Collision risk** for a top-right floating toggle. |

Dead space removed: the ~44px row + `pb-2`(8) + band `pt-2`(8) + `py-3`-top(12) ≈ 45px.

## Research Reconciliation — Spec vs. Codebase

| Investigation claim | Codebase reality | Plan response |
|---|---|---|
| Brand row at `layout.tsx:326` holds close + toggle, nearly empty on desktop | ✅ Confirmed verbatim (lines 326-352). | Restructure as designed. |
| Multi-workspace card has a chevron on the right edge | ✅ `▾` at `org-switcher.tsx:140` (`ml-1 shrink-0 text-soleur-text-muted`). The chevron is at the *expanded pill* far-right, vertically centered in the `py-2.5` card. | The floating toggle sits in the **header strip above** the card (band's `pt-2` zone). Verify no horizontal/vertical overlap with the chevron in VRT (Edge Case 3). |
| Band wrapper is `hidden md:block` | ✅ `layout.tsx:365`. Mobile uses a separate `variant="mobile"` band at `layout.tsx:268` inside the `md:hidden` top bar. | Desktop-only restructure; mobile path untouched. |
| `safe-top` is on the toggle row | ✅ `layout.tsx:326`; `.safe-top` = `padding-top: env(safe-area-inset-top, 0px)` (`globals.css:173`). The **mobile** top bar ALSO carries `safe-top` (`layout.tsx:256`). | When the desktop row is removed, the notch inset is a mobile concern only (desktop has no notch). The mobile row keeps `safe-top`. Confirm the desktop band's top element is not clipped (it has no `safe-top`, which is correct — desktop has no safe-area inset). See Sharp Edge "safe-top". |
| `<aside>` is a positioned ancestor for `absolute` | ✅ `layout.tsx:304-316`: `fixed inset-y-0 ... md:relative`. Both `fixed` and `relative` establish a containing block for `absolute` children. | Render the floating toggle as a direct `absolute` child of the `<aside>` (or a `relative` wrapper) so it anchors to the sidebar box, not the viewport. |
| Reclaims ~45px | Arithmetic confirmed above. | VRT asserts the band's top y-coordinate drops by ≥ ~40px vs the pre-change baseline (tolerance band, not exact 45). |

## User-Brand Impact

**If this lands broken, the user experiences:** a collapse toggle that overlaps the
workspace name / dropdown chevron (unclickable switcher), or — worst case — a *collapsed*
sidebar with no reachable expand control (the rail is stuck narrow with no way back to
full width except the ⌘B shortcut, which a non-technical Soleur user will not know).

**If this leaks, the user's data is exposed via:** N/A — this is a pure CSS/layout change.
No data, credentials, or workflow state are read, written, or transmitted.

**Brand-survival threshold:** none — UI polish. The change touches no regulated-data
surface; the only failure mode is cosmetic/interaction friction, recoverable by ⌘B and
caught by the pre-push VRT gate. (`threshold: none, reason: pure CSS/layout polish; no
sensitive path, no data/auth/API surface touched.`)

## Goals

1. Remove the dedicated desktop toggle row so the workspace band occupies the sidebar top.
2. Float the collapse toggle in the top-right corner with `position: absolute` (zero
   vertical cost), preserving its `onClick`, `aria-label`, `title`, and ⌘B shortcut.
3. Keep the mobile close-button row and the mobile band exactly as they are.
4. Guarantee the toggle is reachable and non-overlapping in **expanded** and **collapsed**
   desktop states, and does not collide with the multi-workspace dropdown chevron.
5. Reclaim ~45px, proven by the pre-push real-browser VRT gate.

## Non-Goals

- No change to mobile layout, the mobile close button, or the mobile band.
- No change to the toggle glyph (`PanelToggleIcon`), the ⌘B handler, or collapse
  persistence (`localStorage["soleur:sidebar.main.collapsed"]`).
- No change to `OrgSwitcher` / `OrgSwitcherContainer` internals (the chevron stays where it
  is; we position the toggle to avoid it, not move the chevron).
- No new dependencies, no new test framework (vitest is the runner — see Sharp Edges).

## Implementation Phases

> **NEVER assert jsdom layout values.** jsdom/happy-dom (vitest) renders no CSS — `absolute`,
> `hidden md:flex`, `md:w-14` are invisible. All pixel/overlap/position proof lives in the
> committed Playwright VRT spec (`apps/web-platform/e2e/nav-states-shell.e2e.ts`). jsdom tests
> may only assert DOM presence and className tokens. (`2026-06-02-ui-structural-diffs-need-prepush-browser-gate.md`)

### Phase 0 — Preconditions (verify, no code)

1. Confirm `<aside>` establishes a containing block: `layout.tsx:304-308` has
   `fixed ... md:relative` → ✅ (already verified). The floating toggle must be a descendant
   of this `<aside>`, NOT of the (`flex flex-col`) inner content, so it overlays rather than
   participating in the column flow.
2. Confirm the desktop collapse toggle is reachable in BOTH states today (Edge Case 2): in
   the collapsed rail (`md:w-14` = 56px) the toggle is currently the only expand affordance
   besides ⌘B. The floating toggle must remain inside the 56px rail when collapsed and must
   not overlap the collapsed band's workspace tile (top element of the `gap-3` column at
   `workspace-context-band.tsx:80-130`).
3. Re-read the e2e VRT spec's existing desktop tests (`nav-states-shell.e2e.ts:361-481`) and
   the vitest collapse test (`dashboard-sidebar-collapse.test.tsx:105-110`) — both pin the
   current row geometry and WILL break. Enumerate the exact assertions to rewrite (below).

### Phase 1 — Restructure the row (desktop) — `layout.tsx`

1. **Make the row mobile-only.** Change the row at `layout.tsx:326` from a shared
   close+toggle row to a `md:hidden` row that holds ONLY the mobile close button. The row's
   `safe-top` stays (mobile notch). Remove `justify-between` (only one child now) — keep the
   close button left-aligned as today. Suggested: `flex items-center safe-top px-2 pt-3 pb-2 md:hidden`.
   - The mobile close button keeps its existing `md:hidden` (now redundant inside a
     `md:hidden` row, but harmless and clarifies intent — keep it for safety).
2. **Float the desktop toggle.** Move the collapse `<button>` (currently `layout.tsx:344-351`)
   OUT of the row and render it as an absolutely-positioned element directly inside the
   `<aside>`, gated `hidden md:flex`. Proposed classes (adopt the repo's existing
   `absolute right-3 top-3` corner-control convention — see precedent below):
   `hidden md:flex absolute right-3 top-3 z-10 h-6 w-6 items-center justify-center rounded text-soleur-text-muted hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary`
   - **Precedent (Phase 4.4 diff):** `components/ui/error-card.tsx:27` floats a dismiss control
     with exactly `absolute right-3 top-3` — same shape, same corner. Adopt it verbatim rather
     than inventing `right-2`/`top-2`. The pattern is not novel.
   - `top-3` (12px) aligns vertically with the band's `pt-2`/`py-3` header zone.
   - `right-3` (12px): the 24px button's box spans 12→36px from the right edge. In the 56px
     collapsed rail that is the right HALF of the rail; the band's monogram tile is centered
     in the `px-2` column (~12→44px) — verify in VRT they don't overlap (the tile is `size="sm"`
     ~28px, centered; the toggle is top-right). In the 224px expanded rail there is ample room.
   - **z-index / dropdown overlap correction:** the multi-workspace dropdown (`org-switcher.tsx:146`)
     opens `top-full` — i.e. it expands DOWNWARD, *below* the card, while the floating toggle
     sits in the header strip ABOVE the card. They occupy disjoint vertical bands, so they
     cannot overlap regardless of z-index (and they live in separate stacking contexts: the
     dropdown's `z-50` is scoped to its own `relative` wrapper at `org-switcher.tsx:111`, not
     comparable to the toggle's `z-10` on the `<aside>`). `z-10` is sufficient to lift the
     toggle above the band's static content; do NOT chase a cross-context `z-40 vs z-50` race.
     VRT Test Scenario 2 still asserts no rect intersection as a regression guard.
   - **Preserve verbatim:** `onClick={toggleCollapsed}`, `aria-label={collapsed ? "Expand
     sidebar" : "Collapse sidebar"}`, `title={collapsed ? "Expand sidebar (⌘B)" : "Collapse
     sidebar (⌘B)"}`, and the `PanelToggleIcon h-4 w-4` child. (Edge Case 4)
3. **Reclaim the band top room.** With the row gone on desktop, the band's `pt-2`
   (`workspace-context-band.tsx:151`) and the collapsed column's `py-3`
   (`workspace-context-band.tsx:86`) now sit at the sidebar top. Verify in VRT that the
   workspace card's top edge is NOT clipped by the floating toggle and that the toggle does
   not overlap the card content. If `top-3 right-2` proves to overlap the card text at narrow
   widths, the fallback is to add a small `md:pr-8` to the band's pill row so text wraps
   clear of the toggle — decide from the VRT screenshots, not speculatively.

> **Phase order note:** Phase 1 is the entire production change. There is no contract change
> and no consumer/producer split — the two test phases (2, 3) are derivative and may land in
> the same commit, but author Phase 1 first so the tests are written against the final markup.

### Phase 2 — Update the vitest DOM/token test — `dashboard-sidebar-collapse.test.tsx`

The test at lines 105-110 asserts `getByLabelText("Collapse sidebar").closest("div")` has
`pb-2` and not `py-5`. After the restructure the toggle's parent is the `<aside>` (or a
floating wrapper), not the old row — this assertion is now meaningless and will break.

1. Rewrite the "Issue 1" test (lines 105-110) to assert the NEW invariant: the collapse
   toggle is **absolutely positioned and not in the document flow** at the token level — e.g.
   `getByLabelText("Collapse sidebar").className` contains `absolute` and `md:flex`. (jsdom
   can read className tokens; it cannot render the position — pixel proof is VRT.)
2. **Keep unchanged** every other test in this file (lines 95-98 toggle present; 112-117
   aria-label toggles; 119-126 collapsed titles; 133-138 localStorage persist; 140-201 ⌘B /
   Ctrl+B + input/textarea guards). These exercise behavior, not the row geometry, and the
   floating toggle must keep them all green (Edge Case 4 regression guard). If any break, the
   restructure has broken behavior — fix the markup, not the test.
3. The file already lives at `apps/web-platform/test/dashboard-sidebar-collapse.test.tsx`,
   matching the vitest jsdom glob `test/**/*.test.tsx` — no path move needed.

### Phase 3 — Update the Playwright VRT gate (the load-bearing proof) — `nav-states-shell.e2e.ts`

This is the gate that catches what jsdom cannot. It already covers desktop expanded/drilled/
collapsed + mobile (`nav-states-shell.e2e.ts:361-481` desktop block; mobile block follows).

1. **Rewrite the Bug-2 alignment assertion (lines 419-440).** It currently asserts the back
   affordance glyph and the collapse-toggle glyph share the rail's px-3 gutter (`Math.abs(
   backGlyph.x - collapseGlyph.x) <= 6`). After the float, the toggle no longer aligns to the
   gutter — it sits in the top-RIGHT corner. Replace with the NEW invariants:
   - **Reclaimed space:** the workspace band's top y-coordinate is at/near the sidebar top
     (assert `railBand.boundingBox().y` is within a few px of the `<aside>` top, i.e. the
     ~45px gap is gone). Use a tolerance band (≤ ~12px from the aside top), not an exact value.
   - **No overlap (expanded, multi-workspace):** the floating toggle's bounding box does NOT
     intersect the workspace card's bounding box NOR the dropdown chevron `▾`
     (`org-switcher.tsx:140`). Compute rect intersection = 0. (Edge Case 3 — requires the
     multi-workspace fixture; confirm `setupNavMocks` seeds ≥2 memberships, else extend it.)
   - **Toggle reachable + correct semantics:** `getByRole("button", { name: "Collapse
     sidebar" })` is visible and within the `<aside>` box.
2. **Add a collapsed-state assertion (extend the test at lines 443-481).** In the collapsed
   rail (`md:w-14` = 56px), assert: the floating toggle is still visible, its bounding box is
   fully INSIDE the 56px rail (`toggleBox.x + toggleBox.width <= asideBox.x + asideBox.width`),
   and it does NOT overlap the collapsed band's workspace tile
   (`getByTestId("workspace-identity-icon")` bounding box). (Edge Case 2.)
3. **Mobile unchanged but guarded.** Confirm the existing mobile block still passes: the
   mobile close button + mobile band must render in the `md:hidden` top bar exactly as before.
   If the mobile block does not already assert the close button presence, add a one-line
   `getByLabelText("Close navigation")` visibility check at the mobile viewport (Edge Case 1).
4. **Prove the gate RED-then-GREEN.** Per `2026-06-02-ui-structural-diffs-need-prepush-
   browser-gate.md`: run the rewritten VRT spec against the OLD markup first (it should fail
   the new reclaimed-space assertion), then against the new markup (green). A green-from-birth
   gate is unvalidated. Document the RED output in the PR body.

## Files to Edit

- `apps/web-platform/app/(dashboard)/layout.tsx` — split the brand row into a mobile-only
  close row + an absolutely-positioned desktop toggle (Phase 1). The sole production change.
- `apps/web-platform/test/dashboard-sidebar-collapse.test.tsx` — rewrite the row-geometry
  token test; keep all behavior tests (Phase 2).
- `apps/web-platform/e2e/nav-states-shell.e2e.ts` — rewrite the Bug-2 alignment assertion,
  add collapsed-state non-overlap + reclaimed-space assertions, guard mobile (Phase 3).

## Files to Create

None.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — Desktop (md+): the dedicated toggle row is gone; the workspace context band is
      the top-most element of the sidebar. VRT: `railBand.boundingBox().y` is within ≤12px of
      the `<aside>` top (was ~45px+ before). RED-then-GREEN proof in PR body.
- [ ] AC2 — The collapse toggle is `position: absolute` (token `absolute` present on the
      button's className; VRT confirms it is out of flow and overlays the top-right corner).
- [ ] AC3 — Expanded multi-workspace: the floating toggle's bounding box does NOT intersect
      the workspace card box OR the dropdown chevron `▾`. VRT rect-intersection = 0.
- [ ] AC4 — Collapsed rail (`md:w-14` = 56px): the toggle is visible, fully inside the 56px
      rail, and does not overlap the collapsed workspace identity tile. VRT.
- [ ] AC5 — Toggle semantics preserved: `aria-label` toggles Expand/Collapse on click;
      `title` carries "(⌘B)"; ⌘B / Ctrl+B still toggle and respect input/textarea focus
      guards. All existing vitest behavior tests in `dashboard-sidebar-collapse.test.tsx`
      (lines 112-201) remain green unmodified.
- [ ] AC6 — Mobile (`md:hidden` top bar): the close button (`Close navigation`) and the
      mobile band render unchanged; the mobile close button still dismisses the drawer. VRT at
      the 390px viewport.
- [ ] AC7 — `tsc --noEmit` clean; full vitest suite green via `vitest` (the package runner —
      NOT `bun test`, which is blocked by `bunfig.toml pathIgnorePatterns`).
- [ ] AC8 — The Playwright VRT spec passes headless against the `authenticated` project
      (offline mock-Supabase storageState, zero credentials).

### Post-merge (operator)

None. No migration, no infra, no external-service state. The `web-platform-release.yml`
pipeline restarts the container on merge to `apps/web-platform/**`; no operator step.

## Domain Review

**Domains relevant:** Product (UI surface)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** ux-design-lead (wireframe producer, via Pencil CLI)
**Skipped specialists:** none
**Pencil available:** yes
**Wireframe artifact:** `knowledge-base/product/design/dashboard-nav/sidebar-float-collapse-toggle.pen`
(committed). Generated via Pencil CLI (auth: Doppler `soleur/dev` `PENCIL_CLI_KEY`; Node
22.22.1 ≥ 22.9.0). Shows the sidebar header BEFORE (wasted ~44px toggle row), AFTER expanded
(band at top + floating top-right toggle, ~45px reclaimed, no chevron collision), and AFTER
collapsed (toggle inside the 56px rail, no monogram-tile overlap).

> **Why a `.pen` despite "advisory":** deepen-plan Phase 4.9 (UI-Wireframe Artifact Halt)
> fires mechanically because `app/(dashboard)/layout.tsx` matches the UI-surface glob superset
> AND this is a structural/layout change (not a pure-copy/style tweak, which IS the only
> exclusion). On the one-shot path plan Phase 2.5 is the SOLE wireframe producer, so the `.pen`
> was generated here (the earlier "N/A, repositioning an existing control" reasoning was
> superseded by the mechanical override per `wg-ui-feature-requires-pen-wireframe`).

#### Findings

The only product-facing risk is interaction friction (toggle reachability / overlap), fully
covered by AC2–AC6, the wireframe, and the pre-push VRT gate. No copy, no flow, no
brand-survival surface.

## Observability

Skipped — pure CSS/layout change. No new code-class logic under `apps/*/server/` or
`apps/*/src/` beyond presentational markup, no new infrastructure surface, no new failure
mode that emits telemetry. The only runtime behavior (collapse toggle, ⌘B) is unchanged and
already covered by existing vitest behavior tests. (Per Phase 2.9 skip condition: no new
code/infra logic surface.)

## Test Scenarios

1. Desktop expanded, solo workspace: band at top, toggle floats top-right, no overlap.
2. Desktop expanded, multi-workspace: toggle does not collide with the `▾` chevron; the
   switcher dropdown opens downward (`top-full`), in a disjoint vertical band from the
   top-right toggle — no overlap (assert rect intersection = 0 in VRT).
3. Desktop collapsed (56px rail): toggle visible, inside rail, no overlap with tile; click
   expands; ⌘B expands.
4. Mobile (390px): close-button row present, mobile band present, drawer dismiss works.
5. ⌘B / Ctrl+B toggle on /dashboard, /kb, /settings, /chat; ignored in input/textarea.

## Risks & Mitigations

- **Risk:** the floating toggle overlaps the workspace card text at narrow expanded width.
  **Mitigation:** AC3 VRT rect-intersection gate; fallback `md:pr-8` on the band pill row,
  decided from screenshots not speculation.
- **Risk:** the collapsed-rail toggle drifts outside the 56px rail.
  **Mitigation:** `right-2` math (8 + 24 = 32 < 56) + AC4 VRT inside-rail assertion.
- **Risk:** `z-index` war — an open switcher dropdown sits under the toggle.
  **Mitigation:** non-issue — the dropdown opens `top-full` (downward, below the card) while
  the toggle sits above the card; disjoint vertical bands, separate stacking contexts. `z-10`
  on the toggle suffices. VRT Test Scenario 2 asserts no rect intersection as a guard.
- **Risk:** removing the row drops the desktop `safe-top` (notch padding).
  **Mitigation:** desktop has no safe-area inset; the mobile row (the only notch surface)
  keeps `safe-top`. See Sharp Edges.
- **Risk:** existing VRT/vitest tests pin the old geometry and silently pass on a broken
  layout or block the change.
  **Mitigation:** Phases 2–3 rewrite exactly the geometry-pinning assertions; RED-then-GREEN
  proof for the VRT gate.

## Sharp Edges

- **Verify both toggle states.** `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`:
  the collapsed and expanded rails render different DOM subtrees (the collapsed band is a
  separate icon-only return at `workspace-context-band.tsx:80-130`). A toggle position that
  works expanded can clip in collapsed. AC3 (expanded) AND AC4 (collapsed) are both required;
  fold both into the same PR.
- **jsdom renders no CSS.** Do not assert `absolute`/`md:w-14`/position values in vitest —
  only className tokens and DOM presence. All pixel/overlap proof is the committed Playwright
  VRT spec. (`2026-06-02-ui-structural-diffs-need-prepush-browser-gate.md`)
- **Test runner is vitest, not bun.** `apps/web-platform/bunfig.toml` sets
  `[test] pathIgnorePatterns = ["**"]` — `bun test <file>` reports "filter did not match"
  even when the file exists. Use `./node_modules/.bin/vitest run <path>` (jsdom specs match
  `test/**/*.test.tsx`).
- **`safe-top` is mobile-only after this change.** `.safe-top` = `env(safe-area-inset-top)`
  (`globals.css:173`). Removing it from the *desktop* path is correct (desktop has no notch);
  the mobile top bar (`layout.tsx:256`) and mobile close row keep it. Do not strip it from the
  mobile row.
- **Preserve the toggle's accessibility contract.** The `aria-label`/`title`/⌘B semantics are
  load-bearing — the collapsed rail's only non-keyboard expand affordance IS this toggle. A
  regression here is the worst-case "stuck collapsed" failure named in User-Brand Impact.
- **This plan's `## User-Brand Impact` section is filled (threshold: none).** An empty/TBD
  section fails `deepen-plan` Phase 4.6 — it is complete here.

## Open Code-Review Overlap

None. `gh issue list --label code-review` cross-referenced against all five touched/named
files returned only #2193 (billing banner unification) — unrelated to the sidebar surface.
