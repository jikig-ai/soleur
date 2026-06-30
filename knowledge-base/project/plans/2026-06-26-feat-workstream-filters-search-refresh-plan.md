---
title: "feat: Workstream board — filter bar, search composition, render cap, collapse animation, reset + refresh"
date: 2026-06-26
type: feat
branch: feat-one-shot-workstream-filters-search-refresh
lane: single-domain
brand_survival_threshold: none
status: draft
---

# feat: Workstream kanban — filtering, search, per-column cap, polished collapse, reset + refresh

✨ Client-only enhancement to the Workstream kanban board. Adds a 4-dimension filter
bar composable with the existing text search, a 200-card per-column render cap, an
empty-column "no toggle" rule, a real width+opacity collapse animation, and Reset +
Refresh top-bar controls. No data-layer / GitHub-reader / API-route changes.

## Enhancement Summary

**Deepened on:** 2026-06-26
**Agents used:** spec-flow-analyzer (flow gaps), code-simplicity-reviewer (YAGNI),
architecture-strategist (layering + blast radius), framework-docs-researcher (SWR/Tailwind).

### Key improvements applied
1. **BLOCKER fixed (arch review):** `domains` changed from **required** → **optional**
   (`domains?: string[]`). A required field would have broken `new-issue-dialog.tsx:63-73`
   (production) + 4 test fixtures and failed the `tsc --noEmit` AC
   (`hr-type-widening-cross-consumer-grep`). Optional ⇒ inert for every existing constructor.
2. **Status simplified (simplicity review):** `Set<"open"|"closed">` + normalization →
   tri-state `"all"|"open"|"closed"` radio. Removes the normalization step + its test.
3. **Coupling hardened (arch review):** shared `CLOSED_STATUSES` set as the single source of
   truth for both `deriveColumn`'s closed branch and `isClosed`, + a round-trip test.
4. **Regression lock (arch review/SE1):** column tests now assert the *opposite* toggle
   button is ABSENT in each state, catching a both-mounted cross-fade that would break the
   aria contract.
5. **Confirmed sound (framework-docs):** SWR **2.4.1** — `mutate()` returns a Promise
   (`.catch` for refresh-failure), `isValidating` drives the spinner without gating the
   first-load skeleton, `mutate()` leaves React filter/search state untouched. Tailwind
   **4.1.0** — `motion-reduce:transition-none` + named transitions valid; no
   `tailwindcss-animate`, so the rAF mount-reveal is the correct path.

### New considerations
- **Domain (1d) is the lowest-value dimension** and the first to defer under scope pressure
  (redundant with the role facet for single-domain issues). Kept because the optional field
  is genuinely inert; routed to operator/UX sign-off (D1).
- `deriveFilterOptions` drops `statuses` (Status is a fixed tri-state control, nothing to
  derive).

## Overview

The board (`workstream-board.tsx`, client) SWR-fetches `/api/workstream/issues`, holds a
`search` string + a localStorage-persisted collapsed-columns `Set`, filters by search,
then renders the 7 fixed `COLUMNS` via `IssueColumn`. `lib/workstream.ts` holds the pure
data model (`WorkstreamIssue`), `COLUMNS`, the GitHub-issue → board mapper, and label
helpers. This plan layers filtering/search/refresh/reset state + a render cap into the
board, refactors the column for a real collapse animation + empty/cap rules, adds a new
`FilterBar` component, and adds **pure** filter/option-derivation helpers (+ one additive
model field) to `lib/workstream.ts`.

Everything operates over the **already-fetched** issue set. The reader
(`server/github-read-tools.ts:listRepoIssues`), the accessor
(`server/workstream/get-workstream-issues.ts`), and the route are **untouched**.

## Research Reconciliation — Spec vs. Codebase

