---
title: "fix: Desktop sidebar/navigation rail UX issues (D4-bolder follow-up)"
type: fix
branch: feat-one-shot-sidebar-rail-ux-fixes
lane: single-domain
date: 2026-06-04
requires_cpo_signoff: false
brand_survival_threshold: none
---

# 🐛 fix: Desktop sidebar/navigation rail UX issues (D4-bolder follow-up)

## Enhancement Summary

**Deepened on:** 2026-06-04
**Sections enhanced:** Overview (precedent), AC4/AC6 (a11y), Risks (precedent-diff)
**Gates passed:** 4.6 User-Brand Impact (threshold `none`, no sensitive paths),
4.7 Observability (client-only — N/A justified), 4.8 PAT-shaped (no matches),
4.9 UI-wireframe (`.pen` committed + referenced).

### Key Improvements
1. **Precedent-Diff (Phase 4.4):** the PRIMARY nav in `layout.tsx:360-399`
   ALREADY implements the canonical collapsed icon-only pattern —
   `${collapsed ? "md:justify-center md:gap-0 md:px-0" : ""}` on a `min-h-[44px]`
   `Link`, with `title={collapsed ? item.label : undefined}` and the text span
   carrying `md:hidden` when collapsed. The collapsed Settings icon column (Issue
   4) MUST reuse this exact form rather than invent one — it already satisfies
   touch-target + tooltip + 56px-safe constraints and is the in-repo convention.
2. **Web Interface Guidelines (Vercel) applied to AC4/AC6:** icon-only nav
   links need `aria-label` (or `title`) — the plan already requires this; the
   inline SVG glyphs are decorative and should carry `aria-hidden="true"` (the
   `<Icon>` in `settings-shell.tsx:106` does not today — fold the
   `aria-hidden` add into Issue 4). Interactive elements need a visible
   `focus-visible:` ring — verify the reused primary-nav classes include it.
3. **Issue 2 keyboard-equivalence (WIG):** if the optional double-click-separator
   collapse (AC2.4) is implemented on a `<div>`/border region, it MUST also have
   a keyboard-operable path — the ⌘B shortcut already provides this, so the
   double-click is purely additive and WIG-compliant. Do NOT add a bare
   `<div onDoubleClick>` without the existing keyboard route (which exists).

### New Considerations Discovered
- The `aria-hidden="true"` on decorative glyphs is currently INCONSISTENT:
  `settings-shell.tsx` active-bar `<span>` has it (line 100-105) but the leading
  `<Icon>` (line 106) does not. The collapsed icon column (Issue 4) should set
  `aria-hidden` on the glyph since the `Link` itself carries the label.
- `iconForHref` (settings-shell.tsx:34-38) already maps EVERY tab including the
  dynamic `/team*` Members/Activity tabs (prefix-match → `PeopleIcon`) and a
  `DotIcon` fallback — so the collapsed icon column needs no new icon plumbing.

## Overview

