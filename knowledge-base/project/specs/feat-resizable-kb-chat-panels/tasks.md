# Tasks: Resizable KB Navigation and Chat Panels

## Phase 1: Auto-Growing Chat Input

- [x] 1.1 Remove `h-[44px]` from textarea className in `chat-input.tsx:489-502`
- [x] 1.2 Add `min-h-[44px] max-h-[100px]` as base CSS constraints
- [x] 1.3 Add `useLayoutEffect` keyed on `value` to set `style.height` via ref (scrollHeight approach)
- [x] 1.4 Add `overflow-y: auto` to textarea for internal scrolling beyond max height
- [x] 1.5 Verify submit resets height (clearing `value` triggers `useLayoutEffect`)
- [x] 1.6 Write tests: auto-grow on type, paste multi-line, programmatic value change (quote insertion), submit reset

## Phase 2: Install react-resizable-panels + Restructure Layout

- [ ] 2.1 Install `react-resizable-panels` in `apps/web-platform/`
- [ ] 2.2 Regenerate both `bun.lock` and `package-lock.json`; verify no peer conflicts with `npm ls`
- [ ] 2.3 Extract `KbChatContent` from `KbChatSidebar` into `kb-chat-content.tsx`
  - [ ] 2.3.1 Move chat messages list, input area, and header into `KbChatContent`
  - [ ] 2.3.2 `KbChatSidebar` becomes thin wrapper: on mobile, renders `KbChatContent` inside Sheet
- [ ] 2.4 Replace flat flex div in `layout.tsx:241-310` with inline PanelGroup
  - [ ] 2.4.1 Three Panels: sidebar (18% default, 10% min, 25% max), doc viewer (60% default, 30% min), chat (22% default, 20% min, 40% max)
  - [ ] 2.4.2 Two `PanelResizeHandle` components (sidebar|doc and doc|chat)
  - [ ] 2.4.3 Single `autoSaveId="kb-panels"`
  - [ ] 2.4.4 Wrap in `useMediaQuery("(min-width: 768px)")` check; below md render existing mobile layout
  - [ ] 2.4.5 Add `min-w-0` to all Panel children
- [ ] 2.5 Chat panel: `collapsible` + `collapsedSize={0}`
  - [ ] 2.5.1 Collapse via `chatPanelRef.collapse()` when `contextPath` is null or chat flag off
  - [ ] 2.5.2 Expand via `chatPanelRef.expand()` when document selected + chat flag on
  - [ ] 2.5.3 Hide doc|chat resize handle when chat panel is collapsed
- [ ] 2.6 Reconcile `sidebarOpen` boolean: redundant on desktop (Panel API replaces it), keep for mobile Sheet
- [ ] 2.7 Write tests: PanelGroup renders on desktop, mobile layout unchanged, chat panel collapses/expands on navigation

## Phase 3: Sidebar Collapse + Handle Styling + Polish

- [ ] 3.1 Delete `apps/web-platform/hooks/use-sidebar-collapse.ts`
- [ ] 3.2 Wire Cmd+B handler to `sidebarRef.current.collapse()`/`.expand()` inline in `layout.tsx`
- [ ] 3.3 Sidebar expand button: render when sidebar is collapsed, adjacent to collapsed sidebar region
  - [ ] 3.3.1 Use Panel `onCollapse`/`onExpand` callbacks to toggle button visibility
  - [ ] 3.3.2 Move existing expand button (layout.tsx:281-294) to new position
- [ ] 3.4 Style resize handles
  - [ ] 3.4.1 4px wide bar, transparent by default
  - [ ] 3.4.2 Hover: `bg-neutral-400/50` with `cursor-col-resize`
  - [ ] 3.4.3 Active drag: `bg-primary/50`
  - [ ] 3.4.4 Grip dots in center (3 dots, 2px each, `bg-neutral-500`)
  - [ ] 3.4.5 `transition-colors duration-150`
- [ ] 3.5 Verify no `backdrop-filter` on PanelGroup ancestors
- [ ] 3.6 Verify tablet (768-1024px): layout usable with min constraints
- [ ] 3.7 Write tests: Cmd+B collapse/expand, expand button visibility, handle keyboard accessibility
- [ ] 3.8 QA: browser testing of all flows (resize, collapse, persist, responsive breakpoint, mobile)
