---
title: "feat: resizable KB navigation and chat panels"
type: feat
date: 2026-04-16
issue: 2434
branch: feat-resizable-kb-chat-panels
pr: 2433
---

# feat: Resizable KB Navigation and Chat Panels

## Overview

Add continuous drag-to-resize handles between the three-panel KB layout
(sidebar | document viewer | chat) and replace the fixed-height chat textarea
with an auto-growing input. Uses `react-resizable-panels` (~4kb gzip) for the
panel system with localStorage persistence via `autoSaveId`.

Two work streams, implemented sequentially:

1. **Auto-growing chat input** (Phase 1) -- standalone, no new dependencies
2. **Resizable panels** (Phases 2-3) -- new dependency, layout restructure

## Research Reconciliation -- Spec vs. Codebase

| Spec Claim | Codebase Reality | Plan Response |
|---|---|---|
| Chat panel width is in `kb-chat-sidebar.tsx` | `w-[380px]` lives in `sheet.tsx:73` (`desktopClasses`), not in `kb-chat-sidebar.tsx` | Phase 2 extracts `KbChatContent` from `KbChatSidebar`; on desktop the layout renders chat content directly inside a Panel, bypassing Sheet |
| Three-panel layout is always visible | Chat panel only renders when `contextPath` is non-null AND `kbChatFlag` is true; KB root (`/dashboard/kb`) shows two panels | Phase 2 uses a single `autoSaveId` with the chat panel collapsible at 0% when absent, avoiding PanelGroup remount |
| `react-resizable-panels` is available | Not installed -- zero hits in `package.json` | Phase 2 adds it to `apps/web-platform/package.json` and regenerates both lockfiles |

## Proposed Solution

### Architecture

Inline a `PanelGroup` from `react-resizable-panels` directly in
`layout.tsx:241-310`, replacing the current flat `flex` three-panel div. The
library handles:

- Percentage-based sizing with min/max constraints
- Keyboard accessibility (arrow keys to resize) out of the box
- `autoSaveId` prop for automatic localStorage persistence
- Collapsible panels via ref API (`panel.collapse()` / `panel.expand()`)

The existing `useSidebarCollapse` hook is deleted. Cmd+B calls
`panelRef.current.collapse()` / `.expand()` inline -- no replacement hook
needed. This eliminates competing state between two persistence mechanisms.

The chat panel is always present in the PanelGroup with `collapsible` +
`collapsedSize={0}`. When `contextPath` is null or the chat flag is off, the
chat panel collapses to 0% via the Panel API. This avoids PanelGroup
unmount/remount on navigation (which would cause a layout flash) and uses a
single `autoSaveId` for all panel configurations.

`KbChatSidebar` is split: chat content is extracted into `KbChatContent`. On
desktop, the layout renders `KbChatContent` directly inside a Panel. On mobile,
`KbChatContent` is wrapped in a Sheet (bottom-sheet). The Sheet component is
not modified.

### Default Proportions

- KB Sidebar: 18% default, 10% min, 25% max
- Document Viewer: 60% default, 30% min, no max (fills remaining space)
- Chat Panel: 22% default, 20% min, 40% max

When chat is collapsed (KB root or flag off): sidebar keeps its percentage,
document viewer expands to fill the freed space.

### Key Design Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Cmd+B calls `panelRef.collapse()`/`expand()` inline; `useSidebarCollapse` deleted | Eliminates competing state; Panel API stores last-set width natively; no wrapper hook needed for two method calls |
| 2 | Single `autoSaveId` with chat panel collapsible at 0% | Avoids PanelGroup remount flash on navigation; library validates stored layouts against current panel state |
| 3 | Extract `KbChatContent` from `KbChatSidebar` | Layout decides mobile (Sheet wrapper) vs desktop (Panel child); Sheet is not modified |
| 4 | Textarea grows upward (pushes messages) | Standard pattern (Slack, ChatGPT); messages scroll up, input stays at bottom |
| 5 | Max 5 lines (~100px) for textarea | 6 lines at ~320px width consumes too much vertical space |
| 6 | Visible resize handle (4px bar with grip dots) | Hover-only handles are not discoverable; users assume layout is fixed |
| 7 | `useLayoutEffect` keyed on `value` for textarea height | Covers programmatic value changes (quote insertion, draft rehydration) that bypass DOM input events |
| 8 | JS-based auto-resize (scrollHeight), not CSS `field-sizing` | `field-sizing: content` has limited browser support (no Firefox/Safari as of knowledge cutoff) |