The spec's "all client-side over the already-fetched issue set" framing collides with the
current model in two places. Both resolved without any IO/reader/route change.

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| (1c)/(1d) "filter by Status open/closed" | `WorkstreamIssue` carries **no raw `state`** field. `deriveColumn` maps `state==="closed"` → `done`/`cancelled` and `state==="open"` → the other five, and **only** those mappings (`lib/workstream.ts:273-290`). | Derive openness from the column: `isClosed ⟺ status ∈ {done, cancelled}`. The biconditional is sound + complete for GitHub-sourced issues (spec-flow confirmed). Caveat: an optimistic local `changeStatus` to done/cancelled also reads as closed — semantically correct. |
| (1d) "filter by domain/* labels" | `WorkstreamIssue` **drops** the raw `labels` array; only the **first** `domain/*` label survives, collapsed into `assigneeRole` (`deriveRole`). A domain filter has no multi-label data, and would be **redundant** with the role facet. | Add an **OPTIONAL** `domains?: string[]` field to `WorkstreamIssue`, populated by the existing **pure** mapper from `input.labels` (which the reader already passes into `BoardIssueInput`). **Optional, NOT required** — a required field would break every existing construction site (arch review: `new-issue-dialog.tsx:63-73` production + 4 test fixtures) and fail the `tsc` AC (`hr-type-widening-cross-consumer-grep`). Optional ⇒ truly inert for existing constructors; consumers read `(i.domains ?? [])`. Lib-only, node-testable, no IO/reader/route change. Makes (1d) real (all `domain/*` labels) and **distinct** from (1c)-role. See Decision Log D1. |
| "lib/workstream.ts only for a small pure filter predicate helper" | The predicate needs `isClosed` + option-derivation + the additive `domains` field. | Scope to `lib/workstream.ts` stays honored — all additions are pure + node-testable in the same leaf module. No `components/` import, no IO. |

## User-Brand Impact

**If this lands broken, the user experiences:** the Workstream board renders wrong/empty
columns, a stuck collapse animation, or a filter bar that can't be cleared — the operator
can't triage their connected-repo issues on the board (degraded, not destructive; the
underlying issue feed is read-only and unchanged).

**If this leaks, the user's data is exposed via:** no new exposure vector — the feature
reads the **same** already-fetched issue feed and renders it client-side; it adds no
network call, no persistence, no new field sourced from outside the existing payload.

**Brand-survival threshold:** none — `threshold: none, reason: client-only, read-only
preview UI over an already-fetched feed; no persistence, no new data surface, no auth/PII
path.`

## Decision Log

- **D1 — OPTIONAL `domains?: string[]` model field (RESOLVES the 1d premise gap).** The pure
  mapper sets `input.labels.filter(l => l.startsWith("domain/"))` on each `WorkstreamIssue`;
  every reader uses `(i.domains ?? [])`. **Optional, not required** — arch review showed a
  required field breaks `new-issue-dialog.tsx:63-73` (production optimistic card) + the
  `workstream-helpers`/`workstream-tools`/`issue-card`/`issue-detail-sheet` test fixtures and
  fails the `tsc --noEmit` AC (`hr-type-widening-cross-consumer-grep`). Optional ⇒ inert for
  every existing constructor (the field is absent, which is valid) and for every reader.
  Lib-only, pure, node-testable; reader/accessor/route untouched. Rejected alternative: cut
  (1d) and merge into the role facet — rejected because the spec lists 4 dimensions and the
  role facet is first-domain-only. **YAGNI note (simplicity review):** Domain is the
  lowest-value dimension (redundant with the role facet for single-domain issues; only
  multi-domain issues differentiate it) — **first to defer under scope pressure**, but cheap
  to keep since the optional field is genuinely inert. Operator/UX may defer (1d) at sign-off.
- **D2 — Assignee is ONE dimension combining role + person, OR-within.** Selecting
  "CTO" OR person "alice" matches issues assigned to either. Rejected: separate role/person
  dimensions AND-ed together — would yield near-always-empty results (role is domain-derived,
  user is the assignee login; rarely both on one issue). Includes an explicit **"Unassigned"**
  option (`assigneeRole === null && !user`) — otherwise unassigned issues are unreachable
  under "hide empty options" (spec-flow F8).
- **D3 — Faceting derives options from the FULL loaded `issues` set**, not the post-filter
  set (spec-flow F1). Stable options, no mid-interaction thrash; "hide empty options" =
  "present in the loaded set". On Refresh the loaded set changes → options recompute.
- **D4 — Status is a TRI-STATE `"all" | "open" | "closed"`, default `"all"`** (simplicity
  review: a `Set<"open"|"closed">` forces a normalization step whose only job is to keep
  "ticked both = inactive" true). Status is intrinsically tri-state; a radio (All / Open /
  Closed) is the honest control. `statusActive ⇔ status !== "all"`. Predicate: `"all"` ⇒ pass;
  else `isClosed(i) === (status === "closed")`. No Set, no normalization, no normalization
  test.
