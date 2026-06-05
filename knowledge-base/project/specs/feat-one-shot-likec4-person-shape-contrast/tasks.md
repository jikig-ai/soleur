---
title: "Tasks — fix LikeC4 person-shape text contrast"
branch: feat-one-shot-likec4-person-shape-contrast
lane: single-domain
plan: knowledge-base/project/plans/2026-06-05-fix-likec4-person-shape-text-contrast-plan.md
date: 2026-06-05
---

# Tasks — fix: LikeC4 person-shape text contrast

Derived from `2026-06-05-fix-likec4-person-shape-text-contrast-plan.md`.

## 1. Setup / Preconditions (verify, no code)

- [x] 1.1 Re-confirm installed-library hooks (Phase 0):
  - [x] 1.1.1 `grep -n 'data-likec4-fill: "mix-stroke"' apps/web-platform/node_modules/@likec4/diagram/dist/base-primitives/element/ElementShape.js` (present in `person` case).
  - [x] 1.1.2 `grep -n 'data-likec4-shape' apps/web-platform/node_modules/@likec4/diagram/dist/base-primitives/element/ElementNodeContainer.js` (container emits `data-likec4-shape`).
  - [x] 1.1.3 `grep -o 'mix-stroke]{[^}]*}' apps/web-platform/node_modules/@likec4/diagram/dist/styles.css2.js` → confirms stroke-tinted `color-mix`.
- [x] 1.2 Confirm `c4-visualizer` flag ON for dev cohort + dev viewer route reachable (running-viewer check feasible).

## 2. Core Implementation

- [x] 2.1 Edit `apps/web-platform/components/kb/c4-theme.css` — add §2c person-silhouette
  legibility rule scoped to `.soleur-c4`, keyed on `[data-likec4-shape="person"]`
  + `[data-likec4-fill="mix-stroke"]`; re-point `fill` to `var(--likec4-palette-fill)`
  (off the 80%-gold mix) and lower `opacity` (~0.35), both `!important`, with the
  explanatory comment. [Plan AC1/AC2/AC3]
- [x] 2.2 Tune opacity within `[0.25, 0.5]` (or use a low-% gold `color-mix`) per the
  Phase 4 visual check so the silhouette reads as a faint person without smearing the
  text. [Plan Phase 1 tuning note]
  - NOTE (deepen): the descendant selector `[data-likec4-shape="person"] [data-likec4-fill="mix-stroke"]`
    resolves correctly (verified DOM nesting). Do NOT over-narrow it to exclude the
    `data-likec4-shape-multiple` copy — `ShapeSvg` can render twice and toning both is
    correct. `opacity` is safe (lone `<path>`, no siblings).

## 3. Testing

- [x] 3.1 Edit `apps/web-platform/test/c4-theme.test.ts` — add `it(...)`:
  - [x] 3.1.1 Assert `c4-theme.css` contains the person-silhouette rule (scoped, both
    attrs, `!important`, references `var(--`). [AC1/AC2/AC3]
  - [x] 3.1.2 Assert installed `ElementShape.js` still contains `data-likec4-fill: "mix-stroke"`
    (define path constant like `LIKEC4_LOGO`). [AC4]
- [x] 3.2 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-theme.test.ts` — all green. [AC5]
- [x] 3.3 Visual check (Playwright MCP) — Founder node in System Context view, both
  `data-theme` light + dark: title/description legible, silhouette a faint gold accent.
  Capture before/after × {light, dark} screenshots for the PR body. [AC6]

## 4. Ship

- [x] 4.1 PR body: root cause (mix-stroke 80%-gold + label overrun), the CSS fix,
  before/after screenshots per theme. `Ref`/`Closes` the tracking issue if one exists.
