---
title: "feat(web): Workstream board — collapse empty columns by default"
date: 2026-06-29
type: feat
branch: feat-one-shot-workstream-collapse-empty-columns
lane: single-domain
brand_survival_threshold: none
status: ready
references:
  - PR #5659 (shipped Workstream kanban board + first collapsible columns)
  - PR #5660 (visible column tints + real collapse icon-button)
  - PR #5661 (filters, search, per-column cap, polished collapse, reset + refresh)
  - knowledge-base/product/design/workstream/workstream-kanban.pen (committed wireframe source — binding)
  - knowledge-base/product/design/workstream/screenshots/01-workstream-kanban-board.png (signed-off mock)
---

# feat(web): Workstream board — collapse empty columns by default ✨

## Enhancement Summary

**Deepened on:** 2026-06-29
**Agents used:** code-simplicity-reviewer, pattern-recognition-specialist (UX/frontend), Explore (verify-the-negative pass).
**Halt gates passed:** 4.6 User-Brand Impact (present, threshold `none`, non-sensitive paths), 4.7 Observability (5 fields, no-SSH), 4.8 PAT-shaped (none), 4.9 UI-wireframe (committed `workstream-kanban.pen` referenced).

### Key improvements over the round-1 plan
1. **Accessibility fold-in (P2).** Phase 2 deletes the expanded `<p>No issues</p>`; the empty state would then be conveyed only by a bare `0` count pill, which a screen reader announces as the ambiguous "Backlog, 0". Added a `sr-only` "No issues" to the empty collapsed strip so the empty state stays announced (`sr-only` is an in-use utility — `components/chat/attachment-display.tsx:122`, `components/scope-grants/scope-grant-row.tsx:166`).
2. **Affordance-distinction note (P2).** A user-collapsed *non-empty* strip and an *empty* strip both render the `w-10` collapsed branch but differ in interactivity (only the former has an Expand chevron). Captured as a design refinement (a subtle dimming option) deferred to the binding mock / QA eyeball — not a code blocker.
3. **Board-test safety is grep-confirmed, not assumed.** The verify-the-negative pass + a direct grep confirm `workstream-board.test.tsx` references only the whole-board `EmptyState`/`NoResults` copy ("No issues to display" / "No issues match…"), never the column-level "No issues" or `w-72`/`w-10` — so empty columns rendering as collapsed strips breaks nothing.

### Verified this pass (grounded, not memory)
- `isCollapsed = isEmpty || collapsed` is the exhaustive, minimal inversion (`collapsed` defaults to `false`, `issue-column.tsx:67`); the expanded branch is provably unreachable for empty columns, so the Phase 2 dead-code deletion is sound (code-simplicity-reviewer returned no P1/P2 on the code change).
- The board already passes `collapsed={collapsed.has(column.status)}` + `onToggleCollapse` per column (`workstream-board.tsx:296-304`) — the change lives entirely in `issue-column.tsx`; `workstream-board.tsx` does not change.
- The collapsed branch renders the Expand button with no `isEmpty` guard today (`issue-column.tsx:94-103`); the new `!isEmpty` guard is the only addition there.

## Overview

