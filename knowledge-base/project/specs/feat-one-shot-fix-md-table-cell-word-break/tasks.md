# Tasks — fix: markdown table data cells break short words mid-character

Derived from `knowledge-base/project/plans/2026-06-16-fix-md-table-cell-word-break-plan.md`.

Lane: `single-domain` (no spec.md present; set from plan frontmatter — leaf
component CSS change in a single package).

## Phase 1 — RED (failing test first)

- [ ] 1.1 In `apps/web-platform/test/markdown-renderer.test.tsx`, extend the
  `MarkdownRenderer — table column widths` describe block (lines 64-101) with a
  new assertion that every rendered `<td>` className contains `break-normal`.
  Reuse the existing `tableMd` fixture or add a fixture with a short-word data
  cell (e.g. `| active | deferred |`). Assert on `td.className` string only
  (happy-dom: no computed-style / layout).
- [ ] 1.2 Add the negative assertion: the `<td>` does NOT carry a literal
  `[overflow-wrap:anywhere]` class (it only inherits via cascade; `break-normal`
  overrides it).
- [ ] 1.3 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/markdown-renderer.test.tsx`
  and confirm the new assertion(s) FAIL against the unmodified component
  (capture RED output).

## Phase 2 — GREEN (minimal fix)

- [ ] 2.1 In `apps/web-platform/components/ui/markdown-renderer.tsx`, add
  `break-normal` to the `<td>` className in `buildComponents` (line 78-79).
  Single-line change. Do NOT modify the `<table>` element, the `<th>` className,
  or the container `<div>`'s `[overflow-wrap:anywhere]`. Keep the explanatory
  comment block (lines 75-77).
- [ ] 2.2 Re-run the vitest file; confirm all tests pass (existing 7 + new).

## Phase 3 — Verify

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/markdown-renderer.test.tsx`
  — full file green.
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — no NEW
  type errors from this change (note any pre-existing errors; do not fix them).
- [ ] 3.3 Confirm the AC checklist in the plan's `### Pre-merge (PR)` section is
  satisfied (regression guards for container `min-w-0`/`[overflow-wrap:anywhere]`,
  `<th>` `whitespace-nowrap`, `<td>` width band, table `w-auto` all still green).

## Out of scope

- No `<table>`-element class change (redundant; `<td>` override is sufficient).
- No removal of the container `[overflow-wrap:anywhere]` (intentional for
  non-table prose/URLs — #2229).
- No Playwright/e2e pass required (pure CSS-class contract, `User-Brand Impact:
  none`; unit className assertion is the gate).
