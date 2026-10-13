---
title: "fix: collapsed single-rail secondary-nav overflow (KB / Settings / Chat)"
date: 2026-06-03
type: bug
status: ready
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_issues: [4813]
related_prs: [4810, 4833]
related_adrs: [ADR-047, ADR-049]
related_brainstorm: knowledge-base/project/brainstorms/2026-06-02-single-nav-rail-brainstorm.md
related_design: knowledge-base/product/design/navigation/single-nav-rail.pen
---

# fix: collapsed single-rail secondary-nav overflow (KB / Settings / Chat) 🐛

## Enhancement Summary

**Deepened on:** 2026-06-03
**Amended on:** 2026-06-03 — folded in the **widenable KB rail** requirement
(expanded-state drag-to-resize) across Overview, Acceptance Criteria (AC9–AC14),
Files to Edit/Create, Design, Sharp Edges, Test Scenarios, Domain Review.
**Sections enhanced:** Design, Files to Edit, Sharp Edges, Acceptance Criteria (testid plumbing)
**Mandatory gates:** 4.6 User-Brand Impact ✅ · 4.7 Observability ✅ (client-only skip documented) · 4.8 PAT-shaped ✅ none · 4.9 UI-wireframe ✅ committed `.pen` referenced (amendment adds a non-blocking follow-up to add a widen-handle frame — see Product/UX Gate)

### Key Improvements (grounded against installed code)

1. **Collapse-threading mechanism made concrete.** `RailSlotProvider value` is typed `HTMLElement | null` (single slot node, `rail-slot.tsx`); the harness sets `value={slot}` and `layout.tsx:205` sets `value={railSlotEl}`. Threading `collapsed` therefore uses a **sibling `RailCollapsedContext`**, NOT widening the existing value (which would break both call sites). This is the load-bearing refinement to Approach A.
2. **Stable wrapper testids required.** `ConversationsRailPortal` already wraps the rail in `data-testid="conversations-rail"` that "resolves to exactly one node regardless of collapsed/expanded branch (AC4d)" — the codebase already anticipated the collapsed branch living *inside* `ConversationsRail`. Settings + KB shells need an equivalent **stable wrapper testid** so the content-present/absent assertion targets one node.
3. **Render-conditional precedent confirmed.** `theme-toggle.tsx:67` (`if (collapsed) return <button…/>`) and `WorkspaceContextBand` (`if (variant === "rail" && collapsed) return …`, `workspace-context-band.tsx:68`) are the in-repo precedents for the `if (collapsed)` render-conditional shape. Reuse it.

### New Considerations Discovered

- The `RailSlotHarness` (`test/helpers/rail-slot-harness.tsx`) provides ONLY the slot node — it MUST be extended to also provide a `collapsed` value for the jsdom collapsed-state tests (folded into Files to Edit / Phase 0).
- `ConversationsRail` is self-contained (own `useConversations` fetch, no context crosses its portal) — its collapsed branch is the simplest (render-conditional inside the component, wrapper testid already stable). KB/Settings need the wrapper testid added.

### Amendment 2026-06-03 — widenable KB rail (expanded state)

Folds in a complementary requirement: in the **expanded** state, let the user
**drag the KB rail's right edge to widen it** so deeply-nested folder/file names
stop truncating. Collapsed = clean hidden secondary nav (the fix above);
expanded = user-widenable. Grounded against installed code:

1. **The nav rail is NOT a resizable Panel today — it is a single `aside` with a
   fixed Tailwind width.** `(dashboard)/layout.tsx:246` sets
   `${collapsed ? "md:w-14" : "md:w-56"}` on the one `aside`. `react-resizable-panels`
   (`^4.10.0`, `package.json`) is installed but used ONLY in
   `kb-desktop-layout.tsx:5` for the **main content area** doc-viewer-vs-chat
   split (`<Group orientation="horizontal">` … `<Panel>`), which lives in `main`,
   NOT in the rail. So widening the KB tree means controlling the **`aside`'s own
   width** (single-side edge drag), not adding a panel split. A full
   PanelGroup-ifying of the dashboard layout (wrapping `aside` + `main` in one
   `Group`) is rejected: large, risky refactor of the load-bearing
   collapse/portal layout for a small affordance.
2. **Persistence precedent already exists — reuse its shape.** `useSidebarCollapse`
   (`hooks/use-sidebar-collapse.ts:35`) is the in-repo localStorage pattern:
   `soleur:sidebar.*` key namespace, `useState` default + post-hydration
   `useEffect` read (PaymentWarningBanner hydration pattern), try/catch around all
   `localStorage` access (private-mode safe). The new `useRailWidth` hook mirrors
   it exactly (key `soleur:sidebar.kb.width`, value = pixel integer). Do NOT invent
   a new persistence mechanism.
3. **Reuse the existing resize-handle visual idiom, add no dependency.** A
   styled drag handle already exists (`ResizeHandle` in `kb-desktop-layout.tsx:17`).
   But `react-resizable-panels`' `Separator` requires sibling `Panel`s in a
   `Group`; the `aside` is not a Panel, so the lib's `Separator` cannot drive the
   `aside` width directly. The consistent choice is a thin pointer-drag handle
   styled to MATCH that idiom (same amber-active treatment, grip dots) but driving
   the `aside` width via the `useRailWidth` hook. No new npm dependency
   (`hr`-consistent: search-first, reuse).

## Overview

When the single nav rail (shipped by PR #4810, the drill-in replacement of the
old two-rail collapsible-sidebars model #2342) is **collapsed** (`⌘B`/`Ctrl+B`
→ `aside` shrinks to `md:w-14` = 56 px) **while drilled into a section**
(`/dashboard/kb`, `/dashboard/settings`, `/dashboard/chat`), the section's
secondary nav is portaled into the `rail-secondary-slot` and renders its
**full-width content unchanged** — full-text Settings labels, the KB search box
+ arbitrarily-nested file-tree rows, and the rich Conversations-rail rows
(status badge, leader-color border, relative time, preview). At 56 px these
clip / bleed off the right edge exactly as the bug-report screenshots show.

