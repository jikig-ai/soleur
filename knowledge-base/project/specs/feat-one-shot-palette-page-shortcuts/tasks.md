---
title: "Tasks — Direct keyboard shortcuts for command-palette destinations"
plan: knowledge-base/project/plans/2026-07-01-feat-command-palette-direct-shortcuts-plan.md
branch: feat-one-shot-palette-page-shortcuts
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks: Direct keyboard shortcuts for command-palette destinations

Derived from `2026-07-01-feat-command-palette-direct-shortcuts-plan.md`. Wireframe of record:
`knowledge-base/product/design/command-palette/command-shortcuts-wireframes.pen` (from #5633).
This work **closes #5636**. CPO sign-off gate: the hero-action binding (`g c` vs a chord) — §Binding Decision.

## Phase 0 — Preconditions (grep-verify, no code)
- [ ] 0.1 Confirm `resolveShortcut` pure-matcher shape + `ShortcutAction` union (`use-shortcuts.tsx:67-93`); sequence resolver returns `CommandEffect | null` (flows through existing `runEffect`).
- [ ] 0.2 Confirm vitest include globs (`vitest.config.ts:44,64`): node `test/**/*.test.ts`, jsdom `test/**/*.test.tsx`. Tests land in `apps/web-platform/test/`.
- [ ] 0.3 Confirm `isAdmin` reaches provider (`layout.tsx:253`) and is in `ShortcutsContextValue` (`use-shortcuts.tsx:204`).
- [ ] 0.4 Audit typing surfaces (chat composer, KB editor) satisfy `isEditable` (INPUT/TEXTAREA/SELECT/contentEditable); flag any `role="textbox"` non-contentEditable node (AC11).

## Phase 1 — Registry: bindings + hints
- [ ] 1.1 Add a `seq` field to each existing `NAV_ITEMS`/`ADMIN_NAV_ITEMS` entry (`"g d"` … `"g a"`) + `seq: "g c"` on the `ask-agent` action. Single source — no separate `NAV_SEQUENCES` table.
- [ ] 1.2 `buildCommands` derives the `keys` hint from `seq` (`"g d"` → `G` `D`) for nav + ask; show `G C` for the hero (not `⌘↵`).
- [ ] 1.3 Add pure `resolveSequence(pending, e, ctx): CommandEffect | "arm" | null` (DOM-free): `"arm"` on bare `g`; mapped 2nd key → effect; `null` on unmapped/second-g/`e.repeat`; `g a` → `null` unless `ctx.isAdmin`. Reuses `isEditable`.

## Phase 2 — Listener: sequence buffer
- [ ] 2.1 Add `pendingPrefixRef` + `SEQUENCE_WINDOW_MS = 1500` inside the ONE existing keydown handler; thread `isAdmin` into `stateRef`; ignore `e.repeat` at the top.
- [ ] 2.2 Order checks: `shortcutsEnabled` → pending-prefix branch (PRECEDES Escape drawer branch; Escape clears prefix + is swallowed) → `resolveShortcut` (chords) → `resolveSequence` arm (only if `enabled` AND not `paletteOpen || helpOpen`).
- [ ] 2.3 Prefix clears on window-expiry (timestamp check on next keydown — NO setTimeout), unmapped-key (fall-through, not swallowed), second-`g`, Escape (swallowed); `focusin` into editable clears it.
- [ ] 2.4 Matched 2nd key `preventDefault()` + `runEffect(effect)`. No `pathname === href` guard (Next.js de-dupes same-route push — FR6).

## Phase 3 — Palette hints render (`command-palette.tsx`)
- [ ] 3.1 Render `cmd.keys` for Navigation-group rows (mirror General group lines 332-343) and the Ask-an-agent hero item, via `.cmdk-keys`.
- [ ] 3.2 Confirm non-admin render omits the Analytics nav row/hint (buildCommands already filters admin nav).

## Phase 4 — Help overlay rows (`help-overlay.tsx`)
- [ ] 4.1 Extend `SHORTCUTS` with six nav rows + agent row; each new `HelpAction` variant runs the matching `CommandEffect` via `runEffect`.
- [ ] 4.2 Gate the Analytics row on `isAdmin` (from `useShortcuts()`); group the agent row under "Ask an agent", not "Navigation".
- [ ] 4.3 Remove the `#5636`-deferred omission comment (`help-overlay.tsx:5-7`).

## Phase 5 — Tests (write failing first)
- [ ] 5.1 `test/shortcuts-registry.test.ts` (node): `resolveSequence` truth table (`"arm"`/resolve/`null` on unmapped/second-g/`e.repeat`); `g a` admin gating; one structural assertion that `buildCommands` hints derive from the `seq` field (AC7 — single source, no drift table).
- [ ] 5.2 `test/command-palette.test.tsx` (jsdom): nav + ask rows show `keys` hint; non-admin has no Analytics hint (AC4).
- [ ] 5.3 `test/help-overlay.test.tsx` (jsdom): overlay lists new rows; Analytics row present iff admin; selecting a nav row runs navigate effect (AC5).
- [ ] 5.4 Integration (jsdom provider harness): `g d` navigates; `g`+Escape / `g`+timeout / `g` in input do not; inert when `shortcutsEnabled=false` and when `enabled=false`; ⌘B still works at `enabled=false` (AC2/AC3/AC8/AC9).

## Phase 6 — Verify
- [ ] 6.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w …`).
- [ ] 6.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/shortcuts-registry.test.ts test/command-palette.test.tsx test/help-overlay.test.tsx` then full suite.
- [ ] 6.3 Confirm `git diff package.json` shows NO new dependency (no `tinykeys`) — AC6.

## Ship
- [ ] S.1 PR body: `Closes #5636`; note #5637/#5638 remain deferred (unchanged).
- [ ] S.2 No flag-create (rides existing `command-palette` flag); no migration/infra. No post-merge operator steps.
