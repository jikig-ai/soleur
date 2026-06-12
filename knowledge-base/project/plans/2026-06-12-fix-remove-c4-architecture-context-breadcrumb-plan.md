---
title: "Remove the 'Architecture · context' breadcrumb from the C4 diagram panel header"
type: fix
date: 2026-06-12
branch: feat-one-shot-c4-remove-context-breadcrumb
lane: cross-domain
brand_survival_threshold: none
status: planned
related_prs: [4938, 4925]
---

# 🐛 fix: Remove the "Architecture · context" breadcrumb from the C4 diagram panel header

## Enhancement Summary

**Deepened on:** 2026-06-12
**Sections enhanced:** Scope Decision, Research Reconciliation, Product/UX Gate (Phase 4.9 determination), Risks
**Research agents used:** Explore (wireframe-gate resolution), Explore (verify-the-negative pass), repo-research-analyst, learnings-researcher

### Key Improvements

1. **All 6 technical claims independently verified** via a verify-the-negative grep pass — every `currentView` reader, the optional `onViewChange?` signature, C4Canvas's independent internal view state, the absence of any breadcrumb test assertion, and the `noUnusedLocals`-unset tsconfig are confirmed against the live source (citations in Research Reconciliation + Risks).
2. **Wireframe gate (Phase 4.9) resolved with documented precedent.** The mechanical glob flags this as a UI-surface plan, but it qualifies for the `ui-surface-terms.md` Excluded carve-out (pure removal, no structural change). The plan now carries an explicit Phase 4.9 determination + override mirroring **PR #4938** (verified MERGED 2026-06-04, same two files), which shipped a near-identical C4 label removal without a `.pen`.
3. **Scope decision made explicit and precedent-backed** — both breadcrumb surfaces (`c4-workspace.tsx` + `c4-diagram.tsx`) are fixed together to avoid the paired-UI follow-up-PR anti-pattern.

### New Considerations Discovered

- The `Architecture · {currentView}` label was introduced by **PR #4925** (the full-screen C4 workspace), and **PR #4938** later removed the *adjacent* LikeC4 logo from the same header — so this change is the natural next cleanup of the same panel chrome. No design regression: the panel was iterated three times (#4925 → #4938 → #4947 collapsible panel) and the label is the last vestigial status mirror.
- No CI lint or `noUnusedLocals` gate exists for `apps/web-platform`, so the orphaned-`currentView` sweep is enforced **only** by plan AC2's grep — this is the single load-bearing gate against an incomplete (span-only) removal.

## Overview

When a KB C4/LikeC4 diagram is opened, the right-hand panel header renders a muted
label `Architecture · {currentView}` (e.g. `Architecture · context »`-style text) in the
top-right corner, immediately to the left of the **Collapse Concierge** chevron and to the
right of the **Concierge | Code** toggle tabs. This label is visual noise and should be
removed entirely.

The label is a pure status mirror — it reflects the diagram's currently-active view id
(`currentView`), updated via the diagram canvas's `onViewChange` callback. Removing the
label orphans the parent-side `currentView` state and the `onViewChange` wiring, which must
be swept per `cq-ref-removal-sweep-cleanup-closures`. The diagram canvas keeps its OWN
internal view state for drill-down (`C4Canvas` owns `currentView` at
`components/kb/c4-shared.tsx:164`), so dropping the parent's mirror has **zero behavioral
effect** on diagram navigation — it only removes the label.

> **Lane note:** No `spec.md` exists for this branch, so `lane:` defaulted to
> `cross-domain` (TR2 fail-closed). The change is in substance single-domain (one component
> cluster, frontend-only), but the plan honors the fail-closed default.

### The breadcrumb appears in TWO surfaces

| File | Surface | Line(s) | In task scope? |
| --- | --- | --- | --- |
| `apps/web-platform/components/kb/c4-workspace.tsx` | **Fullscreen workspace** — diagram ‖ Concierge/Code panel. The header described in the task (breadcrumb next to Concierge/Code toggle + collapse chevron). | span `157-159`; state `48`; prop `108` | ✅ Primary target |
| `apps/web-platform/components/kb/c4-diagram.tsx` | **Inline embedded widget** — Diagram\|Code tabbed block rendered in-place inside markdown. Same `Architecture · {currentView}` span, same orphan pattern. | span `62-64`; state `38`; prop `84` | ⚠️ Same visual element — see Scope Decision |

## Scope Decision — fix both surfaces

