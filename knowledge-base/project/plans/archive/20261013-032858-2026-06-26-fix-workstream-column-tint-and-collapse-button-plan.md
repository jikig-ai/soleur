---
title: "fix(web): visible Workstream column tints + a real collapse icon-button"
date: 2026-06-26
type: fix
branch: feat-one-shot-workstream-column-colors-collapse-btn
lane: single-domain
brand_survival_threshold: none
status: ready
references:
  - PR #5659 (shipped Workstream kanban board)
  - knowledge-base/product/design/workstream/screenshots/01-workstream-kanban-board.png (binding mock)
  - knowledge-base/product/design/workstream/workstream-kanban.pen (committed wireframe source)
---

# fix(web): visible Workstream column tints + a real collapse icon-button ✨

## Enhancement Summary

**Deepened on:** 2026-06-26
**Sections enhanced:** Implementation Phases, Domain Review, + new Observability section
**Verification done in this pass (grounded against the worktree, not memory):**

1. `ChevronDownIcon` exists at `components/icons/index.tsx:110` (down-pointing
   `<polyline points="6 9 12 15 18 9" />`, `stroke="currentColor"`). Confirmed
   in-repo, so item 2 needs **no** new icon and **no** inline SVG.
2. Import convention confirmed: `import { ChevronDownIcon } from "@/components/icons";`
   — used verbatim in `connect-repo/select-project-state.tsx:5` and
   `kb/c4-shared.tsx:20`. The icon is already used with `className` rotation +
   sizing (`c4-shared.tsx:542` → `h-3 w-3 … -translate-y-1/2`), establishing the
   sizing/transform precedent this plan reuses.
3. The committed `.pen` wireframe source
   `knowledge-base/product/design/workstream/workstream-kanban.pen` and the
   signed-off PNG mock both exist on the branch — the binding design references
   already exist (Phase 4.9 wireframe gate satisfied).
4. `workstream-board.test.tsx:227,232` queries the toggle by `aria-label`
   ("Collapse Backlog" / "Expand Backlog") — since this change preserves the
   `aria-label`, the existing board test stays green with **no edits**
   (verify-the-negative pass on "no edits to workstream-board.tsx").
5. `hover:bg-soleur-bg-surface-2` is the board's hover convention
   (`issue-card.tsx:25`); inputs use `focus:outline-none`
   (`workstream-board.tsx:210`). The affordance classes in Phase 2 reuse these
   existing tokens — no new color token introduced.

### Key Improvements over the round-1 plan
1. Icon reuse pinned to the exact existing export + import path (zero new icon code).
2. 8-digit `#RRGGBBAA` hex support confirmed as universally supported; tint band fixed at `0x1f`–`0x33`.
3. Added the gate-required `## Observability` section (client-render surface, no SSH).

## Overview

Two operator-requested polish changes to the Workstream kanban board shipped in
PR #5659. Both are visual-only refinements to a single client component
(`apps/web-platform/components/workstream/issue-column.tsx`) against the
already-committed, operator-signed-off design mock
(`knowledge-base/product/design/workstream/screenshots/01-workstream-kanban-board.png`).
The data layer, the GitHub-issues reader, and the Concierge field are **out of
scope** and must not change.

1. **Restore visible colored column backgrounds.** The two render branches
   currently tint with `backgroundColor: \`${column.accent}0d\`` — hex alpha
   `0d` = 13/255 ≈ **5%**, which on the near-black board surface reads as flat
   near-black (operator complaint). The mock shows each column carrying a soft,
   clearly-perceptible colored wash behind its cards. Raise the tint to a
   tasteful ~15% (hex alpha `26`), applied **consistently** to both the expanded
   column (line 71) and the collapsed strip (line 37).

2. **A real collapse/expand icon-button.** The toggle is currently a bare
   unicode glyph (`⌄` expanded, line 81; `›` collapsed, line 46) with no button
   affordance. Replace the glyph with the existing `ChevronDownIcon`
   (`components/icons/index.tsx:110`) — pointing down in the expanded state,
   rotated to point right (`-rotate-90`) in the collapsed strip — and give the
   button a hover/focus background, border-radius, and clear affordance
   consistent with the board's other controls. The existing `aria-label`,
   `aria-expanded`, and localStorage-persisted collapse behaviour stay intact.

## Research Reconciliation — Spec vs. Codebase

