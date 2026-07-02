---
feature: feat-one-shot-super-key-shortcuts
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-02-feat-super-key-nav-shortcuts-plan.md
status: BLOCKED — operator decision required (see plan Decision Matrix)
---

# Tasks — Super/Meta-key navigation shortcuts

> **GATE (Phase 0):** This feature is a DECISION plan. Do NOT start Phase 1+ until the
> operator signs off on an option (A/B/C/D) in the plan's Decision Matrix. Three domain
> leaders (CPO, CLO) + spec-flow converge that a full literal rebind (Option C) is a
> cross-platform + accessibility regression. `requires_cpo_signoff: true`.

## Phase 0 — Decision gate (blocking)

- [ ] 0.1 Operator reviews the plan's Research Reconciliation collision matrix + Decision Matrix.
- [ ] 0.2 Operator picks an option and records it in the (eventual) PR body.
  - A (keep `g`-leader) → docs-only PR; skip Phases 1-3 except 1.1 (glyph fix is optional-standalone).
  - D (reframe to speed goal) → file a tracking issue, route to `/soleur:brainstorm`; stop.
  - B / C → proceed to Phases 1-3 with the guard rails.

## Phase 1 — Safe wins (do regardless of A/B/C; the one unambiguous improvement)

- [ ] 1.1 Create `apps/web-platform/components/command-palette/platform.ts` — pure,
  SSR-safe `isApplePlatform()` (inject nav shape for testability). (FR1)
- [ ] 1.2 Create `apps/web-platform/test/platform.test.ts` — true / false / no-navigator. (AC3)
- [ ] 1.3 Platform-aware glyphs in `help-overlay.tsx` (`CHORDS`) + `command-palette.tsx`
  hints + `use-shortcuts.tsx` `⌘B`/`⌘↵` literals → `⌘`/`Ctrl` per FR1. (FR2, AC2)
- [ ] 1.4 Extend `test/help-overlay.test.tsx` to assert `Ctrl` on non-Apple nav shape. (AC2)

## Phase 2 — Reserved-chord model + resolver (only if B/C signed off)

- [ ] 2.1 `nav-items.ts`: add per-destination `metaKey?` + `reservedReason?` metadata,
  preserving the `seq` single-source invariant. (FR3)
- [ ] 2.2 `help-overlay.tsx`: render reserved letters as struck/click-only caps + reason +
  "Click to open" (match the `.pen` wireframe). (FR3, AC5)
- [ ] 2.3 `use-shortcuts.tsx`: split `mod = metaKey || ctrlKey` into `metaOnly`; add the
  macOS additive accelerator arm — gated on `isApplePlatform()`, suppressed in editables +
  under `[role=dialog][aria-modal]`, NEVER binding reserved letters (⌘K/⌘W/⌘C). (FR4, AC5, AC6)
- [ ] 2.4 Keep `resolveSequence` + arm/resolve state machine intact (dual-bind). (FR5, AC4)

## Phase 3 — Tests + verification

- [ ] 3.1 `test/shortcuts-registry.test.ts`: keep `g`-leader cases; add platform-aware +
  resolver-arm + reserved-letter-non-binding assertions. (AC4, AC5)
- [ ] 3.2 `test/command-palette.test.tsx`: hint rows, go-to integration, modal-suppression,
  WCAG turn-off (extend :603 for new arms). (AC7)
- [ ] 3.3 Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. (AC8)
- [ ] 3.4 Tests: `cd apps/web-platform && ./node_modules/.bin/vitest run test/shortcuts-registry.test.ts test/help-overlay.test.tsx test/command-palette.test.tsx test/platform.test.ts`. (AC8)
- [ ] 3.5 PR body records the chosen option + `Ref` (not `Closes`) any reframe tracking issue. (AC1)

## Guard rails (apply throughout)

- Never bind a `metaKey || ctrlKey` union arm for nav — `metaKey` only, macOS-gated.
- Never bind ⌘W (closes tab), ⌘K (palette), ⌘C (copy). They stay `g`-leader / click-only.
- Retain `soleur:shortcuts.enabled` turn-off (CLO blocking condition).
- `apps/web-platform` typecheck uses in-package `tsc`, tests use `vitest` (not `bun test`);
  test files must live under `test/**` to match `vitest.config.ts` `include:` globs.
