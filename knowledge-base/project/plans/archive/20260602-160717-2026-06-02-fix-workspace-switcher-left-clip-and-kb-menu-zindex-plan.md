---
title: "fix: Workspace switcher left-clip + KB menu z-index/stacking overlap"
date: 2026-06-02
type: fix
branch: feat-one-shot-workspace-switcher-clip-zindex
lane: single-domain
requires_cpo_signoff: false
brand_survival_threshold: none
status: planned
---

# 🐛 fix: Workspace switcher left-clip + KB menu z-index/stacking overlap

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** Implementation Phases (1 + 2), Research Reconciliation, Risks/Sharp Edges, AC4
**Verification passes run:** 4.6 User-Brand Impact (pass), 4.7 Observability (pass — pure-client skip-eligible but section present), 4.8 PAT-shaped variable (pass — no matches), 4.45 verify-the-negative (confirmed `<main>` has no competing z-index/transform), 4.4 precedent-diff (canonical left-anchor precedent found)

### Key Improvements

1. **Phase 1 fix now adopts a verified codebase precedent.** `conversation-row.tsx:77` already uses `absolute left-0 top-full z-50` for an identical dropdown-menu use case — the org-switcher is the ONLY dropdown in `components/` using the clip-prone `left-1/2 -translate-x-1/2`. Phase 1 now mirrors the precedent (`left-0 top-full mt-2`) instead of inventing a one-off, eliminating the magic `top-12` offset too.
2. **Phase 2 stacking fix empirically confirmed.** Verify-the-negative grep proved `<main>` is `flex-1 overflow-y-auto bg-soleur-bg-base` with NO z-index and NO transform/filter, so raising `<aside>` `md:z-auto → md:z-30` is sufficient and safe; no mobile-drawer z-index collision (`z-50`/`z-40` are unprefixed mobile classes overridden by `md:z-30` at md+).
3. **Containing-block trap ruled out.** No `transform`/`filter`/`backdrop`/`will-change` exists in the KB layout-level subtree, so the dropdown won't be re-trapped below `<main>` (cross-checked against learning `2026-02-17-backdrop-filter-breaks-fixed-positioning.md`).

### New Considerations Discovered

- The sibling `share-popover.tsx:142` (also `w-80`, also a KB component) uses `right-0 top-full` — confirming `w-80` is fine when anchored to an edge rather than centered.
- Siblings universally use `top-full mt-N`, not a hardcoded `top-12`. Adopt `top-full mt-2` for resilience against trigger-height changes.

## Overview

Two related layout defects in the web-platform dashboard navbar/sidebar chrome:

1. **Left-clip:** the workspace (org) switcher dropdown is cut off on the left edge.
   The dropdown menu in `org-switcher.tsx` is `w-80` (320px) and positioned
   `absolute left-1/2 -translate-x-1/2`, centering a 320px panel on the trigger
   button's horizontal center. The trigger lives inside the dashboard `<aside>`
   sidebar, which is only `md:w-56` (224px) wide with `px-3` horizontal padding.
   A 320px panel centered on a button inside a 224px column overhangs the
   sidebar's left border and the viewport's left edge (x≈0), so its left portion
   is clipped / painted off-screen.

2. **KB menu overlap / wrong stacking:** when on a Knowledge-Base route, the KB
   folder tree (rendered inside `<main>`) paints **over** the open workspace
   switcher dropdown, so the user cannot reliably click workspace rows. Root
   cause is a stacking-context bug: the dropdown is `z-50`, but that z-index is
   scoped to the **aside's** stacking context. The dashboard `<aside>` is
   `md:relative md:z-auto` (no positioned z-index of its own) and `<main>` is its
   flex sibling appearing **after** it in DOM order. With both at `z-auto`,
   paint order falls back to DOM order — `<main>` (and the KB tree within it)
   paints on top of everything inside `<aside>`, including the `z-50` dropdown.
   The `z-50` only ranks the dropdown *within* the aside, never against `<main>`.

Both are pure frontend CSS/layout fixes. No data, schema, auth, or API surfaces
are touched.

### Affected files (verified to exist on branch)