- **D5 — Filters are in-memory (NOT persisted), matching the existing `search` precedent.**
  Collapsed columns stay persisted (unchanged). Documented non-persistence (spec-flow F9).
- **D6 — Refresh replaces optimistic local cards** (New Issue / status-move). `mutate()`
  with revalidate is the spec's prescription; the board already advertises "Preview —
  changes aren't saved yet," so authoritative refetch superseding ephemeral preview state is
  consistent and honest. No confirm dialog (keep minimal). Documented (spec-flow F4). Filters
  + search are React state, untouched by `mutate()`, so they survive a refresh automatically.

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)
- `grep -nE "export type WorkstreamStatus|export interface WorkstreamIssue" apps/web-platform/lib/workstream.ts` — confirm current model shape.
- Confirm vitest include globs: node `["test/**/*.test.ts","lib/**/*.test.ts"]`, jsdom `["test/**/*.test.tsx"]` (`apps/web-platform/vitest.config.ts:44,64`). New predicate tests MUST land at `test/**/*.test.ts`; component tests at `test/components/workstream/*.test.tsx` (co-located `components/**/*.test.tsx` would be **silently skipped**).
- Confirm icons available (no new icon needed): `SearchIcon`, `ChevronDownIcon`, `RefreshIcon`, `CheckCircleIcon`, `XCircleIcon` (`components/icons/index.tsx`).
- Confirm `bunfig.toml [test] pathIgnorePatterns = ["**"]` — tests run under **vitest only**: `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`. (Never `bun test`, never `npm run -w`.)