## Technical Approach

### Implementation Phases

#### Phase 1: Auto-Growing Chat Input

**Goal:** Replace the fixed `h-[44px]` textarea with one that grows as the user
types, capped at 5 lines (~100px).

**Files to modify:**

- `apps/web-platform/components/chat/chat-input.tsx:489-502` -- textarea element

**Implementation:**

1. Remove `h-[44px]` from textarea className
2. Add `min-h-[44px] max-h-[100px]` as base constraints
3. Set `rows={1}` (already present) and keep `resize-none`
4. Add `useLayoutEffect` keyed on `value` that sets `style.height` via ref:

```typescript
const textareaRef = useRef<HTMLTextAreaElement>(null)

useLayoutEffect(() => {
  const el = textareaRef.current
  if (!el) return
  el.style.height = "auto" // Reset to measure scrollHeight
  el.style.height = `${Math.min(el.scrollHeight, 100)}px`
}, [value])
```

   `useLayoutEffect` (not `useEffect`) prevents a visible flicker between
   renders. Keying on `value` covers all change sources: typing, paste,
   programmatic changes (quote insertion, draft rehydration, at-mention).

5. On submit, clear value (existing) -- `useLayoutEffect` fires and resets height
6. Add `overflow-y: auto` to textarea so content scrolls beyond max height

**Edge cases:**

- Paste multi-line content: instant resize (no animation), scrollHeight handles it
- Attachments + max height: the attachment preview strip is above the textarea in a flex column; both contribute to the input area height. No special handling needed -- the textarea max-height cap applies independently
- Empty submit: textarea already resets value; height reset follows

**Acceptance criteria:**

- [ ] Textarea starts at 1 line (~44px)
- [ ] Textarea grows to match content up to 5 lines (~100px)
- [ ] Beyond 5 lines, textarea scrolls internally
- [ ] On submit, textarea resets to 1 line
- [ ] Paste multi-line content triggers immediate resize
- [ ] No visual jank during growth (no layout shift)

#### Phase 2: Install react-resizable-panels + Restructure Layout

**Goal:** Replace the flat flex layout with PanelGroup inline in `layout.tsx`.
Handle dynamic chat panel visibility via the Panel collapse API.

**Files to create:**

- `apps/web-platform/components/chat/kb-chat-content.tsx` -- extracted chat content (messages, input) without Sheet wrapper

**Files to modify:**

- `apps/web-platform/package.json` -- add `react-resizable-panels` dependency
- `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx:241-310` -- replace flex div with inline PanelGroup
- `apps/web-platform/components/chat/kb-chat-sidebar.tsx` -- extract content into `KbChatContent`, keep Sheet wrapper for mobile only

**Implementation:**

1. Install dependency and regenerate both lockfiles:

```bash
cd apps/web-platform && bun add react-resizable-panels && bun install && npm install
```

2. Verify no peer conflicts: `npm ls react-resizable-panels`

3. Extract `KbChatContent` from `KbChatSidebar`:
   - Move the chat messages list, input area, and header into `kb-chat-content.tsx`
   - `KbChatSidebar` becomes a thin wrapper: on mobile, renders `KbChatContent` inside a Sheet; the layout handles desktop rendering directly
   - The Sheet component is not modified