The bug-report screenshots themselves depict the **superseded** two-rail model
(pre-#4810) — but the same *defect class* is live in the current single-rail
model because `collapsed` is **never threaded to the portaled secondary nav**.
The fix: make the drilled secondary nav respond to `collapsed` the same way the
top-level rail and the workspace context band already do — by **hiding the
secondary-nav content when collapsed** (the rail shows only the always-present,
already-collapse-aware `WorkspaceContextBand` icon column), and strengthen the
existing visual-regression gate so it asserts no-overflow against **populated**
secondary-nav content for all three sections (it currently false-GREENs on an
empty KB tree and never visits Settings/Chat collapsed).

This is a **single-user-incident** change (carried forward from ADR-047 / the
single-nav-rail brainstorm): a clipped, half-rendered rail during a
tenant-sensitive action (inviting a member, sharing an API key, editing scope
grants — all reachable from the Settings drill) degrades the workspace-identity
legibility that ADR-047 exists to protect.

### Complementary requirement — widenable KB rail (expanded)

The collapse fix solves the *too-narrow* end; the mirror complaint is the
*not-wide-enough* end: in the EXPANDED state the KB secondary nav is the
recursive arbitrary-depth `FileTree` (`file-tree.tsx`) inside a **fixed**
`md:w-56` (224 px) `aside`, so deeply-nested folder/file rows truncate. This
amendment makes the **expanded KB rail horizontally resizable** — the user drags
the rail's right edge to widen it; the chosen width persists across reloads,
clamps to a sensible min/max, and is **subordinate to collapse** (collapsed
always wins → 56 px, no handle, no widen). Resize applies ONLY to the KB drill
(its tree is the surface with the truncation problem); Settings/Chat keep the
default width (their secondary nav is short text links / fixed-layout rows with
no deep nesting). Together: collapsed = clean hidden/icon rail; expanded = clean
default OR user-widened-to-see-deep-trees.

### Why "hide when collapsed" and not "icon-only condense"

| Section | Secondary nav | Can it become a meaningful icon-only rail at 56 px? |
|---|---|---|
| KB | `SearchOverlay` + recursive arbitrary-depth `FileTree` (`file-tree.tsx`) | **No.** A nested file tree has no per-row glyph that conveys identity; nesting at 56 px is incoherent. The #4833 wireframe frames 06/07 explored a "tree-peek" but the simple, correct behavior is to hide the tree (the file is still reachable via the URL + the expand toggle). |
| Settings | 5–7 text-label links (`General` … `Team Activity`) | Possible in theory, but the labels have **no icon vocabulary** today; inventing 7 icons is net-new design scope, not a bug fix. |
| Chat | Rich conversation rows (badge + color + time + preview) | **No.** Same as KB. |

Uniform **hide-when-collapsed** is the smallest correct fix consistent across
all three, requires no net-new iconography, and matches the brainstorm's
already-decided model (collapse reclaims width; the context band keeps identity
visible). Collapsing the rail while drilled becomes "I want the content area
wide; the section nav steps out of the way" — the back chevron + section title
in the (collapse-aware) context band still tell the user where they are, and
`⌘B` / the expand chevron bring the nav back.

## User-Brand Impact

**If this lands broken, the user experiences:** a visibly broken left rail —
clipped half-rendered file/folder names, a search box bleeding off the 56 px
edge, Settings labels truncated to single characters ("Gene", "Integ", "Billi")
— while performing tenant-sensitive Settings actions. The brand reads as
unfinished/buggy at the exact moment trust matters most.

**If this leaks, the user's workflow is exposed via:** N/A — no data leak vector;
this is a presentation defect. The adjacent brand risk (carried from ADR-047) is
**wrong-workspace action under an illegible rail**: the workspace context band is
already collapse-aware and stays visible (this plan does not touch it), so
identity remains legible; the fix removes the *clipped secondary nav* noise that
sits beside it.

**Brand-survival threshold:** single-user incident. (Carried forward from
ADR-047 / `2026-06-02-single-nav-rail-brainstorm.md`. One user seeing a broken
rail during an invite/key-share is brand-damaging; CPO sign-off required at plan
time per `wg`/User-Brand-Impact gate.)

**Amendment (widenable KB rail) — brand impact.** Positive when it works: a user
with a deep `knowledge-base/...` tree can finally see full folder/file names
instead of `knowledge-ba…`/`roa…`, which directly improves the KB's legibility —
the product's core "your knowledge, navigable" promise. Failure modes if it lands
broken: (a) a stored bad width hydrates and the rail swallows the doc viewer on
load (mitigated by clamp-on-read, AC11); (b) the inline width leaks into the
collapsed branch and regresses the collapse fix (mitigated by branch-gating +
AC12/AC14); (c) a leaked global pointer listener makes the whole dashboard feel
janky after a drag (mitigated by pointer-capture cleanup, §Sharp Edges). All three
are caught by the e2e/jsdom gates before merge. No data-leak vector (client-only
presentation; the width is a single integer in localStorage).

## Premise Validation

Checked at plan-write time (this plan was entered via the one-shot path; the
bug report's screenshots are stale):

- **#4813 (single nav rail)** — `CLOSED`, closed by **PR #4810 (`MERGED`)**.
  Present in this branch at commit `7dc1a355`. The two-rail collapsible model
  the bug report describes is **superseded**, not current. *Premise reframed:
  fix the same defect class in the new model.*
- **PR #4833 (`a6d6365b`)** — already shipped: (a) collapse-aware
  `WorkspaceContextBand` (icon-only form, `data-collapsed="true"`), (b) the
  headless visual-regression gate `apps/web-platform/e2e/nav-states-shell.e2e.ts`
  (ADR-049). **This plan does NOT re-fix the band**; it fixes the *secondary
  nav*, which #4833 did not touch.
- **Defect confirmed live in current code:** `collapsed` (owned by
  `useSidebarCollapse` in `(dashboard)/layout.tsx:111`) is **never** passed to
  `RailSlotPortal` / the portaled content. `git grep "collapsed"` returns zero
  hits in `rail-slot.tsx`, `settings-shell.tsx`, `kb-sidebar-shell.tsx`,
  `kb/layout.tsx`, `settings/layout.tsx`.
- **Existing e2e gate false-GREENs here:** the "collapsed drilled" test
  (`nav-states-shell.e2e.ts:267`) navigates to `/dashboard/kb` with the KB tree
  mocked **empty** (`tree: []`), so `KbSidebarShell` renders the short
  `RailEmptyState` CTA, not populated rows — overflow passes vacuously. The test
  never visits Settings or Chat collapsed.
- **#4826 (position resume)** — `OPEN`, deliberately out of scope (a deferred
  follow-up from ADR-047; not part of this fix).
- **No external-state / API-contract premises** to validate (pure client UI).

## Research Reconciliation — Bug Report vs. Codebase

| Bug-report claim | Reality (current code) | Plan response |
|---|---|---|
| "workspace switcher icons + labels clipped" (old primary rail) | Switcher/`OrgSwitcherContainer` now lives only in the collapse-aware `WorkspaceContextBand` (ADR-047 single-mount); already fixed by #4833 | Do not touch the band. Scope to the *secondary nav* only. |
| "the expanded sidebar content is just clipped by the narrower rail" | True of the **secondary nav** (Settings/KB/Chat) — `collapsed` is not threaded into the portal | Thread collapse to the portaled content; hide secondary nav when collapsed. |
| screenshots show two rails | Single rail now; secondary *replaces* primary via portal swap (ADR-047) | Reframe as single-rail secondary-nav defect. |
| "consistent with how the chat/main navbar collapses" | Top-level rail collapses to icon-only via `md:justify-center md:gap-0 md:px-0` + `overflow-hidden whitespace-nowrap md:hidden` (`layout.tsx:330,333`); band collapses via its `collapsed` prop | Reuse the same collapse semantics; secondary nav hides rather than icon-condenses (no icon vocabulary). |

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — collapse reaches the portal.** `collapsed` flows from
  `(dashboard)/layout.tsx` to the portaled secondary-nav content via
  `RailCollapsedContext` (Approach A). Verification:
  `grep -nE "RailCollapsedContext|useRailCollapsed" apps/web-platform/components/dashboard/rail-slot.tsx`
  returns ≥1 hit, and each of `settings-shell.tsx`, `kb-sidebar-shell.tsx`,
  `conversations-rail.tsx` calls `useRailCollapsed()`
  (`grep -nE "useRailCollapsed" <file>` ≥1 each). If Approach B is chosen instead,
  the invariant is "the portaled content's visibility is a function of `collapsed`"
  — verify the layout's render-gate instead. The plumbing is approach-specific;
  the invariant is not.
- [x] **AC2 — secondary nav is hidden (DOM-removed) when collapsed.** In the
  collapsed+drilled state the populated secondary nav is **not in the DOM** (a
  render-conditional, not `display:none` — so the jsdom half of the gate can
  assert absence; cf. the #4833 Bug-1 render-conditional learning). Verification:
  jsdom test renders the shell with `collapsed=true` and asserts the nav
  content (`data-testid` for the settings nav / file tree / conversation rows) is
  absent via `queryByTestId(...) === null`.
- [x] **AC3 — no horizontal overflow with POPULATED content, all 3 sections.**
  The e2e gate asserts `scrollWidth - clientWidth <= 1` on the collapsed `aside`
  for **populated** Settings sub-nav, **populated** KB tree (≥1 nested dir + ≥1
  file), and **populated** Conversations rail (≥3 rows). The KB/Chat mocks must
  return non-empty fixtures (the current `tree: []` is the false-GREEN). Proven
  RED first (revert the fix → test fails) per ADR-049.
- [x] **AC4 — content present when EXPANDED (no regression).** The same e2e cases
  re-run with `collapsed=false` assert the secondary-nav content IS present and
  legible (testid present), so AC2 is not satisfied by an always-empty rail
  (assert-the-invariant-not-a-proxy, per
  `2026-06-02-visual-regression-gate-must-assert-content-not-band-box.md`).
- [x] **AC5 — workspace identity still visible when collapsed+drilled.** The e2e
  cases assert `railBand` is visible with `data-collapsed="true"` AND the band's
  identity icon (`data-testid="workspace-identity-icon"`) is present in every
  collapsed+drilled section — the band is mocked with non-null
  `/api/workspace/active-repo` + `/api/workspace/list-memberships` (already done
  in `setupNavMocks`). This plan must NOT regress the band.
- [x] **AC6 — collapse-aware in BOTH toggle states for all 3 sections.** Per the
  "verify both toggle states" learning: each section has a collapsed assertion
  (AC2/AC3) AND an expanded assertion (AC4). No section is fixed in only one
  state.
- [x] **AC7 — full suite green.** `tsc --noEmit`, the affected vitest files, and
  `nav-states-shell.e2e.ts` (authenticated Playwright project) all pass. Run via
  `package.json` `scripts.test` runner (vitest for `apps/web-platform`; e2e via
  the project's playwright invocation), not a hardcoded runner.

#### Widenable KB rail (amendment)

- [x] **AC9 — drag widens the expanded KB rail.** When drilled into `/dashboard/kb`
  and EXPANDED, a drag handle on the `aside`'s right edge resizes the rail: a
  pointer drag rightward increases the `aside` width (asserted via the e2e
  overflow harness measuring `aside` `clientWidth` before/after a
  `mouse.down`→`mouse.move`→`mouse.up` on the handle, `nav-states-shell.e2e.ts`).
  Verification: `grep -nE "useRailWidth|kb-rail-resize-handle" apps/web-platform/...`
  returns the hook + handle testid; e2e asserts post-drag `clientWidth` > default.
- [x] **AC10 — width persists across reload.** After a drag sets a width, a full
  page reload restores it: the hook reads `localStorage["soleur:sidebar.kb.width"]`
  in a post-hydration `useEffect` (mirroring `useSidebarCollapse`). Verification:
  e2e drags, reloads, asserts `aside` `clientWidth` ≈ dragged width (±1 px); a
  jsdom test asserts the hook reads/writes the key.
- [x] **AC11 — width clamps to min/max.** The persisted/applied width is clamped
  to `[RAIL_MIN_PX, RAIL_MAX_PX]` (min ≥ the default 224 px so widening never
  makes it *narrower* than today; max bounded so the rail cannot swallow the
  content area, e.g. `min(480, 40vw)`). Verification: jsdom test feeds an
  out-of-range stored value and an out-of-range drag delta, asserts the applied
  width is clamped both ends.
- [x] **AC12 — collapse takes precedence over width.** When `collapsed=true` the
  rail is 56 px (`md:w-14`) regardless of any stored KB width, the drag handle is
  NOT rendered, and the stored width is preserved (not cleared) so it returns on
  expand. Verification: e2e collapses a previously-widened KB rail, asserts
  `clientWidth` ≈ 56 px and `queryByTestId("kb-rail-resize-handle")` absent; then
  expands and asserts the widened width returns.
- [x] **AC13 — resize is KB-only.** The drag handle renders only when
  `drill === "kb" && !collapsed`. Settings/Chat drills render no handle and use
  the default `md:w-56`. Verification: e2e asserts `kb-rail-resize-handle` absent
  on `/dashboard/settings` and `/dashboard/chat`; jsdom asserts the handle is
  gated on the KB drill.
- [x] **AC14 — no regression to collapse fix.** AC1–AC7 still hold with the resize
  code present: the inline width style is applied to the `aside` (not the portaled
  secondary nav), so collapsed-hide (AC2) and overflow (AC3) assertions are
  unaffected; the e2e overflow check still measures the live `aside` width.

### Post-merge (operator)

- [ ] **AC8 — visual confirmation.** Playwright MCP (`mcp__playwright__*`) drives
  the deployed dashboard: collapse the rail while drilled into KB (with docs),
  Settings, and Chat (with conversations); screenshot each; confirm no clipped
  rows. **Also (amendment):** in expanded KB, drag the rail wider and confirm a
  deeply-nested folder/file name that truncated at the default width is now fully
  visible; reload and confirm the width persists. *Automation: feasible via
  Playwright MCP — runs in `/soleur:qa` / post-merge, not operator-manual.*

## Files to Edit

- `apps/web-platform/components/dashboard/rail-slot.tsx` — add a **sibling**
  `RailCollapsedContext = createContext<boolean>(false)` + `RailCollapsedProvider`
  + `useRailCollapsed()` hook (do NOT widen the existing `RailSlotContext` value,
  which is `HTMLElement | null` and set positionally at two call sites). Portaled
  content reads collapse through the React tree via `useRailCollapsed()`.
  **Decision gate (§Design):** if Approach B (render-gate the slot in the layout)
  is chosen instead, this file is untouched. Default A.
- `apps/web-platform/app/(dashboard)/layout.tsx` — provide `collapsed` to the
  rail-slot context (it already holds the value at line 111), OR render-gate the
  `rail-secondary-slot` swap so the portaled nav is hidden when collapsed
  (without unmounting the slot node mid-portal — see §Sharp Edges on portal
  target lifetime).
- `apps/web-platform/components/settings/settings-shell.tsx` — wrap the portaled
  `<nav>` in a stable `data-testid="settings-rail-nav"` div; when collapsed
  (`useRailCollapsed()`), do not render the `<ul>` of tabs (render-conditional).
  Keep the content-area `children` untouched (page body, not the rail).
- `apps/web-platform/components/kb/kb-sidebar-shell.tsx` — wrap in a stable
  `data-testid="kb-rail-tree"` div; when collapsed, do not render the
  `SearchOverlay` + `FileTree`/`RailEmptyState` block (render-conditional).
- `apps/web-platform/components/chat/conversations-rail.tsx` — when collapsed,
  do not render the conversation rows (render-conditional). The stable
  `data-testid="conversations-rail"` wrapper already exists in
  `conversations-rail-portal.tsx` (no change needed there).
- `apps/web-platform/e2e/nav-states-shell.e2e.ts` — (a) change the KB mock to
  return a **populated** tree (≥1 nested dir + ≥1 file) for the collapsed-drilled
  case; (b) add a **Settings** collapsed+drilled case (`/dashboard/settings`) and
  a **Chat** collapsed+drilled case (`/dashboard/chat`) with populated
  conversations; (c) assert overflow ≤1 AND secondary-nav content absent when
  collapsed; (d) add the expanded-state content-present counterpart (AC4).
- `apps/web-platform/test/settings-sidebar-collapse.test.tsx` — extend (or add a
  sibling) jsdom test asserting the Settings nav is DOM-absent when
  `collapsed=true` via `RailSlotHarness`. (Harness must be able to supply a
  collapsed value — see §Design.)
- `apps/web-platform/test/kb-sidebar-collapse.test.tsx` — same for KB
  (`FileTree` mocked) — assert tree/search absent when collapsed.
- `apps/web-platform/test/conversations-rail.test.tsx` — same for Chat — assert
  rows absent when collapsed.
- `apps/web-platform/test/helpers/rail-slot-harness.tsx` — extend to accept an
  optional `collapsed?: boolean` prop and wrap children in `RailCollapsedProvider`
  so the jsdom collapsed-state tests can drive `useRailCollapsed()`. (The harness
  today provides only the slot node via `RailSlotProvider value={slot}`.)

### Files to Edit — widenable KB rail (amendment)

- `apps/web-platform/app/(dashboard)/layout.tsx` — (a) call the new `useRailWidth`
  hook; (b) when `drill === "kb" && !collapsed`, apply the resolved width to the
  `aside` via inline `style={{ width: railWidthPx }}` (md+ only) **overriding** the
  `md:w-56` class (keep `md:w-14`/`md:w-56` as the non-KB / collapsed default —
  inline style only set in the KB-expanded branch so collapsed `md:w-14` and
  Settings/Chat `md:w-56` are untouched, AC12/AC13); (c) render the
  `<RailResizeHandle>` on the `aside`'s right edge in the same `drill === "kb" && !collapsed`
  branch. The inline width is on the `aside`, NOT on the portaled secondary nav,
  so the collapse-hide and overflow assertions (AC2/AC3) are unaffected (AC14).
- `apps/web-platform/e2e/nav-states-shell.e2e.ts` — add expanded-KB resize cases:
  (a) drag the handle and assert `aside` `clientWidth` increases (AC9); (b) reload
  and assert width persists (AC10); (c) drag past max and assert clamp (AC11);
  (d) collapse a widened KB rail and assert ≈56 px + handle absent, then expand and
  assert width returns (AC12); (e) assert handle absent on Settings/Chat (AC13).

## Files to Create

- `apps/web-platform/hooks/use-rail-width.ts` — `useRailWidth()` hook mirroring
  `useSidebarCollapse` (`hooks/use-sidebar-collapse.ts:35`): `useState` default
  `RAIL_DEFAULT_PX` (224, = `md:w-56`), post-hydration `useEffect` reading
  `localStorage["soleur:sidebar.kb.width"]`, a `setWidth(px)` that clamps to
  `[RAIL_MIN_PX, RAIL_MAX_PX]` and persists, all `localStorage` access in
  try/catch (private-mode safe). Exports `RAIL_MIN_PX`/`RAIL_MAX_PX`/`RAIL_DEFAULT_PX`
  constants. Returns `[widthPx, setWidth]`. (New file because it is a distinct hook
  with its own key/clamp; the collapse hook is left unchanged — do NOT widen its
  return tuple, two call sites.)
- `apps/web-platform/components/dashboard/rail-resize-handle.tsx` —
  `<RailResizeHandle width onWidthChange min max />`: a thin (`w-1`) absolutely-
  positioned right-edge handle, `data-testid="kb-rail-resize-handle"`,
  `role="separator"` + `aria-orientation="vertical"` + `aria-valuenow/min/max`
  (a11y), keyboard support (Arrow Left/Right nudge ±16 px) for non-pointer users,
  styled to MATCH the existing `ResizeHandle` idiom in `kb-desktop-layout.tsx:17`
  (amber-active grip). `onPointerDown` captures the pointer and on `pointermove`
  computes `clamp(startWidth + (e.clientX − startX), min, max)` → `onWidthChange`;
  commits to localStorage via the hook on `pointerup`. (New file: no reusable
  single-side edge-drag component exists — the only resize handle in-repo is the
  lib's `Separator`, which requires sibling `Panel`s, so it cannot drive the
  `aside` width; a new lightweight handle is the search-first / no-new-dependency
  choice.)
- The collapse-fix half adds the only other new symbol `RailCollapsedContext`
  inside the existing `rail-slot.tsx` (an edit, not a new file); `RailSlotHarness`
  is extended in place (see Files to Edit).

## Design

**Two viable approaches — pick A unless §Sharp Edges portal-lifetime concern bites, then B:**

- **Approach A — sibling collapse context + per-shell render-conditional (preferred).**
  `RailSlotContext`'s value is typed `HTMLElement | null` (the slot node only;
  `rail-slot.tsx`), and both `(dashboard)/layout.tsx:205` (`value={railSlotEl}`)
  and `RailSlotHarness` set it positionally — do NOT widen this value. Instead add
  a **sibling `RailCollapsedContext`** (`createContext<boolean>(false)`) exported
  from `rail-slot.tsx` with a `useRailCollapsed()` hook, provided alongside
  `RailSlotProvider` in `layout.tsx` (the layout already holds `collapsed` at
  line 111). Each shell calls `useRailCollapsed()` and render-conditionals its nav
  body: `if (collapsed) return null;` inside a STABLE wrapper that always renders
  (so the content-present/absent assertion targets exactly one node — mirroring
  `ConversationsRailPortal`'s `data-testid="conversations-rail"` wrapper). Pros:
  the slot node stays mounted (no portal-target churn); content presence is a pure
  function of `collapsed`; jsdom can assert absence. Mirrors `ThemeToggle({ collapsed })`
  (`theme-toggle.tsx:67`) and the band's `collapsed` prop (`workspace-context-band.tsx:68`).
  **The portal stays valid because the slot `<div>` is always rendered when
  drilled; only the portaled *children* change.**

  **Stable wrapper testids (required for AC2/AC3/AC4):**
  - Chat: `ConversationsRailPortal` ALREADY has `data-testid="conversations-rail"`
    around `<ConversationsRail/>` — render-conditional the rows INSIDE
    `ConversationsRail` so the wrapper survives both branches.
  - Settings: wrap `SettingsShell`'s portaled `<nav>` in a stable
    `data-testid="settings-rail-nav"` div that always renders; conditional the
    `<ul>` of tabs off when collapsed.
  - KB: wrap `KbSidebarShell`'s search+tree block in a stable
    `data-testid="kb-rail-tree"` div that always renders; conditional the
    `SearchOverlay`+`FileTree`/`RailEmptyState` off when collapsed.

- **Approach B — render-gate the slot in the layout.** In `(dashboard)/layout.tsx`,
  when `drill !== null && collapsed`, render the rail body with *no* slot (so the
  portals no-op via `RailSlotPortal`'s `if (!slot) return null`). Simpler diff but
  the slot node disappears/reappears on every collapse toggle, which churns the
  portal target and could interact badly with the KB tree's scroll position /
  context-following portal. **Only choose B if A's context plumbing proves
  awkward; document the choice at /work Phase 0.**

**Collapse semantics to reuse (cite, don't reinvent):** the top-level rail uses
`overflow-hidden whitespace-nowrap` + `md:hidden` on label spans and
`md:justify-center md:gap-0 md:px-0` on rows (`layout.tsx:330,333`). For the
secondary nav we go further (full hide) because there is no icon vocabulary —
but the *context-threading mechanism* should match the band/theme-toggle prop
pattern, not a new global store.

### Design — widenable KB rail (amendment)

**Mechanism: control the `aside`'s own width; do NOT PanelGroup-ify the layout.**
The rail is a single `aside` whose width is a Tailwind class
(`${collapsed ? "md:w-14" : "md:w-56"}`, `layout.tsx:246`). `react-resizable-panels`
(`^4.10.0`) is installed but the only `Group`/`Panel`/`Separator` usage is the
**main-area** doc-vs-chat split in `kb-desktop-layout.tsx` (`Group orientation="horizontal"`
in `main`, not the rail). Wrapping `aside` + `main` in one top-level `Group` to
make the rail a `Panel` was considered and rejected: it would rewrite the
load-bearing collapse/portal layout (the `aside` `transition-[width]`, the
`md:relative`/`fixed` drawer behavior, the slot ref) for a small affordance, and
`Panel` sizing is %-based (awkward to clamp to a px min ≥ the current 224 px and a
px/vw max). Instead drive the `aside`'s width directly:

1. **`useRailWidth()` hook** (new, `hooks/use-rail-width.ts`) — a near-verbatim
   structural copy of `useSidebarCollapse` (`hooks/use-sidebar-collapse.ts:35`):
   `useState(RAIL_DEFAULT_PX=224)`, post-hydration `useEffect` reading
   `localStorage["soleur:sidebar.kb.width"]` (same `soleur:sidebar.*` namespace,
   same hydration-safe / private-mode-safe try/catch pattern), `setWidth(px)`
   that `clamp`s to `[RAIL_MIN_PX, RAIL_MAX_PX]` then persists. Returns
   `[widthPx, setWidth]`.
2. **Inline width on the `aside`, KB-expanded branch only.** In `layout.tsx`, when
   `drill === "kb" && !collapsed`, set `style={{ width }}` on the `aside` (and a
   `md:` min/max via the clamp) — overriding `md:w-56`. In every other state the
   inline style is omitted, so `md:w-14` (collapsed) and `md:w-56` (Settings/Chat,
   top-level) are exactly as today. This makes collapse **structurally win**: the
   collapsed branch never sets an inline width and keeps `md:w-14` (AC12), and the
   resize affordance is gated on `drill === "kb"` (AC13).
3. **`<RailResizeHandle>`** (new, `components/dashboard/rail-resize-handle.tsx`) —
   a thin right-edge handle styled to MATCH the existing `ResizeHandle`
   (`kb-desktop-layout.tsx:17`: amber-active, grip dots) so the two resize
   affordances feel like one system, but driving the `aside` width via pointer
   capture (`setPointerCapture` + `pointermove` delta → `onWidthChange(clamp(...))`,
   commit on `pointerup`). It is `role="separator"` `aria-orientation="vertical"`
   with `aria-valuenow/min/max` and Arrow-key nudge for keyboard/AT users. Rendered
   only in the `drill === "kb" && !collapsed` branch.

**Why KB-only (not shared with Settings/Chat):** the truncation problem is
specific to the recursive arbitrary-depth `FileTree`; Settings is 5–7 short text
links and Chat rows are fixed-layout (badge+time+preview that already wrap). The
hook + handle are generic enough to extend later if Settings/Chat ever need it,
but YAGNI: scope to the KB drill that has the defect. (If a reviewer wants it
shared, the gate is `drill !== null` instead of `drill === "kb"` — a one-line
change — but default KB-only.)

## Sharp Edges

- **Portal target lifetime (Approach B risk).** The `rail-secondary-slot` div is
  the `createPortal` target. If collapse toggling unmounts/remounts that div, the
  KB tree's portal re-attaches and may lose scroll/expand state. Approach A keeps
  the div mounted and only hides the *portaled children* — prefer it.
- **Assert content, not a wrapper box** (`2026-06-02-visual-regression-gate-must-assert-content-not-band-box.md`):
  the collapsed e2e overflow assertion (`scrollWidth <= clientWidth`) is satisfied
  by an *empty* rail — that is exactly the current false-GREEN. The fix's e2e MUST
  (a) use populated fixtures, (b) assert content-absent when collapsed via
  testid, (c) assert content-present when expanded. A gate that an empty rail
  passes is not a gate.
- **Prove RED first** (ADR-049): before committing the fix, revert it locally and
  confirm the new populated-content collapsed e2e case FAILS (overflow > 1 with
  the old full-width nav). A green-from-birth assertion is unvalidated.
- **DOM-removal vs CSS-hide:** the jsdom half (`*-sidebar-collapse.test.tsx`)
  cannot see `display:none`/`md:hidden` — the hide MUST be a render-conditional
  (element leaves the DOM) for `queryByTestId(...) === null` to pass. This is the
  same constraint the #4833 Bug-1 fix hit.
- **Do not touch `WorkspaceContextBand`.** It is already collapse-aware (#4833),
  single-mount-enforced (ADR-047 `nav-single-mount.test.ts`), and the load-bearing
  identity surface. Adding a second collapse-aware path through it would risk the
  single-mount invariant. Scope the fix to the *secondary* nav only.
- **`RailSlotHarness` may not inject `collapsed`.** The existing harness
  (`test/helpers/rail-slot-harness.tsx`) supplies a slot node; if it does not
  also supply a collapse-context value, extend it to accept a `collapsed` prop so
  the jsdom collapsed-state tests can drive the new behavior. Read it at /work
  Phase 0 before writing the tests.
- **Playwright project routing is already correct.** `nav-states-*.e2e.ts` is
  routed to the `authenticated` project (`playwright.config.ts:52`) and ignored
  from `chromium` (`:39`). New cases added to the same file inherit this — no
  config change needed. Do NOT rename the file (would drop it from `testMatch`).
- **Precedent-diff (deepen Phase 4.4): the `collapsed`-render-conditional pattern
  is established in-repo, NOT novel.** Two precedents to copy verbatim:
  `theme-toggle.tsx:67` (`if (collapsed) { … return <button data-testid=…/> }`)
  and `workspace-context-band.tsx:68` (`if (variant === "rail" && collapsed) return
  <icon-column/>`). The secondary-nav shells go one step further (return nothing,
  not a minimal icon) because there is no icon vocabulary — but the prop-driven
  render-conditional shape is identical. The context-threading precedent is
  `RailSlotContext` itself (`createContext` + provider in `layout.tsx` + hook read
  through the React tree); `RailCollapsedContext` is its sibling. No novel pattern.
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (Filled above.)

### Sharp Edges — widenable KB rail (amendment)

- **Inline width must not break the collapse fix.** The inline `style={{ width }}`
  goes on the `aside`, and ONLY in the `drill === "kb" && !collapsed` branch. If it
  ever leaks into the collapsed branch, `md:w-14` is overridden and the whole
  collapse fix regresses. Gate it explicitly; the e2e AC12 case (collapse a
  widened rail → ≈56 px) is the guard.
- **Tailwind class vs inline style precedence.** `md:w-56` is a class; inline
  `style.width` wins over classes at any breakpoint, so on mobile (`<md`) the
  `aside` is already `w-64` fixed/drawer — only apply the inline width at `md+`
  (e.g. gate on the existing desktop assumption or use a `md`-scoped wrapper) so
  the mobile drawer width is untouched. Verify on the `MOBILE` viewport
  (`nav-states-shell.e2e.ts:188`) that the handle is absent and width unchanged.
- **Clamp the STORED value on read, not just on drag.** A stale/corrupt
  localStorage value (hand-edited, or from a future build with different bounds)
  must be clamped when hydrated, else a 9999 px rail swallows the content area on
  load. Clamp inside the hook's hydration `useEffect`, mirroring the collapse
  hook's defensive read. (AC11 jsdom case feeds an out-of-range stored value.)
- **Pointer capture + cleanup.** Use `setPointerCapture`/`releasePointerCapture`
  and remove listeners on `pointerup`/`pointercancel` (and on unmount) so a drag
  that ends outside the handle still commits and never leaks a global listener
  (`cq-ref-removal-sweep-cleanup-closures`). Commit to localStorage once on
  `pointerup` (not on every `pointermove`) to avoid thrashing storage.
- **No new dependency.** `react-resizable-panels`' `Separator` needs sibling
  `Panel`s in a `Group`; the `aside` is not a `Panel`, so the lib cannot drive its
  width. The new `RailResizeHandle` reuses the lib's *visual* idiom
  (`kb-desktop-layout.tsx:17`) without importing it — search-first / reuse-style,
  zero net-new packages (`cq-before-pushing-package-json-changes` unaffected).
- **Keyboard/AT parity (a11y).** A pure mouse-drag handle is inaccessible. The
  handle is `role="separator" aria-orientation="vertical"` with
  `aria-valuenow/min/max` and Arrow-Left/Right nudge so keyboard and AT users can
  widen too. (Web Interface Guidelines: resize handles need keyboard operability.)
- **Persisted width is NOT cleared on collapse.** Collapsing must preserve the
  stored KB width so it returns on expand (AC12). Collapse and width are
  independent keys (`soleur:sidebar.main.collapsed` vs `soleur:sidebar.kb.width`);
  the collapse toggle must not touch the width key.

## Test Scenarios

1. **Collapsed + drilled into Settings (populated):** rail = 56 px, no overflow,
   the 5–7 Settings links are DOM-absent, the context band shows the icon column
   with identity icon. Expand → links return.
2. **Collapsed + drilled into KB (populated tree, ≥1 nested dir + ≥1 file):** no
   overflow, search box + tree DOM-absent. Expand → tree returns.
3. **Collapsed + drilled into Chat (≥3 conversations):** no overflow, rows
   DOM-absent. Expand → rows return.
4. **Expanded + drilled (all 3):** secondary nav content present & legible
   (AC4 regression guard).
5. **Top-level collapsed (no drill):** unchanged — existing `nav-states` case
   still green (this plan does not touch the top-level rail).

### Widenable KB rail (amendment)

6. **Expanded KB — drag widens (AC9).** Drilled into `/dashboard/kb`, expanded;
   record `aside` `clientWidth`; `mouse.down` on `kb-rail-resize-handle`,
   `mouse.move` +120 px right, `mouse.up`; assert `clientWidth` increased by
   ≈120 px (within clamp). A previously-truncated deep file name is now visible.
7. **Persist across reload (AC10).** After scenario 6, `page.reload()`; assert
   `aside` `clientWidth` ≈ the dragged width (±1 px); jsdom: hook writes/reads
   `soleur:sidebar.kb.width`.
8. **Clamp bounds (AC11).** Drag far past `RAIL_MAX_PX` → assert `clientWidth`
   pinned at max; jsdom: stored value `9999` hydrates clamped to max, stored value
   `10` hydrates clamped to min (≥224). Drag never makes the rail narrower than the
   224 px default.
9. **Collapse precedence (AC12).** Widen KB rail, then collapse (`⌘B`): assert
   `clientWidth` ≈ 56 px (`md:w-14`) AND `kb-rail-resize-handle` absent AND the
   stored width key is unchanged; expand → `clientWidth` returns to the widened
   value (width key honored).
10. **KB-only (AC13).** On `/dashboard/settings` and `/dashboard/chat`, assert
    `kb-rail-resize-handle` is absent and `aside` width is the default `md:w-56`.
11. **Collapse-fix non-regression (AC14).** Re-run scenarios 1–4 with the resize
    code present: collapsed-hide and overflow assertions unchanged (inline width
    is on the `aside`, never on the portaled secondary nav).
12. **Mobile (a11y/viewport).** On `MOBILE` viewport (`:188`), assert the handle is
    absent and the drawer width is unchanged (inline width is md+ only).
13. **Keyboard resize (a11y).** Focus `kb-rail-resize-handle`, press ArrowRight
    several times; assert `aria-valuenow` and `aside` `clientWidth` increase, ±max
    clamp.

## Domain Review

**Domains relevant:** Product, Engineering

### Engineering (CTO)

**Status:** reviewed (carry-forward from `2026-06-02-single-nav-rail-brainstorm.md` + ADR-047)
**Assessment:** This is the secondary-nav completion of the single-rail collapse
behavior CTO already framed. The load-bearing structural rule (identity/switcher
mounts OUTSIDE the swap region, never gated on collapse) is satisfied and NOT
modified by this plan. Risk is LOW and concentrated in the portal-target-lifetime
choice (Approach A vs B) — documented in §Sharp Edges. Reuses existing
collapse-context / prop patterns; no new global state; no new fetch. The e2e
gate hardening (populated fixtures) closes a real false-GREEN.

**Amendment (widenable KB rail) — Assessment:** LOW risk, additive, client-only.
Reuses the in-repo localStorage persistence shape (`useSidebarCollapse`) and the
existing resize-handle visual idiom (`kb-desktop-layout.tsx`); adds NO npm
dependency and NO server/fetch. The chosen mechanism (inline width on the `aside`
in the KB-expanded branch only) keeps collapse structurally dominant and isolates
the change from the load-bearing portal/collapse layout — rejected the
PanelGroup-ify-the-layout alternative as a high-risk refactor for a small
affordance. Two new client files (`use-rail-width.ts`, `rail-resize-handle.tsx`),
both small and testable in jsdom. Width clamp + collapse-precedence + KB-only
gating are the three invariants the e2e/jsdom gates lock.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline) — this MODIFIES an existing UI surface
(the already-shipped single nav rail) to fix a presentation defect; it adds no
new page, flow, or component, and introduces no new copy or iconography. The
collapsed-drilled behavior (hide secondary nav, keep collapse-aware context band)
is already specified by the existing wireframe
`knowledge-base/product/design/navigation/single-nav-rail.pen` (collapsed-rail
frames 06/07, added in #4833) and ADR-047 — no net-new design.
**Agents invoked:** none (pipeline auto-accept on ADVISORY; existing `.pen`
covers the collapsed states)
**Skipped specialists:** none — `ux-design-lead` not required: this is a
behavioral fix to an existing surface whose collapsed-state design already exists
as a committed `.pen` (frames 06/07). No new user-facing surface is created.
**Pencil available:** N/A (no net-new UI surface; design pre-exists)

#### Findings

The fix realizes the already-decided collapse model. CPO's brainstorm dissent
(prefer icon-rail-collapse) was overridden in favor of the drill-in model with
the persistent context band as the orientation mitigation — which stays visible
and collapse-aware here. Hiding the secondary nav (vs inventing 7 Settings icons)
is the YAGNI-correct fix and matches the wireframe.

#### Amendment — widenable KB rail (UI affordance note)

**Tier:** advisory. The drag-to-widen handle is a NEW interactive affordance on an
existing surface (not a new page/flow). Per `wg-ui-feature-requires-pen-wireframe`,
a UI feature warrants a `.pen` wireframe; the existing committed wireframe
`knowledge-base/product/design/navigation/single-nav-rail.pen` (frames 06/07)
covers the rail's collapsed/expanded states but does NOT yet depict the widen
handle. **Follow-up (non-blocking for this pipeline, but tracked):** add a
"widened KB rail + edge handle" frame to that `.pen` during /work Phase 0 or at
QA so the design source of truth reflects the affordance. The visual treatment is
NOT net-new invention — it reuses the existing `ResizeHandle` idiom
(`kb-desktop-layout.tsx:17`, amber-active grip), so there is no new visual
vocabulary to design from scratch; the handle simply appears on a second edge.
The affordance is discoverable via the standard `col-resize` cursor + grip dots on
hover, consistent with the doc/chat splitter the user already uses in KB. No new
copy. `ux-design-lead` not required (reuses an existing component idiom on an
existing surface); the `.pen` frame addition is the only design follow-up.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` → only #2193 substring-
matched `(dashboard)/layout.tsx`, but #2193 is about unifying the past_due/unpaid
**billing banners** in that file — unrelated to nav-rail collapse. Acknowledge:
no fold-in; different concern, stays open.)

## Observability

This plan edits only client-side `app/(dashboard)/**` + `components/**` +
`e2e/**` + `test/**` — no `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or
`plugins/*/scripts/` code-class file, and introduces no new infrastructure
surface. Per the Phase 2.9 skip condition (no server/infra code-class file in
Files-to-Edit), the 5-field observability schema is **not required**. The
behavioral correctness signal is the `nav-states-shell.e2e.ts` headless
visual-regression gate (ADR-049), which runs in CI / `/soleur:qa` and fails loud
on overflow regression — no SSH, no dark surface.

The widenable-KB-rail amendment adds only client-side files
(`hooks/use-rail-width.ts`, `components/dashboard/rail-resize-handle.tsx`, edits to
`(dashboard)/layout.tsx` + `e2e/` + `test/`) — still no server/infra code-class
file, so the skip condition still holds. Its correctness signal is the same e2e
gate, extended with the drag/persist/clamp/precedence cases (AC9–AC14); the width
is a localStorage integer with no telemetry or backend.

## Notes

- Spec lacks `lane:` (no `spec.md` for this branch yet) — `lane: cross-domain`
  set in frontmatter (TR2 fail-closed) because the fix spans Engineering + Product.
- This is a UI fix to an already-shipped surface; the bug report's screenshots
  are pre-#4810 and were reframed (see §Premise Validation).
