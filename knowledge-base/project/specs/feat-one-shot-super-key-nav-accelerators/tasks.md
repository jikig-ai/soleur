---
feature: feat-one-shot-super-key-nav-accelerators
plan: knowledge-base/project/plans/2026-07-02-feat-super-key-nav-accelerators-plan.md
lane: cross-domain # spec.md absent — defaulted to cross-domain (TR2 fail-closed)
brand_survival_threshold: single-user incident
status: ready
---

# Tasks — Super/Meta-key nav accelerators (additive to the g-leader)

Derived from the finalized (post-review) plan. Additive client-only change; rides
the existing `command-palette` Flagsmith flag. `resolveShortcut`'s line-88
`metaKey || ctrlKey` union MUST NOT be touched.

## Phase 0 — Preconditions (read-only)

- [ ] 0.1 Confirm `use-shortcuts.tsx:88` union untouched-target; `resolveShortcut` L488 + g-arm L512 + modal guard L518 anchors.
- [ ] 0.2 Confirm `modChord` / `isApplePlatform` exports in `platform.ts`.
- [ ] 0.3 `git grep -n "NavItem" apps/web-platform` — no consumer expects a closed field set.
- [ ] 0.4 Confirm app modals set `aria-modal="true"` (`command-palette.tsx:559-561`) — accelerator + g-leader modal suppression parity.

## Phase 1 — nav-items `accel` single source

- [ ] 1.1 Add `readonly accel?: string` to `NavItem` (doc-comment mirroring `seq`; single source).
- [ ] 1.2 Bind `accel`: Dashboard `d`, Inbox `i`, Routines `r`; Analytics `a` (ADMIN). Workstream + KB get NO `accel`.

## Phase 2 — `resolveNavChord` resolver + maps

- [ ] 2.1 Add `ASK_AGENT_ACCEL = "c"` (mirrors `ASK_AGENT_SEQ`).
- [ ] 2.2 Derive `NAV_ACCEL_EFFECTS` (nav `accel` + `[ASK_AGENT_ACCEL]: {openChat}`) and `ADMIN_ACCEL_EFFECTS` from the `accel` fields (module-private, like `NAV_SEQUENCE_EFFECTS`).
- [ ] 2.3 Add pure `resolveNavChord(e, ctx)`: `isEditable`→null, `repeat`→null, `!metaKey`→null (metaKey ONLY, never ctrl), `shiftKey`→null, admin-gate for `a`. Keep DOM-free. Corrected ⌥/Alt doc-comment (Win/Linux harmless-unguarded).
- [ ] 2.4 Tests (`shortcuts-registry.test.ts`, node): `describe("resolveNavChord")` — meta arms d/i/r/c; admin gate a; reject ctrl/shift/editable/repeat; unmapped k/w/x → null. Assert single-source via behavior, NOT by importing the private map (Kieran P2c).

## Phase 3 — Listener precedence + ⌘C selection-yield

- [ ] 3.1 Insert accelerator branch AFTER `resolveShortcut`'s `if (action){…return}`, BEFORE the g-arm. Gate on `s.enabled` + `!paletteOpen && !helpOpen`.
- [ ] 3.2 Resolve FIRST, then run the modal `querySelector` ONLY on a truthy effect (invert — DHH#1 / code-simplicity). `preventDefault` + `runEffect` on match.
- [ ] 3.3 ⌘C selection-yield in the LISTENER: `const sel = window.getSelection(); navEffect.kind==="openChat" && !!sel && !sel.isCollapsed` → return without preventDefault (native copy; `!isCollapsed` covers text AND non-text selections — user-impact Finding 2). Scoped to ⌘C only. NO prefix-clear needed here (the pending-prefix block at `use-shortcuts.tsx:459` already clears it before this branch).
- [ ] 3.4 Confirm WCAG `!s.shortcutsEnabled` early-return (listener top) already disables this branch.
- [ ] 3.5 Tests (`command-palette.test.tsx`, dom): assert preventDefault via `createEvent.keyDown` + `act(fireEvent)` + `ev.defaultPrevented` (test-design review — not `=== false`). Cover AC7 (D/I/R via `it.each` + `mockClear`), AC7b (⌘C no-selection→chat+cancel; ⌘C with stubbed `getSelection` `{isCollapsed:false}`→native copy, not canceled), AC8 (admin gate owns ⌘A + not-canceled for non-admin), AC9 (suppression matrix incl. palette/help-open, focus on body), AC10 (⌘K→palette, g d intact), AC10b (real timers: armed-g × ⌘D → routerPush times(1) + bare-d no re-nav; g × ⌘K → palette). Route `getSelection`/`navigator` stubs through `vi.stubGlobal` (no file-scope `vi.mock` of platform).

## Phase 4 — Hint rendering (Apple-only)

- [ ] 4.1 Add `readonly accelKeys?: string` to `Command`; populate in `buildCommands` ONLY when `isApple` (`item.accel && isApple ? modChord(item.accel.toUpperCase(), true) : undefined`); ask-agent `isApple ? modChord("C", true) : undefined`. `keys` unchanged.
- [ ] 4.2 `command-palette.tsx`: render `accelKeys` on nav rows; ask hero accel gated on the SAME `!trimmed` condition as its `keys` hint (Kieran P2b). Badge order: accel first, then g-seq, 8px gap, no separator, flush-right column (per wireframe).
- [ ] 4.3 `help-overlay.tsx`: `SeqRow.accel?`; populate from `accel`/`ASK_AGENT_ACCEL`; render accel `<kbd>` only when `isApplePlatform`, BEFORE `<kbd>{keys}</kbd>`. Keep `data-testid=help-row-${keys}`.
- [ ] 4.4 Tests: buildCommands accelKeys for both `isApplePlatform` values (AC11 — undefined off-mac); palette + help dual-hint mac-only render (AC12).

## Phase 5 — Verify

- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/shortcuts-registry.test.ts test/command-palette.test.tsx test/help-overlay.test.tsx` — green.
- [ ] 5.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
- [ ] 5.3 Confirm AC1–AC14 satisfied; `.pen` (AC14) already committed at `79fd7acbe`.
