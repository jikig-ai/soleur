# Tasks: Resizable KB Navigation and Chat Panels

## Phase 1: Auto-Growing Chat Input

- [x] 1.1 Remove `h-[44px]` from textarea className in `chat-input.tsx:489-502`
- [x] 1.2 Add `min-h-[44px] max-h-[100px]` as base CSS constraints
- [x] 1.3 Add `useLayoutEffect` keyed on `value` to set `style.height` via ref (scrollHeight approach)
- [x] 1.4 Add `overflow-y: auto` to textarea for internal scrolling beyond max height
- [x] 1.5 Verify submit resets height (clearing `value` triggers `useLayoutEffect`)
- [x] 1.6 Write tests: auto-grow on type, paste multi-line, programmatic value change (quote insertion), submit reset

## Phase 2: Install react-resizable-panels + Restructure Layout

- [x] 2.1 Install `react-resizable-panels` in `apps/web-platform/`
- [x] 2.2 Regenerate both `bun.lock` and `package-lock.json`; verify no peer conflicts with `npm ls`
- [x] 2.3 Extract `KbChatContent` from `KbChatSidebar` into `kb-chat-content.tsx`
  - [x] 2.3.1 Move chat messages list, input area, and header into `KbChatContent`
  - [x] 2.3.2 `KbChatSidebar` becomes thin wrapper: on mobile, renders `KbChatContent` inside Sheet
- [x] 2.4 Replace flat flex div in `layout.tsx:241-310` with inline PanelGroup
  - [x] 2.4.1 Three Panels: sidebar (18% default, 10% min, 25% max), doc viewer (60% default, 30% min), chat (22% default, 20% min, 40% max)
  - [x] 2.4.2 Two Separator components (sidebar|doc and doc|chat)
  - [x] 2.4.3 Single `autoSaveId="kb-panels"`
  - [x] 2.4.4 Wrap in `useMediaQuery("(min-width: 768px)")` check; below md render existing mobile layout
  - [x] 2.4.5 Add `min-w-0` to all Panel children
- [x] 2.5 Chat panel: `collapsible` + `collapsedSize={0}`
  - [x] 2.5.1 Collapse via `chatPanelRef.collapse()` when `contextPath` is null or chat flag off
  - [x] 2.5.2 Expand via `chatPanelRef.expand()` when document selected + chat flag on
  - [ ] 2.5.3 Hide doc|chat resize handle when chat panel is collapsed (Phase 3)
- [x] 2.6 Reconcile `sidebarOpen` boolean: redundant on desktop (Panel API replaces it), keep for mobile Sheet
- [x] 2.7 Write tests: PanelGroup renders on desktop, mobile layout unchanged, chat panel collapses/expands on navigation

## Phase 3: Sidebar Collapse + Handle Styling + Polish

- [x] 3.1 Remove `useSidebarCollapse` import from KB layout (hook kept for dashboard/settings use)
- [x] 3.2 Wire Cmd+B handler to `sidebarRef.current.collapse()`/`.expand()` inline in `layout.tsx`
- [x] 3.3 Sidebar expand button: render when sidebar is collapsed, adjacent to collapsed sidebar region
  - [x] 3.3.1 Use Panel `onCollapse`/`onExpand` callbacks to toggle button visibility
  - [x] 3.3.2 Expand button in docContent shows when `kbCollapsed` state is true
- [x] 3.4 Style resize handles
  - [x] 3.4.1 4px wide bar, transparent by default
  - [x] 3.4.2 Hover: `bg-neutral-400/50`
  - [x] 3.4.3 Active drag: `bg-amber-500/50`
  - [x] 3.4.4 Grip dots in center (3 dots)
  - [x] 3.4.5 `transition-colors duration-150`
- [x] 3.5 Verify no `backdrop-filter` on PanelGroup ancestors
- [x] 3.6 Doc|chat handle hidden when chat panel is collapsed (conditional Separator)
- [x] 3.7 Write tests: Cmd+B collapse/expand, collapse button visibility
- [ ] 3.8 QA: browser testing of all flows (resize, collapse, persist, responsive breakpoint, mobile)