4. Replace the flat flex div in `layout.tsx` with an inline PanelGroup:
   - Three Panels: sidebar, document viewer, chat
   - Two `PanelResizeHandle` components between them (sidebar|doc and doc|chat)
   - Single `autoSaveId="kb-panels"` -- the library validates stored layouts against current panel state
   - Wrap in `useMediaQuery("(min-width: 768px)")` check: below md, render existing mobile layout
   - Add `min-w-0` to all Panel children (prevents markdown/code overflow)

5. Chat panel uses `collapsible` + `collapsedSize={0}`:
   - When `contextPath` is null or chat flag is off, collapse via `chatPanelRef.current.collapse()`
   - When a document is selected and chat flag is on, expand via `chatPanelRef.current.expand()`
   - The doc|chat resize handle hides when chat is collapsed (no handle for an invisible panel)

6. The existing `sidebarOpen` boolean on desktop becomes redundant -- the Panel
   collapse API replaces it. On mobile, `sidebarOpen` continues to control Sheet
   mount (no change to mobile behavior).

**Acceptance criteria:**

- [ ] `react-resizable-panels` installed and importable
- [ ] Both `bun.lock` and `package-lock.json` regenerated
- [ ] PanelGroup renders inline in `layout.tsx` (no wrapper component)
- [ ] `KbChatContent` extracted; Sheet untouched
- [ ] Two `PanelResizeHandle` components in three-panel mode
- [ ] Chat panel collapses to 0% at KB root (no document selected)
- [ ] Chat panel expands when document is selected + chat flag on
- [ ] Mobile layout unchanged (Sheet-based chat, collapsible sidebar)
- [ ] `min-w-0` on all Panel children

#### Phase 3: Sidebar Collapse + Handle Styling + Polish

**Goal:** Wire Cmd+B to Panel collapse API, delete `useSidebarCollapse`, style
resize handles, verify edge cases.

**Files to delete:**

- `apps/web-platform/hooks/use-sidebar-collapse.ts` -- replaced by inline Panel ref calls

**Files to modify:**

- `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` -- wire Cmd+B to panel ref, sidebar expand button

**Implementation:**

1. Delete `useSidebarCollapse`. Wire Cmd+B keyboard handler directly:

```typescript
const sidebarRef = useRef<ImperativePanelHandle>(null)

// In the existing Cmd+B handler:
if (sidebarRef.current?.isCollapsed()) {
  sidebarRef.current.expand()
} else {
  sidebarRef.current?.collapse()
}
```

   The Panel's `collapsible` prop + `collapsedSize={0}` handles the 0px state.
   On expand, the library automatically restores the last user-set drag width.

2. **Sidebar expand button:** When the sidebar Panel is collapsed, render a
   small expand button on the sidebar|doc resize handle (or as a floating
   element at the left edge of the document viewer). Use the Panel's
   `onCollapse` / `onExpand` callbacks to toggle button visibility. The current
   expand button (layout.tsx:281-294) is inside the content area -- move it to
   be adjacent to or overlaid on the collapsed sidebar region.

3. Style resize handles (`PanelResizeHandle` components):
   - 4px wide bar, transparent by default
   - On hover: `bg-neutral-400/50` (subtle gray) with `cursor-col-resize`
   - On active drag: `bg-primary/50` (brand color accent)
   - Grip dots in center (3 horizontal dots, 2px each, `bg-neutral-500`)
   - Transition: `transition-colors duration-150`
   - The doc|chat handle hides when chat panel is collapsed

4. Verify: `backdrop-filter` is NOT on any ancestor of the PanelGroup (per
   learning: `backdrop-filter` creates containing blocks for fixed children).

5. **Tablet (768-1024px):** Accept tight layout at md breakpoint. Min-size
   constraints prevent panels from becoming unusable. If user feedback indicates
   tablet is too cramped, a follow-up can raise the resize threshold to `lg`.

**Acceptance criteria:**

