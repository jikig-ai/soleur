---
title: "feat: Mobile Kanban Board Layout — Workstream Phase 3 (Option A)"
date: 2026-07-23
branch: feat-mobile-kanban-board-layout
lane: single-domain
type: enhancement
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
wireframe: knowledge-base/product/design/mobile-kanban/mobile-kanban-board-phase-3.pen
wireframe_frame: "01-mobile-kanban-option-a-status-selector.png"
design_status: operator-approved (Option A)
---

# feat: Mobile Kanban Board Layout — Workstream Phase 3 (Option A) ✨

## Enhancement Summary

**Deepened on:** 2026-07-23
**Sections enhanced:** Files to Create, Implementation Phases, Risks (precedent-diff), Research Insights added.

### Deepen-plan gate results
- **4.6 User-Brand Impact:** PASS — section present, threshold `aggregate pattern` (valid).
- **4.7 Observability:** PASS — section present with all 5 fields, non-placeholder, `discoverability_test.command` SSH-free.
- **4.8 PAT-shaped variable:** PASS — no PAT-shaped var/literal (no infra surface).
- **4.5 Network-outage:** SKIP — no trigger patterns.
- **4.4 Precedent-diff:** applied — both key patterns (scrollable tablist, CSS breakpoint dual-render) have in-repo precedents (below); no novel pattern.

### Key improvements
1. **Tablist pattern grounded** against `crm-surface.tsx` / `routines-surface.tsx` (canonical `role="tablist"`/`role="tab"`/`aria-selected` + keyboard arrows) — the selector should mirror these, not invent an a11y model.
2. **CSS breakpoint dual-render grounded** against `nav-count-badge.tsx:90` (`hidden md:flex`) — confirms the SSR-safe CSS gate (not `useMediaQuery`) is the established codebase idiom.
3. **Verify-the-negative** confirmed: the plan's presentation-only / no-new-data claim holds — no `NEXT_PUBLIC_*` exposure, no server path; the only new persistence is a client-local sessionStorage status enum.

## Overview

On viewports **below the `md` breakpoint (768px)**, the Workstream kanban board
today renders the same desktop 7-column `flex gap-3 overflow-x-auto` layout —
seven `w-72` columns crammed into a horizontal scroller, unusable on a phone.

This plan adds a **mobile-only, breakpoint-gated** layout (Option A, operator-
approved wireframe of record):

1. A horizontally-scrollable **status-selector tab strip** showing all 7
   statuses. Each tab = the column accent dot + label + a count pill. The
   selected tab carries a gold ring.
2. A single **full-width, vertically-stacked column** of the selected status's
   cards below the strip.

Tapping a tab (and, secondarily, swiping left/right on the card area) changes
the selected status. The selected status persists across reloads
(sessionStorage), defaulting to the first non-empty column, else `in_progress`.

**Desktop (md and up) is unchanged.** The existing 7-column board keeps its
exact markup and behavior; it is merely wrapped so it renders only at `md+`. The
new mobile surface is an **additive sibling** rendered only below `md`. This is a
presentation-only change — no server, API, migration, SWR, or write-path change.

## Research Reconciliation — Premise Validation & Spec vs. Codebase

**Premise validation (Phase 0.6).** All cited artifacts verified against the
worktree at plan time:

| Cited artifact | Verified | Status |
| --- | --- | --- |
| `components/workstream/workstream-board.tsx` 7-col render (~L584) + skeleton (~L624) | Read — render at L584, `BoardSkeleton` at L624 | ✅ holds |
| `components/workstream/issue-column.tsx` (dot + label + count pill, collapsible) | Read — header dot L154-158, label L159, count pill L162 | ✅ holds |
| `components/workstream/issue-card.tsx` (reusable card) | Read — `IssueCard({issue, onOpen})`, self-contained | ✅ reuse as-is |
| `components/workstream/issue-detail-sheet.tsx` | Read — portal drawer `w-full max-w-[440px]` | ✅ already mobile-full-width (see below) |
| `lib/workstream.ts` `COLUMNS` + `WorkstreamStatus` + filter/search | Read — 7 `COLUMNS` w/ `accent`, `matchesFilters`/`matchesSearch` | ✅ holds |
| Wireframe `.pen` + operator sign-off | `ls` — `mobile-kanban-board-phase-3.pen` (87 KB) + `screenshots/` present | ✅ committed |
| `useMediaQuery` hook | Read — `hooks/use-media-query.ts`, `(min-width: 768px)` precedent in `sheet.tsx` | ✅ available |
| `safe-bottom` / `safe-top` utilities | `globals.css` L206-210 — `env(safe-area-inset-*)` | ✅ available |
| Gold token | `bg-soleur-gold` / `border-soleur-gold` used across components | ✅ `ring-soleur-gold` valid |

