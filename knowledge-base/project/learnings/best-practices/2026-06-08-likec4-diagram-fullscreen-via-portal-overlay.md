---
title: "@likec4/diagram has no native fullscreen on LikeC4Diagram — use a portal overlay; re-parenting remounts the canvas"
date: 2026-06-08
category: best-practices
module: web-platform/kb
tags: [likec4, react, createPortal, fullscreen, modal, c4-diagram, library-api]
related_pr: feat-one-shot-c4-diagram-fullscreen-expand
---

# Learning: fullscreen for a LikeC4 diagram = custom portal overlay (no native prop)

## Problem

Needed a "fullscreen / expand" control on the C4 diagram (`components/kb/c4-shared.tsx`
`C4Canvas` → `LikeC4Diagram`). The instinct is "the library probably has a fullscreen
prop or a maximize control."

## Solution / Findings (verified against installed @likec4/diagram@1.50.0)

1. **No native fullscreen on the component the codebase uses.** `LikeC4Diagram`
   (`dist/LikeC4Diagram.props.d.ts`) has NO `fullscreen`/`maximize`/`browser` prop.
   The native click-to-open `browser` modal exists ONLY on the *different*
   `LikeC4View` component (`dist/LikeC4View.d.ts`) — which is **ShadowRoot-wrapped**
   (breaks the `.soleur-c4` scoped re-theme) and whose `browser` **conflicts with
   `enableFocusMode`** (which `ViewCanvas` sets). The internal `Overlay { fullscreen }`
   primitive is NOT re-exported from `index.d.ts`. → A custom overlay is the
   sanctioned path (Context7 confirms `LikeC4Diagram` supports composition), NOT
   reinvention. Pin this verdict to the version — re-check on a major bump.

2. **Portal overlay, not CSS-only.** `createPortal(…, document.body)` +
   `fixed inset-0` escapes the inline embed's `h-[600px] overflow-hidden` clip
   robustly. A CSS-only `position:fixed` (no portal) would be clipped if ANY
   ancestor establishes a containing block (`transform`/`filter`/`will-change`/
   `contain`) — action-at-a-distance the leaf component can't see. Portal matches
   the codebase convention (`sheet.tsx`, `selection-toolbar.tsx`, etc.).

3. **Re-parenting a single React subtree remounts it.** Rendering the SAME
   `canvas` element in two mutually-exclusive branches (inline vs portal) is an
   unmount+remount on toggle — React reconciles by tree position, not by element
   identity. The WebGL/React-Flow canvas re-inits and `fitView` re-fits (pan/zoom
   resets). **Lift the drill-down state (`currentView`) to the parent** so view
   *navigation* survives the toggle even though the *viewport* re-fits. This keeps
   ONE diagram instance (no forked state, no double WebGL context). If pan/zoom
   retention matters, the alternative is a single persistent node whose wrapper
   toggles `fixed inset-0` (CSS-only, accepts the containing-block risk).

4. **Move the theme-scope wrapper to the shared parent.** The `.soleur-c4`
   re-theme wrapper must live on BOTH the inline container AND the portal overlay.
   Lift it from `ViewCanvas` up to `C4Canvas` so both render positions carry it.

5. **Read-only-by-construction for public surfaces.** `C4Canvas` renders ONLY the
   diagram; the Code editor + Concierge are SIBLINGS in parent components, never
   children of `C4Canvas`. So a portal that re-parents only the `C4Canvas` subtree
   structurally cannot leak owner-only affordances to an anonymous share viewer —
   no prop-check needed. Verify-the-negative with a grep that `C4Canvas` imports
   no Code/Concierge component, and an AC asserting the overlay subtree has no
   such control.

## Key Insight

Before building a UI affordance "the library should have," read the INSTALLED
version's `.d.ts` for the EXACT component you use — a sibling/higher-level
component often has the feature but with constraints (ShadowRoot, prop conflicts)
that make it the wrong tool. For "maximize an embedded canvas," a portal overlay
with lifted drill-down state is the durable pattern; accept the viewport re-fit
or go CSS-only-with-caveats. Esc/scroll-lock/focus-return mirror the existing
modal precedent (`typed-confirm-modal.tsx`); the Tab focus-trap is the project's
shared deferral, not a per-feature gap.

## Session Errors

1. **Pencil Desktop AppImage core-dumped** (forwarded from plan phase) — the
   headless Pencil CLI produced the `.pen` wireframe instead. **Prevention:** none
   needed — the headless path is the documented fallback; one-off environment issue.
2. **A long-fallback `ScheduleWakeup` set for a prior PR (#5007) fired after that
   PR had already completed**, re-entering `/soleur:go` for finished work.
   **Recovery:** recognized the wakeup as stale (the PR was MERGED + released +
   worktree reaped) and resumed the in-progress feature instead of re-running.
   **Prevention:** a long fallback that outlives its task is self-correcting (the
   re-entry just confirms completion); the ScheduleWakeup long-fallback choice was
   correct. One-off; no rule change warranted.

## Tags
category: best-practices
module: web-platform/kb