### Phase 1 — `lib/workstream.ts`: pure model + predicates (RED tests first)
1. **Optional model field** (D1): add `domains?: string[]` to `WorkstreamIssue`; populate in `githubIssueToWorkstreamIssue` via `...(domains.length ? { domains } : {})` where `domains = input.labels.filter(l => l.startsWith("domain/"))` (mirrors the existing `...(user ? {user} : {})` spread idiom). Optional ⇒ existing constructors + mapper tests stay green; `new-issue-dialog.tsx` untouched.
2. **Shared closed-status source + derivation** (arch review — removes the implicit `deriveColumn`↔`isClosed` coupling): `export const CLOSED_STATUSES: ReadonlySet<WorkstreamStatus> = new Set(["done", "cancelled"]);` and `export function isClosed(i: WorkstreamIssue): boolean { return CLOSED_STATUSES.has(i.status); }`. (Optionally have `deriveColumn`'s closed branch reference the same set.)
3. **Filter-state type + pure predicate** (the "small pure filter helper" the scope allows):
   ```ts
   export interface WorkstreamFilters {
     priorities: Set<WorkstreamPriority>;
     status: "all" | "open" | "closed";        // D4 tri-state, default "all"
     roles: Set<WorkstreamRole>;
     users: Set<string>;                       // user.name
     unassigned: boolean;                      // assignee dimension: include unassigned
     domains: Set<string>;                     // domain/* label
   }
   export function matchesFilters(i: WorkstreamIssue, f: WorkstreamFilters): boolean
   // AND across dimensions, OR within. Empty/"all" dimension ⇒ pass.
   // Priority: priorities.size === 0 || priorities.has(i.priority)
   // Status (D4): f.status === "all" || isClosed(i) === (f.status === "closed")
   // Assignee (D2): roles/users empty && !unassigned ⇒ pass; else
   //   (i.assigneeRole && roles.has(i.assigneeRole)) || (i.user && users.has(i.user.name))
   //   || (unassigned && i.assigneeRole === null && !i.user)
   // Domain: domains.size === 0 || (i.domains ?? []).some(d => domains.has(d))
   export function hasActiveFilters(f: WorkstreamFilters, search: string): boolean
   // search.trim() !== "" || priorities.size || status !== "all" || roles.size || users.size || unassigned || domains.size
   export function emptyFilters(): WorkstreamFilters   // status: "all", all sets empty, unassigned false
   ```
4. **Option derivation** (D3) from the full loaded set — pure:
   `export function deriveFilterOptions(issues: WorkstreamIssue[]): { priorities; roles; users; hasUnassigned; domains }` (each a de-duplicated, order-stable list present in the set). **No `statuses`** — Status is the fixed `all/open/closed` tri-state control, nothing to derive (simplicity review).
5. **Constants:** `export const COLUMN_RENDER_CAP = 200;` and
   `export const COLUMN_CAP_NOTICE = "Some board columns are showing up to 200 issues. Refine filters or search to reveal the rest.";` (EXACT string — the spec mandates this verbatim copy; single source of truth, asserted by tests).
6. Tests → `test/workstream-filters.test.ts` (node): each dimension predicate; OR-within; AND-across; assignee combined-OR incl. Unassigned; `isClosed` for all 7 statuses + a **round-trip test** (every status `deriveColumn` yields for `state:"closed"` ∈ `CLOSED_STATUSES`); status tri-state (all/open/closed); `matchesFilters` ∘ search composition; `deriveFilterOptions` hides empty options + surfaces all domains of a multi-domain issue; `hasActiveFilters` true/false incl. `status !== "all"`.

### Phase 2 — `filter-bar.tsx` (NEW component)
- Props: `{ options: ReturnType<typeof deriveFilterOptions>; filters: WorkstreamFilters; onChange: (f) => void; }`.
- One dropdown per dimension (Priority, Status, Assignee, Domain), each a button labelled with the dimension + an active marker, opening a menu (closes on outside-click + Escape). Priority/Assignee/Domain are **multi-select checkbox** menus; **Status is a 3-option radio** (All / Open / Closed, default All) — no normalization. Assignee menu lists roles, then persons, then "Unassigned". Hide Priority/Assignee/Domain dimensions whose option list is empty; Status is always shown (fixed control).
- **Square corners per brand** for the new filter chrome (`rounded-none`), gold accent on active state via existing soleur tokens / `GOLD_GRADIENT`. **Flag (Domain Review):** the existing board chrome is `rounded-lg`/`rounded-xl`; square filter controls are an intentional brand choice to confirm at wireframe review.
- Accessible: each menu is a labelled group of checkboxes (queryable by role for tests).
- Tests → `test/components/workstream/filter-bar.test.tsx`: options render + empty-dimension hidden; toggling a checkbox calls `onChange` with the right Set mutation; active-count badge reflects selection.

### Phase 3 — `workstream-board.tsx` (state + composition + top bar)
1. Add `const [filters, setFilters] = useState(emptyFilters())`.
2. `const options = useMemo(() => deriveFilterOptions(issues ?? []), [issues])` (full set, D3).
3. Compose: `visible = (issues ?? []).filter(i => matchesSearch(i, q) && matchesFilters(i, filters))`. Per-column: `visible.filter(i => i.status === column.status)` → pass to `IssueColumn` (which caps at render — Phase 4).
4. Render `<FilterBar options filters onChange={setFilters} />` above the board row.
5. **Reset** button (top bar): `disabled={!hasActiveFilters(filters, search)}`; onClick `setFilters(emptyFilters()); setSearch("")`. (Disabled-not-hidden → stable layout; D4/F7.)
6. **Refresh** button: onClick `void mutate()` (revalidate). Spinner via SWR `isValidating` while refetching. Track refresh failure: `mutate().catch(...)` → small inline "Couldn't refresh — showing last loaded" near the button (spec-flow F11). Filters/search are React state, untouched by `mutate()` → retained automatically (D6).
7. **Combined empty state** (spec-flow F6): replace the search-only `NoResults`. When `issues.length > 0 && visible.length === 0` → "No issues match your filters or search." with a single **Reset filters** action (clears filters **and** search). Keep the true `EmptyState` (`issues.length === 0` → New Issue CTA) and `ErrorCard` branches. Fixes the current blank-quote `No issues match ""` bug when filters (not search) empty the board.
8. Drawer is unaffected: `selected` resolves from the **full** `issues` set, so a card filtered out while its drawer is open does not dead-end (spec-flow F10) — documented, no special handling.
9. Tests (extend `workstream-board.test.tsx`): filter+search composition narrows columns; Reset clears **all four dims + search**; Refresh calls the fetcher again **and** a card excluded by an active filter stays excluded after refresh (filters not dropped); combined filtered-empty state shows "Reset filters".

### Phase 4 — `issue-column.tsx` (animation + empty rule + cap)
**Load-bearing refactor (see Sharp Edges SE1).** Replace the `if (collapsed) return <strip>` early-return with a **single persistent `<section>`** whose **width** transitions:
- Section: persistent across the toggle, `className` toggles `w-72 ↔ w-10`, with `transition-[width] duration-200 ease-out motion-reduce:transition-none` (named transition — never `transition-all`, anti-slop Tier-1). Width animates **because the element persists**.
- Inner content (expanded body vs collapsed strip) is conditionally rendered and wrapped in a **rAF mount-reveal** (opacity `0→1` via a `requestAnimationFrame` state flip, `transition-opacity motion-reduce:transition-none`) — the `cta-banner.tsx` idiom (learning 2026-06-09) — satisfying "content opacity". Only **one** control button exists at a time (Collapse when expanded / Expand when collapsed) → the existing aria-label / `aria-expanded` contract + `getByRole("Collapse|Expand …")` tests stay green.
- **Empty-column rule** (req 3 / spec-flow F3): when `issues.length === 0`, render the **expanded** "No issues" layout with **NO toggle button** (ignore the persisted `collapsed` flag while empty). The localStorage collapsed-set is **not** mutated, so when Reset/Refresh repopulates the column the persisted collapsed state re-applies.
- **200-cap** (req 2): render `issues.slice(0, COLUMN_RENDER_CAP)`; when `issues.length > COLUMN_RENDER_CAP`, render `COLUMN_CAP_NOTICE` (EXACT, imported) at the **bottom of the column's card area**. The header count pill shows the **true** `issues.length` (honest total). Notice only appears in the expanded layout (a collapsed strip shows no cards).
- Tests (extend `issue-column.test.tsx`): empty column has **no** Collapse and **no** Expand button; **expanded state asserts the `Expand` button is ABSENT and collapsed state asserts the `Collapse` button is ABSENT** (locks "one control at a time" against a both-mounted cross-fade regression — arch review Q3/SE1); 201 issues → exactly 200 cards + the exact `COLUMN_CAP_NOTICE` string; <=200 → no notice; one minimal animation-class assertion (`transition-[width]` + `motion-reduce:transition-none` on the persistent section — a change-detector, kept only as the cheapest guard against re-introducing the inert conditional-swap); existing tint + icon-button assertions stay green.

## Acceptance Criteria

### Filtering & search
- [ ] Filter bar renders 4 dimensions (Priority, Status, Assignee, Domain); a dimension with zero options in the loaded set is hidden.
- [ ] Within a dimension = OR; across dimensions = AND; all composed on top of the text search.
- [ ] Status defaults to **All** (both open and closed); selecting Open or Closed narrows; back to All = inactive (tri-state radio, no normalization).
- [ ] Assignee dimension matches role OR person OR "Unassigned" (combined-OR).
- [ ] Domain dimension filters on real `domain/*` labels (multi-label), distinct from the role facet.
- [ ] Options derived from the full loaded issue set (do not thrash as filters narrow).

### Render cap
- [ ] A column with >200 post-filter cards renders exactly the first 200 + the EXACT notice `Some board columns are showing up to 200 issues. Refine filters or search to reveal the rest.` at the column bottom. The count pill shows the true total. (Separate from the 500-issue fetch cap.)

### Empty column
- [ ] A column with 0 post-filter issues shows neither a Collapse nor an Expand toggle and is not collapsible/openable; its persisted collapsed state is untouched and re-applies when it repopulates.

### Collapse animation
- [ ] Collapse/expand animates column width (72 ↔ strip) + content opacity over ~200ms ease; under `prefers-reduced-motion` the change is instant (`motion-reduce:` reset).
- [ ] localStorage collapsed-set + `aria-label`/`aria-expanded` contract preserved (existing board + column tests green).

### Reset & Refresh
- [ ] "Reset filters" clears all 4 dimensions AND the search box; disabled when nothing is active.
- [ ] "Refresh" refetches via SWR `mutate()` (revalidate), keeps active filters/search applied to the fresh set, and shows a brief loading affordance; a refresh failure with existing data shows an inline notice (data retained).

### Regressions
- [ ] All existing workstream tests pass (`vitest run test/components/workstream test/workstream-helpers.test.ts test/workstream-filters.test.ts`).
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.

## Test Scenarios
- Pure predicates: each dimension in isolation; OR-within; AND-across; assignee combined-OR incl. Unassigned; `isClosed` for all 7 statuses + `CLOSED_STATUSES` round-trip vs `deriveColumn(closed)`; status tri-state (all/open/closed); predicate ∘ search; option derivation hides empties + surfaces all domains of a multi-domain issue; `hasActiveFilters` true/false incl. `status !== "all"`.
- Board: filter+search narrows; Reset clears filters+search; Refresh re-fetches and retains filters (filtered-out card stays out); filtered-empty → "Reset filters" state.
- Column: empty → no toggle; 201 → 200 + exact notice; animation className contract; reduced-motion reset class.

## Domain Review

**Domains relevant:** Product (UI surface).

### Product/UX Gate

**Tier:** blocking (mechanical UI-surface override — new file `components/workstream/filter-bar.tsx` matches `components/**/*.tsx`).
**Decision:** reviewed (partial) — pipeline/headless path.
**Agents invoked:** spec-flow-analyzer.
**Skipped specialists:** none silently — see Pencil note below.
**Pencil available:** yes (headless CLI Tier 0; Node v24.15.0). **Committed wireframe:**
`knowledge-base/product/design/workstream/workstream-kanban.pen` (git-tracked) is the
canonical board wireframe; the approved mock
`knowledge-base/product/design/workstream/screenshots/01-workstream-kanban-board.png`
renders the card/column visual language. The **filter bar is additive chrome not yet in that
wireframe**. Outstanding async deliverable before the UI merges: `ux-design-lead` extends the
`.pen` with the filter-bar layout (4 dropdowns + Reset/Refresh) and the "square corners per
brand" reconciliation against the existing rounded board chrome — surface at `/work`
Phase 2.5. Referencing the committed `.pen` satisfies `wg-ui-feature-requires-pen-wireframe`;
the filter-bar extension is a tracked follow-up, not a silent skip.

#### Findings (spec-flow-analyzer)
11 gaps surfaced; all resolved in Decision Log + Implementation Phases: domain-label premise
(D1), assignee combined-OR + Unassigned (D2/F8), faceting source (D3/F1), status default
normalization (D4/F7), in-memory filters (D5/F9), refresh vs optimistic cards (D6/F4),
empty-while-collapsed (Phase 4/F3), combined empty state + blank-quote bug (Phase 3/F6),
200-cap count/placement/collapsed semantics (Phase 4/F5), refresh-failure feedback
(Phase 3/F11), drawer-over-filtered-out-card (Phase 3/F10).

## Architecture Decision (ADR/C4)

No architectural decision. Checked all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`): the
**founder** actor, the **GitHub** external system (`model.c4:171`, description already
includes "issue tracking"), and the `dashboard → api → github` edges are already modeled.
This feature adds **no** new external human actor, **no** new external system, **no** new
container/data-store, and **no** changed access relationship — it is client-side rendering
over the already-modeled GitHub-issue feed; the additive `domains` field is internal lib
enrichment of data the existing reader already passes. **No C4 impact.**

## Observability

Client-only UI. There is **no new server error path, network endpoint, cron, or infra
surface** — the feature renders the already-fetched `/api/workstream/issues` payload.
Schema below reflects the existing client telemetry stack (`@sentry/nextjs` browser SDK,
`apps/web-platform/sentry.client.config.ts`) rather than a new server signal.

```yaml
liveness_signal:
  what: "Workstream board + filter bar render and the existing component test suite passes"
  cadence: "CI on every PR (vitest) + render-on-load in the browser"
  alert_target: "CI red on the workstream test files; Sentry browser issue on a render throw"
  configured_in: "apps/web-platform/vitest.config.ts; sentry.client.config.ts"
error_reporting:
  destination: "Sentry browser SDK (existing @sentry/nextjs client) for uncaught render errors; the in-board ErrorCard for the SWR fetch-error path"
  fail_loud: "true — a fetch error surfaces ErrorCard with a Try-again retry; a refresh-with-existing-data failure surfaces an inline 'Couldn't refresh' notice (data retained)"
failure_modes:
  - mode: "Filter predicate excludes everything"
    detection: "Combined filtered-empty state renders with a Reset-filters action (visible to the user)"
    alert_route: "user-facing UI state (no alert — recoverable in one click)"
  - mode: "Refresh (mutate) revalidation fails while data exists"
    detection: "mutate() promise rejection caught; inline notice shown; Sentry browser SDK captures if it throws"
    alert_route: "inline UI notice + Sentry browser issue"
  - mode: "Collapse animation regresses (inert) after the persistent-section refactor"
    detection: "issue-column.test.tsx asserts the transition-[width] + motion-reduce className contract"
    alert_route: "CI red"
logs:
  where: "Browser console + Sentry breadcrumbs (existing client SDK); no new server log"
  retention: "Sentry default project retention (unchanged)"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/components/workstream test/workstream-filters.test.ts && ./node_modules/.bin/tsc --noEmit"
  expected_output: "all workstream component + predicate tests pass; tsc reports no errors (no ssh required)"
```

## Files to Edit
- `apps/web-platform/lib/workstream.ts` — **optional** `domains?: string[]` field + mapper spread line; `CLOSED_STATUSES` + `isClosed`, `WorkstreamFilters`, `matchesFilters`, `hasActiveFilters`, `emptyFilters`, `deriveFilterOptions`; `COLUMN_RENDER_CAP` + `COLUMN_CAP_NOTICE`.
- `apps/web-platform/components/workstream/workstream-board.tsx` — filter state, option derivation, predicate composition, Reset + Refresh top-bar controls, refresh-failure inline notice, combined filtered-empty state, cap plumbing.
- `apps/web-platform/components/workstream/issue-column.tsx` — single-persistent-section width+opacity animation, empty-column no-toggle force-expanded, 200-cap slice + notice, true-total count pill.
- `apps/web-platform/test/components/workstream/workstream-board.test.tsx` — filter/search/reset/refresh/empty-state cases.
- `apps/web-platform/test/components/workstream/issue-column.test.tsx` — empty-no-toggle, 200-cap, animation-class cases.

**Deliberately NOT edited** (`domains?` is optional → inert): `new-issue-dialog.tsx`,
`issue-card.tsx`, `issue-detail-sheet.tsx`, `workstream-helpers.test.ts`,
`workstream-tools.test.ts`, `issue-card.test.tsx`, `issue-detail-sheet.test.tsx`. If the
field is ever made required, all seven must be added here (arch review).

## Files to Create
- `apps/web-platform/components/workstream/filter-bar.tsx` — the FilterBar component.
- `apps/web-platform/test/components/workstream/filter-bar.test.tsx` — FilterBar tests.
- `apps/web-platform/test/workstream-filters.test.ts` — pure predicate + option-derivation tests (node).

## Open Code-Review Overlap
None — `gh issue list --label code-review --state open` checked; no open scope-out names the workstream board/column/lib filter files. (Re-verify at /work if the backlog changed.)

## Sharp Edges
- **SE1 — A conditional-render swap does NOT animate (learning 2026-06-09, PR #5075).** The
  current `if (collapsed) return <strip>` mounts/unmounts different DOM subtrees, so a
  `transition-[width]` on either branch is **inert** (no prior committed frame to animate
  from) and ships **zero** width animation even though it typechecks and unit tests pass.
  The animation requirement is only met by a **single persistent `<section>`** whose width
  class toggles, plus a rAF mount-reveal for the inner content opacity. happy-dom cannot
  evaluate the compositor — tests assert the **className contract**, not computed transition
  values. Do not "slap `transition-all`"; it is anti-slop Tier-1 (`TRANSITION-ALL`) **and**
  inert here.
- **SE2 — Refresh wipes optimistic preview cards (D6/spec-flow F4).** `mutate()` with
  revalidate discards New Issue / status-move cards that use `{ revalidate: false }`.
  Accepted + documented (Preview banner already says changes aren't saved). If a reviewer
  wants preservation, that is a scope change, not a bug.
- **SE3 — `domains` field is additive but real.** Existing mapper tests must stay green
  (additive). Confirm the reader already passes `domain/*` labels in `BoardIssueInput.labels`
  (it does — `lib/workstream.ts:237`) so no reader change is needed.
- **SE4 — Test path discovery.** Predicate tests MUST be `test/workstream-filters.test.ts`
  (node glob `test/**/*.test.ts`); component tests MUST be under
  `test/components/workstream/*.test.tsx`. A co-located `components/**/*.test.tsx` is silently
  skipped by the vitest include globs.
- **SE5 — Use the EXACT notice string** from the `COLUMN_CAP_NOTICE` constant (single source);
  do not re-type it inline. The plural "columns" wording is intentional per spec even though
  it renders per-column.
- **SE6 — A plan whose `## User-Brand Impact` section is empty/`TBD` fails deepen-plan Phase
  4.6.** This section is filled (threshold none + reason).

## Non-Goals
- No data-layer / GitHub-reader / `/api/workstream/issues` route changes.
- No new sort order for the visible-200 (keeps existing fetch order; the cap is a render
  guard, not a ranking feature).
- No filter persistence across reload (in-memory like search; D5).
- No "scheduled routines" exclusion (confirmed: the board shows GitHub issues only; Inngest
  routine definitions live in the separate Routines tab).