**Spec vs. codebase divergences that shape the plan:**

| Spec/description claim | Codebase reality | Plan response |
| --- | --- | --- |
| "confirm the detail sheet is usable as a mobile bottom sheet or note minimal changes" | `IssueDetailSheet` is a **custom portal overlay** (`fixed inset-0`, panel `w-full max-w-[440px]`), NOT the shared `Sheet` primitive. On a <440px viewport it already renders full-width right-slide-in. | **No change required.** It is already usable on mobile (full-width). Not converting it to a bottom sheet — out of scope and unnecessary. The mobile board reuses the parent's existing `openIssue` → same `?issue` URL sync + same drawer. |
| Board owns `filtered` (post search+filter), `openIssue`, collapse persistence | Confirmed — `filtered` (L464-470) already applies `matchesSearch` + `matchesFilters`; `openIssue`/`closeIssue` push/replace `?issue`. Collapse persistence is desktop-column-specific (`toggleCollapse`, localStorage). | Mobile board consumes the **same `filtered` array + `openIssue`** → filters/search/URL-sync are preserved for free. Collapse persistence stays desktop-only (mobile has no collapsible columns). |
| "useOptionalFeatureFlag/breakpoint patterns" | `useOptionalFeatureFlag` exists but gates *feature* rollouts; this is a **layout** gate. | Gate with a **pure Tailwind breakpoint** (`hidden md:flex` / `md:hidden`), NOT a runtime flag — SSR-safe, no hydration flash, no flag lifecycle. No new flag. |

## User-Brand Impact

**If this lands broken, the user experiences:** a phone user opening Workstream
sees either a blank card area, the wrong status's cards, or a duplicated/overlapping
board (mobile + desktop both visible) — the mobile board is the *only* usable
kanban surface on a phone, so a regression makes the feature unusable on mobile.

**If this leaks, the user's data/workflow is exposed via:** N/A — presentation-only.
No new data read, no new endpoint, no new persistence beyond a client-local
sessionStorage `selectedStatus` string (a status enum value, not user data).

**Brand-survival threshold:** aggregate pattern. This is a UI/presentation change
over the already-fetched, already-authorized issue set; a regression degrades the
mobile Workstream UX across users but carries no single-user data/money/exposure
vector. No CPO per-PR sign-off required; no sensitive path touched.

## Files to Create

- **`apps/web-platform/components/workstream/mobile-board.tsx`** — the mobile
  board container (`"use client"`). Props: `{ issues: WorkstreamIssue[]; onOpen: (id: string) => void; className?: string }`. Owns:
  - `selectedStatus` state (`WorkstreamStatus`) + sessionStorage persistence.
  - Per-status counts derived from the passed (already-filtered) `issues`.
  - Renders `<MobileStatusSelector>` + the single vertical card column
    (reusing `<IssueCard>`), plus the per-column empty state and the
    `COLUMN_RENDER_CAP` / `COLUMN_CAP_NOTICE` cap (mirrors `issue-column.tsx`).
  - Optional lightweight touch swipe (left/right) on the card area to advance
    to the prev/next **non-empty-or-any** status in `STATUS_ORDER`.
- **`apps/web-platform/components/workstream/mobile-status-selector.tsx`** — the
  horizontally-scrollable tab strip (`"use client"`). Props:
  `{ columns: readonly ColumnConfig[]; counts: Record<WorkstreamStatus, number>; selected: WorkstreamStatus; onSelect: (s: WorkstreamStatus) => void }`.
  Each tab: accent dot (`style={{ backgroundColor: column.accent }}`) + label +
  count pill; selected tab gets `ring-2 ring-soleur-gold` + `aria-selected`.
  Uses `role="tablist"` / `role="tab"`; 44px min touch target; `overflow-x-auto`.

## Files to Edit

- **`apps/web-platform/components/workstream/workstream-board.tsx`** — minimal
  desktop diff, three edits, all inside the final render branch (L584-596) plus
  imports:
  1. Add `import { MobileBoard } from "./mobile-board";`.
  2. Gate the existing 7-column div: `className="flex gap-3 overflow-x-auto pb-4"`
     → `className="hidden md:flex gap-3 overflow-x-auto pb-4"`.
  3. Add a sibling immediately after it:
     `<MobileBoard issues={filtered} onOpen={openIssue} className="md:hidden" />`.
  - `BoardSkeleton` (L622), `EmptyState`, `NoResults` are shared pre-board states;
    they are mobile-acceptable as-is → **no change** (keeps desktop diff minimal).