The Workstream kanban board renders 7 fixed columns (`Backlog … Cancelled`).
Columns are collapsible — the board owns a `collapsed` `Set<WorkstreamStatus>`
persisted in `localStorage` (`workstream:collapsed-columns`), and each
`IssueColumn` toggles between a `w-72` expanded card list and a `w-10` vertical
strip with a real `transition-[width]` animation (shipped in PRs
#5659/#5660/#5661).

Today an **empty** column (0 post-filter issues) is the *exact opposite* of what
this feature wants: it is **force-expanded** and shows **no toggle**
(`issue-column.tsx:16-17` "Empty rule", `:79` `isCollapsed = collapsed && !isEmpty`,
`:124-135` collapse button gated on `!isEmpty`, `:149-152` "No issues" body).
With 7 columns and several routinely empty (Blocked / In Review / Cancelled), the
board wastes horizontal space and forces sideways scrolling past empty card wells.

**This change inverts the empty rule:** an empty column renders **collapsed by
default** (a thin `w-10` strip showing the colored dot, a `0` count pill, and the
vertical label). The change is a single, faithful inversion that *builds on* —
not replaces — the existing collapsible machinery: the persisted `collapsed` set,
the `w-72 ↔ w-10` width transition, the `MountReveal` fade, and the count pill all
stay exactly as shipped. The data layer, the GitHub-issues reader, the filters,
the Concierge field, and `workstream-board.tsx` are **out of scope**.

## Research Reconciliation — Spec vs. Codebase

| Claim (from ARGUMENTS / premise) | Reality in repo (verified this pass) | Plan response |
| --- | --- | --- |
| "existing collapsible-column behavior from PRs #5659/#5660/#5661" | Confirmed merged: commits `0102ad1a1` (#5659), `2d6023a33` (#5660), `13cc78bfc` (#5661) on `main`. Collapse state owned by board (`workstream-board.tsx:43,74-79,177-192`), persisted to `localStorage`. | Build on it — reuse the `collapsed` prop + width-transition section; touch only the empty-column branch. |
| "empty column should render collapsed by default" | Today empty ⇒ **force-expanded, no toggle** (`issue-column.tsx:79` `collapsed && !isEmpty`; `:124-135`; `:149-152`). | Invert to `isCollapsed = isEmpty || collapsed`; move the "no toggle when empty" rule into the collapsed branch. |
| (premise) PRs cited verifiable via `gh` | `gh` is network-restricted in this sandbox; verified via local `git log` + direct file reads instead. | No external premise is stale; proceed. |
| Existing `issue-column.test.tsx` empty-column tests | `:108-128` assert empty ⇒ no toggle **and name it "force-expanded"**. | These stay partly true (no toggle) but the *intent* inverts — rewrite to assert the **collapsed strip** (`w-10`), not expansion. |
| Board collapse test seeds only Backlog | `workstream-board.test.tsx:333-354` seeds 1 issue in Backlog (non-empty); the other 6 columns are empty. | Board test stays green (Backlog stays expanded → "Collapse Backlog" still present); add a new board assertion that a sibling empty column renders as a collapsed strip. |

## User-Brand Impact

**If this lands broken, the user experiences:** a Workstream board whose empty
columns render wrong — either still expanded (feature no-op) or, worst case, a
populated column wrongly collapsed/hidden so its issues become invisible behind a
strip. Cosmetic/layout only; no data loss, no broken flow, no persistence
corruption (the `collapsed` localStorage set is never mutated by this change).

**If this leaks, the user's data is exposed via:** N/A — this change touches no
data, no network, no server code, and no new persistence. It reads the existing
client-only `collapsed-columns` localStorage key and derives layout from the
already-fetched issue counts.

**Brand-survival threshold:** none — a client-only layout refinement to an
already-shipped component. No sensitive path is touched (preflight Check 6 regex
covers schemas/migrations/auth/API routes — none of which this diff hits).

## Implementation Phases

### Phase 1 — Invert the empty-column rule (single source of truth)

In `apps/web-platform/components/workstream/issue-column.tsx`:

1. **Flip the derivation** (line 79). Replace:

   ```tsx
   // Empty columns are force-expanded with no toggle; the persisted collapsed
   // flag is ignored (not mutated) while empty.
   const isCollapsed = collapsed && !isEmpty;
   ```

   with:

   ```tsx
   // Empty columns render COLLAPSED by default (a thin strip), regardless of the
   // persisted flag; a populated column honors the user's persisted choice.
   // INVARIANT: isEmpty ⇒ isCollapsed, so the expanded branch never sees an
   // empty column (relied on below — do not add empty-handling to that branch
   // without re-checking this line).
   const isCollapsed = isEmpty || collapsed;
   ```

   This is the whole behavioral change. `isEmpty || collapsed`:
   - empty ⇒ `true` (collapsed strip), **whatever** the persisted flag says;
   - non-empty ⇒ `collapsed` (the persisted per-column choice — unchanged);
   - the persisted `collapsed` set is still **never mutated** for empty columns,
     so a user's prior collapse/expand intent re-applies once the column
     repopulates (same guarantee as today, just with collapsed as the empty
     default instead of expanded).

2. **Move "no toggle when empty" into the collapsed branch.** Today the collapsed
   branch (lines 91-119) renders the Expand button unconditionally. Gate it on
   `!isEmpty` so an empty collapsed strip shows the dot + `0` count + vertical
   label but **no** expand chevron (symmetric to the old empty-expanded column,
   which had no collapse chevron):

   ```tsx
   {!isEmpty ? (
     <button
       type="button"
       aria-label={`Expand ${column.label}`}
       aria-expanded={false}
       onClick={() => onToggleCollapse?.(column.status)}
       className={TOGGLE_BTN_CLASS}
     >
       <ChevronDownIcon className="h-3.5 w-3.5 -rotate-90" />
     </button>
   ) : null}
   ```

3. **Preserve the accessible empty-state announcement (deepen P2).** Phase 2
   deletes the expanded `<p>No issues</p>`. Without a replacement, an empty
   collapsed strip is conveyed only by the bare `0` count pill — a screen reader
   announces "Backlog, 0" (ambiguous: 0 of what?). Add a visually-hidden label to
   the empty strip so the empty state stays announced, reusing the app's existing
   `sr-only` utility (`components/chat/attachment-display.tsx:122`,
   `components/scope-grants/scope-grant-row.tsx:166`):

   ```tsx
   {isEmpty ? <span className="sr-only">No issues</span> : null}
   ```

   Place it inside the collapsed strip's flex column (alongside the dot / count /
   label). This keeps the exact prior SR text ("No issues") while the visual stays
   the compact strip.

### Phase 2 — Remove the now-unreachable expanded-empty code

Because `isCollapsed = isEmpty || collapsed`, the **expanded branch (lines
120-167) can only run for a non-empty column** (`!isCollapsed ⇒ !isEmpty`). The
expanded branch's empty handling is now dead. To keep the component honest (a
contradictory "No issues" path that can never render is a review red flag — DHH /
code-simplicity reviewers will ask "when does this show?"), simplify:

1. Remove the `{!isEmpty ? (<Collapse button/>) : null}` guard (lines 124-135) —
   in the expanded branch the column is always non-empty, so always render the
   Collapse button.
2. Remove the `isEmpty ? (<p>No issues</p>) : (<>cards</>)` conditional (lines
   148-165) — always render the cards block.

Net: the "empty has no toggle" rule lives in exactly one place (the collapsed
branch, Phase 1.2), and the expanded branch has no empty special-casing.

> Conservative fallback (if a reviewer prefers minimal diff over dead-code
> removal): leave the expanded branch untouched. It is provably unreachable for
> empty columns, so behavior is identical either way. The Phase-1 invariant
> comment documents why. Phase 2 is a cleanliness pass, not a correctness
> requirement — do it unless review pushes back.

### Phase 3 — Refresh the header doc comment

Rewrite the `issue-column.tsx` "Empty rule" comment block (lines 16-17) to:

```tsx
// Empty rule (v4): a column with 0 issues renders COLLAPSED by default — a thin
// strip with the dot, a 0 count, and the vertical label, and NO toggle (you
// cannot expand an empty column). The persisted collapsed flag is left untouched
// while empty, so a populated column's prior choice re-applies on repopulate.
```

### Phase 4 — Tests

**Edit** `apps/web-platform/test/components/workstream/issue-column.test.tsx`
(happy-dom `test/**/*.test.tsx` project per `vitest.config.ts:64`):

- **Rewrite** the `describe("IssueColumn — empty column has no toggle")` block
  (lines 108-128) to assert the **collapsed-strip** behavior, not expansion:
  - `empty column (collapsed flag false) → collapsed strip + no toggle`: render
    `issues={[]}`, no `collapsed` prop. Assert **no** `Collapse Backlog` and
    **no** `Expand Backlog` button (`queryByRole … toBeNull()`), AND the
    `<section>` class contains `w-10` and **not** `w-72` (proves it collapsed).
  - `empty column ignores collapsed=true the same way → still collapsed strip, no
    toggle`: render `issues={[]} collapsed`. Same assertions.
- **Add** `empty collapsed strip shows the 0 count and the column label`:
  `getByText("0")` and the label `Backlog` are present.
- **Add** `empty collapsed strip announces "No issues" for screen readers`:
  `getByText("No issues")` is present (the `sr-only` span) when `issues=[]`.