Six UX issues observed on the iPad/desktop web platform against the navigation
rail that landed in the recent D4-bolder work (PR #4939 "D4-bolder desktop rail
variant", PR #4948 "D4-bolder rail identity treatment", both merged 2026-06-04,
issue family #4915/#4810/#4833). All six are presentation/copy fixes in the
already-shipped single-nav-rail (ADR-047) surface — no schema, no API, no new
infrastructure.

The rail lives in `apps/web-platform/app/(dashboard)/layout.tsx` (the `<aside>`
that owns the collapse toggle, the persistent workspace band, and the
swap-region slot). Drilled sections (Settings / Knowledge Base) portal their
secondary nav into that slot via `rail-slot.tsx`. The workspace band
(`workspace-context-band.tsx`) carries the "Back to menu" affordance and section
title in both expanded and collapsed forms.

### Issue → root-cause map (verified against codebase)

| # | Reported issue | Root cause (file:line) |
|---|----------------|------------------------|
| 1 | Big empty gap between collapse arrow and workspace switcher | Compounding top padding: brand-row `py-5` (layout.tsx:308) + band pill `pt-3` (workspace-context-band.tsx:149) |
| 2 | Collapse chevron reads like "back" on secondary menus | Collapse `ChevronLeftIcon` (layout.tsx:328) sits one row above the band's `BackArrowIcon` "Back to menu" (workspace-context-band.tsx:176); glyphs already differ but proximity + both-pointing-left still confuses |
| 3 | "Back to menu" too close to Settings / section title | Back link `pt-2` (workspace-context-band.tsx:174) immediately followed by section-title row `pb-3` (workspace-context-band.tsx:181-188), no inter-row gap |
| 4 | Collapsed Settings nav hides per-item icons | `settings-shell.tsx:77` gates the WHOLE `<nav>` behind `{!collapsed && ...}` — the per-item icons already exist (`TAB_ICONS`, lines 26-38) but never render collapsed |
| 5 | Rename "Conversation names" → "Domain Leaders" | Nav label literal `settings-shell.tsx:14`. NOTE: the page heading is ALREADY "Domain Leaders" (conversation-names-settings.tsx:30) — only the nav label is stale |
| 6 | Collapsed Knowledge Base nav looks empty/bad | `kb-sidebar-shell.tsx:38` gates the whole tree behind `{!collapsed && ...}`; KB has no flat icon list (nested file tree), so the collapsed rail shows only band glyphs |

### Research Reconciliation — Spec vs. Codebase

| Reported claim | Codebase reality | Plan response |
|----------------|------------------|---------------|
| #5 "rename label + page heading/route copy" | Page heading at `conversation-names-settings.tsx:30` is **already** "Domain Leaders". Only `settings-shell.tsx:14` nav label and `TAB_ICONS` key (cosmetic, href-based) still read "Conversation names" | Scope #5 to the nav label only. Leave route path `/dashboard/settings/conversation-names` and component/file names unchanged (renaming a live route is out-of-scope risk: redirects, bookmarks, the `iconForHref` prefix-match map, `inKbDocView`/drill detection). Document this scoping. |
| #2 "collapse can read like back arrow" | Glyphs ALREADY differ (collapse = `ChevronLeftIcon M15.75 19.5 8.25 12l7.5-7.5`; back = `BackArrowIcon M10.5 19.5 3 12...M3 12h18`), and `nav-chevron-alignment.test.tsx` already guards non-identity | The confusion is positional/semantic, not glyph-identity. Disambiguate further by changing the collapse glyph to a NON-directional icon (panel/sidebar-toggle glyph) so it no longer "points back". Double-click-on-separator is rejected as primary (see Decisions). |
| #4/#6 "collapsed nav should show item icons" | Collapse intentionally DOM-removes the secondary nav (`settings-shell.tsx:77`, `kb-sidebar-shell.tsx:38`) with shipped tests (`settings-sidebar-collapse.test.tsx` AC2, `kb-sidebar-collapse.test.tsx`) AND e2e overflow gates (`e2e/nav-states-shell.e2e.ts` AC3) asserting NO horizontal overflow at the 56px collapsed rail | #4 is feasible (Settings is a flat list of single icons — icon-only buttons fit 56px). #6 differs: a nested file tree has no coherent icon-only form. Settings gets per-item icon buttons; KB collapsed gets an improved icon-only affordance (see Decisions), NOT a clipped tree. Both reverse the AC2 "DOM-remove" invariant for Settings and require updating those tests + re-verifying the e2e overflow gate. |

## User-Brand Impact

**If this lands broken, the user experiences:** a misaligned or overflowing
navigation rail (icons clipping past the 56px collapsed edge, a collapse control
that still reads as "back", or a settings nav item mislabeled) — orientation
friction on the primary app chrome the user sees on every screen.

**If this leaks, the user's data is exposed via:** N/A — this is presentation
and copy only; no data, workflow-state, or money surface is touched. No new
data read/write, no new route, no auth change.

**Brand-survival threshold:** none — purely cosmetic rail polish on an
already-shipped surface; worst case is a visual regression caught by the e2e VRT
gate, not a per-user incident.

## Acceptance Criteria

### Pre-merge (PR)

**Issue 1 — tighten top gap (expanded rail):**
- [x] AC1.1 The vertical whitespace between the collapse control row and the
  workspace switcher pill is reduced. Implementation: reduce the brand-row
  bottom padding and/or the band pill `pt-3` so the two are visually adjacent
  (target: brand row `py-3`/`pb-2` instead of `py-5`, pill `pt-2` instead of
  `pt-3` — exact values tuned against the wireframe + e2e screenshot).
- [x] AC1.2 The collapsed-rail brand row spacing is NOT regressed (collapsed
  band already uses `px-2 py-3`; verify the collapsed top gap stays balanced).
- [x] AC1.3 A jsdom structural test asserts the brand-row container className no
  longer contains `py-5` (or whatever the chosen reduced token is), pinning the
  fix against silent revert. (Layout-pixel proof stays in the e2e VRT gate —
  jsdom has no layout engine.)

**Issue 2 — disambiguate collapse vs back:**
- [x] AC2.1 The collapse toggle glyph is changed from a left/right CHEVRON to a
  non-directional sidebar-panel-toggle icon (e.g. a "panel-left" rectangle glyph
  whose direction does not read as "back"). The expand state may keep a subtle
  directional cue but MUST be visibly distinct from the `BackArrowIcon`.
- [x] AC2.2 `nav-chevron-alignment.test.tsx`'s `COLLAPSE_CHEVRON_PATH` constant
  is updated to the new collapse glyph path, and the existing "back affordance
  glyph distinct from collapse" assertions still pass (both expanded + collapsed
  band paths).