**No other files change.** `issue-card.tsx`, `issue-detail-sheet.tsx`,
`issue-column.tsx`, `lib/workstream.ts`, `filter-bar.tsx` are untouched
(reused/imported only).

## Implementation Phases

### Phase 1 — `MobileStatusSelector` (presentational)
- New file `mobile-status-selector.tsx`. Pure presentational tablist:
  scrollable row of tabs; each = dot + label + count pill; selected = gold ring.
- Brand conventions: `text-base` (mobile-only surface), 44px min tab height
  (`min-h-[44px]`), brand tokens (`text-soleur-text-*`, `bg-soleur-bg-surface-*`,
  `ring-soleur-gold`), accent dot from `column.accent`.
- A11y (mirror `crm-surface.tsx` / `routines-surface.tsx`): `role="tablist"` on
  the strip, `role="tab"` + `aria-selected` per tab, roving `tabIndex`
  (selected 0, rest -1), left/right Arrow keydown moves selection,
  `aria-controls` → the card-column region id (`role="tabpanel"` +
  `aria-labelledby` the active tab).

### Phase 2 — `MobileBoard` (state + column)
- New file `mobile-board.tsx`. State: `selectedStatus`.
  - **Persistence:** on mount, read `sessionStorage["workstream:mobile-status-v1"]`;
    if it is a valid `WorkstreamStatus`, use it; else default to the first column
    in `STATUS_ORDER` whose count > 0, else `"in_progress"`. Write on every change.
    Guard `sessionStorage` access in try/catch (SSR/private-mode safe), mirroring
    `readCollapsedColumns` in the board.
  - **Counts:** `counts[status] = issues.filter(i => i.status === status).length`
    over the passed-in already-filtered `issues` → respects active filters+search.
  - Render `<MobileStatusSelector columns={COLUMNS} counts={counts} selected onSelect>`
    then the selected column: `issues.filter(i => i.status === selectedStatus)`,
    `.slice(0, COLUMN_RENDER_CAP)` → `<IssueCard>` list, `COLUMN_CAP_NOTICE` when
    over cap, and a per-column empty message ("No issues in {statusLabel}") when
    the selected status is empty.
  - Card-column region: `id` referenced by the selector's `aria-controls`,
    `role="tabpanel"`, `safe-bottom` padding on the scroll container.
  - **Selection stability:** a filter/search change that empties the selected
    status does NOT auto-jump — the strip keeps the tab selected and the column
    shows its empty message (predictable; the user chose that tab). Counts on all
    tabs still update live.
- Optional **swipe**: `onTouchStart`/`onTouchEnd` on the card region; horizontal
  delta beyond a threshold advances `selectedStatus` to the prev/next entry in
  `STATUS_ORDER` (clamped at ends). Keep it self-contained; no external dep.

### Phase 3 — Wire into `WorkstreamBoard` (minimal desktop diff)
- Import `MobileBoard`; add `hidden md:flex` to the existing board div; add the
  `<MobileBoard … className="md:hidden" />` sibling. Nothing else in the parent
  changes — `filtered`, `openIssue`, drawer, toasts, read-only, board precedence
  all continue to flow through the unchanged parent.

### Phase 4 — Tests + typecheck
- Component tests (see Test Scenarios) go in the flat `test/` dir as
  `apps/web-platform/test/workstream-mobile-board.test.tsx` — verified against
  `vitest.config.ts`: the `component` project uses `environment: "happy-dom"` and
  `include: ["test/**/*.test.tsx"]` (sibling precedent: `test/workstream-nav-badge.test.tsx`).
  A co-located `components/**/*.test.tsx` is NOT collected.
- Typecheck: `cd apps/web-platform && npm run typecheck` (`tsc --noEmit`). Test:
  `npm run test:ci` (`vitest run`) or scoped `./node_modules/.bin/vitest run test/workstream-mobile-board.test.tsx`. Do NOT assume `bun test`.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] Below `md` (e.g. 375px), the Workstream board renders the status-selector
      strip (7 tabs, each dot+label+count) + a single full-width card column; the
      desktop 7-column scroller is NOT visible.
- [ ] At `md+` (e.g. 1024px), the desktop 7-column board renders **unchanged**
      and the mobile board is NOT visible (verified via `hidden md:flex` /
      `md:hidden` classes + a rendered-DOM assertion).
- [ ] Tapping a status tab swaps the visible card column to that status; the
      tapped tab shows the gold ring + `aria-selected="true"`.