- The tint / one-control-at-a-time / animation / 200-cap blocks use the non-empty
  `issue()` fixture and are **unaffected** — keep green, no edits.

**Edit** `apps/web-platform/test/components/workstream/workstream-board.test.tsx`:

- The existing collapse/persist test (lines 333-354) seeds Backlog only and
  drives "Collapse Backlog" — Backlog stays non-empty/expanded, so it stays
  green. Verify, do not edit.
- **Add** a board-level proof of the feature: render with a single Backlog issue,
  wait for the card, then assert a **sibling empty column renders as a collapsed
  strip** — e.g. the `<section aria-label="Todo">` class contains `w-10` and
  there is **no** `Collapse Todo` / `Expand Todo` button. This is the
  integration-level guarantee that empty columns collapse on a populated board.

## Files to Edit

- `apps/web-platform/components/workstream/issue-column.tsx` — flip `isCollapsed`
  (Phase 1.1); gate the collapsed-branch Expand button on `!isEmpty` (Phase 1.2);
  remove unreachable expanded-empty handling (Phase 2); refresh the "Empty rule"
  comment (Phase 3).
- `apps/web-platform/test/components/workstream/issue-column.test.tsx` — rewrite
  the empty-column block to assert the collapsed strip; add the 0-count/label
  assertion (Phase 4).
- `apps/web-platform/test/components/workstream/workstream-board.test.tsx` — add a
  board-level "empty sibling column renders collapsed" assertion (Phase 4).

## Files to Create