The task names the fullscreen workspace (Concierge/Code toggle). The **identical** breadcrumb
in the inline embed (`c4-diagram.tsx`) is the same visual element of the same class. Leaving
one behind produces an inconsistent UI and a guaranteed follow-up PR (cf. learning
`2026-04-17-alignment-fixes-must-verify-both-toggle-states.md` — fixing one surface of a
paired UI element and leaving the sibling is a recurring net-negative pattern).

**Decision: remove the breadcrumb (and sweep the orphaned state) in BOTH files in this PR.**
Both are trivially small, identical edits; folding them in is strictly cheaper than a second
cleanup cycle. This is a documented scope expansion, not silent scope creep.

## Research Reconciliation — Spec vs. Codebase

| Claim (task description) | Codebase reality | Plan response |
| --- | --- | --- |
| "breadcrumb text in top-right of C4 diagram panel header next to Concierge/Code tabs" | Confirmed at `c4-workspace.tsx:157-159` — `<span class="text-[11px] text-soleur-text-muted">Architecture · {currentView}</span>` inside the `ml-auto` group with the collapse chevron. | Remove the span. |
| "text reads `Architecture · context »`" | The literal rendered text is `Architecture · ` + the active view id (e.g. `context`). The `»` is not in the source — likely a visual artifact of the operator's reading. The source span is `Architecture · {currentView}`. No `»` / `»` token exists in either file (grep clean). | Remove the whole span; no `»` glyph to chase. |
| "small frontend UI fix" | Confirmed — 2 component files, frontend-only, no API/schema/infra surface. | NONE infra; ADVISORY UX tier (label removal, no new surface). |
| (implicit) removal is self-contained | **NOT self-contained** — removing the span orphans `currentView`/`setCurrentView` (only reader was the span) in both files. `noUnusedLocals` is NOT set in `tsconfig.json` (only `strict: true`) and no ESLint runs in CI, so the orphan is **not** a CI failure — but it is dead code requiring a sweep per `cq-ref-removal-sweep-cleanup-closures`. | Sweep `currentView` state + `onViewChange` prop in both files. `C4Canvas.onViewChange?` is optional (`c4-shared.tsx:162`) so dropping the prop is safe. |

## User-Brand Impact

**If this lands broken, the user experiences:** the C4 diagram workspace fails to render
(blank right panel) or the diagram canvas loses drill-down navigation. Both are prevented by
the fact that `C4Canvas` owns its own internal view state — the parent mirror being removed
is display-only.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this is a
display-label removal with no data path, no auth surface, no persistence, and no network
call. Nothing is read or written.

**Brand-survival threshold:** `none` — a cosmetic label removal on an authenticated,
operator-only KB diagram surface. Reason for `none`: no user data, no external exposure
vector, no sensitive path touched (per preflight Check 6 — the edited files are
`components/kb/*.tsx`, outside the sensitive-path regex).

## Files to Edit

- `apps/web-platform/components/kb/c4-workspace.tsx`
  - Remove the breadcrumb `<span>` (lines **157-159**): `Architecture · {currentView}`.
  - Remove the orphaned state declaration (line **48**): `const [currentView, setCurrentView] = useState(viewId);`.
  - Remove the `onViewChange={setCurrentView}` prop from `<C4Canvas …>` (line **108**).
  - **Preserve** the surrounding `ml-auto flex items-center gap-1.5 pr-1` group and the
    Collapse-Concierge chevron `<button>` (lines 160-170) — only the `<span>` is removed.
    After removal the group holds just the chevron; the chevron stays right-aligned via
    `ml-auto`, so no flex realignment is needed. Verify the chevron alignment is unchanged.
- `apps/web-platform/components/kb/c4-diagram.tsx`
  - Remove the breadcrumb `<span>` (lines **62-64**): `Architecture · {currentView}`.
    Note this span carries `ml-auto` itself (`<span className="ml-auto pr-1 …">`) — it is the
    only right-aligned element in this header. After removal there is no `ml-auto` consumer,
    which is fine (the Diagram|Code tabs simply left-align). No replacement needed.
  - Remove the orphaned state declaration (line **38**): `const [currentView, setCurrentView] = useState(viewId);`.
  - Remove the `onViewChange={setCurrentView}` prop from `<C4Canvas …>` (line **84**).

## Files to Create

None.

## Open Code-Review Overlap

None. (Checked `gh issue list --label code-review --state open` against both edited file
paths at plan time — no open scope-out names `c4-workspace.tsx` or `c4-diagram.tsx`.)

## Implementation Phases