- [ ] Tab count pills equal `filtered.filter(status).length` and **update when a
      filter or the search box changes** (mobile respects active filters+search).
- [ ] Tapping a card calls the parent `openIssue` → the URL gains `?issue=<id>`
      and the existing `IssueDetailSheet` opens (URL↔drawer sync preserved).
- [ ] Selected status persists across reload via sessionStorage; default with no
      stored value = first non-empty column in `STATUS_ORDER`, else `in_progress`.
- [ ] A selected status with 0 (post-filter) cards shows the per-column empty
      message; a status over `COLUMN_RENDER_CAP` shows the exact `COLUMN_CAP_NOTICE`.
- [ ] Tabs are ≥44px touch targets; the card-column scroller carries `safe-bottom`.
- [ ] Tabs follow the codebase tab a11y model: `role="tablist"`/`role="tab"`,
      `aria-selected`, roving `tabIndex`, left/right Arrow moves selection; the
      card region is `role="tabpanel"` labelled by the active tab.
- [ ] Desktop-side diff in `workstream-board.tsx` is exactly: one import, one
      className edit, one sibling element (no changes to write handlers, SWR,
      collapse persistence, drawer, toolbar).
- [ ] `tsc --noEmit` clean; new component tests pass under the configured runner.
- [ ] No new dependency added (swipe is hand-rolled touch handlers).

## Domain Review

**Domains relevant:** Product (UX).

### Product/UX Gate

**Tier:** blocking (mechanical escalation — two new `components/**/*.tsx` files).
**Decision:** reviewed — **satisfied via approved wireframe of record (carry-forward).**
**Agents invoked:** ux-design-lead (wireframe committed prior to this plan).
**Skipped specialists:** none.
**Pencil available:** N/A (wireframe already produced + committed).

#### Findings

The design gate is **already closed**: Option A is operator-approved, with the
binding wireframe committed at
`knowledge-base/product/design/mobile-kanban/mobile-kanban-board-phase-3.pen`
(frame `01-mobile-kanban-option-a-status-selector.png`). Per the pipeline
instruction, this plan does **not** re-open the design gate or re-run
ux-design-lead — it records ux-design-lead as invoked (wireframe committed) with
operator sign-off. Implementation follows the approved wireframe. No other
business domain (Engineering-only, presentation-tier) is materially implicated.

## Observability

Presentation-only client UI; no new server, telemetry, or infra surface (Files to
Edit are under `apps/web-platform/components/**`, outside the code/infra trigger
set). Declared for completeness:

```yaml
liveness_signal:    { what: "mobile board renders below md", cadence: "on page load", alert_target: "none (client UI)", configured_in: "workstream-board.tsx breakpoint gate" }
error_reporting:    { destination: "existing board-level error/toast surfaces (unchanged)", fail_loud: "N/A — no new fallible path" }
failure_modes:      [ { mode: "sessionStorage unavailable (private mode/SSR)", detection: "try/catch guard → default status", alert_route: "none — graceful default" }, { mode: "both boards visible (breakpoint gate regression)", detection: "component test asserts hidden/md: classes", alert_route: "CI test failure" } ]
logs:               { where: "none new (browser only)", retention: "N/A" }
discoverability_test: { command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/workstream-mobile-board.test.tsx", expected_output: "mobile board renders selector + selected column; hidden md: gate present" }
```

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (60 open) checked against
`workstream-board.tsx`, `issue-column.tsx`, `issue-detail-sheet.tsx` — no open
scope-out references any Workstream board file.

## Test Scenarios

Vitest + Testing Library (`component` project, `environment: "happy-dom"`, glob
`test/**/*.test.tsx`). File: `test/workstream-mobile-board.test.tsx`. Drive the
breakpoint via class assertions rather than real media queries where possible.

1. **Selector renders 7 tabs** with correct label + count pill from a fixture
   issue set; selected tab has the gold-ring class + `aria-selected="true"`.
2. **Tab tap** swaps the visible card column to the tapped status and updates
   `aria-selected`.
3. **Counts respect filters** — re-render with a reduced `issues` prop (simulating
   an active filter) and assert every tab's count reflects the filtered set.
4. **Card tap** invokes the `onOpen` prop with the issue id.
5. **Persistence** — a stored valid status in sessionStorage is honored on mount;
   with none, the default is the first non-empty column, else `in_progress`.
6. **Empty selected status** shows the per-column empty message; over-cap shows
   the exact `COLUMN_CAP_NOTICE`.
