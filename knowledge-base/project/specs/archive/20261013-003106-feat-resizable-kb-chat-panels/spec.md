# Feature: Resizable KB Navigation and Chat Panels

## Problem Statement

The KB three-panel layout (nav sidebar | document viewer | chat panel) uses fixed widths that create friction:

- KB nav sidebar at 256px truncates file names, making similarly-named files indistinguishable
- Chat panel at 380px is cramped for reading agent responses with tables and code blocks
- Chat input at 44px (single row) discourages longer, detailed prompts

Users cannot adjust these proportions to their needs.

## Goals

- Allow users to resize the KB nav sidebar and chat panel via drag handles
- Make the chat input auto-grow as users type longer prompts
- Persist user's panel width preferences across sessions
- Maintain compatibility with existing Cmd+B collapse/expand behavior

## Non-Goals

- Resizing the main dashboard sidebar (left nav with KB/Settings links)
- Mobile layout changes (mobile already has snap-point-based drag on the Sheet)
- Redesigning the overall dashboard layout or navigation structure
- Adding discrete size presets (compact/default/wide toggles)

## Functional Requirements

### FR1: Auto-growing chat input

The chat textarea expands vertically as the user types, from a minimum height (~44px / 1 line) up to a maximum height (~6 lines / ~160px). Beyond max height, the textarea scrolls internally. Replaces the current fixed `h-[44px]` with `resize-none`.

### FR2: Resizable KB nav sidebar

A drag handle on the right edge of the KB nav sidebar allows users to resize it horizontally. Minimum width prevents collapse to unusable size. Maximum width prevents document viewer from becoming too narrow. Default width remains 256px on first visit.

### FR3: Resizable chat panel

A drag handle on the left edge of the chat panel allows users to resize it horizontally. Same min/max constraints apply. Default width remains 380px on first visit.

### FR4: Width persistence

User-set panel widths persist to localStorage and restore on page load. Follow the existing `useSidebarCollapse` pattern.

### FR5: Collapse-resize interaction

Cmd+B toggles the KB sidebar between collapsed (0px) and the user's last-set drag width. If the user has never resized, it restores to the default 256px.

### FR6: Coordinated panel sizing

All three panels (sidebar, document viewer, chat) must always fill 100% of available width. Resizing one panel adjusts the document viewer (center panel) to compensate.

## Technical Requirements

### TR1: Library choice

Use `react-resizable-panels` (~4kb gzip) for the panel resize system. Provides `PanelGroup`, `Panel`, and `PanelResizeHandle` with built-in keyboard accessibility, SSR safety, and constraint enforcement.

### TR2: Responsive behavior

Resizable panels are desktop-only (md breakpoint and above). Below md, fall back to the existing mobile layout (collapsible sidebar, bottom-sheet chat). Verify tablet breakpoint (769-1024px) does not regress.

### TR3: Accessibility

Drag handles must be keyboard-operable (arrow keys to resize). `react-resizable-panels` provides this by default.

### TR4: No backdrop-filter on panel containers

Per institutional learning: `backdrop-filter`, `transform`, and `filter` create new containing blocks for `position: fixed` children. Avoid on ancestors of resizable panels.

### TR5: UX design artifacts

UX design lead produces wireframes (.pen files) for resize handle styling, min/max constraint visualization, and collapse/expand states before panel implementation begins.
