---
title: "Global keyboard go-sequences must suppress while ANY app modal is open, not just the palette/help overlay"
date: 2026-07-01
category: ui-bugs
module: apps/web-platform/components/command-palette
tags: [keyboard-shortcuts, command-palette, modals, data-loss, user-impact-review]
pr: 5867
closes: 5636
---

# Global go-sequences must suppress under any app modal

## Problem

PR #5867 added global two-key "go-to" sequences (`g d`, `g i`, … `g c`) to the
command palette. The plan's FR7 suppressed sequences only while `paletteOpen ||
helpOpen` — reasoning that the help overlay has no focused input, so `isEditable`
alone would let `g d` navigate from underneath it.

The `user-impact-reviewer` (fired by the plan's `single-user incident` threshold)
found the guard was too narrow: the app has ~17 OTHER modals (`new-issue-dialog`,
`cancel-retention-modal`, `transfer-ownership-dialog`, …). With focus on a
**button** inside one of those (non-editable, so `isEditable` does not suppress),
`g d` would arm + resolve → `router.push` → unmount the modal → **silently discard
the modal's unsaved input**. The plan's own "navigating from underneath an open
overlay is surprising" reasoning was never generalized past palette/help.

## Solution

Generalize the arm guard to also suppress while any app modal is mounted, using
the app's consistent `[role="dialog"][aria-modal="true"]` convention:

```ts
if (s.enabled && !s.paletteOpen && !s.helpOpen) {
  if (resolveSequence(false, e, { isAdmin: s.isAdmin }) === "arm") {
    // Suppress while ANY app modal is open — a go-sequence fired from a button
    // inside a modal would navigate away and discard unsaved input. Cheap: the
    // querySelector only runs on a `g` press (the arm candidate).
    if (document.querySelector('[role="dialog"][aria-modal="true"]')) return;
    e.preventDefault();
    pendingPrefixRef.current = Date.now();
  }
}
```

The DOM query is gated behind the `=== "arm"` check so it runs only on a `g`
keypress, not every keystroke. The palette/help overlays are also `[role=dialog]`
[aria-modal] when open, but they're already excluded by the explicit
`!paletteOpen && !helpOpen` state and aren't in the DOM when closed, so there's
no double-count.

## Key Insight

**A global keyboard-navigation binding is a document-level action, so its
suppression set must be document-level too.** `isEditable(target)` only covers the
*focused typing surface*; it does NOT cover "focus is on a non-editable control
inside a modal that holds unsaved state." When you add any global go-to / navigate
shortcut, enumerate every surface that holds unsaved user input — modals, drawers,
wizards — not just text inputs, and suppress the shortcut while any is open. The
app's `[role="dialog"][aria-modal="true"]` convention makes this a one-line DOM
check.

Corollary: `user-impact-reviewer` reliably surfaces this class where
simplicity-biased plan-time review does not — its "name the artifact + name the
vector" mandate forces enumeration of the unsaved-input surfaces the arm guard
must respect.

## Session Errors

1. **Removed a load-bearing union-narrowing guard on a "redundant" review note.**
   The code-quality reviewer flagged `if (effect && effect !== "arm")` as
   redundant defensive code (true at runtime — the resolve phase can't return
   `"arm"`). Collapsing `resolveSequence`'s pending arg to a boolean and dropping
   the `!== "arm"` check broke `tsc` (TS2345: `CommandEffect | "arm"` not
   assignable to `CommandEffect` at `runEffect(effect)`). The guard is
   runtime-impossible but TYPE-required. — Recovery: restored `!== "arm"` with a
   comment explaining it narrows the union for the compiler. — **Prevention:** a
   union-narrowing guard flagged "redundant / always true" by a reviewer is often
   load-bearing for the type system; run `tsc --noEmit` before removing it, and
   keep it with a comment rather than deleting. Caught here by the Phase-6 tsc
   gate before commit.