- [x] AC2.3 The collapse button retains its `aria-label` ("Collapse sidebar" /
  "Expand sidebar") and `title` (with ⌘B hint) — accessibility unchanged.
- [~] AC2.4 (Secondary affordance, OPTIONAL) double-click-to-collapse — SCOPED
  OUT. The only draggable separator today is the KB-expanded resize handle
  (`rail-resize-handle.tsx`); a double-click toggle there risks colliding with
  its pointer-drag semantics, and the glyph swap (AC2.1) already resolves the
  reported confusion. ⌘B remains the keyboard route. Documented in the PR body.

**Issue 3 — spacing between "Back to menu" and section title:**
- [x] AC3.1 In the EXPANDED band, a clear vertical gap separates the "Back to
  menu" link from the section-title row below it (target: section-title row
  gains `pt-3`/`mt-2` or the back link gains `pb-2`). Applies to BOTH Settings
  and Knowledge Base (the band is shared, keyed by `segmentToDrillLevel`).
- [x] AC3.2 `workspace-context-band.test.tsx` gains an assertion that the
  section-title row carries the new spacing token (or that back-link and title
  are not in the same tight `pt-2`/`pb-3` pair).

**Issue 4 — collapsed Settings nav shows per-item icons:**
- [x] AC4.1 When the rail is collapsed, the Settings secondary nav renders an
  icon-only column: one icon button per tab (General/gear, Domain Leaders/chat,
  Integrations/plug, Scope Grants/key, Billing/card, Members/people, Team
  Activity/people), reusing the existing `iconForHref` map. NOT DOM-removed.
- [x] AC4.2 Each collapsed icon button is a `Link` to its `tab.href`, carries
  `aria-current="page"` when active, a `title`/`aria-label` of the tab label
  (tooltip recovery), and the active gold-edge treatment in a 56px-safe form.
- [x] AC4.3 The collapsed icon column does NOT overflow the 56px rail
  horizontally (no full-text labels). The stable `settings-rail-nav` wrapper
  still renders in both toggle states.
