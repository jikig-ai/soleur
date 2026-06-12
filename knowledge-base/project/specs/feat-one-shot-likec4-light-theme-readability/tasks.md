---
title: "Tasks — fix: LikeC4 light-theme readability"
plan: knowledge-base/project/plans/2026-06-12-fix-likec4-light-theme-readability-plan.md
branch: feat-one-shot-likec4-light-theme-readability
lane: single-domain
date: 2026-06-12
---

# Tasks — LikeC4 light-theme readability

Derived from `2026-06-12-fix-likec4-light-theme-readability-plan.md`. Two coordinated
levers: (1) bind Mantine color scheme to Soleur `data-theme` (the seam fix — load
bearing), (2) light-scoped node-separation + edge-label contrast tuning.

## Phase 0 — Preconditions (verify, no code)

- [ ] 0.1 Re-confirm the Mantine seam: `DefaultMantineProvider.js:67` is
  `defaultColorScheme:"auto"`; `EnsureMantine.js:13` defers to an existing
  `MantineContext`; no `MantineProvider` exists in `apps/web-platform/app|components`.
- [ ] 0.2 Confirm light-branch edge-label rule + DOM hooks in `styles.css2.js`:
  `[data-mantine-color-scheme=light] … --xy-edge-label-color/-background-color`, and
  `.likec4-edge-label { color/background: var(--xy-edge-label-*) }` +
  `.react-flow__edge-text { fill: var(--xy-edge-label-color) }`.
- [ ] 0.3 **Lever-1 mechanism = 1a (resolved at deepen-plan; re-confirm facts).**
  `use-provider-color-scheme.cjs:10` writes `data-mantine-color-scheme` to
  `getRootElement()` = `<html>` (so 1b wrapper-attr is NOT viable);
  `MantineProvider.d.ts:16` has `forceColorScheme?: 'light'|'dark'`;
  `EnsureMantine.js:13` defers to our provider.
- [ ] 0.4 Confirm `@mantine/core` resolves: `node -e "require.resolve('@mantine/core')"`
  and capture the in-tree version for the package.json pin.
- [ ] 0.5 Confirm Soleur theme hook: `useTheme()` → `resolvedTheme: "light"|"dark"`
  (`components/theme/theme-provider.tsx:343`).
- [ ] 0.6 Confirm `c4-visualizer` flag ON for dev + viewer route reachable (MEMORY).

## Phase 1 — Lever 1: bind color scheme to `resolvedTheme` (seam fix, approach 1a)

- [ ] 1.1 In `components/kb/c4-shared.tsx`, wrap `<LikeC4Diagram>` at the `.soleur-c4`
  choke point (covers inline embed + fullscreen portal) in
  `<MantineProvider forceColorScheme={resolvedTheme}>`, where
  `const { resolvedTheme } = useTheme()` (from `components/theme/theme-provider.tsx`).
  Import `MantineProvider` from `@mantine/core`. Do NOT read `data-theme` off the DOM
  (non-reactive). Keep the provider scoped to the canvas (do not hoist to app root).
- [ ] 1.2 Add `"@mantine/core": "8.3.15"` (the version `@likec4/diagram@1.50.0` pins)
  to `apps/web-platform/package.json` deps — robustness (resolves via hoisting today
  but a stricter installer could un-hoist). Run the workspace install + lockfile-sync
  gate (`cq-before-pushing-package-json-changes`).

> Phase order: Lever 1 lands before/with Lever 2 (token correctness depends on the
> right scheme branch firing).

## Phase 2 — Lever 2: light-theme node separation + edge-label contrast

- [ ] 2.1 Add §4 (light-theme readability) to `components/kb/c4-theme.css`, scoped to
  `[data-mantine-color-scheme="light"] .soleur-c4` (light only — dark untouched).
- [ ] 2.2 Node separation: re-point the light-theme diagram `--likec4-palette-fill`
  to a surface distinct from the canvas (e.g. `--soleur-bg-surface-1` / near-white)
  AND/OR verify the gold stroke renders as a visible border. `!important`. Tuned by
  the Phase 3 visual check within AC bounds.
- [ ] 2.3 Edge-label contrast: darken light-theme `--likec4-palette-relation-label`
  toward `--soleur-text-primary` AND/OR raise `--xy-edge-label-background-color`
  opacity on `.soleur-c4 .likec4-edge-label`. `!important`, theme-aware var (no hex).
- [ ] 2.4 Confirm no `#3b82f6` regression and dark-theme path still resolves to the
  existing dark tokens.

## Phase 3 — Tests + verification

- [ ] 3.1 Extend `test/c4-theme.test.ts` (AC6):
  - New CSS-rule presence: light-scoped node + edge-label rules, theme-aware var,
    `!important`.
  - Installed-library seam guard: `styles.css2.js` still gates light rules on
    `[data-mantine-color-scheme=light]` and consumes `--xy-edge-label-color` /
    `--xy-edge-label-background-color` on `.likec4-edge-label` / `.react-flow__edge-text`.
  - Assert `c4-shared.tsx` wraps `<LikeC4Diagram>` in `<MantineProvider>` with
    `forceColorScheme`.
- [ ] 3.2 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-theme.test.ts`
  → green (all prior + new). NOT `bun test`.
- [ ] 3.3 **Visual verification (Playwright MCP, post-merge AC8):** open "Soleur
  Platform — System Context"; for Soleur Light + Dark assert nodes separate from
  canvas, edge labels legible, titles/descriptions legible, gold accent preserved.
  Capture before/after × {light, dark}.
- [ ] 3.4 **OS-mismatch regression (AC1):** emulate `prefers-color-scheme: dark` with
  Soleur Light → diagram renders light (`data-mantine-color-scheme=light` on the
  diagram subtree). Attach screenshots to PR body.

## Phase 4 — Ship

- [ ] 4.1 PR body: before/after screenshots (both themes + OS-mismatch), note the
  seam root cause + chosen Lever-1 mechanism. Acknowledge #3564 / #2349 (globals.css,
  unrelated) — no `Closes`.
- [ ] 4.2 Run review + merge per `/soleur:ship`.