### Phase 0 — Preconditions (re-verify before editing)

1. `cd apps/web-platform` and confirm the two spans still sit at the cited lines (a prior
   edit could have shifted them): `grep -n "Architecture · " components/kb/c4-workspace.tsx components/kb/c4-diagram.tsx` → expect exactly 2 hits.
2. Confirm `C4Canvas.onViewChange` is still optional: `grep -n "onViewChange" components/kb/c4-shared.tsx` → expect `onViewChange?: (viewId: string) => void;`.
3. Confirm no test asserts the breadcrumb text: `grep -rn "Architecture ·\|currentView" test/` → only producer-side mocks, no `Architecture ·` assertion. (`c4-theme.test.ts:48-51` guards `"LikeC4 ·"` branding — a DIFFERENT label — and will NOT break.)

### Phase 1 — Edit `c4-workspace.tsx`

1. Delete the breadcrumb `<span>` (lines 157-159), keeping the enclosing `ml-auto` group and chevron button intact.
2. Delete the `currentView` state declaration (line 48).
3. Delete `onViewChange={setCurrentView}` from the `<C4Canvas>` call (line 108).

### Phase 2 — Edit `c4-diagram.tsx`

1. Delete the breadcrumb `<span>` (lines 62-64).
2. Delete the `currentView` state declaration (line 38).
3. Delete `onViewChange={setCurrentView}` from the `<C4Canvas>` call (line 84).

### Phase 3 — Verify

1. **Typecheck:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → clean.
   (Per repo convention; do NOT use `npm run -w` — the repo root declares no `workspaces`.)
2. **Tests (C4 cluster):** `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-workspace.test.tsx test/c4-diagram.test.tsx test/c4-shared.test.tsx test/c4-fullscreen.test.tsx test/c4-theme.test.ts test/shared-page-diagram.test.tsx` → all pass (none assert the breadcrumb; `c4-theme.test.ts`'s `"LikeC4 ·"` guard is unaffected).
3. **Residual grep:** `grep -rn "Architecture · \|currentView" components/kb/c4-workspace.tsx components/kb/c4-diagram.tsx` → **zero** hits in both files (span gone AND state swept).
4. **Visual (both toggle states):** Per learning `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`, confirm via the app (Playwright/manual) that:
   - **Workspace, Concierge expanded:** breadcrumb gone; collapse chevron still right-aligned; tabs unchanged.
   - **Workspace, Concierge collapsed:** right panel is unmounted entirely (header not rendered) — confirm collapse still works and reveal re-renders cleanly with no breadcrumb.
   - **Inline embed (`c4-diagram`):** breadcrumb gone; Diagram|Code tabs render; tab toggle still works.
   - Per learning `2026-06-04-vendored-library-css-hook-must-be-verified-against-rendered-dom-not-stylesheet.md`: confirm against the RENDERED DOM (not just source) that the label element is actually absent.
   - Per learning `2026-04-17-raf-batching-and-dead-ref-cleanup.md`: after removing the `onViewChange` wiring, confirm the diagram canvas still renders and drill-down navigation still works (canvas owns its own view state; the removed prop is the parent mirror only).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — breadcrumb removed:** `grep -c "Architecture · " apps/web-platform/components/kb/c4-workspace.tsx` returns `0` AND `grep -c "Architecture · " apps/web-platform/components/kb/c4-diagram.tsx` returns `0`.
- [ ] **AC2 — orphan state swept:** `grep -c "currentView" apps/web-platform/components/kb/c4-workspace.tsx` returns `0` AND `grep -c "currentView" apps/web-platform/components/kb/c4-diagram.tsx` returns `0`. (Asserts the removal is a clean sweep, not a span-only delete that leaves dead state.)
- [ ] **AC3 — typecheck clean:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits `0`.
- [ ] **AC4 — C4 tests pass:** `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-workspace.test.tsx test/c4-diagram.test.tsx test/c4-shared.test.tsx test/c4-fullscreen.test.tsx test/c4-theme.test.ts test/shared-page-diagram.test.tsx` exits `0`.
- [ ] **AC5 — canvas unchanged:** `C4Canvas` (`components/kb/c4-shared.tsx`) is NOT edited — the diagram's own drill-down view state and the optional `onViewChange?` signature are preserved (verify file unchanged in the diff).
- [ ] **AC6 — visual, both states:** Screenshot/observe the workspace with Concierge expanded (breadcrumb gone, chevron right-aligned, tabs intact) and the inline embed (breadcrumb gone, Diagram|Code toggle works). Diagram drill-down navigation still functions in both.

### Post-merge (operator)

- [ ] **AC7 — live render check (automatable):** On the deployed KB C4 diagram page, confirm the panel header no longer shows the `Architecture · …` label. Automation: Playwright MCP navigate to a KB diagram route + DOM assertion. Not operator-manual.

## Domain Review

**Domains relevant:** Product (mechanical UI-surface override — edits `components/**/*.tsx`).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline path; advisory tier auto-accepts)
**Skipped specialists:** none — this is a pure label REMOVAL (no new user-facing surface, no new component file, no copy added/changed beyond deletion). `ux-design-lead` is not required: `wg-ui-feature-requires-pen-wireframe` governs NEW UI surfaces; removing a label creates none. No `.pen` wireframe is warranted for deleting a status label.
**Pencil available:** N/A (no new UI surface — label removal only, no wireframe needed)

