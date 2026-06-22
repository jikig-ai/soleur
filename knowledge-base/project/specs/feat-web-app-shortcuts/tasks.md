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

- [ ] 0.1 Add `command-palette` to `RUNTIME_FLAGS` in `apps/web-platform/lib/feature-flags/server.ts` (must precede any `useFeatureFlag("command-palette")` consumer)

## Phase 1: Registry + global listener

- [ ] 1.1 `bun install` (cold worktree), then `bun add cmdk` in `apps/web-platform`, then `bun install --frozen-lockfile` to validate
- [ ] 1.2 Extract `NAV_ITEMS`/`ADMIN_NAV_ITEMS` from `layout.tsx:95,102` into `components/command-palette/nav-items.ts`; re-import in layout
- [ ] 1.3 Create `components/command-palette/use-shortcuts.tsx` — provider owning the flat registry (`{id,label,group,keys?,when?,run()}`) + single client-only global keydown listener + shared `isEditable()` predicate + `shortcutsEnabled` (localStorage)
  - [ ] 1.3.1 Suppression contract: skip input/textarea/contenteditable incl. the palette's own search input
  - [ ] 1.3.2 No `navigator.platform` read during render (SSR/hydration safe)
- [ ] 1.4 Migrate `⌘B` (layout.tsx:204–221) + drawer `Escape` (192–201) into the registry/listener; remove the old standalone `handleToggleShortcut`

## Phase 2: Command palette (⌘K)

- [ ] 2.1 `command-palette.tsx` (`cmdk` `Command.Dialog`): `role=dialog`, `aria-modal`, `aria-labelledby`, focus trap, `inert={open||undefined}`, Esc-close + focus restoration to captured `document.activeElement`
- [ ] 2.2 Static groups render immediately; async groups (KB `/api/kb/tree`, routines `/api/dashboard/routines`) fetched lazily on first open with `mountedRef` guard + single "Searching…" affordance
- [ ] 2.3 KB error states: `needsReconnect` → inline reconnect row; `503/500` → "temporarily unavailable"; failure must not break Navigation/Ask-an-agent groups
- [ ] 2.4 Empty state: "No results for '<q>'" + "Ask an agent about '<q>'" → `/dashboard/chat/new`
- [ ] 2.5 Selection: arrow keys + Enter; navigate/open-chat via `router.push` then close
- [ ] 2.6 Stacking/Esc policy: suppress ⌘K while a blocking/confirm modal is open; allow over mobile drawer; top-most layer consumes Esc

## Phase 3: Trigger-routine row (brand-critical)

- [ ] 3.1 Workflow rows show `domain` + `scheduleLabel` + `lastRun` + explicit "Run routine" action (wireframe 01)
- [ ] 3.2 On Enter → same-origin POST `/api/dashboard/routines/run` `{fnId}` (Origin-check, no token); branch on `res.status`: 202 success / 409 → confirm modal above palette → re-POST `{fnId,confirmed:true}` / 400|502 → inline error + Sentry. Palette stays open until resolved

## Phase 4: Help overlay (?) + WCAG

- [ ] 4.1 `help-overlay.tsx` sharing the palette's dialog/focus-trap primitive; lists ONLY `⌘K`/`⌘/`/`⌘B`/`?`/`Esc` (no G-sequence rows)
- [ ] 4.2 Open via `⌘/` (canonical, WCAG-exempt) + `?` (alias, guarded by `isEditable`)
- [ ] 4.3 WCAG SC 2.1.4: global listener honors `shortcutsEnabled` (localStorage, default true) — surfaced as a single Settings "Enable keyboard shortcuts" toggle

## Phase 5: Flag gate + tests

- [ ] 5.1 Gate both surfaces behind `useFeatureFlag("command-palette")` (default OFF, dev cohort); create via `soleur:flag-create command-palette` (dev+prd OFF)
- [ ] 5.2 Component tests in `apps/web-platform/test/*.test.tsx`: open/close + suppression, grouped contents, empty/loading/error, routine 202/409/error, focus restore, `?`-in-input types literal, help shortcut list
- [ ] 5.3 Registry unit tests in `apps/web-platform/test/shortcuts-registry.test.ts`

## Phase 6: Verify

- [ ] 6.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean
- [ ] 6.2 Run vitest suite for the new tests via the package runner
- [ ] 6.3 All Pre-merge ACs (AC1–AC13) checked
