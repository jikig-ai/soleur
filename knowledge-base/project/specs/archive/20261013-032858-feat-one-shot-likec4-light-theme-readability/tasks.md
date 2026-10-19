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

- [x] 0.1 Re-confirm the Mantine seam: `DefaultMantineProvider.js:67` is
  `defaultColorScheme:"auto"`; `EnsureMantine.js:13` defers to an existing
  `MantineContext`; no `MantineProvider` exists in `apps/web-platform/app|components`.
- [x] 0.2 Confirm light-branch edge-label rule + DOM hooks in `styles.css2.js`:
  `[data-mantine-color-scheme=light] … --xy-edge-label-color/-background-color`, and
  `.likec4-edge-label { color/background: var(--xy-edge-label-*) }` +
  `.react-flow__edge-text { fill: var(--xy-edge-label-color) }`.
- [x] 0.3 **Lever-1 mechanism = 1a (resolved at deepen-plan; re-confirm facts).**
  `use-provider-color-scheme.cjs:10` writes `data-mantine-color-scheme` to
  `getRootElement()` = `<html>` (so 1b wrapper-attr is NOT viable);
  `MantineProvider.d.ts:16` has `forceColorScheme?: 'light'|'dark'`;
  `EnsureMantine.js:13` defers to our provider.
- [x] 0.4 Confirm `@mantine/core` resolves: `node -e "require.resolve('@mantine/core')"`
  and capture the in-tree version for the package.json pin. → `8.3.15`.
- [x] 0.5 Confirm Soleur theme hook: `useTheme()` → `resolvedTheme: "light"|"dark"`
  (`components/theme/theme-provider.tsx:343`).
- [~] 0.6 Confirm `c4-visualizer` flag ON for dev + viewer route reachable (MEMORY).
  Deferred to the post-merge AC8 Playwright visual check (the running-viewer gate).

## Phase 1 — Lever 1: bind color scheme to `resolvedTheme` (seam fix, approach 1a)

- [x] 1.1 In `components/kb/c4-shared.tsx`, wrap the diagram subtree at the
  `.soleur-c4` choke point (covers inline embed + fullscreen portal via the shared
  `canvas` const) in `<MantineProvider forceColorScheme={resolvedTheme}>`, where
  `const { resolvedTheme } = useTheme()` (from `components/theme/theme-provider.tsx`).
  Imported `MantineProvider` from `@mantine/core`. Reads the reactive hook, not the
  DOM. Provider scoped to the canvas (not hoisted).
- [x] 1.2 Added `"@mantine/core": "8.3.15"` to `apps/web-platform/package.json` deps;
  regenerated `package-lock.json` (npm@11 `--package-lock-only`, the CI gate) and
  `bun.lock` (`bun install`); both frozen-installs pass (1-line surgical add — the
  version was already in-tree as a transitive).

> Phase order: Lever 1 lands before/with Lever 2 (token correctness depends on the
> right scheme branch firing).

## Phase 2 — Lever 2: light-theme node separation + edge-label contrast

- [x] 2.1 Added §4 (light-theme readability) to `components/kb/c4-theme.css`, scoped
  to `[data-mantine-color-scheme="light"] .soleur-c4` (light only — dark untouched).
- [x] 2.2 Node separation: light-theme `--likec4-palette-fill` re-pointed to
  `color-mix(in oklab, var(--soleur-bg-surface-2), var(--soleur-border-default) 25%)`
  — a deeper warm tan distinct from the pale `--soleur-bg-base` canvas (the §2b fill
  surface-2 sat within ~6% L of the canvas), keeping the cream identity. `!important`.
  Exact value tuned by the Phase 3 visual check within AC bounds.
- [x] 2.3 Edge-label contrast: light-theme `--likec4-palette-relation-label` darkened
  to `--soleur-text-primary`, AND `--xy-edge-label-background-color` re-pointed to the
  opaque `--soleur-bg-surface-1` on `.likec4-edge-label` (library drops it to 60%).
  `!important`, theme-aware var (no hex).
- [x] 2.4 Confirmed no `#3b82f6` (existing AC3 test) and §4 is fully light-scoped
  (new "keeps every §4 rule light-scoped" test) so the dark-theme path is byte-identical.

## Phase 3 — Tests + verification

- [x] 3.1 Extended `test/c4-theme.test.ts` (AC6): light-scoped node + edge-label
  CSS-rule presence (theme-aware var + `!important`), the all-§4-rules-light-scoped
  guard, the installed-library seam guards (`styles.css2.js`
  `[data-mantine-color-scheme=light]` + `--xy-edge-label-*` on `.likec4-edge-label` /
  `.react-flow__edge-text`; `EnsureMantine.js`/`DefaultMantineProvider.js` seam), and
  the `c4-shared.tsx` `<MantineProvider forceColorScheme={resolvedTheme}>` source
  assertion. Also fixed `test/c4-fullscreen.test.tsx` (the only direct `<C4Canvas>`
  consumer) to stub `useTheme`/`MantineProvider` now that C4Canvas needs theme context.
- [x] 3.2 `vitest run test/c4-theme.test.ts` → 13 passed; full web-platform suite green.
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