**Phase 4.9 UI-wireframe gate determination:** This plan edits `components/kb/*.tsx`, so the
mechanical glob superset (`components/**/*.tsx`) flags it as a UI-surface plan. However, the
change is a **pure removal of an existing status label** with **zero new components, pages,
layouts, flows, or interactive surfaces** and **no structural/layout change** — it matches the
`ui-surface-terms.md` **Excluded** carve-out ("pure copy or style tweaks with no
structural/layout change"). No `.pen` wireframe is produced because there is nothing to design:
the design action is "delete one element"; the surrounding header geometry is unchanged. This
is the same determination and the same precedent as **PR #4938** (2026-06-04, "remove LikeC4
logo + re-theme C4 visualizer"), which edited these exact two files (`c4-workspace.tsx` +
`c4-diagram.tsx`) to remove a UI label and shipped with `Pencil available: N/A (no new UI
surface — re-skin only, no wireframe needed)` and an explicit Phase 4.9 waiver. **Explicit
override:** the only UI surface shipped without wireframe review is the C4 panel header with the
`Architecture · {currentView}` label deleted; no design review is warranted for an element
deletion.

#### Findings

The mechanical UI-surface override fires because the plan edits `components/**/*.tsx`, forcing
Product-relevant = true. Classification is **ADVISORY** (modifies existing components, removes
a label, adds no new interactive surface). On the one-shot/pipeline path, ADVISORY auto-accepts.
No domain leader flagged a copywriter/content need — the change deletes text rather than
authoring it. No cross-domain (legal, finance, sales, marketing, support, ops) implications:
the surface is an authenticated operator-only KB diagram viewer with no data, billing, or
external-facing content.

## Observability

Skip — pure frontend label removal with deletes-only net effect on observable surface. No new
error path, no new server/infra code, no new failure mode. The edited files are client
components under `apps/web-platform/components/`; no `apps/*/server/`, `apps/*/infra/`, or
`plugins/*/scripts/` file is touched. (Per Phase 2.9: skip silently when the plan is
frontend-component-only with no new error/failure surface.)

## Infrastructure (IaC)

None — pure code change against an already-provisioned surface. No server, service, cron,
secret, DNS, vendor account, or persistent runtime process introduced. (Per Phase 2.8: a plan
that only edits files under `apps/<app>/components/` skips.)

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| Removing `onViewChange` breaks diagram drill-down navigation. | Very low | `C4Canvas` owns its own `currentView` state (`c4-shared.tsx:164`) and `onViewChange?` is optional; the parent prop is a display mirror only. AC5 + Phase 3 visual check confirm. |
| A test asserts the breadcrumb text and goes red. | None (verified) | No test asserts `Architecture ·`; `c4-theme.test.ts:48-51` guards the unrelated `"LikeC4 ·"` branding string. AC4 confirms. |
| Removing the only `ml-auto` element in `c4-diagram.tsx` header misaligns remaining tabs. | Low | The remaining Diagram\|Code tabs are `gap-1` left-aligned by default; with no right-aligned element they simply left-align — the intended result. Phase 3 visual check on the inline embed confirms. |
| Span-only delete leaves orphaned `currentView` dead code (silent, since no CI lint/`noUnusedLocals`). | Medium if not swept | AC2 greps `currentView` count == 0 in both files — fails the PR if the sweep is incomplete. |

### Research Insights

**Verify-the-negative pass (all CONFIRMED against live source):**