| Concern | File | Key line(s) |
| --- | --- | --- |
| Switcher dropdown (clip + z-index) | `apps/web-platform/components/dashboard/org-switcher.tsx` | trigger L67-90; dropdown L92-148 (`absolute left-1/2 top-12 z-50 w-80 -translate-x-1/2`, L95) |
| Switcher mount + sidebar band | `apps/web-platform/components/dashboard/org-switcher-container.tsx` | mount L112-114; band `px-3 py-3` L113 |
| Dashboard sidebar/main stacking | `apps/web-platform/app/(dashboard)/layout.tsx` | `<aside>` L234-243 (`md:relative md:z-auto`, L240); `<main>` L385-388 (`flex-1 overflow-y-auto`); switcher mount L281 |
| KB desktop layout (sibling that overlaps) | `apps/web-platform/components/kb/kb-desktop-layout.tsx` | KB `<aside>` L57-66 (`md:overflow-hidden`) |
| KB layout entry | `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` | renders inside dashboard `<main>` |

## Research Reconciliation — Spec vs. Codebase

No spec file exists for this branch (`knowledge-base/project/specs/feat-one-shot-workspace-switcher-clip-zindex/` absent). Premise was validated directly against the codebase:

| Claim (from feature description) | Codebase reality | Plan response |
| --- | --- | --- |
| "Workspace switcher cut on the left side" | Dropdown `w-80` (320px) `left-1/2 -translate-x-1/2` inside a `md:w-56` (224px) aside — confirmed geometric overhang past sidebar/viewport left edge | Fix: anchor the dropdown to the left edge of the trigger and clamp its width to the available column, OR widen+left-align so it never overhangs (Phase 1) |
| "KB folders overlap the workspace switcher; menu must be above all layers" | Dropdown `z-50` lives inside `<aside md:z-auto>`; `<main>` (KB tree) is a later DOM sibling at `z-auto` → paints over dropdown. Confirmed stacking-context bug, not a missing z-index value | Fix: raise the aside (or the dropdown's positioning ancestor) into a stacking context that ranks above `<main>` — see Phase 2 |
| Both are "UI exists but is broken" | Both components present and mounted on branch; behavioral CSS bug, not never-built | Patch plan, not build plan ✅ |

## User-Brand Impact

**If this lands broken, the user experiences:** a workspace switcher whose dropdown is either still clipped on the left (unreadable workspace names) or still painted under the KB folder tree (unclickable rows) — i.e., a multi-org user cannot switch workspaces while on a KB page.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this is a pure presentational CSS/layout change. No data crosses a boundary; no auth/billing/tenant logic is altered. The switch action itself (`set_current_workspace_id` RPC in `org-switcher-container.tsx`) is untouched.

**Brand-survival threshold:** none — `reason: pure CSS/layout fix to existing client components; no data, auth, API, schema, or tenant-scope surface is touched, and the switch RPC path is unchanged.`

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 (left-clip):** With ≥2 memberships and the dropdown open, the dropdown's left edge is `≥ 0` relative to the viewport and does not overflow the sidebar's left border. Implementation: replace `left-1/2 top-12 -translate-x-1/2` with the precedent anchor `left-0 top-full mt-2` plus `max-w-[calc(100vw-1.5rem)]` to clamp the mobile drawer, keeping `w-80` for the desktop width (overflows rightward over `<main>`). Verified visually (Playwright screenshot) + by a jsdom assertion that the menu element does NOT carry `-translate-x-1/2` / `left-1/2` and DOES carry `left-0` + `top-full` (see AC4).
- [x] **AC2 (z-index/stacking):** On a `/dashboard/kb` route with the dropdown open, the dropdown paints **above** the KB folder tree and all rows are clickable. Implementation: give the dashboard `<aside>` (or the switcher's positioned ancestor) a stacking context that ranks above `<main>` — preferred minimal fix is to change the aside's desktop class from `md:z-auto` to a positive `md:z-30` (it is already `md:relative`), so the entire sidebar — and the `z-50` dropdown within it — paints over the `z-auto` `<main>`. Confirm `<main>` does not itself establish a competing positive z-index (it does not — `flex-1 overflow-y-auto`, no `z-*`).
- [ ] **AC3 (no regression — collapsed/expanded both states):** Verify the dropdown alignment AND stacking in BOTH sidebar states the switcher can render in: expanded desktop sidebar (`md:w-56`) and the mobile drawer (`w-64`, `z-50`). The switcher is hidden when `collapsed` (layout L281 `{!collapsed && ...}`), so collapsed state needs no dropdown check — but assert the mobile-drawer dropdown is not clipped against the 256px drawer either.
- [x] **AC4 (test):** Extend the existing `apps/web-platform/test/org-switcher.test.tsx` with a case asserting the dropdown menu element's className no longer contains the clipping classes (`left-1/2`, `-translate-x-1/2`) and DOES contain `left-0` + `top-full`. The vitest jsdom project collects this file via `include: ["test/**/*.test.tsx"]` (verified in `vitest.config.ts`) — do NOT co-locate under `components/` (the node project's `test/**/*.test.ts` and jsdom's `test/**/*.test.tsx` globs both require the `test/` root; a co-located `components/**/*.test.tsx` is silently never run). Run via `./node_modules/.bin/vitest run test/org-switcher.test.tsx` from `apps/web-platform/`.
- [x] **AC5 (no a11y/behavior regression):** All pre-existing `org-switcher.test.tsx` cases still pass (chip render, dropdown lists memberships, current-row checkmark, onSwitch on non-current, no-op on current, ESC/outside-click close). `org-switcher-container.test.tsx` still passes.
- [x] **AC6 (lint/type):** `tsc --noEmit` clean for the touched files; no new Tailwind class typos (classes resolve against existing `soleur-*` tokens).

### Post-merge (operator)

- [ ] **AC7:** None required. PR merge to `main` touching `apps/web-platform/**` triggers the existing `web-platform-release.yml` container restart automatically; no manual deploy step. Visual confirmation can be done post-deploy via Playwright but is not a gating operator action.

## Implementation Phases

### Phase 1 — Fix the left-clip (org-switcher.tsx dropdown)

The dropdown (`org-switcher.tsx` L92-96) is currently:

```tsx
<div
  role="menu"
  className="absolute left-1/2 top-12 z-50 w-80 -translate-x-1/2 rounded-md ..."
>
```

Problem: `left-1/2 -translate-x-1/2` centers a 320px (`w-80`) panel on the trigger's
center; inside a 224px sidebar this overhangs the left edge.

Fix (left-anchor + responsive width) — adopt the **verified codebase precedent**.
Replace with a left-aligned anchor so the panel grows rightward from the trigger's
left edge and never overhangs the sidebar/viewport:

```tsx
// BEFORE (clip-prone — the ONLY dropdown in components/ using this pattern):
className="absolute left-1/2 top-12 z-50 w-80 -translate-x-1/2 rounded-md ..."

// AFTER (mirrors conversation-row.tsx:77 precedent):
className="absolute left-0 top-full z-50 mt-2 w-80 max-w-[calc(100vw-1.5rem)] rounded-md ..."
```

- `left-0` anchors to the trigger's left edge (the trigger is full-width inside the
  `px-3` band, so `left-0` ≈ the sidebar content's left padding). Drop
  `-translate-x-1/2` entirely.
- `top-full mt-2` replaces the magic `top-12` — matches the sibling precedent and
  is resilient to trigger-height changes (every other dropdown uses `top-full`,
  none uses a fixed `top-N`).
- `w-80` keeps the desired 320px width on desktop where `<main>` provides room to
  the right (the dropdown is `absolute`, so it overflows the 224px sidebar to the
  RIGHT, over `<main>` — the intended, readable direction once Phase 2 fixes
  stacking). Verified safe: sibling `share-popover.tsx:142` uses `w-80` with an
  edge anchor and does not clip.
- `max-w-[calc(100vw-1.5rem)]` clamps the panel on the mobile drawer (`w-64` =
  256px) so it never exceeds the viewport.

Sub-task: confirm the trigger button row (L75) does not itself clip — it uses
`min-w-0` + `truncate`, fine.

#### Precedent diff (Phase 4.4 gate)

| Component | Anchor pattern | Width | Clips? |
| --- | --- | --- | --- |
| `components/inbox/conversation-row.tsx:77` | `absolute left-0 top-full z-50` | `min-w-[160px]` | no (canonical) |
| `components/kb/share-popover.tsx:142` | `absolute right-0 top-full z-50` | `w-80` | no |
| `components/settings/api-usage-info-tooltip.tsx:30` | `absolute left-0 top-full z-10` | `w-64` | no |
| `components/dashboard/org-switcher.tsx:95` (current) | `absolute left-1/2 top-12 -translate-x-1/2 z-50` | `w-80` | **YES — the bug** |

The org-switcher is the sole outlier. The fix brings it onto the established
`left-0 top-full` pattern — no novel approach.

### Phase 2 — Fix the stacking so the dropdown is above the KB tree

Root cause: dashboard `<aside>` (`layout.tsx` L240) is `md:relative md:z-auto`.
A positioned element with `z-auto` does NOT create a stacking context, so the
`z-50` dropdown inside it is only ranked within the aside; `<main>` (later DOM
sibling, `z-auto`) paints over it.

Minimal fix: raise the aside to a positive desktop z-index so the whole sidebar
(and the dropdown within) outranks `<main>`:

```tsx
// layout.tsx L240 — change `md:z-auto` → `md:z-30`
md:relative md:z-30 md:translate-x-0
```

Rationale for `z-30`: the mobile drawer already uses `z-50` and its backdrop
`z-40` (L223, L237); on desktop the sidebar just needs to outrank the `z-auto`
`<main>`. `md:z-30` is above `<main>` and below the mobile-drawer/backdrop band,
avoiding any new conflict. The dropdown's own `z-50` then correctly ranks above
sibling sidebar content (theme toggle, nav, live-repo badge).

**Verification (done at deepen time — empirically confirmed):**

- `<main>` (L385-386) is exactly `className="flex-1 overflow-y-auto bg-soleur-bg-base"`
  — NO `z-*`, NO `transform`/`filter`/`backdrop`/`will-change`. It relies on DOM
  paint order, so raising `<aside>` to a positive `md:z-30` is sufficient to make
  the sidebar (and its `z-50` dropdown) outrank `<main>`. ✓
- No `transform`/`filter`/`backdrop`/`will-change` exists in the KB layout-level
  subtree (`kb-desktop-layout.tsx`, `kb-doc-shell.tsx`, `kb-sidebar-shell.tsx`,
  `kb/layout.tsx`), so no ancestor containing-block re-traps the dropdown (per
  learning `2026-02-17-backdrop-filter-breaks-fixed-positioning.md`). ✓
- `kb-desktop-layout.tsx` uses `md:overflow-hidden` on its inner aside (clips the
  KB tree itself, not the dashboard dropdown) and `transition-transform` on tree
  chevrons (inside the tree, not an ancestor of the dropdown). Neither traps the
  dashboard switcher. ✓
- No `md:z-40`+ descendant exists under `components/dashboard/`, so `md:z-30` on
  the aside does not invert any existing intra-sidebar layering. ✓

Mobile-drawer collision check: the aside's `z-50` (L237) and backdrop `z-40`
(L223) are UNPREFIXED Tailwind classes (apply at all breakpoints); `md:z-30`
overrides only at md+ where the drawer is translated off-screen and the backdrop
is `md:hidden`. So the drawer keeps `z-50` on mobile and the sidebar becomes
`z-30` on desktop — no collision in either regime. ✓

### Phase 3 — Tests + regression guard

- Extend `apps/web-platform/test/org-switcher.test.tsx` with AC4 assertions
  (menu className no longer has `left-1/2` / `-translate-x-1/2`; has `left-0`).
- Confirm all existing cases still pass (AC5).
- Optionally add a layout-level assertion that the dashboard `<aside>` carries
  `md:z-30` — but the dashboard layout is a large client component with many
  effects; a className grep test may be more brittle than valuable. Prefer a
  Playwright visual check (Phase 4) for the cross-`<main>` stacking, since jsdom
  has no real paint/compositing model and cannot prove z-index paint order.

### Phase 4 — Visual verification (Playwright, advisory)

jsdom cannot verify actual paint order (no layout engine). Use the
`soleur:test-browser` / agent-browser path to: log in as a multi-org user, open
the switcher on a `/dashboard/kb` route, screenshot, and confirm (a) the dropdown
left edge is on-screen and (b) it paints over the folder tree with clickable rows.
This is the only check that truly validates AC1+AC2 together; the jsdom test only
guards the class contract.

## Sharp Edges

- **jsdom proves the class contract, not the paint.** z-index / stacking-context
  bugs are invisible to jsdom (no compositing). The jsdom test (AC4) can only
  assert the *classes* changed; the actual "dropdown paints above KB tree" claim
  (AC2) must be validated with a real browser (Phase 4). Do not mark AC2 satisfied
  on a green vitest run alone.
- **Verify alignment in BOTH toggle/render states.** Per learning
  `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`: the switcher
  renders in the expanded desktop sidebar (`md:w-56`) AND the mobile drawer
  (`w-64`). A left-anchor fix that looks right on desktop can still clip or
  overhang in the 256px mobile drawer. Check both (AC3). The collapsed sidebar
  hides the switcher entirely (`{!collapsed && <OrgSwitcherContainer />}`,
  layout L281) so that state needs no dropdown check.
- **Don't introduce a containing-block trap.** Adding `transform`,
  `filter`, `backdrop-filter`, or `will-change` to any ancestor of the dropdown
  (e.g., for a polish animation) would create a new containing block / stacking
  context and could re-trap the `z-50` dropdown below `<main>` — the exact class
  documented in `2026-02-17-backdrop-filter-breaks-fixed-positioning.md`. Keep
  the fix to `position`/`left`/`width`/`z-index` only.
- **`md:z-30` must outrank `<main>` but not collide with the mobile band.** The
  mobile drawer aside is `z-50` and its backdrop `z-40`; those are mobile-only
  (`md:hidden` backdrop, drawer transforms off-screen at md+). `md:z-30` applies
  only at md+ where the drawer is irrelevant, so there is no collision. Confirm
  no other dashboard descendant uses `md:z-40`+ that would now sit below the
  raised sidebar unintentionally.
- **A plan whose `## User-Brand Impact` section is empty, contains only
  TBD/TODO/placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6.**
  This plan's section is filled with threshold `none` + reason (sensitive-path
  scope-out), satisfying the gate.

## Observability

This is a pure client-side CSS/layout change with no new code path, network call,
cron, or infrastructure surface. Per the Phase 2.9 skip criteria (no Files-to-Edit
introduces a new server/infra runtime surface; the change edits existing client
`.tsx` render output only), a 5-field observability schema is not required. The
only verification signal is visual (Playwright screenshot, Phase 4) — there is no
runtime liveness/error/log surface to declare because no logic executes.

discoverability_test: open `/dashboard/kb` as a multi-org user, click the
workspace switcher, screenshot (NO ssh) — expected: dropdown left-edge on-screen
and painted above the folder tree.

## Domain Review

**Domains relevant:** Product (UI presentation only)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** ux-design-lead (advisory tier, pipeline mode — no new
user-facing surface; this corrects alignment/stacking of an existing component,
matching the ADVISORY definition "modifies existing user-facing components
without adding new interactive surfaces")
**Pencil available:** N/A

#### Findings

No new pages, flows, or components. The change corrects the geometry and paint
order of the existing workspace-switcher dropdown so its already-shipped rows
become reliably visible and clickable. No copy, no new interaction.

## Infrastructure (IaC)

None — no server, secret, vendor, cron, DNS, or runtime process introduced. Pure
edits under `apps/web-platform/components/` and `apps/web-platform/app/`. Phase 2.8
skip criteria met.

## Open Code-Review Overlap

Checked at deepen time (`gh issue list --label code-review --state open`, 73 open
issues). One match against a touched file:

- **#2193** (`refactor(billing): unify past_due and unpaid banners into shared
  component + extract useDismissiblePersistent`) touches
  `apps/web-platform/app/(dashboard)/layout.tsx`. **Disposition: Acknowledge.**
  Different concern — #2193 is about the payment-banner JSX (`PaymentWarningBanner`,
  the `unpaid`/`past_due` blocks at L390-406), entirely separate from the single
  `<aside>` className change (`md:z-auto → md:z-30`) this plan makes. No conflict;
  the scope-out remains open and is not folded in (it would expand this CSS-only
  fix into a billing-component refactor).

No matches against `org-switcher.tsx` or `org-switcher.test.tsx`.

## Files to Edit

- `apps/web-platform/components/dashboard/org-switcher.tsx` — dropdown positioning
  classes (Phase 1): `left-1/2 -translate-x-1/2 w-80` → `left-0 w-80
  max-w-[calc(100vw-1.5rem)]`.
- `apps/web-platform/app/(dashboard)/layout.tsx` — `<aside>` desktop z-index
  (Phase 2): `md:z-auto` → `md:z-30`.
- `apps/web-platform/test/org-switcher.test.tsx` — AC4 class-contract assertions.

## Files to Create

- None (extend existing test file).

## Test Scenarios

1. Multi-org user, desktop, `/dashboard` route: open switcher → dropdown fully
   on-screen, left edge ≥ 0.
2. Multi-org user, desktop, `/dashboard/kb` route with folders: open switcher →
   dropdown paints above the KB tree; every row clickable; selecting a non-current
   row fires the confirm flow.
3. Mobile drawer (< md), multi-org user: open drawer → open switcher → dropdown
   clamped to viewport (no horizontal overflow).
4. Solo user (≤1 membership): switcher renders nothing (unchanged, AC-C).
5. Existing jsdom suite (`org-switcher.test.tsx`, `org-switcher-container.test.tsx`)
   all green.
