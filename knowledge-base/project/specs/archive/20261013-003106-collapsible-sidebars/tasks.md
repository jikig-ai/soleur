---
title: "Collapsible Sidebars Tasks"
feature: collapsible-sidebars
issue: 2342
pr: 2415
date: 2026-04-16
---

# Collapsible Sidebars — Tasks

## Phase 1: Main Sidebar + Shared Hook + Keyboard Shortcut

### 1.1 Create shared hook

- [ ] Create `apps/web-platform/hooks/use-sidebar-collapse.ts`
- [ ] Implement `useSidebarCollapse(storageKey): [collapsed, toggle]`
- [ ] `useState(false)` with `useEffect` hydration from `localStorage`
- [ ] try/catch for private browsing mode

### 1.2 Main dashboard sidebar collapse

- [ ] Import hook with key `"soleur:sidebar.main.collapsed"` in `apps/web-platform/app/(dashboard)/layout.tsx`
- [ ] Replace `md:transition-none` with `md:transition-[width] md:duration-200 md:ease-out`
- [ ] Toggle `md:w-56` (expanded) / `md:w-14` (collapsed) on the `<aside>`
- [ ] Hide label text when collapsed (`overflow-hidden whitespace-nowrap`), keep icons
- [ ] Add `title` attribute to nav links for native tooltips when collapsed
- [ ] Add chevron toggle button at bottom of sidebar nav
- [ ] Add inline `ChevronLeftIcon` / `ChevronRightIcon` SVG components

### 1.3 Keyboard shortcut (main sidebar)

- [ ] Add `Cmd/Ctrl+B` keydown listener in `layout.tsx`
- [ ] Guard: skip if pathname starts with `/dashboard/kb` or `/dashboard/settings`
- [ ] Guard: skip if `e.target` is input/textarea/contenteditable
- [ ] `e.preventDefault()` to suppress browser bold

### 1.4 Verify mobile drawer regression

- [ ] Mobile drawer slide-in still works after `md:transition-none` removal
- [ ] Backdrop overlay, ESC close, body scroll lock unchanged
- [ ] Breakpoint boundary at 768px transitions cleanly

## Phase 2: KB Sidebar + Settings Sidebar

### 2.1 KB file tree sidebar collapse

- [ ] Import hook with key `"soleur:sidebar.kb.collapsed"` in `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx`
- [ ] Add `md:transition-[width] md:duration-200 md:ease-out` to `<aside>`
- [ ] Toggle `md:w-64` (expanded) / `md:w-0 md:overflow-hidden md:border-r-0` (collapsed)
- [ ] Preserve mobile class-swap (`hidden`/`block` from `isContentView`)
- [ ] Add chevron toggle in sidebar header (expanded) and content left edge (collapsed)
- [ ] Always render sidebar element (never conditional render for transitions)

### 2.2 KB keyboard shortcut

- [ ] Add `Cmd/Ctrl+B` handler guarded to `/dashboard/kb*` routes
- [ ] Same input/textarea/contenteditable guard

### 2.3 Settings sidebar collapse

- [ ] Import hook with key `"soleur:sidebar.settings.collapsed"` in `apps/web-platform/components/settings/settings-shell.tsx`
- [ ] Add `md:transition-[width] md:duration-200 md:ease-out` to `<nav>`
- [ ] Keep `hidden md:block` — mobile display unaffected
- [ ] Toggle `md:w-48` (expanded) / `md:w-0 md:overflow-hidden md:border-r-0` (collapsed)
- [ ] Add chevron toggle in sidebar header (expanded) and content left edge (collapsed)
- [ ] Mobile bottom tab bar unchanged

### 2.4 Settings keyboard shortcut

- [ ] Add `Cmd/Ctrl+B` handler guarded to `/dashboard/settings*` routes

### 2.5 Cross-surface QA

- [ ] All 3 sidebars at 375px, 768px, 1024px, 1280px breakpoints
- [ ] `Cmd/Ctrl+B` routing: correct sidebar toggles per route
- [ ] localStorage persistence: collapse survives page refresh
- [ ] Private browsing: graceful degradation (collapse works, no persist)
- [ ] No layout shift on first hydration (expanded default matches SSR)
- [ ] KB: `Cmd+B` toggles file tree, not chat sidebar