| Claim (from ARGUMENTS) | Reality in repo | Plan response |
| --- | --- | --- |
| "~5% accent tint `${column.accent}0d`" | Confirmed — `0d` = 5% at both line 37 (collapsed) and line 71 (expanded) | Raise both to `26` (~15%) via one shared const |
| "use the existing icon set in `components/icons` if a chevron exists, otherwise inline SVG" | `ChevronDownIcon` **exists** at `components/icons/index.tsx:110` (down-pointing `<polyline points="6 9 12 15 18 9" />`) | Reuse it; no new icon, no inline SVG |
| "Keep existing aria-labels / aria-expanded / localStorage" | Board owns collapsed state (`workstream-board.tsx:32` `COLLAPSED_STORAGE_KEY`, persisted at :156); button carries `aria-label="Collapse/Expand <label>"` + `aria-expanded` | Touch only the icon glyph + button affordance classes; leave aria + handlers byte-for-byte |
| "add/adjust coverage for the collapse button" | No `issue-column.test.tsx` exists; board collapse/persist is covered by `test/components/workstream/workstream-board.test.tsx:218` | Add a focused `issue-column.test.tsx`; keep the board test green (it asserts via `aria-label`, which is unchanged) |

## User-Brand Impact

**If this lands broken, the user experiences:** a Workstream board whose columns
still read as flat near-black (tint regression) or a collapse control that looks
like stray text rather than a button — cosmetic only; no data loss, no broken
flow.

**If this leaks, the user's data is exposed via:** N/A — this change touches no
data, no persistence beyond the pre-existing client-only `collapsed-columns`
localStorage key, no network, no server code.

**Brand-survival threshold:** none — a client-only visual refinement to an
already-shipped component; no sensitive path is touched (preflight Check 6
regex covers schemas/migrations/auth/API, none of which this diff hits).

## Implementation Phases

### Phase 1 — Restore visible column tints

In `apps/web-platform/components/workstream/issue-column.tsx`:

1. Add a single module-level constant so both branches stay in lockstep (a
   shared const is the structural guard against the "fix one toggle state, miss
   the other" defect — see Sharp Edges):

   ```tsx
   // ~15% accent wash — visible soft tint behind the cards, not a saturated
   // block (operator sign-off 2026-06-26, matches 01-workstream-kanban-board.png).
   const COLUMN_TINT_ALPHA = "26"; // hex 0x26 = 38/255 ≈ 15%
   ```

2. Replace **both** occurrences of `backgroundColor: \`${column.accent}0d\``
   (collapsed branch line 37, expanded branch line 71) with
   `backgroundColor: \`${column.accent}${COLUMN_TINT_ALPHA}\``.

3. Update the stale `~5%` code comments (lines 3-4 header block and line 70) to
   describe the new ~15% wash.

4. **Eyeball against the mock.** Run the board locally (or compare the rendered
   column against `01-workstream-kanban-board.png`). If `26` reads too strong or
   too weak, tune within the **`0x1f`–`0x33` (12%–20%)** band — stay subtle, not
   a saturated block. Do not exceed `0x33`.

### Phase 2 — Real collapse/expand icon-button

In the same file:

1. Import the existing icon: `import { ChevronDownIcon } from "@/components/icons";`
   (confirm the import path/alias matches sibling usage; `components/icons/index.tsx`
   exports `ChevronDownIcon`).

2. **Expanded branch** (header button, lines 74-82): replace
   `<span aria-hidden="true">⌄</span>` with
   `<ChevronDownIcon className="h-3.5 w-3.5" />` (down chevron = "collapse").

3. **Collapsed strip** (button, lines 39-47): replace
   `<span aria-hidden="true">›</span>` with
   `<ChevronDownIcon className="h-3.5 w-3.5 -rotate-90" />` (down chevron rotated
   −90° points **right** = "expand"). Verify rotation direction renders a
   right-pointing chevron; if it points left, use `rotate-90` instead.

4. **Affordance** on both buttons — extend the existing className
   (`flex h-5 w-5 items-center justify-center rounded-md text-soleur-text-tertiary transition-colors hover:text-soleur-text-primary`,
   `h-6 w-6` on the collapsed strip) with a hover/focus background consistent
   with the board's controls (`hover:bg-soleur-bg-surface-2` is the convention
   already used in `issue-card.tsx:25`; inputs use `focus:outline-none` per
   `workstream-board.tsx:210`):

   ```text
   hover:bg-soleur-bg-surface-2 focus-visible:bg-soleur-bg-surface-2
   focus-visible:text-soleur-text-primary focus-visible:outline-none
   ```

   Keep `rounded-md`. The `ChevronDownIcon` SVG inherits color via
   `stroke="currentColor"`, so the existing text-color classes drive it.