- [x] AC4.4 `settings-sidebar-collapse.test.tsx` AC2 ("DOM-removes the settings
  nav when collapsed") is REPLACED with assertions that the collapsed nav
  renders icon-only links (present, no visible text labels) — the old invariant
  is intentionally reversed; the test is updated, not deleted, to keep coverage.

**Issue 5 — rename nav label:**
- [x] AC5.1 `settings-shell.tsx:14` nav label changes from "Conversation names"
  to "Domain Leaders". The `href` (`/dashboard/settings/conversation-names`) and
  `TAB_ICONS` key are UNCHANGED (route stays; icon map is href-keyed).
- [x] AC5.2 Any test asserting the literal "Conversation names" nav label is
  updated to "Domain Leaders" (grep `test/` first; `settings-sidebar-collapse`
  asserts General/Integrations/Billing only today — verify none break).
- [x] AC5.3 The page heading stays "Domain Leaders" (already correct — no edit).

**Issue 6 — collapsed Knowledge Base nav no longer empty/awkward:**
- [x] AC6.1 When the rail is collapsed AND drilled into KB, the rail surfaces a
  meaningful icon-only affordance instead of an empty tree region. Chosen
  approach (see Decisions): a single labeled icon-only "Browse files" / search
  affordance + sync glyph that expands the rail on activation (the nested tree
  has no coherent icon-only form, so it is reachable via ⌘B / click-to-expand,
  not clipped). The collapsed KB rail no longer renders as just band glyphs.
- [x] AC6.2 The collapsed KB affordance carries a `title`/`aria-label` and does
  NOT overflow 56px. Stable `kb-rail-tree` wrapper renders in both states.
- [x] AC6.3 `kb-sidebar-collapse.test.tsx` is updated to assert the new
  collapsed KB affordance is present (icon-only, no clipped tree rows), reversing
  the prior "DOM-removed" assertion where applicable.

**Cross-cutting:**
- [x] AC-X1 `e2e/nav-states-shell.e2e.ts` collapsed-overflow gate (AC3) passes
  with the new collapsed Settings icon column + KB affordance (NO horizontal
  overflow at 56px). Update the e2e fixtures/assertions if the collapsed
  secondary-nav DOM shape changed.
- [x] AC-X2 `npx vitest run` (web-platform) is green; `tsc --noEmit` clean.
- [x] AC-X3 No new horizontal-overflow VRT regression in the existing
  navigation screenshot gate.

### Post-merge (operator)
- [x] None. Pure client UI change; deploy is the standard `web-platform-release`
  pipeline on merge to main (container restart is automatic).

## Implementation Phases

**Phase order is dependency-driven** (contract/shared edits before consumers):

### Phase 0 — Preconditions (verify, no code)
- [x] 0.1 Confirm test runner + globs: web-platform uses **vitest** (`"test":
  "vitest"`), component tests under `test/**/*.test.tsx`, unit under
  `test/**/*.test.ts` (`vitest.config.ts:44,60`). `bunfig.toml` blocks `bun
  test`. New tests MUST live under `test/`, NOT co-located.
- [x] 0.2 Re-grep for any other "Conversation names" copy:
  `grep -rn "Conversation name" apps/web-platform/{app,components,server,hooks}`
  — expected: only `settings-shell.tsx:14` (label) + an internal console.error
  prefix + the href/component name (both unchanged).
- [x] 0.3 Read `e2e/nav-states-shell.e2e.ts` collapsed-overflow + back-affordance
  assertions (AC3, AC #4810 follow-up) so the Settings/KB collapsed changes are
  written to satisfy them, not break them.

### Phase 1 — Shared band + layout spacing (Issues 1, 3) + collapse glyph (Issue 2)
- [x] 1.1 `app/(dashboard)/layout.tsx`: reduce brand-row top/bottom padding
  (Issue 1 — `py-5` → tuned smaller); swap `ChevronLeftIcon`/`ChevronRightIcon`
  collapse glyph for a non-directional panel-toggle icon (Issue 2). Add new icon
  component(s) inline (matches existing inline-SVG convention in this file).
- [x] 1.2 `components/dashboard/workspace-context-band.tsx`: reduce pill `pt-3`
  (Issue 1); add inter-row gap between "Back to menu" (`pt-2`) and section-title
  (`pb-3`) rows (Issue 3) in the EXPANDED return. Verify the COLLAPSED band
  branch spacing stays balanced.
- [~] 1.3 (Optional, Issue 2 secondary) double-click-to-collapse — SKIPPED (see
  AC2.4). The glyph swap is the durable fix; double-click risks the resize-handle
  interaction and is not worth the cost.

### Phase 2 — Collapsed Settings icon column (Issue 4) + label (Issue 5)
- [x] 2.1 `components/settings/settings-shell.tsx:14`: rename nav label to
  "Domain Leaders" (Issue 5).
- [x] 2.2 `settings-shell.tsx`: in the collapsed branch (currently `{!collapsed
  && <nav>}`), render an icon-only `<nav aria-label="Settings">` variant — one
  `Link` per tab with the `iconForHref(tab.href)` glyph, `title`/`aria-label` =
  `tab.label`, `aria-current` on active, 56px-safe active gold treatment, no
  text label. The glyph `<Icon>` carries `aria-hidden="true"` (the `Link` owns
  the accessible name via `aria-label`/`title`). **Reuse the canonical collapsed
  pattern from the primary nav** (`layout.tsx:360-399`): `min-h-[44px]`,
  `md:justify-center md:gap-0 md:px-0`, `title={tab.label}` — do NOT invent a new
  form. Keep the stable `settings-rail-nav` wrapper across both branches (Issue 4).

### Phase 3 — Collapsed KB affordance (Issue 6)
- [x] 3.1 `components/kb/kb-sidebar-shell.tsx`: in the collapsed branch, render a
  compact icon-only affordance (search/browse + sync glyph) instead of nothing —
  per Decisions, an icon button that expands the rail (⌘B / click) plus the
  collapsed sync glyph. Keep the stable `kb-rail-tree` wrapper. Must satisfy the
  e2e 56px no-overflow gate (Issue 6).

### Phase 4 — Tests
- [x] 4.1 Update `nav-chevron-alignment.test.tsx` `COLLAPSE_CHEVRON_PATH` + back
  distinctness (AC2.2).
- [x] 4.2 Update `settings-sidebar-collapse.test.tsx` AC2 → icon-only assertion
  (AC4.4); update any "Conversation names" label assertion (AC5.2).
- [x] 4.3 Add/adjust `workspace-context-band.test.tsx` spacing assertion (AC3.2).
- [x] 4.4 Update `kb-sidebar-collapse.test.tsx` collapsed assertion (AC6.3).
- [x] 4.5 Run `npx vitest run` + `tsc --noEmit`; run the e2e nav-states gate if
  the harness is available locally, else rely on CI.

## Files to Edit

- `apps/web-platform/app/(dashboard)/layout.tsx` — Issue 1 (brand-row padding),
  Issue 2 (collapse glyph swap), Issue 2-optional (double-click separator)
- `apps/web-platform/components/dashboard/workspace-context-band.tsx` — Issue 1
  (pill `pt`), Issue 3 (back-link ↔ section-title gap)
- `apps/web-platform/components/settings/settings-shell.tsx` — Issue 4
  (collapsed icon column), Issue 5 (nav label rename)
- `apps/web-platform/components/kb/kb-sidebar-shell.tsx` — Issue 6 (collapsed
  affordance)
- `apps/web-platform/test/nav-chevron-alignment.test.tsx` — AC2.2
- `apps/web-platform/test/settings-sidebar-collapse.test.tsx` — AC4.4, AC5.2
- `apps/web-platform/test/workspace-context-band.test.tsx` — AC3.2
- `apps/web-platform/test/kb-sidebar-collapse.test.tsx` — AC6.3
- `apps/web-platform/e2e/nav-states-shell.e2e.ts` — AC-X1 (collapsed-nav DOM
  shape changed for Settings/KB; update fixtures/assertions if needed)

## Files to Create

- (None expected — all edits are in existing components. New collapse-glyph icon
  component lives inline in `layout.tsx` per the file's existing convention.)

## Alternative Approaches Considered

| Approach | Decision |
|----------|----------|
| Issue 2: double-click nav separator as the PRIMARY collapse control | Rejected as primary — undiscoverable, and the only draggable separator today is the KB-expanded resize handle (`rail-resize-handle.tsx`), so it would not exist on Settings/top-level. Keep the button as canonical; offer double-click only as an ADDITIVE convenience (AC2.4, optional). |
| Issue 2: just move the collapse chevron to a different position | Insufficient — the report is about glyph semantics (both point left/back). Changing the GLYPH to non-directional is the durable fix. |
| Issue 4/6: render the full nav with `display:none`+CSS at 56px | Rejected — the shipped design DOM-removes (not hides) precisely to avoid full-text clipping; reverting to display:none reintroduces the clip the original fix solved. Settings gets purpose-built icon-only buttons; KB gets a click-to-expand affordance. |
| Issue 6: shrink the file tree to icon-only rows when collapsed | Rejected — a nested tree has no coherent icon-only representation (the shipped comment in `kb-sidebar-shell.tsx:30-33` documents this). A single browse/expand affordance is the right collapsed form. |
| Issue 5: also rename the route `/conversation-names` → `/domain-leaders` | Deferred / out-of-scope — live route rename means redirect stubs, bookmark breakage, and touching drill-detection + `iconForHref` keys for a cosmetic gain. Label-only rename satisfies the user-visible request. |

## Domain Review

**Domains relevant:** Product (UI surface — mechanical override fires: edits
`components/**/*.tsx` + `app/**/layout.tsx`)

### Product/UX Gate

**Tier:** advisory — modifies EXISTING user-facing components (no new page,
route, or net-new interactive surface; the collapsed icon column and KB
affordance are restyles of existing nav regions). No file under `## Files to
Create` matches `components/**/*.tsx` / `app/**/page.tsx` / `app/**/layout.tsx`
(all edits are to EXISTING files), so the mechanical BLOCKING escalation does
not fire.
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (advisory, pipeline context)
**Skipped specialists:** none
**Pencil available:** N/A — existing D4-bolder wireframes already cover these
surfaces (`knowledge-base/product/design/navigation/kb-nav-d4-bolder-drilled.pen`,
`single-nav-rail.pen`, `sidebar-band-reorder-fold.pen`). The collapsed
Settings-icons treatment is shown in mock 27
(`screenshots/27-desktop-d4-bolder-settings-drilled.png`) referenced in
`settings-shell.tsx:20`. No new flows are introduced, so no new `.pen` is
required.

#### Findings

The six fixes refine an already-wireframed rail. The only design decision
needing taste (collapsed KB affordance shape) is bounded by the documented
constraint that a nested tree has no icon-only form; the chosen click-to-expand
affordance is the conservative, low-risk option. Recommend the implementer
screenshot the collapsed Settings + KB states during /work and compare against
mock 26/27 before opening the PR.

## Observability

Not applicable — this plan's Files-to-Edit are all client React components and
tests under `apps/web-platform/components/`, `app/`, and `test/`. No
server/infra code path, no new failure mode, no new log/alert surface. Per the
plan Phase 2.9 skip rule (pure client-UI change, no new code/infra surface that
can fail silently), the 5-field observability schema does not apply. The
existing e2e VRT gate (`e2e/nav-states-shell.e2e.ts`) is the regression
detector for this surface.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Collapsed icon column invents a non-canonical form that drifts from the primary nav | **Precedent exists** — `layout.tsx:360-399` is the canonical collapsed icon-only pattern (`min-h-[44px]` + `md:justify-center md:gap-0 md:px-0` + `title` + `md:hidden` text span). Reuse it verbatim. No novel pattern. |
| Reversing the "DOM-remove on collapse" invariant reintroduces the 56px clip the original fix solved | Settings uses single-glyph icon-only buttons (fit 56px by construction, proven by the primary nav already doing it). KB does NOT clip a tree — it shows a click-to-expand affordance. The e2e overflow gate (AC-X1) is the regression net. |
| Collapse-glyph swap breaks the `nav-chevron-alignment.test.tsx` byte-identity guard | The guard's `COLLAPSE_CHEVRON_PATH` constant must be updated to the new glyph in the SAME commit (AC2.2). The back-arrow distinctness assertion still holds (a non-directional panel glyph is even MORE distinct from the back arrow than the old chevron). |
| Decorative-glyph `aria-hidden` inconsistency (existing) propagates into new code | Set `aria-hidden="true"` on the icon `<Icon>` in the new collapsed column; the `Link` carries the accessible name (WIG: icon-only links need `aria-label`; decorative icons need `aria-hidden`). |
| Optional double-click-separator (AC2.4) ships as a bare `<div onDoubleClick>` with no keyboard path | ⌘B already provides the keyboard route (`layout.tsx:198-210`), so double-click is purely additive. If the cost is non-trivial (interaction with the KB resize handle), skip it and document the scope-out — it is explicitly optional. |

## Test Scenarios

1. Expanded rail, top-level: collapse control is a non-directional panel glyph;
   minimal gap above the workspace pill.
2. Expanded rail, drilled (Settings): "Back to menu" and "Settings" title have a
   clear gap; collapse glyph ≠ back arrow.
3. Expanded rail, drilled (KB): same back↔title gap.
4. Collapsed rail, Settings: icon-only column with all 7 item glyphs, active item
   marked, no text, no 56px overflow.
5. Collapsed rail, KB: meaningful icon-only affordance (browse/expand + sync),
   not empty, no overflow.
6. Settings nav label reads "Domain Leaders"; clicking it still routes to
   `/dashboard/settings/conversation-names` and the page heading reads "Domain
   Leaders".
7. ⌘B still toggles collapse; double-click separator toggles collapse IFF that
   optional affordance was implemented.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold
  fails `deepen-plan` Phase 4.6. This plan declares threshold `none` with a
  reason (cosmetic-only); it touches no sensitive path per preflight Check 6, so
  no scope-out bullet is required.
- **Both toggle states must be verified.** Issues 1/2/3 are expanded-state;
  issues 4/6 are collapsed-state; they render DIFFERENT DOM subtrees in
  `workspace-context-band.tsx` (the `variant === "rail" && collapsed` early
  return at line 80 vs the default return at 133) and in `settings-shell.tsx` /
  `kb-sidebar-shell.tsx` (the `{!collapsed && ...}` gate). A spacing or glyph fix
  applied to one branch can miss the other. Verify collapse AND expand for every
  issue. (Learning: `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`
  — PR #2494 fixed collapsed chevron but left expanded misaligned.)
- **Issues 4/6 reverse a deliberate shipped invariant.** `settings-sidebar-collapse.test.tsx`
  AC2 and `kb-sidebar-collapse.test.tsx` explicitly assert the collapsed nav is
  DOM-REMOVED, and `e2e/nav-states-shell.e2e.ts` AC3 asserts NO horizontal
  overflow at 56px. The fix must UPDATE these tests (not delete) and re-satisfy
  the e2e overflow gate — the whole point of the original DOM-removal was to
  avoid clipping, so the replacement icon-only forms must be genuinely 56px-safe.
- **Issue 5 is narrower than the brief implies.** The page heading is ALREADY
  "Domain Leaders" (`conversation-names-settings.tsx:30`). Only the nav label is
  stale. Do not rename the route, component, or file (out-of-scope risk).
- jsdom has no layout engine: pixel-spacing / overflow proofs live in the e2e
  Playwright VRT gate, NOT in vitest. The vitest tests pin STRUCTURAL invariants
  (className tokens present/absent, icon-only links present, glyph-path
  distinctness). Do not attempt to assert computed geometry in jsdom.
- New tests MUST live under `apps/web-platform/test/` (vitest `include` globs:
  `test/**/*.test.tsx`, `test/**/*.test.ts`); a co-located component test is
  silently never run. `bun test` is blocked by `bunfig.toml` — use
  `npx vitest run <path>`.

## Open Code-Review Overlap

Two open `code-review`-labeled issues name `layout.tsx`, the file this plan
edits:

- **#2194** `refactor(dashboard): decompose DashboardLayout into hooks and
  subcomponents` (P3, Large effort) — **Acknowledge.** This is a structural
  decomposition of the ~213-line `DashboardLayout` Long Method, a different
  concern from the targeted spacing/glyph/copy fixes here. Folding a Large P3
  refactor into a focused UX-fix PR would blow scope and obscure the visual
  diff the e2e VRT gate reviews. The scope-out remains open. My edits to
  `layout.tsx` are small, localized (brand-row padding + collapse glyph) and do
  not conflict with a future decomposition.
- **#2193** `refactor(billing): unify past_due and unpaid banners` (P3) —
  **Acknowledge.** Touches the payment banners in `layout.tsx`, not the rail
  chrome this plan edits. No overlap with the rail fixes; remains open.

(#2197 and #3564 matched on generic `layout.tsx`/`apps/web-platform` body
mentions but concern billing types and Core Web Vitals infra respectively — no
rail overlap. If the corpus changes at /work time, re-run the overlap check
against the final Files-to-Edit list.)