- `c4-workspace.tsx`: `currentView` declared at `:48`, written only via `onViewChange={setCurrentView}` at `:108`, read only by the span at `:157-159`. No other reader. Safe to sweep.
- `c4-diagram.tsx`: `currentView` at `:38`, written at `:84`, read only by the span at `:62-64` (span carries `ml-auto pr-1`). Safe to sweep.
- `c4-shared.tsx:162` — `onViewChange?: (viewId: string) => void;` is OPTIONAL → dropping the prop is type-safe.
- `c4-shared.tsx:164` — `C4Canvas` owns its OWN `const [currentView, setCurrentView] = useState(initialViewId);` for drill-down; the parent mirror is redundant. Removing it has zero navigation effect.
- `test/`: no assertion on `Architecture ·`. `c4-theme.test.ts:48-51` guards only the unrelated `"LikeC4 ·"` upstream-branding string.
- `tsconfig.json`: `strict: true`, no `noUnusedLocals`/`noUnusedParameters` → orphaned `currentView` is NOT a `tsc` error (hence AC2's grep is the load-bearing sweep gate).

**Precedent-diff (Phase 4.4 — pattern-bound UI-label removal):**

- **PR #4938** (`d6823197`, MERGED 2026-06-04, verified via `gh pr view 4938`) removed the LikeC4 logo from `c4-workspace.tsx` + `c4-diagram.tsx` — the same two files, same panel header, same "remove a label" shape. It shipped without a `.pen` via an explicit Phase 4.9 waiver. This plan adopts the identical determination and override language. The pattern is NOT novel; it has a directly-applicable precedent.

**Edge cases handled:**

- Both Concierge toggle states (expanded / collapsed) verified per learning `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md` — collapsed unmounts the panel entirely, so the header (and thus the removed label) is not rendered; only the expanded state shows the change.
- Rendered-DOM verification (not source-only) per learning `2026-06-04-vendored-library-css-hook-must-be-verified-against-rendered-dom-not-stylesheet.md` — confirm the label element is actually absent in the live DOM.
- Dead-ref cleanup hazard per learning `2026-04-17-raf-batching-and-dead-ref-cleanup.md` — after dropping `onViewChange`, confirm the canvas still renders and drill-down works (canvas owns view state).

**References:**

- `apps/web-platform/components/kb/c4-shared.tsx:155-177` (C4Canvas prop contract + internal view state + `onViewChange?` effect).
- PR #4938 plan: `knowledge-base/project/plans/2026-06-04-feat-likec4-remove-logo-soleur-theme-plan.md` (precedent for the Phase 4.9 waiver pattern).

## Out of Scope / Non-Goals

- No change to `C4Canvas` internal view state, drill-down behavior, or `onViewChange?`
  signature in `c4-shared.tsx`.
- No restyling of the panel header beyond removing the span (chevron, tabs, borders, padding
  unchanged).
- No change to the public read-only share variant beyond the inline-embed breadcrumb removal
  (the `c4-diagram.tsx` edit already covers the shared-page render path via
  `shared-page-diagram.test.tsx`).

## Sharp Edges

- The literal source text is `Architecture · {currentView}`, not `Architecture · context »`.
  The view id (`context`) is runtime data and the `»` is not in source — do not grep for the
  `»` glyph or hard-code the view id; remove the whole span.
- This is a paired-UI element across two files. Removing only `c4-workspace.tsx` leaves the
  inline-embed breadcrumb live and guarantees a follow-up PR — both must land together
  (Scope Decision above).
- `currentView` removal is a sweep, not a span delete. `noUnusedLocals` is NOT set and no
  ESLint runs in CI, so an orphaned `currentView` ships green and silent — AC2's grep count
  is the only gate that catches an incomplete sweep. Do not rely on `tsc` to flag it.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is
  filled with threshold `none` + reason.)

## Test Scenarios

1. **Workspace, Concierge expanded:** open a KB C4 diagram → right panel header shows
   Concierge\|Code tabs + collapse chevron, NO `Architecture · …` label.
2. **Workspace, drill-down:** click a node to drill into a sub-view → diagram navigates
   correctly (canvas owns view state); no label updates because the label is gone.
3. **Workspace, collapse/reveal:** collapse the Concierge → right panel unmounts; reveal via
   the top-bar trigger → panel re-renders with no breadcrumb, Concierge thread resumes.
4. **Inline embed:** render a markdown doc with a `likec4-view` fenced block → Diagram\|Code
   header shows tabs, NO `Architecture · …` label; toggling Diagram↔Code still works.
5. **Public share read-only:** open a shared diagram link → read-only inline embed renders
   with no Code tab and no breadcrumb (`shared-page-diagram.test.tsx` path).
