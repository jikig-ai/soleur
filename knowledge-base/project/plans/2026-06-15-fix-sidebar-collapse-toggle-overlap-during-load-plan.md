---
title: "fix(dashboard): sidebar collapse toggle overlaps nav during not-yet-loaded/transition state"
date: 2026-06-15
type: fix
branch: feat-one-shot-sidebar-collapse-button-overlap
lane: single-domain
status: draft
brand_survival_threshold: none
---

# 🐛 fix(dashboard): sidebar collapse toggle overlaps nav during not-yet-loaded state

## Enhancement Summary

**Deepened on:** 2026-06-15
**Sections enhanced:** Overview (fix approach), Implementation Phases, Files to Edit, Test Scenarios
**Research agents used:** verify-the-negative grep pass (sonnet), Tailwind min-height geometry research (sonnet)

### Key Improvements
1. **Exact fix pinned down (approach A).** The fix is a single conditional Tailwind token —
   add `md:min-h-[64px]` to the pill-container `<div>` at `workspace-context-band.tsx:153`,
   gated on `drill === null`. The 64px is derived from the toggle bottom edge
   (`top-10` 40px + `h-6` 24px = 64px from aside top); reserving it stops the band from
   collapsing below the toggle while the membership fetch is in flight.
2. **All six negative/causal claims independently CONFIRMED by grep** (z-10 vs md:z-30 not a
   z-index bug; `OrgSwitcherContainer` returns null at :214; band has no `min-h-` today; toggle
   tokens; nav `pt-3`; the three rail widths). No premise drift.
3. **Scope-containment proven safe.** The `md:` prefix excludes the mobile `variant="mobile"`
   path; the `drill === null` guard excludes drilled (Settings/KB/Chat) bands (already tall via
   back-link + section title); the collapsed icon-only form returns early at :83 and never
   reaches :153. So collapsed (`md:w-14`), Settings/Chat (`md:w-56`), and mobile (`w-64`) are
   structurally untouched.
4. **Repo precedent found.** `components/shared/cta-banner.tsx` uses `min-h-[1rem]` for the same
   idiom (reserve space for conditionally-rendered content to prevent async layout shift). The fix
   is convention-aligned, not novel.

