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

## Phase 1 — Shippable scope (Option A′; FR1/FR2 — the one unambiguous improvement)

- [x] 1.1 Create `apps/web-platform/components/command-palette/platform.ts` — pure,
  SSR-safe `isApplePlatform()` (inject nav shape; novel — no existing helper). (FR1)
- [x] 1.2 Fold `isApplePlatform()` unit tests (true/false/no-navigator) into
  `test/shortcuts-registry.test.ts` — no separate `platform.test.ts`. (AC3)
- [x] 1.3 Platform-aware glyphs as a DISPLAY substitution (no `seq`/`formatSeqHint` change):
  `help-overlay.tsx` `CHORDS` (`:31-35`) + `command-palette.tsx` hints + `use-shortcuts.tsx`
  `⌘B` literal (`:249`) → `⌘`/`Ctrl`. Render off hydrated state via the provider's
  init-default-then-`useEffect`-sync pattern (`:335-344`); SSR default = `Ctrl`. (FR2, AC2)
- [x] 1.4 Extend `test/help-overlay.test.tsx` to assert `Ctrl` on non-Apple nav shape. (AC2)

## Phase 2 — APPENDIX: accelerator model + resolver (ONLY if operator picks B/C)

- [ ] 2.1 `nav-items.ts`: add single `accel?` field (NOT `metaKey` — DOM-prop collision)
  + advisory `reservedReason?`; binding-eligibility ⇔ presence of `accel`; keep `seq`.
- [ ] 2.2 `help-overlay.tsx`: render reserved letters as struck/click-only caps + reason +
  "Click to open" (match the `.pen`). (AC5)
- [ ] 2.3 `use-shortcuts.tsx`: add `resolveNavChord(e, ctx): CommandEffect | null` sibling of
  `resolveSequence` (reads `e.metaKey` ONLY — do NOT touch the `:88` `mod` union); inject
  `isApplePlatform` on `ShortcutContext`; listener precedence `resolveShortcut →
  resolveNavChord → g-leader`; NEVER bind ⌘K/⌘W/⌘C/⌘R/⌘D/⌘A (safe subset ~empty). (AC5, AC6)
- [ ] 2.4 If any accelerator is bound, assert `preventDefault` fires on non-editable focus. (AC6b)
- [ ] 2.5 Keep `resolveSequence` + arm/resolve intact (dual-bind). (FR3, AC4)

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
