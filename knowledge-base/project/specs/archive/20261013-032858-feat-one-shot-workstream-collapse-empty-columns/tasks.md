---
title: "Tasks — Workstream: collapse empty columns by default"
branch: feat-one-shot-workstream-collapse-empty-columns
lane: single-domain
plan: knowledge-base/project/plans/2026-06-29-feat-workstream-collapse-empty-columns-plan.md
---

# Tasks — Workstream: collapse empty columns by default

Derived from `2026-06-29-feat-workstream-collapse-empty-columns-plan.md`.
Single client component + its two test files. No new files; no server/infra.

## Phase 1 — Invert the empty-column rule (component)

- [x] 1.1 In `apps/web-platform/components/workstream/issue-column.tsx`, replace
  `const isCollapsed = collapsed && !isEmpty;` (line 79) with
  `const isCollapsed = isEmpty || collapsed;` and add the INVARIANT comment
  (empty ⇒ collapsed; expanded branch never sees an empty column).
- [x] 1.2 In the collapsed branch (lines 91-119), gate the Expand `<button>` on
  `{!isEmpty ? (...) : null}` so an empty collapsed strip has no toggle.
- [x] 1.3 In the collapsed branch, add a `sr-only` empty-state announcement so the
  empty strip is not conveyed by a bare `0` to screen readers (deepen P2 a11y):
  `{isEmpty ? <span className="sr-only">No issues</span> : null}` alongside the
  dot / count / label. (`sr-only` is in use already — `attachment-display.tsx:122`.)

## Phase 2 — Remove unreachable expanded-empty code

- [x] 2.1 Remove the `{!isEmpty ? (<Collapse button/>) : null}` guard in the
  expanded branch (lines 124-135) — always render the Collapse button there.
- [x] 2.2 Remove the `isEmpty ? (<p>No issues</p>) : (<>cards</>)` conditional
  (lines 148-165) — always render the cards block.
  - (Conservative fallback: skip Phase 2 entirely if review prefers minimal diff;
    behavior is identical — the expanded-empty path is provably dead.)

## Phase 3 — Docs

- [x] 3.1 Rewrite the "Empty rule" header comment (lines 16-17) to describe the
  collapse-by-default behavior (v4).

## Phase 4 — Tests

- [x] 4.1 `test/components/workstream/issue-column.test.tsx`: rewrite the
  `empty column has no toggle` block to assert the **collapsed strip** —
  `<section>` class contains `w-10` (not `w-72`), no Collapse/Expand button — for
  both `collapsed` unset and `collapsed=true`.
- [x] 4.2 Add an assertion that the empty collapsed strip shows the `0` count and
  the column label.
- [x] 4.2b Add an assertion that the empty collapsed strip renders the `sr-only`
  "No issues" announcement (`getByText("No issues")` present when `issues=[]`).
- [x] 4.3 `test/components/workstream/workstream-board.test.tsx`: add a
  board-level assertion that, with one Backlog issue loaded, a sibling empty
  column (`<section aria-label="Todo">`) renders as a `w-10` collapsed strip with
  no toggle.
- [x] 4.4 Verify the existing board collapse/persist test (lines 333-354) stays
  green with no edits (Backlog stays non-empty/expanded).

## Phase 5 — Verify

- [x] 5.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/components/workstream/` green.
- [x] 5.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [x] 5.3 Eyeball the populated board: empty columns are thin strips; populated
  columns unaffected.
