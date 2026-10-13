---
title: "fix: KB delete button overlaps time label on hover"
type: fix
date: 2026-04-14
deepened: 2026-04-14
---

## Enhancement Summary

**Deepened on:** 2026-04-14
**Sections enhanced:** 2 (Proposed Solution, Test Scenarios)
**Research agents used:** codebase pattern analysis, edge case review

### Key Improvements

1. Clarified conditional className for file nodes -- `isAttachment` must gate the hover classes to avoid hiding time labels on `.md` file rows
2. Added `pointer-events-none` consideration for the time span to prevent click-through issues during the opacity transition
3. Confirmed `group-hover:opacity-0` is already supported by the project's Tailwind setup (used in the same file as `group-hover:opacity-100`)

### New Considerations Discovered

- The time span is inside the `<Link>` element while the delete button is a sibling outside it -- the opacity swap is purely visual with no DOM restructuring needed
- `transition-opacity` is already used on the action buttons, so adding it to the time spans ensures synchronized animation timing

# fix: KB delete button overlaps time label on hover

## Overview

In the KB file tree sidebar, hovering over an attachment file row reveals a trash/delete button that overlaps the relative time label (e.g., "3d ago"). The time text should disappear on hover so only the delete icon is visible. The same overlap exists for the upload button on directory rows.

## Problem Statement

The delete button (`TrashIcon`) and the time span (`formatRelativeTime`) both occupy the right side of the file tree row. The delete button uses `absolute right-1 top-1/2` positioning and `group-hover:opacity-100` to appear on hover, but the time span remains visible underneath, creating a visual clash where the icon sits directly on top of the text.

**Root cause:** The time span lacks a `group-hover:opacity-0` (or `group-hover:hidden`) class to hide it when the hover action button appears.

**Affected file:** `apps/web-platform/components/kb/file-tree.tsx`

**Affected rows:**

1. **File nodes** (line 320-323): Time span overlaps with delete button (line 332-344)
2. **Directory nodes** (line 226-230): Time span overlaps with upload button (line 233-244)

## Proposed Solution

Add `group-hover:opacity-0` to the time span's className in both file nodes and directory nodes. This uses the existing Tailwind `group`/`group-hover` pattern already in use for the action buttons, ensuring the time text fades out as the action button fades in -- creating a clean swap effect.

### File node time span (line 320-323)

The time span is rendered for all file types, so the hover-hide classes must be conditional on `isAttachment`. `.md` files have no delete button, so their time label should remain visible on hover.

Change:

```tsx
<span className="ml-auto shrink-0 text-xs text-neutral-600">
```

To:

```tsx
<span className={`ml-auto shrink-0 text-xs text-neutral-600${isAttachment ? " group-hover:opacity-0 transition-opacity" : ""}`}>
```

### Research Insights

- **Conditional className:** Using template literal with ternary is the existing pattern in this component (see `isActive` and `isDeleting` ternaries on the Link element at line 311-315). This keeps the approach consistent.
- **No `pointer-events-none` needed:** The time span is inside the `<Link>`, so clicks pass through to the link regardless. The delete button is a sibling `<button>` positioned with `absolute`, so it sits above the link in stacking order.
- **Transition timing:** Both the time span fade-out and button fade-in use `transition-opacity`, which defaults to `150ms ease` in Tailwind. This creates a synchronized crossfade.

### Directory node time span (line 226-230)

Directories always have an upload button (when not busy), so the hide class can be applied unconditionally.

Change:

```tsx
<span className="ml-auto shrink-0 text-xs text-neutral-600">
```

To:

```tsx
<span className="ml-auto shrink-0 text-xs text-neutral-600 group-hover:opacity-0 transition-opacity">
```

This aligns with the upload button's existing `transition-opacity` and `group-hover:opacity-100`.

## Acceptance Criteria

- [x] Hovering a file row hides the time label and shows only the delete button (attachment files)
- [x] Hovering a directory row hides the time label and shows only the upload button
- [x] Time label remains visible on hover for `.md` files (no delete button, no hide)
- [x] The opacity transitions are smooth (both time-out and button-in animate together)
- [x] No layout shift occurs during the transition (the row height stays constant)
- [x] Existing delete and upload button functionality is unchanged

## Test Scenarios

- Given a file tree with an attachment file (e.g., `.png`), when hovering the file row, then the time label fades out and the delete button fades in
- Given a file tree with a `.md` file, when hovering the file row, then the time label remains visible (no delete button exists)
- Given a file tree with a directory, when hovering the directory row, then the time label fades out and the upload button fades in
- Given a file row in its default (non-hovered) state, then the time label is visible and the delete/upload button is hidden
- Given a file is being deleted (isDeleting state), then the "Deleting..." text is shown instead of the time label (no change in behavior)

### Edge Cases

- Given a directory in `isBusy` state (uploading/processing), when hovering, then no upload button appears and no time label is shown (existing `!isBusy` guard handles this -- no change needed)
- Given a file row where `deleteState.status !== "idle"` (confirming or error), when hovering, then the delete button is already hidden and the time label opacity change is irrelevant (the confirmation/error UI is displayed below the row)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- CSS layout fix for existing component.

## Context

- **Related issue:** [#2154](https://github.com/jikig-ai/soleur/issues/2154)
- **Related PR that introduced the delete button:** [#2143](https://github.com/jikig-ai/soleur/pull/2143)
- **File:** `apps/web-platform/components/kb/file-tree.tsx`
- **Test file:** `apps/web-platform/test/file-tree-delete.test.tsx`

## References

- Tailwind `group-hover` docs: classes applied when a parent with `group` class is hovered
- Existing pattern in the same file: the delete and upload buttons already use `opacity-0 transition-opacity group-hover:opacity-100`