7. **Breakpoint gate** — in `workstream-board.tsx`, the desktop board div has
   `hidden md:flex` and the mobile board has `md:hidden` (rendered-DOM class
   assertion; both subtrees present in the DOM, gated by CSS).

## Research Insights (Precedent-Diff, Phase 4.4)

**Scrollable tablist pattern — precedent exists (not novel).** The mobile status
selector must adopt the codebase's established tab a11y model, not invent one:

- `apps/web-platform/components/crm/crm-surface.tsx:164-172` — `role="tablist"`
  wrapper, per-tab `role="tab"` + `aria-selected={view === v}`.
- `apps/web-platform/components/routines/routines-surface.tsx:164-210` — same,
  with a reusable tab-button sub-component.

Apply verbatim: `role="tablist"` on the strip; each tab `role="tab"`,
`aria-selected`, `tabIndex` roving (selected = 0, others = -1), and left/right
Arrow keydown to move selection (keyboard parity — a `role="tab"` control that
ignores arrows is an a11y regression). The card region gets `role="tabpanel"` +
`aria-labelledby` the selected tab. This is the ONLY novel-looking surface; it is
in fact well-precedented.

**CSS breakpoint dual-render — precedent exists (not novel).**
`apps/web-platform/components/dashboard/nav-count-badge.tsx:90` already uses the
`hidden md:flex` dual-render idiom ("Only exists when collapsed, only paints at
md+"). Confirms the plan's choice: gate with Tailwind classes, keep both subtrees
in the DOM, do NOT branch on `useMediaQuery` (which renders `false` on the server
and flashes on hydration). `useMediaQuery` is reserved for cases that must portal
or measure (e.g. `sheet.tsx`), not for a static layout swap.

**Cap + accent + count parity with `issue-column.tsx`.** The mobile column reuses
the SAME `COLUMN_RENDER_CAP` slice, the SAME exact `COLUMN_CAP_NOTICE` copy, the
SAME `column.accent` dot, and count = `issues.filter(status).length` — do not
re-derive or re-word any of these (tests assert `COLUMN_CAP_NOTICE` verbatim; the
count pill must show the true post-filter total, matching the desktop column's
rule that the cap limits rendered cards, never the displayed count).

**No new dependency for swipe.** The optional swipe is hand-rolled
`onTouchStart`/`onTouchEnd` delta math inside `mobile-board.tsx` — no gesture lib.
Keep it guarded (ignore near-vertical drags so it doesn't fight page scroll).

## Risks & Sharp Edges

- **Both-boards-visible regression.** The gate is pure CSS (`hidden md:flex` +
  `md:hidden`) — both subtrees are in the DOM; only CSS hides one. A dropped/typo'd
  class shows both. Mitigation: AC + Test Scenario 7 assert the exact gate classes.
- **`useMediaQuery` is NOT used for the gate** (would flash on SSR: server renders
  `matches=false`). CSS gating is SSR-safe and matches the wireframe brief
  ("hidden md:flex etc."). Do not "simplify" to a `useMediaQuery` conditional render.
- **Reusing the same `IssueCard`** means card interior styling is shared with
  desktop; that is intended (single card design). The mobile column is full-width,
  so cards stretch — verify line-clamp/overflow at 320px.
- **Detail sheet is a right-slide overlay, not a bottom sheet.** On mobile it is
  already full-width (`w-full max-w-[440px]`), so no change is made. If a true
  bottom-sheet is later desired, that is a separate change (out of scope here).
- **Test path must satisfy the runner's discovery glob.** `vitest.config.ts`
  `component` project collects `test/**/*.test.tsx` (happy-dom) — a co-located
  `components/**/*.test.tsx` is silently skipped. Place the test at
  `test/workstream-mobile-board.test.tsx`; do not assume `bun test`.
- **A plan whose `## User-Brand Impact` section is empty or placeholder fails
  `deepen-plan` Phase 4.6.** This section is filled (threshold: aggregate pattern).

## Out of Scope

- Option B (snap-scroll board toggle) — deferred; not this PR.
- Other Phase-3 items: tables→cards elsewhere, ⌘K mobile sheet, KB touch,
  `next/image`, list virtualization — separate work.
- Converting `IssueDetailSheet` to a bottom sheet — unnecessary (already
  full-width on mobile).
- Any desktop board behavior change, new feature flag, ADR, server/API/migration
  change, or new runtime dependency.

## Deploy Note

Repo-wide deploy is currently blocked by unrelated #6852 / #6860. This PR is
presentation-only and merges green; it will not deploy until #6860 resolves. Do
not touch the deploy pipeline in this PR.
