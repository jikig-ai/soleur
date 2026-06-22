---
name: feat-web-app-shortcuts
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-22-feat-command-palette-help-overlay-plan.md
issue: 5635
pr: 5633
---

# Tasks: Command Palette (⌘K) + Help Overlay (?)

## Phase 0: Flag union (contract before consumer)

- [x] 0.1 Add `command-palette` to `RUNTIME_FLAGS` in `apps/web-platform/lib/feature-flags/server.ts` (must precede any `useFeatureFlag("command-palette")` consumer)

## Phase 1: Registry + global listener

- [x] 1.1 `bun install` (cold worktree), then `bun add cmdk` in `apps/web-platform`, then `bun install --frozen-lockfile` to validate
- [x] 1.2 Extract `NAV_ITEMS`/`ADMIN_NAV_ITEMS` from `layout.tsx:95,102` into `components/command-palette/nav-items.ts`; re-import in layout
- [ ] 1.3 Create `components/command-palette/use-shortcuts.tsx` — provider owning the flat registry + single client-only global keydown listener + shared `isEditable()` predicate + `shortcutsEnabled` (localStorage)
  - [x] 1.3.0 `Command = {id,label,group,keys?,when?(ctx),run(): CommandEffect}` — `run()` returns a serializable `{kind:'navigate'|'runRoutine'|'openChat', …}` effect the UI interprets (NOT an opaque closure); makes #5638 expose effects, not rewrite run()
  - [ ] 1.3.1 Mount provider wrapping `{children}` with `useMemo`'d context value; palette `open` state lives INSIDE the provider, not the layout's useState cluster
  - [ ] 1.3.2 Suppression contract: skip input/textarea/contenteditable incl. the palette's own search input (use `onKeyDownCapture`+`stopPropagation` for in-input `?`)
  - [ ] 1.3.3 No `navigator.platform` read during render (SSR/hydration safe; ⌘ vs Ctrl glyph post-hydration)
- [ ] 1.4 Migrate `⌘B` (layout.tsx:204–221) + drawer `Escape` (192–201) into the registry/listener; remove the old standalone `handleToggleShortcut`

## Phase 2: Command palette (⌘K)

- [ ] 2.1 `command-palette.tsx` (`cmdk` `Command.Dialog` — Radix-backed; provides focus trap + restoration + background `inert` for the base case, NO manual `document.activeElement` capture needed). Add `aria-label`. `useCommandState()` not in cmdk 1.1.1 → use `shouldFilter`/`filter`/`loop`
- [ ] 2.2 Static groups render immediately; async groups (KB `/api/kb/tree`, routines `/api/dashboard/routines`) fetched lazily on first open with `mountedRef` guard + single "Searching…" affordance
- [ ] 2.3 KB error states: `needsReconnect` → inline reconnect row; `503/500` → "temporarily unavailable"; failure must not break Navigation/Ask-an-agent groups
- [ ] 2.4 Empty state: "No results for '<q>'" + "Ask an agent about '<q>'" → `/dashboard/chat/new`
- [ ] 2.5 Selection: arrow keys + Enter; navigate/open-chat via `router.push` then close
- [ ] 2.6 Stacking/Esc policy: suppress ⌘K while a blocking/confirm modal is open; allow over mobile drawer; top-most layer consumes Esc. Account for `selection-toolbar.tsx:144` CAPTURE-phase Esc listener (fires before bubble-phase regardless of mount order) + ⌘⇧L at :170 — define precedence explicitly

## Phase 3: Trigger-routine row (brand-critical)

- [ ] 3.1 Workflow rows show `domain` + `scheduleLabel` + `lastRun` + explicit "Run routine" action (wireframe 01)
- [ ] 3.2 On Enter → same-origin POST `/api/dashboard/routines/run` `{fnId}` (Origin-check, no token); branch on `res.status`: 202 success / 409 → confirm modal above palette → re-POST `{fnId,confirmed:true}` / 400|502 → inline error + Sentry. Palette stays open until resolved

## Phase 4: Help overlay (?) + WCAG

- [ ] 4.1 `help-overlay.tsx` sharing the palette's dialog/focus-trap primitive; lists ONLY `⌘K`/`⌘/`/`⌘B`/`?`/`Esc` (no G-sequence rows)
- [ ] 4.2 Open via `⌘/` (canonical, WCAG-exempt) + `?` (alias, guarded by `isEditable`)
- [ ] 4.3 WCAG SC 2.1.4: global listener honors `shortcutsEnabled` (localStorage, default true) — single Settings "Enable keyboard shortcuts" toggle. OFF disables the WHOLE listener (⌘K/⌘/`/`?`/⌘B), not just `?`

## Phase 5: Flag gate + tests

- [ ] 5.1 Gate both surfaces behind `useFeatureFlag("command-palette")` (default OFF, dev cohort); create via `soleur:flag-create command-palette` (dev+prd OFF)
- [ ] 5.2 Component tests in `apps/web-platform/test/*.test.tsx`. MANDATORY: `vi.stubGlobal("fetch", …)` per `test/components/routines/routines-surface.test.tsx` (fail-loud blockade in `test/setup-dom.ts`); mock kb/tree, routines, routines/run (status-keyed). Assert DOM affordances not `res.status`. Named tests: open/close+suppression; `?`-in-palette-input literal; grouped contents+admin-gating; empty-state fallback; KB needsReconnect/503 (assert reconnect row PRESENT); routine 202 / 409→confirm→202 / 502→error+Sentry (3 tests); focus restore (`activeElement === trigger`); ⌘B call-count===1; shortcutsEnabled=false disables ⌘B too + default-true; nested 409-modal focus-trap
- [x] 5.3 Unit tests `apps/web-platform/test/shortcuts-registry.test.ts`: `isEditable` (input/textarea/CE/palette-input/null/SVG) + `when?(ctx)` guards + `run()` returns correct `CommandEffect` (pure fns)
- [ ] 5.4 Author each phase's tests alongside its implementation (cq-write-failing-tests-before) — this is the inventory, not test-after

## Phase 6: Verify

- [ ] 6.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean
- [ ] 6.2 Run vitest suite for the new tests via the package runner
- [ ] 6.3 All Pre-merge ACs (AC1–AC13) checked
