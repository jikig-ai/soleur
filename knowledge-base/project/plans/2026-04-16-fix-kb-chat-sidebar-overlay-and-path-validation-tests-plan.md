---
title: "fix: KB chat sidebar overlays PDF content instead of pushing it aside; update path validation tests"
type: fix
date: 2026-04-16
---

# fix: KB chat sidebar overlays PDF content instead of pushing it aside; update path validation tests

## Overview

Two related fixes for the KB chat feature:

1. **Layout fix**: The chat sidebar overlays the PDF/document content instead of sitting beside it. The `Sheet` component (`components/ui/sheet.tsx`) uses `createPortal(panel, document.body)` with `position: fixed`, which renders the sidebar on top of the content area. On desktop, the sidebar should render inline within the flex layout so the content area narrows when the sidebar opens.

2. **Test fix**: The path validation tests in `test/ws-context-validation.test.ts` still assert against the old regex-based error messages and old behavior (rejecting spaces, non-`.md` extensions). Commit `c912d554` relaxed validation to accept spaces, unicode, `.pdf`, and any valid file path, but the tests were not updated.

## Proposed Solution

### Layout fix

Modify `Sheet` to render inline (no portal, no `fixed` positioning) on desktop, while preserving the portal-based bottom-sheet on mobile. Sheet is only consumed by `KbChatSidebar`, and `KbChatSidebar` is already rendered inside the flex container in `KbLayout` (line 257). This means removing the portal and fixed positioning on desktop makes the Sheet an inline flex child -- the content area shrinks automatically.

Implementation in `components/ui/sheet.tsx`:

- When `resolvedSide === "right"` (desktop), return `panel` directly instead of `createPortal(panel, document.body)`
- Remove `fixed right-0 top-0` from `desktopClasses`, replace with flex-compatible classes (e.g., `shrink-0` to prevent the sidebar from shrinking)
- Keep `w-[380px]`, `h-[100dvh]`, `border-l`, `bg-neutral-950`, `shadow-2xl`, `z-40` in desktop classes
- Mobile bottom-sheet continues to use `createPortal` (it must overlay, not participate in flex layout)

**Verification point**: The Escape-to-close handler in Sheet's `useEffect` does not depend on portal rendering -- it listens on `document` and checks `panelRef.current.contains(document.activeElement)`. This works identically whether the panel is portaled or inline. No change needed, but verify in testing.

### Test fix

Update `test/ws-context-validation.test.ts`:

- Change error message assertions from `"path must match"` to `"path must be a valid file path"` (lines 49, 58, 63, 72, 85)
- Change `"rejects non-.md path extensions"` to `"accepts non-.md path extensions"` -- replace `expect(() => ...).toThrow(...)` with `expect(validateConversationContext({path: "file.js", type: "kb-viewer"})).toEqual({path: "file.js", type: "kb-viewer", content: undefined})`
- Change `"rejects path with spaces"` to `"accepts path with spaces"` -- same pattern, expect valid result
- Add new test cases:
  - `"accepts .pdf paths"`: `validateConversationContext({path: "docs/report.pdf", type: "kb-viewer"})` returns valid
  - `"accepts unicode filenames"`: `validateConversationContext({path: "docs/cafe-menu.md", type: "kb-viewer"})` returns valid
  - `"rejects empty string path"`: `validateConversationContext({path: "", type: "kb-viewer"})` throws
  - `"rejects path with no extension"`: `validateConversationContext({path: "README", type: "kb-viewer"})` throws (isSafePath requires a dot in filename)
- Keep the existing tests that should still pass: `..` traversal rejection, null byte rejection, leading `/` rejection

## Acceptance Criteria

- [x] On desktop (>=768px), when the KB chat sidebar is open, the PDF/document content area shrinks to accommodate the sidebar -- no overlay, no content hidden behind the sidebar
- [x] On mobile (<768px), the chat sidebar continues to render as a bottom sheet (existing behavior preserved)
- [x] The sidebar width on desktop is 380px (matching current Sheet desktop width)
- [x] Opening/closing the sidebar does not cause layout jumps or content reflow glitches
- [x] All path validation tests pass with updated assertions matching the new `isSafePath` behavior
- [x] Path validation still rejects `..` traversal, leading `/`, and null bytes
- [x] Path validation accepts: `.pdf` files, files with spaces, unicode filenames
- [x] Path validation rejects: empty string paths, paths with no file extension
- [x] Escape-to-close works on the inline desktop sidebar (no regression from portal removal)

## Test Scenarios

### Layout

- Given a desktop viewport (>=768px) and a PDF file open in the KB viewer, when the user opens the chat sidebar, then the PDF content area width decreases by ~380px and the sidebar appears to its right
- Given a desktop viewport with the sidebar open, when the user closes the sidebar, then the content area expands back to full width
- Given a mobile viewport (<768px) and a file open, when the user opens the chat sidebar, then a bottom sheet appears (overlay behavior preserved)

### Path validation

- Given `context-validation.ts` with `isSafePath`, when validating `"document.pdf"`, then it returns valid
- Given `isSafePath`, when validating `"my file with spaces.pdf"`, then it returns valid
- Given `isSafePath`, when validating `"docs/accents-cafe.md"`, then it returns valid
- Given `isSafePath`, when validating `"../etc/passwd"`, then it throws (path traversal blocked)
- Given `isSafePath`, when validating `"/absolute/path.md"`, then it throws (leading slash blocked)
- Given `isSafePath`, when validating a path with null byte, then it throws
- Given `isSafePath`, when validating `""` (empty string), then it throws
- Given `isSafePath`, when validating `"README"` (no extension), then it throws

## Implementation Phases

### Phase 1: Update path validation tests (`test/ws-context-validation.test.ts`)

**Files to modify:**

- `apps/web-platform/test/ws-context-validation.test.ts` -- update error message assertions, invert tests for spaces and non-`.md` extensions, add new acceptance test cases

### Phase 2: Fix sidebar layout

**Files to modify:**

- `apps/web-platform/components/ui/sheet.tsx` -- remove portal and fixed positioning on desktop; keep portal for mobile bottom-sheet

**Files to update tests:**

- `apps/web-platform/test/sheet.test.tsx` -- update desktop class assertions (no longer `fixed right-0`), verify inline rendering on desktop
- `apps/web-platform/test/kb-layout.test.tsx` -- add test verifying sidebar renders within the flex container, not as a portal

**Files NOT modified (no changes needed):**

- `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` -- KbChatSidebar is already inside the flex container
- `apps/web-platform/components/chat/kb-chat-sidebar.tsx` -- no API changes

### Phase 3: Ship

- Run all tests
- Review, compound, PR, merge

## Context

- Path validation fix: commit `c912d554`
- KB chat sidebar feature: PR #2347 (`e3a2acc3`)
- Branch: `feat-fix-kb-chat-path-and-layout`
- Worktree: `.worktrees/feat-fix-kb-chat-path-and-layout/`

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

Layout fix restores intended behavior (sidebar beside content, not overlaying it). No new UI surfaces created -- this corrects an existing component's positioning.

## References

- `apps/web-platform/components/ui/sheet.tsx` -- Sheet component using `createPortal`
- `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` -- KbLayout flex container
- `apps/web-platform/components/chat/kb-chat-sidebar.tsx` -- KbChatSidebar wrapping Sheet
- `apps/web-platform/server/context-validation.ts` -- updated validation (commit `c912d554`)
- `apps/web-platform/test/ws-context-validation.test.ts` -- tests needing update