- None. (Reuses the existing component, test files, icon, and persistence path.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `issue-column.tsx` derives `const isCollapsed = isEmpty || collapsed;`
  (grep: `grep -n 'isEmpty || collapsed' issue-column.tsx` returns 1; the old
  `collapsed && !isEmpty` no longer appears: `grep -c 'collapsed && !isEmpty'` → 0).
- [ ] An empty column renders the **collapsed** strip: the `<section>` carries
  `w-10` (not `w-72`) when `issues=[]`, for both `collapsed` unset and
  `collapsed=true`.
- [ ] An empty column shows **no** toggle: neither `Collapse <label>` nor
  `Expand <label>` button is present when `issues=[]`.
- [ ] The collapsed empty strip still shows the colored dot, the `0` count pill,
  and the vertical column label.
- [ ] The collapsed empty strip carries an accessible empty-state announcement:
  a `sr-only` (visually-hidden) "No issues" is rendered when `issues=[]` so a
  screen reader does not announce a bare "0" (deepen P2 a11y fold-in).
- [ ] A **non-empty** column is unchanged: expanded by default with a working
  `Collapse <label>` toggle; collapsing/expanding it still persists to
  `localStorage` (`workstream-board.tsx` untouched — no edits to that file:
  `git diff --name-only` does not list `workstream-board.tsx`).
- [ ] The existing `workstream-board.test.tsx` suite stays green with no edits —
  grep-confirmed safe: it references only the whole-board `EmptyState`/`NoResults`
  copy ("No issues to display" :227 / "No issues match…" :103), never the
  column-level "No issues" nor `w-72`/`w-10`, so empty columns becoming collapsed
  strips does not break any assertion.
- [ ] The expanded branch contains no empty special-casing after Phase 2
  (no `No issues` literal reachable in the expanded render), OR — if the
  conservative fallback was taken — the Phase-1 invariant comment is present
  explaining why the expanded-empty path is dead.
- [ ] Board-level: on a board with ≥1 issue, a sibling empty column renders as a
  `w-10` collapsed strip (new `workstream-board.test.tsx` assertion passes).
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/components/workstream/`
  is green (issue-column + workstream-board suites).
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.

## Observability

This is a **client-rendered** React component (`apps/web-platform/components/`);
it ships no server route, no Inngest function, no infra, no new persistence. Its
observability surface is the browser render path, covered by the app's existing
client error plumbing and by CI unit tests.

```yaml
liveness_signal:
  what: IssueColumn renders empty columns as collapsed strips on the /dashboard/workstream board
  cadence: per page load (client); asserted on every PR run in CI
  alert_target: CI red on the vitest workstream suite (PR-blocking)
  configured_in: apps/web-platform/test/components/workstream/ (vitest, happy-dom project)
error_reporting:
  destination: existing client Sentry browser SDK + the dashboard React error boundary (no new path added by this change)
  fail_loud: a render-time throw surfaces in the dashboard error boundary, not a silent blank column
failure_modes:
  - mode: empty column renders expanded again (isCollapsed derivation regresses)
    detection: vitest assertion that an empty <section> carries w-10 (not w-72)
    alert_route: CI red (PR-blocking)
  - mode: a populated column is wrongly collapsed/hidden (isEmpty mis-evaluated)
    detection: vitest assertion that a non-empty column is expanded with a Collapse toggle
    alert_route: CI red (PR-blocking)
  - mode: empty strip leaks a stray Expand button (the !isEmpty guard regresses)
    detection: vitest assertion that no Collapse/Expand button exists when issues=[]
    alert_route: CI red (PR-blocking)
logs:
  where: browser console only (client component); no new server-side log lines
  retention: N/A (client-side; nothing persisted beyond the pre-existing collapsed-columns localStorage key, which this change does not mutate)
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/components/workstream/"
  expected_output: all tests pass (issue-column + workstream-board suites), no SSH required
```

## Domain Review

**Domains relevant:** Product (UI surface)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** ux-design-lead (N/A — binding design artifacts already
exist and are operator-signed-off: the committed wireframe source
`knowledge-base/product/design/workstream/workstream-kanban.pen` and the rendered
mock `…/screenshots/01-workstream-kanban-board.png`. The collapsed-column strip
visual is already part of that frozen design; this change only changes *when* a
column adopts the already-designed collapsed strip — empty by default — not how
it looks. No new page, flow, modal, or interactive surface is introduced;
regenerating wireframes would be ceremony. The committed `.pen` satisfies the
`wg-ui-feature-requires-pen-wireframe` gate.)
**Pencil available:** N/A (no new design surface; a behavioral default-flip on an
already-designed collapsible component)

#### Findings

The mechanical UI-surface trigger fires (a `components/**/*.tsx` path is in Files
to Edit). The only files created are tests (none created here, in fact — both
test files already exist), so the BLOCKING "new component file" escalation does
not apply. This modifies the default render state of an existing, already-designed
component → ADVISORY, auto-accepted in the non-interactive pipeline, mirroring the
sibling PR #5660 plan precedent for the same component. The deepen-plan UX pass
(pattern-recognition-specialist) surfaced two P2 refinements now folded into the
plan: (1) an `sr-only` "No issues" to keep the empty state accessible after the
visible text is removed (Phase 1.3 + AC + test), and (2) a noted design option to
dim the empty strip so it reads as distinct from a user-collapsed non-empty strip
(deferred to the binding mock + QA eyeball — see Sharp Edges). QA/PR-review should
eyeball the populated board to confirm empty columns appear as thin strips, the
empty/collapsed strips are distinguishable, and populated columns are unaffected.

## Architecture Decision (ADR/C4)

No architectural decision. Flipping an existing component's default collapsed
state for empty columns introduces no new data-ownership/tenancy boundary, no new
substrate/integration, and no resolver/dispatch/trust-boundary change.

**C4 completeness check (all three model files considered):** the Workstream
board is a purely client-side view over the already-modeled GitHub-issues read
path; this change adds **no** external human actor, **no** external system/vendor,
**no** new container/data-store, and **no** actor↔surface access-relationship
change (the only persistence touched — the `collapsed-columns` localStorage key —
is pre-existing and unmodified). No C4 element or view is affected. Gate skips.

## Test Scenarios

| Scenario | Expectation |
| --- | --- |
| Empty column, no `collapsed` prop | Collapsed `w-10` strip; dot + `0` + vertical label; `sr-only` "No issues"; **no** toggle |
| Empty column, `collapsed=true` | Same collapsed strip (default already collapsed); **no** toggle |
| Empty column — screen reader | `sr-only` "No issues" announced (not a bare "0") |
| Non-empty column, default | Expanded `w-72`; `Collapse <label>` button present (unchanged) |
| Non-empty column, `collapsed=true` | Collapsed `w-10` strip with `Expand <label>` toggle (unchanged) |
| Toggle a non-empty column (board) | Persists to `localStorage`; still green (unchanged) |
| Populated board, sibling empty column | Renders as a `w-10` collapsed strip with no toggle |
| Empty column repopulates | Reverts to the user's persisted flag (collapsed-set untouched while empty) |

## Sharp Edges / Risks

- **Verify all four quadrants — {empty, non-empty} × {collapsed-branch,
  expanded-branch}.** Toggleable controls are the classic "fix one state, miss the
  other" trap (learning `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`,
  PR #2494→#2504). The single source of truth `isCollapsed = isEmpty || collapsed`
  plus the four test scenarios are the guard.
- **The collapsed branch now renders for two reasons** — empty (no toggle) OR
  user-collapsed non-empty (with toggle). The `!isEmpty` guard on the Expand
  button is the *only* thing distinguishing them; keep it. Removing it would put a
  dead "Expand" button on an empty strip that adds the status to the persisted set
  on click (polluting `localStorage`).
- **Do not mutate the persisted set for empty columns.** Resist any temptation to
  "force-collapse" by adding empty statuses to the board's `collapsed` set — that
  would corrupt the user's true collapse intent and survive repopulation
  incorrectly. The derivation reads emptiness at render time; persistence stays
  the user's explicit-intent store only.
- **Test path must match the runner's globs.** New/edited tests live under
  `apps/web-platform/test/components/workstream/*.test.tsx`, collected by the
  happy-dom project (`vitest.config.ts:64` `test/**/*.test.tsx`). A co-located
  `components/**/*.test.tsx` would be silently skipped (learning
  `2026-05-29-…-consumer-enumeration.md` SE#2). Keep them under `test/`.
- **Collapsed-strip detection in tests is class-based** (`w-10` vs `w-72`) — this
  is the existing collapsed/expanded discriminator in the component, so it is a
  stable assertion target; do not invent a new marker.
- **A11y: do not let the empty state collapse to a bare "0" (deepen P2).** Phase 2
  removes the visible "No issues" text; the `sr-only` "No issues" in the empty
  strip (Phase 1.3) is the replacement. A screen reader on the empty strip must
  announce "No issues", not just "Backlog, 0". The new test asserts the `sr-only`
  text is present.
- **Empty-vs-collapsed affordance look-alike (deepen P2, design).** A
  user-collapsed *non-empty* strip (has an Expand chevron) and an *empty* strip
  (no toggle) both render the `w-10` collapsed branch and look near-identical. A
  user may click an empty strip expecting it to open. Minimal mitigation if QA
  finds it confusing: subtly dim the empty strip (e.g. reduce the label/count
  opacity) so it reads as "nothing here" rather than "collapsed — click to open".
  Defer the exact look to the binding mock + QA eyeball; do not over-build.
- **QA the live filter→empty transition, not just initial render (deepen P3).** The
  width `transition-[width]` animates cleanly because all 7 `<section>`s are keyed
  by status and always mounted (`workstream-board.tsx:295-306`), so the element
  persists across the empty flip. But the inner `MountReveal` swap
  (`key="expanded"`→`key="collapsed"`) is a fade-in-from-blank, not a crossfade,
  and the row height can snap (un-animated) when filtering empties the tallest
  column. Both are pre-existing behaviors this change now triggers automatically
  on search keystrokes — QA the filter-to-empty transition by hand; it is not a
  blocker.
- **Two collapse mental models share one store (deepen P3, constraint).**
  Post-change "collapsed" means either auto (empty, not in the persisted Set) or
  explicit (user choice in the Set). Fine today (no board-level "expand all" /
  collapsed-count UI exists). If such an affordance lands later, it must account
  for auto-collapsed empties (which are not in the Set) — note for the future, no
  action now.
- **Empty `## User-Brand Impact` fails deepen-plan Phase 4.6** — section is filled
  above (threshold: none, no sensitive path).
- This plan introduces no infrastructure, no migration, no ADR/C4 change, no
  regulated-data surface, and no server/`src`/`infra` code — so the IaC (2.8),
  GDPR (2.7), and ADR/C4 (2.10) gates skip; the Observability section is included
  for parity with the sibling PR #5660 plan even though `components/` is outside
  the strict trigger set.