5. **Do not touch** `aria-label`, `aria-expanded`, `onClick`/`onToggleCollapse`,
   or any state — only the glyph and the button's visual classes change.

### Phase 3 — Tests

Add `apps/web-platform/test/components/workstream/issue-column.test.tsx`
(matches the vitest `test/**/*.test.tsx` happy-dom project — see
`vitest.config.ts:63-64`; co-located component tests are NOT collected, so it
must live under `test/`). Render `IssueColumn` directly with a minimal
`ColumnConfig` + issue array. Cover:

- **Expanded:** the `Collapse <label>` button exists, has `aria-expanded="true"`,
  and renders an `<svg>` (the chevron icon) — assert via
  `button.querySelector("svg")` is truthy, proving the glyph→icon swap.
- **Collapsed:** with `collapsed`, the `Expand <label>` button exists, has
  `aria-expanded="false"`, and renders an `<svg>`.
- **Toggle callback:** clicking the button calls `onToggleCollapse` with
  `column.status`.
- **Tint applied to both branches:** the `<section>` `style.backgroundColor`
  carries the accent with a **non-`0d`** alpha (assert it ends in the chosen
  alpha, e.g. `toContain("26")`, OR simply assert it is not the old `0d` value)
  in BOTH the expanded and collapsed renders.

Keep `test/components/workstream/workstream-board.test.tsx` green — its collapse
test (line 218) queries by `aria-label` ("Collapse Backlog" / "Expand Backlog"),
which this change preserves, so it must not need edits.

## Files to Edit

- `apps/web-platform/components/workstream/issue-column.tsx` — tint const + both
  `backgroundColor` sites; `ChevronDownIcon` import + both glyph swaps; button
  affordance classes; comment refresh.

## Files to Create

- `apps/web-platform/test/components/workstream/issue-column.test.tsx` —
  focused coverage for the icon-button + tint on both branches.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Both render branches of `issue-column.tsx` set
  `backgroundColor` to `\`${column.accent}${COLUMN_TINT_ALPHA}\`` with a single
  shared `COLUMN_TINT_ALPHA` const; the literal `0d` no longer appears in the
  file (`grep -c '}0d`' returns 0`).
- [ ] `COLUMN_TINT_ALPHA` is within `0x1f`–`0x33` (12%–20%).
- [ ] Neither branch renders a bare `⌄` or `›` glyph; both buttons render
  `<ChevronDownIcon>` (collapsed strip rotated to point right). `grep -F '⌄' issue-column.tsx`
  and `grep -F '›' issue-column.tsx` both return nothing.
- [ ] Both buttons retain `aria-label` ("Collapse <label>" / "Expand <label>"),
  `aria-expanded` (`true` expanded / `false` collapsed), `rounded-md`, and gain a
  hover **and** focus background (`hover:bg-…` + `focus-visible:bg-…`).
- [ ] `onToggleCollapse` / localStorage persistence path is byte-for-byte
  unchanged (no edits to `workstream-board.tsx`).
- [ ] New `issue-column.test.tsx` passes and asserts: icon `<svg>` present in
  both states, `aria-expanded` per state, toggle callback fires, non-`0d` tint
  on both branches.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/components/workstream/`
  is green (board test + new column test).
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] Rendered board visually matches the tint level in
  `01-workstream-kanban-board.png` (eyeball check noted in PR description).

## Observability

This is a **client-rendered** React component (`apps/web-platform/components/`);
it ships no server route, no Inngest function, no infra. Its observability
surface is the browser render path, covered by the app's existing client error
plumbing and by CI unit tests — no new server liveness signal is introduced.

```yaml
liveness_signal:
  what: IssueColumn renders 7 columns on the /dashboard/workstream board
  cadence: per page load (client); asserted on every PR run in CI
  alert_target: CI red on the vitest workstream suite (PR-blocking)
  configured_in: apps/web-platform/test/components/workstream/ (vitest, happy-dom project)
error_reporting:
  destination: existing client Sentry browser SDK + the dashboard React error boundary (no new path added by this change)
  fail_loud: a render-time throw surfaces in the dashboard error boundary, not a silent blank column
failure_modes:
  - mode: tint reverts to flat near-black (alpha drift back toward 0d)
    detection: vitest assertion that backgroundColor carries a non-0d alpha on both branches
    alert_route: CI red (PR-blocking)
  - mode: chevron glyph renders instead of the icon button (icon import regressed)
    detection: vitest assertion that the toggle button contains an <svg>
    alert_route: CI red (PR-blocking)
  - mode: aria-label / aria-expanded regression breaks the collapse control contract
    detection: existing workstream-board.test.tsx collapse test + new aria assertions
    alert_route: CI red (PR-blocking)
logs:
  where: browser console only (client component); no new server-side log lines
  retention: N/A (client-side; nothing persisted beyond the pre-existing collapsed-columns localStorage key)
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/components/workstream/"
  expected_output: all tests pass (board suite + new issue-column suite), no SSH required
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
mock `…/screenshots/01-workstream-kanban-board.png`, plus the "Design Revision
Addendum (operator sign-off 2026-06-26)" recorded in `lib/workstream.ts:7`. This
change is a *correction toward* that frozen design — the tint is too faint vs.
the mock; the chevron lacks affordance — not a new surface or flow. Regenerating
wireframes would be ceremony. The committed `.pen` satisfies the
`wg-ui-feature-requires-pen-wireframe` deepen-plan gate.)
**Pencil available:** N/A (no new design surface; refining an existing,
already-designed component)