- [ ] `useSidebarCollapse` hook deleted, no replacement hook
- [ ] Cmd+B collapses sidebar to 0% via `panelRef.collapse()`
- [ ] Cmd+B expands sidebar to last user-set drag width
- [ ] If user never dragged, Cmd+B expands to default (18%)
- [ ] Sidebar expand button visible when sidebar is collapsed
- [ ] Resize handles visible on hover with grip dots
- [ ] Doc|chat handle hidden when chat panel is collapsed
- [ ] Handles are keyboard-accessible (arrow keys)
- [ ] No `backdrop-filter` on PanelGroup ancestors
- [ ] Tablet (768-1024px): layout usable with tight but functional proportions

## Alternative Approaches Considered

| Approach | Why Rejected |
|---|---|
| CSS-native `resize` property | No coordinated sizing between panels; no persistence; no keyboard accessibility |
| Custom `useResizablePanel` hook | Reimplements pointer-capture drag, keyboard nav, constraints, and persistence that `react-resizable-panels` already provides. ~200 LOC custom vs ~4kb library |
| Discrete size presets (compact/default/wide) | Brainstorm Decision #2: continuous drag preferred for fine-grained control |
| Keep sidebar at fixed width (conversion-optimizer #5) | Brainstorm Decision #2 explicitly chose resizable sidebar; file name truncation is the core usability problem that fixed width cannot solve |
| CSS `field-sizing: content` for textarea | Limited browser support (Chrome 123+ only, no Firefox/Safari as of knowledge cutoff); JS-based scrollHeight is universally supported |

## Acceptance Criteria

### Functional Requirements

- [ ] Chat textarea auto-grows from 1 line to 5 lines as user types
- [ ] Chat textarea height syncs on programmatic value changes (quote, draft rehydration)
- [ ] Chat textarea scrolls internally beyond 5 lines
- [ ] Chat textarea resets to 1 line on submit
- [ ] KB sidebar resizable via drag handle (10%-25% range)
- [ ] Chat panel resizable via drag handle (20%-40% range)
- [ ] Document viewer fills remaining space (min 30%)
- [ ] Panel widths persist to localStorage across page loads (single `autoSaveId`)
- [ ] Cmd+B collapses sidebar via Panel API and restores to last user-set width
- [ ] `useSidebarCollapse` hook deleted
- [ ] Resize handles are keyboard-accessible (arrow keys)
- [ ] Mobile layout unchanged (no resize handles below 768px)
- [ ] Chat panel collapses to 0% at KB root (no PanelGroup remount)
- [ ] Sidebar expand button visible when sidebar is collapsed

### Non-Functional Requirements

- [ ] `react-resizable-panels` adds ~4kb gzip to bundle
- [ ] No `backdrop-filter` on PanelGroup ancestors (per TR4)
- [ ] Resize interactions at 60fps (no jank during drag)
- [ ] Minimal layout shift on page load (library renders defaults on server, hydrates from localStorage on client)

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given a user on the KB page with a document selected, when they type a multi-line message in the chat input, then the textarea grows from 1 line to match content up to 5 lines
- Given a textarea at max height (5 lines), when the user types more content, then the textarea enables internal scrolling
- Given a multi-line textarea, when the user submits the message, then the textarea resets to 1 line height
- Given a programmatic value change (quote insertion via `insertQuote`), when the value updates, then the textarea height adjusts to match content
- Given a user on the KB page at desktop width, when they drag the resize handle between sidebar and document viewer, then both panels resize continuously
- Given a user who has resized panels, when they reload the page, then the panels restore to their last-set widths
- Given a user who has dragged the sidebar wider, when they press Cmd+B twice (collapse then expand), then the sidebar restores to their drag-set width (not the default 18%)
- Given a user on the KB root (no document selected), when they view the layout, then the chat panel is collapsed at 0% and the doc|chat resize handle is hidden
- Given a collapsed sidebar, when the user clicks the expand button, then the sidebar expands to its last-set drag width

### Edge Cases

- Given a user who pastes 20 lines of text, when the paste completes, then the textarea jumps to max height immediately (no animation)
- Given a viewport at exactly 768px, when all three panels render, then minimum constraints prevent any panel from collapsing to unusable size
- Given corrupted localStorage values, when the page loads, then panels render at default proportions (18%/60%/22%)
- Given the kb-chat feature flag is off, when the user navigates to a document, then the chat panel stays collapsed at 0% (no PanelGroup remount)

### Regression Tests

- Given the existing mobile layout, when the viewport is below 768px, then the Sheet-based chat bottom sheet still works
- Given the existing Cmd+B shortcut, when the user presses Cmd+B in a text input or textarea, then the shortcut does NOT fire (existing focus guard)
- Given the sidebar expand button (layout.tsx:281-294), when the sidebar is collapsed via Cmd+B, then the expand button renders and is clickable

## Domain Review

**Domains relevant:** Product, Marketing

### Marketing (CMO)

**Status:** reviewed (carry-forward from brainstorm)
**Assessment:** Ship quietly as UX polish. Update product screenshots post-ship. Include in changelog as one-liner under UX improvements. Default proportions are a conversion surface -- smaller chat default (22% vs current 26%) gives more document space.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, conversion-optimizer
**Skipped specialists:** none
**Pencil available:** yes
**Wireframes:** `knowledge-base/project/specs/feat-resizable-kb-chat-panels/resizable-panels-wireframes.pen` (committed, approved during brainstorm)

**Brainstorm-recommended specialists:** ux-design-lead (wireframes produced pre-plan), conversion-optimizer (invoked, findings integrated into default proportions and handle visibility)

#### Findings

**SpecFlow (critical gaps resolved in plan):**

1. Dynamic panel count (2 vs 3) -- resolved with single `autoSaveId` + chat panel collapsible at 0%
2. Cmd+B integration -- resolved by deleting `useSidebarCollapse`, using inline Panel ref calls
3. Sidebar expand button placement -- render on collapsed sidebar region or as floating element
4. `KbChatContent` extraction -- cleaner separation than Sheet skip-prop
5. Tablet feasibility -- accepted at md breakpoint with min constraints
6. Textarea height sync -- `useLayoutEffect` keyed on `value` covers programmatic changes

**Conversion-Optimizer (recommendations integrated):**

1. Chat default reduced from 380px to ~317px (22%) -- more document space
2. Min constraints: sidebar 10%, doc 30%, chat 20%
3. Visible resize handles with grip dots -- not hover-reveal
4. Textarea capped at 5 lines (not 6)

## Dependencies and Risks

| Risk | Mitigation |
|---|---|
| `react-resizable-panels` peer conflict with existing deps | Verify with `npm ls` after install; regenerate both lockfiles |
| Bundle size increase | Library is ~4kb gzip; within acceptable range |
| Tablet layout too cramped at 768px | Min constraints prevent unusable state; can raise to `lg` (1024px) in follow-up |
| SSR hydration mismatch for localStorage widths | `react-resizable-panels` is SSR-safe -- renders default sizes on server, hydrates from localStorage on client |

## References

### Internal References

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-16-resizable-kb-chat-panels-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-resizable-kb-chat-panels/spec.md`
- Wireframes: `knowledge-base/project/specs/feat-resizable-kb-chat-panels/resizable-panels-wireframes.pen`
- KB layout: `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx:241-310`
- Chat input: `apps/web-platform/components/chat/chat-input.tsx:489-502`
- Sheet component: `apps/web-platform/components/ui/sheet.tsx:73` (desktop `w-[380px]`)
- Sidebar collapse hook: `apps/web-platform/hooks/use-sidebar-collapse.ts`
- Learning -- backdrop-filter: `knowledge-base/project/learnings/2026-02-17-backdrop-filter-breaks-fixed-positioning.md`
- Learning -- flex overflow: `knowledge-base/project/learnings/ui-bugs/2026-04-15-flex-column-width-and-markdown-overflow-2229.md`
- Learning -- lockfile conflicts: `knowledge-base/project/learnings/2026-03-30-unused-dep-peer-conflict-docker-build.md`

### Related Work

- Issue: #2434
- PR: #2433