### New Considerations Discovered
- The loaded band height at `drill === null` is ~96px (pill `pt-2` 8 + `OrgSwitcherContainer`
  `py-3` 12+12 + pill `py-2.5` 10+10 + lg tile `h-11` 44). The 64px reserve is the *minimum* that
  clears the toggle, not the full loaded height — so the fix removes the overlap without forcing a
  visible "tall empty band" (the band still grows to ~96px once loaded, but never shrinks below the
  toggle's footprint mid-load). This also damps the "pop-in" layout shift the operator sees.
- No `globals.css` interaction: the `aside[data-kb-rail-width]` rule sets `width` only, never height.

## Overview

When the dashboard page is not yet fully loaded and the user collapses then re-expands the
sidebar, the **floated collapse/toggle button** (top of the sidebar header) visually overlaps
the nav items — specifically it sits on top of the "Dashboard" nav item area.

### Root cause (confirmed by code read — NOT a z-index problem)

The floated collapse toggle in `apps/web-platform/app/(dashboard)/layout.tsx:366-373` is
`absolute`-positioned against the `<aside>`. Its **expanded** position is `right-3 top-10`
(`top-10` = 40px). That `top-10` offset is calibrated — per the long comment at layout.tsx:335-365
— to **vertically center the h-6 (24px) toggle on the workspace pill**, whose center is asserted to
sit ~52px below the aside top *when the band is fully rendered*.

The workspace pill content is **async-fetched**. The pill is rendered by `OrgSwitcherContainer`
(`components/dashboard/org-switcher-container.tsx:214`), which returns `null` until
`/api/workspace/list-memberships` resolves:

```tsx
// org-switcher-container.tsx:214
if (memberships === null) return null;   // No flash before the membership fetch resolves.
```

The band itself (`components/dashboard/workspace-context-band.tsx:128-200`) is
`className="flex flex-col"` with **no reserved min-height**. On the top-level `/dashboard` route
(`drill === null`), the band's only content is the pill — there is no "Back to menu" link and no
section title. So while the fetch is in flight the **entire expanded band collapses to ~0px tall**.

Result: the floated toggle, pinned at `top-10` (40px) against the `<aside>`, floats DOWN into the
visual region where the nav starts. The nav's first item ("Dashboard") begins at `pt-3` (12px)
below the band (layout.tsx:403) — and with an empty band that region is exactly where the toggle
lands. The toggle (`z-10`) paints over the "Dashboard" `Link`. Collapse→re-expand surfaces it
because the user is interacting before the async band height settles; once `list-memberships`
resolves and the pill (~64px) renders, the band grows and the `top-10` toggle lands back on the
pill center — so the overlap is transient and load-timing-dependent (which is exactly the reported
"page isn't fully loaded" condition).

The width transition (`md:transition-[width] md:duration-200`, layout.tsx:309) is a secondary
contributor: during collapse→expand the aside animates width over 200ms, but the toggle's `top`
offset does not animate — the dominant cause is the **height-collapse of the not-yet-loaded band**,
not the width animation.

### Fix approach (to be finalized in implementation)

Make the floated toggle's expanded vertical position **independent of the async band height** so it
never overlaps the nav, in BOTH the not-yet-loaded and loaded states, AND in both toggle states
(collapsed + expanded). Two candidate mechanisms, to be chosen at /work Phase 0 after a real-CSS VRT
repro:

- **(A) Reserve a stable min-height on the band's expanded form** so the band occupies its
  fully-loaded height (~64px) even while `OrgSwitcherContainer` returns `null` — keeping the
  `top-10` toggle centered on a stable anchor and the nav pushed below it at all load stages. This
  is the smallest, most convention-aligned change (no toggle re-calibration) and also removes the
  transient layout shift the operator sees as the band "pops in".
- **(B)** Pin the expanded toggle to a band-independent anchor (e.g. a fixed `top-3` corner like the
  collapsed state, decoupling it from the pill center). Rejected-leaning: it regresses the deliberate
  pill-centering from PR #4997/#5015 and re-introduces the off-axis "corner" look #5015 fixed.

The plan recommends **(A)** as primary (preserves the #5015 centering invariant; fixes the actual
height-collapse cause), with (B) documented as the fallback if VRT shows a residual ≤2px misalignment.

This is a single-file React/Tailwind change with a real-CSS e2e VRT addition. No data, no schema, no
infra.

## Research Reconciliation — Spec vs. Codebase

No spec exists for this branch (direct one-shot → plan path). The feature description's premise was
validated against `origin/main` and held:

| Description claim | Codebase reality | Plan response |
| --- | --- | --- |
| "collapse button in top-right of sidebar header" | Confirmed: `absolute right-3 top-10` floated toggle, layout.tsx:366-373 | Target this element |
| "overlaps the Dashboard nav item" | Confirmed: nav at layout.tsx:400-439; first item "Dashboard" at `/dashboard`, `pt-3` below the band | Fix overlap geometry |
| "likely z-index/positioning issue during transition" | **Refined:** it is a POSITIONING issue (async-band height-collapse), NOT z-index (`z-10` < aside `z-30` is correct) | Fix `top` offset stability, not z-index |
| "during page-not-loaded/transition state" | Confirmed: `OrgSwitcherContainer` returns `null` until `/api/workspace/list-memberships` resolves (org-switcher-container.tsx:214); band has no reserved height | Reserve band min-height / decouple toggle |

## Premise Validation

No GitHub issue is cited by the feature description (one-shot direct invocation). The cited
*artifacts* all exist on `origin/main`: the floated toggle (layout.tsx, added PR #4997, re-tuned
#5015/#5029), the async band (#4915, ADR-047), and the e2e VRT gate `e2e/nav-states-shell.e2e.ts`
(ADR-049). The reported behavior is a real *transient* overlap, not a never-built feature — a
behavioral fix is correct, not a build. No external premises beyond these repo artifacts.

## User-Brand Impact

**If this lands broken, the user experiences:** the collapse toggle continues to paint over the
"Dashboard" nav link during page load, making the nav item look broken / partially obscured and
(worst case) intercepting the click meant for "Dashboard" while the toggle sits on top of it.

**If this leaks, the user's data is exposed via:** N/A — this is a presentational CSS/layout change
with no data path, no auth surface, no persistence.

**Brand-survival threshold:** none — cosmetic/interaction polish on an already-shipped surface; no
single-user data-loss or money/exposure vector. (No sensitive path touched: only
`app/(dashboard)/layout.tsx` + an e2e spec.)

## Implementation Phases

### Phase 0 — Repro + mechanism confirmation (real CSS)
1. Reproduce headlessly: extend the `authenticated` Playwright project setup used by
   `e2e/nav-states-shell.e2e.ts` to **delay** the `/api/workspace/list-memberships` mock (e.g.
   resolve after a short timer / leave pending) so the band renders its `null` (height-collapsed)
   state, on the top-level `/dashboard` route, expanded. Screenshot and confirm the toggle rect
   overlaps the "Dashboard" nav link rect.
2. Confirm both toggle states: capture the **collapsed** state under the same delayed mock — verify
   the `left-1/2 top-3` collapsed toggle does NOT overlap (collapsed nav uses an icon column; expected
   clear). Document the result either way (both-toggle-states rule, learning
   `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`).

### Phase 1 — Write the failing VRT assertion (RED)
3. Add a spec/assertion to `e2e/nav-states-shell.e2e.ts` (or a sibling spec) that, under the
   in-flight (delayed) `list-memberships` mock on `/dashboard` expanded, asserts the toggle's
   bounding rect does **not** intersect the "Dashboard" nav link's bounding rect (rect-intersection
   check, the same geometry style the existing AC1/AC3/AC4 blocks use). It must FAIL against current
   `main`.

### Phase 2 — Fix (GREEN)
4. Apply approach (A) — the deepen-pass pinned the exact change. In
   `apps/web-platform/components/dashboard/workspace-context-band.tsx`, change the pill-container
   `<div>` at **line 153** from:

   ```tsx
   <div className="flex items-center gap-2 px-3 pt-2 md:pr-10">
   ```
   to:
   ```tsx
   <div className={`flex items-center gap-2 px-3 pt-2 md:pr-10${drill === null ? " md:min-h-[64px]" : ""}`}>
   ```

   - **64px** = toggle bottom edge from aside top (`top-10` 40px + `h-6` 24px). Reserving this on the
     band means the nav below it can never rise into the toggle's footprint while
     `OrgSwitcherContainer` is returning `null` (the in-flight membership fetch, org-switcher-container.tsx:214).
   - **`md:`** prefix scopes it to the desktop rail only — the mobile `variant="mobile"` band (a
     separate DOM element in the mobile top bar) is below the md breakpoint and unaffected, matching
     the `md:pr-10` already on this same div.
   - **`drill === null`** guard scopes it to the top-level route only — drilled (Settings/KB/Chat)
     bands already exceed 64px via the back-link (`pt-2`) + section-title (`pt-3 pb-3`) rows, so the
     reserve is unnecessary there and the guard avoids inflating them.
   - Collapsed is unaffected: the icon-only form returns early at workspace-context-band.tsx:83 and
     never reaches line 153.
   - Convention precedent: `components/shared/cta-banner.tsx` `min-h-[1rem]` (reserve-for-conditional-content idiom).
5. If VRT (Phase 1) shows a residual ≤2px misalignment with (A) alone — e.g. the 64px floor proves
   slightly under the toggle's true footprint at some zoom/DPI — bump the reserve (e.g. `md:min-h-[68px]`)
   rather than switching to approach (B). Approach (B) (re-anchoring the toggle off the pill center,
   e.g. a fixed `top-3`) is the LAST resort: it regresses the deliberate pill-centering from PR #5015
   and requires updating the calibrated comment at layout.tsx:335-365 — document the trade-off if taken.

### Research Insights (Phase 2)

**Geometry (verified by deepen-pass grep):**
- Toggle center anchor = `top-10` (40px) + `h-6`/2 (12px) = 52px from aside top; toggle bottom edge = 64px.
- Loaded band height at `drill === null` ≈ 96px; in-flight (OrgSwitcherContainer null) ≈ 8px (pill `pt-2` only) → the toggle floats over the nav. The 64px reserve closes exactly this gap.
- `z-10` (toggle) < `md:z-30` (aside) confirmed at layout.tsx:370 / :308 — z-index is correct; do NOT touch it.

**Edge cases:**
- Single-workspace (solo) user: `OrgSwitcher` renders a non-interactive identity chip with the same `px-3 py-2.5` — same loaded height, same fix applies. (VRT AC2 covers the solo state per the existing `nav-states-shell.e2e.ts` single-workspace block.)
- Zero-membership user: `OrgSwitcher` renders nothing even when loaded — the `md:min-h-[64px]` reserve still holds the band open so the toggle never overlaps the nav (a strictly-better state than today).

### Phase 3 — Lock the contract (both states + both load stages)
6. Keep/extend the jsdom className tripwires in `test/dashboard-sidebar-collapse.test.tsx`
   (expanded `right-3 top-10`; collapsed `left-1/2 -translate-x-1/2 top-3`) — these guard token drift
   only (jsdom has no layout engine).
7. The **load-timing overlap proof lives in the e2e VRT** (ADR-049 / learning
   `2026-06-02-ui-structural-diffs-need-prepush-browser-gate.md`): the new rect-non-intersection
   assertion (Phase 1) is the binding gate.

## Files to Edit

- `apps/web-platform/components/dashboard/workspace-context-band.tsx` — **primary edit (approach A)**:
  add `md:min-h-[64px]` (gated on `drill === null`) to the pill-container `<div>` at line 153, so the
  not-yet-loaded band cannot collapse below the toggle's 64px footprint. See Phase 2 step 4 for the
  exact before/after.
- `apps/web-platform/app/(dashboard)/layout.tsx` — only IF approach (B) fallback is taken (toggle
  anchor re-calibration + comment update at :335-365). Under approach (A) this file is **untouched**.
- `apps/web-platform/e2e/nav-states-shell.e2e.ts` — add the in-flight-`list-memberships` repro mock +
  toggle-vs-Dashboard rect-non-intersection assertion (expanded; and a collapsed-state companion).
- `apps/web-platform/test/dashboard-sidebar-collapse.test.tsx` — confirm/extend className tripwires for
  both toggle states (only if approach (B) shifts a token).

## Files to Create

- None. (The VRT assertion folds into the existing `nav-states-shell.e2e.ts` spec; no new file.)

## Acceptance Criteria

### Pre-merge (PR)
- [x] **AC1 (RED→GREEN):** a Playwright assertion in `e2e/nav-states-shell.e2e.ts` renders the
  `/dashboard` route, expanded, with `/api/workspace/list-memberships` mock **in-flight/delayed**, and
  asserts the collapse toggle's bounding rect does NOT intersect the "Dashboard" nav link's bounding
  rect. It fails on `main` (HEAD before fix) and passes after the fix.
- [x] **AC2 (loaded state still correct):** under the normal (immediately-resolved) mock, the existing
  expanded centering assertion (toggle vertically centered on the identity chip, AC1/AC3 in the spec)
  still passes — the fix does not regress the #5015 pill-centering.
- [x] **AC3 (both toggle states):** a collapsed-state companion assertion confirms the collapsed
  toggle (`left-1/2 top-3`) does not overlap the collapsed icon nav, under both in-flight and loaded
  mocks. (Enforces `2026-04-17-alignment-fixes-must-verify-both-toggle-states`.)
- [x] **AC4 (scope containment):** collapsed (`md:w-14`), Settings/Chat (`md:w-56`), and mobile
  (`w-64`) rail widths are unchanged — verified by the existing width/drill specs staying green.
- [x] **AC5 (jsdom tripwires green):** `test/dashboard-sidebar-collapse.test.tsx` passes; if a Tailwind
  token changed, the tripwire assertions are updated to match in the same commit.
- [x] **AC6 (typecheck):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean.
- [x] **AC7 (unit suite):** the affected vitest files pass via the package's configured runner
  (`apps/web-platform` uses vitest; run `cd apps/web-platform && ./node_modules/.bin/vitest run test/dashboard-sidebar-collapse.test.tsx test/workspace-context-band.test.tsx`).

### Post-merge (operator)
- [x] None. The e2e VRT gate runs in CI (ADR-049); no manual/operator step. (`web-platform-release.yml`
  restarts the container on merge — no operator deploy action.)

## Domain Review

**Domains relevant:** Product (UI surface — mechanical UI-surface override fires: `app/(dashboard)/layout.tsx` + `components/dashboard/*` are UI-surface paths).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** ux-design-lead (N/A — this MODIFIES an existing control's positioning; it
creates NO new page, flow, component file, or interactive surface. Per the plan skill ADVISORY rule
and the NONE-vs-BLOCKING definition, a bug-fix that re-positions an existing element without adding a
user-facing surface is ADVISORY, not BLOCKING — no `.pen` wireframe is required for a pixel-alignment
regression fix.)
**Pencil available:** N/A (no new UI surface)

#### Findings

Pure positional/layout bug fix on an already-shipped, already-wireframed control (D4 rail, PR
#4948/#4997/#5015/#5029). No new surface, copy, or flow. The visual contract is enforced by the e2e
VRT gate (ADR-049), which is the appropriate review surface for a CSS-geometry fix. No brand/voice or
flow-completeness implications.

## Open Code-Review Overlap

One open code-review issue references `app/(dashboard)/layout.tsx`:

- #2193 (`refactor(billing): unify past_due and unpaid banners into shared component`) — **Acknowledge.**
  Different concern: it targets the `PaymentWarningBanner`/`unpaid` banner blocks (layout.tsx:36-93,
  522-538), not the floated sidebar toggle or the workspace band. This fix does not touch those banner
  blocks. The scope-out remains open and is not folded in (banner unification is its own cycle).

## Observability

Not applicable — pure client-side presentational CSS/layout change. No new code under
`apps/*/server/`, `apps/*/infra/`, or `plugins/*/scripts/`; no new error path, log site, infra surface,
or failure mode. (Plan skill Phase 2.9: skip silently for pure client-UI diffs with no server/infra
Files-to-Edit. The visual-regression surface is covered by the e2e VRT gate, not runtime telemetry.)

## Infrastructure (IaC)

None — no server, service, cron, vendor account, DNS, secret, or firewall rule introduced. Pure code
change against the already-provisioned `apps/web-platform` surface. (Phase 2.8: skip.)

## Test Scenarios

1. **In-flight band, expanded (the bug):** `/dashboard`, expanded, `list-memberships` pending → toggle
   rect must NOT intersect "Dashboard" nav link rect. (RED on main.)
2. **Loaded band, expanded:** `list-memberships` resolved → toggle centered on identity chip (existing
   AC1/AC3 stays green).
3. **In-flight band, collapsed:** `/dashboard` collapsed, `list-memberships` pending → collapsed toggle
   (`top-3`, icon column) does not overlap nav icons.
4. **Loaded band, collapsed:** existing collapsed centering assertion stays green.
5. **Drilled (Settings/KB) expanded:** band has back-link + section title (non-collapsing) → toggle
   already clears; confirm no regression.

## Sharp Edges

- jsdom (vitest) renders NO CSS — the `test/dashboard-sidebar-collapse.test.tsx` className assertions
  can pass while the rendered layout is still broken. The binding proof for THIS bug is the real-CSS
  e2e VRT rect-intersection assertion (ADR-049). Do not "verify" the overlap fix in jsdom.
- A toggleable control has TWO states; a fix for the expanded state does not carry to the collapsed
  state. Both must be asserted (learning `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`).
- The `top-10` expanded offset is a *calibrated* value tied to the pill center (PR #5015 comment at
  layout.tsx:335-365). If approach (B) moves the anchor, re-read that comment and update it — do not
  leave the comment asserting a now-false geometry.
- `e2e/nav-states-shell.e2e.ts` can flake on throttled local runs; CI's containerized e2e is the
  authoritative gate (learning `test-failures/2026-06-08-nav-states-structural-ui-gate-flakes-on-throttled-local.md`).
  Use localStorage seeding for deterministic collapsed state rather than click+animation-wait.
- The `## User-Brand Impact` section must remain filled (threshold `none` with a reason); an empty or
  placeholder section fails `deepen-plan` Phase 4.6.

## Related

- `apps/web-platform/app/(dashboard)/layout.tsx:366-373` — floated collapse toggle (the control).
- `apps/web-platform/components/dashboard/workspace-context-band.tsx:128-200` — async band, no reserved height.
- `apps/web-platform/components/dashboard/org-switcher-container.tsx:214` — `null` until fetch resolves (the height-collapse source).
- `apps/web-platform/e2e/nav-states-shell.e2e.ts` — e2e VRT gate (ADR-049).
- ADR-047 (`knowledge-base/engineering/architecture/decisions/ADR-047-nav-context-band-outside-swap.md`).
- ADR-049 (`knowledge-base/engineering/architecture/decisions/ADR-049-headless-visual-regression-gate.md`).
- PRs #4997 (float toggle), #5015 (center on pill), #5029 (collapsed `top-3`) — the toggle's positioning history.
- Learnings: `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`,
  `2026-06-02-ui-structural-diffs-need-prepush-browser-gate.md`,
  `test-failures/2026-06-08-nav-states-structural-ui-gate-flakes-on-throttled-local.md`.