#### Findings

The change modifies one existing client component to better match an
already-approved mock; it adds no new page, flow, modal, or interactive surface.
The mechanical UI-surface trigger fires (a `components/**/*.tsx` path is in Files
to Edit), but the only new file is a test, not a component — so the BLOCKING
"new component file" escalation does not apply. Treated as ADVISORY,
auto-accepted in the non-interactive pipeline. The binding visual reference is
the committed mock; QA/PR-review should compare the rendered tint against it.

## Test Scenarios

| Scenario | Expectation |
| --- | --- |
| Expanded column renders | `Collapse <label>` button present, `aria-expanded="true"`, contains an `<svg>` chevron |
| Collapsed strip renders | `Expand <label>` button present, `aria-expanded="false"`, contains an `<svg>` chevron (right-pointing) |
| Click toggle | `onToggleCollapse(column.status)` called once |
| Tint — expanded | `<section>` backgroundColor = accent + chosen alpha (not `0d`) |
| Tint — collapsed | same alpha as expanded (lockstep via shared const) |
| Board collapse/persist (existing) | still green — queries by `aria-label`, unchanged |

## Sharp Edges / Risks

- **Both toggle states must change together.** The collapsed strip and expanded
  column are two separate return branches that each carry their own
  `backgroundColor` and their own button glyph. A fix to one that misses the
  other is the documented failure mode for toggleable controls (learning
  `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`; PR #2494→#2504).
  The shared `COLUMN_TINT_ALPHA` const and the two-branch test assertions are the
  guards — verify the tint AND the icon in BOTH states.
- **Tailwind tokens are pre-existing.** `bg-soleur-bg-surface-2`,
  `soleur-text-tertiary`, `soleur-text-primary`, `soleur-border-default` are
  already used in `issue-column.tsx` / `issue-card.tsx`, so the affordance classes
  are valid; do not introduce a new color token.
- **`-rotate-90` direction.** A down chevron rotated −90° should point right
  (expand). If the rendered glyph points left, swap to `rotate-90`. Confirm
  visually before merge; the test asserts presence of the `<svg>`, not its angle.
- **Tint is alpha-on-hex.** `column.accent` values are 6-digit hex
  (`lib/workstream.ts:74-82`); appending a 2-digit alpha yields valid 8-digit
  `#RRGGBBAA`, which every target browser supports. Do not change the accent hex
  values themselves (data layer — out of scope).
- **Empty `## User-Brand Impact` fails deepen-plan Phase 4.6** — section is
  filled above (threshold: none, no sensitive path).
- This plan introduces no infrastructure, no migration, no ADR/C4 change, no
  regulated-data surface, and no server/`src`/`infra` code — so the IaC (2.8),
  Observability (2.9), ADR/C4 (2.10), and GDPR (2.7) gates all skip silently.
