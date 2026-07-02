---
title: "Additive Super/Meta accelerator layer — metaKey-only resolver, listener-level ⌘C selection-yield, Apple-only hints"
date: 2026-07-02
category: best-practices
module: apps/web-platform/components/command-palette
tags: [keyboard-shortcuts, metaKey, preventDefault, cross-platform, pure-resolver, single-user-incident]
pr: "#5901"
---

# Learning: adding a held-modifier accelerator layer beside a leader-key sequence

## Problem

Operator asked to put nav shortcuts on the Super/Meta key. The literal request is a
cross-platform + a11y regression (0/7 letters collision-free; several OS-reserved), so
the shipped answer was an **additive** layer: `Super+D/I/R/A/C` navigate, coexisting with
the collision-free `g`-leader which stays as the universal fallback. Overriding browser
defaults (⌘C copy, ⌘R reload, ⌘A select-all, ⌘D bookmark) for navigation is a
`single-user incident` risk if done carelessly.

## Solution

Add a NEW pure `resolveNavChord(e, ctx)` sibling of the existing leader resolver, wired as
a listener branch between `resolveShortcut` and the g-leader arm. Guard-rail invariants
(confirmed by a 6-agent review, 0 P1/P2):

1. **metaKey-ONLY, never the `metaKey || ctrlKey` union.** The Windows/Super and macOS ⌘
   keys both surface as `event.metaKey`; `Ctrl` does NOT. Reading `metaKey` only means
   Ctrl+letter on Windows/Linux never arms the (hostile) nav binding. NEVER widen the
   existing `resolveShortcut` union (`mod = metaKey || ctrlKey`) — a global split regresses
   ⌘K/⌘B on non-mac. The split is LOCAL to the new resolver.
2. **Listener-level selection-yield for ⌘C.** The pure resolver stays DOM-free; the
   copy-yield lives in the listener: `const sel = window.getSelection(); if (effect.kind
   === "openChat" && sel && !sel.isCollapsed) return; // let native copy win`. Use
   `!isCollapsed` (covers text AND rich/non-text selections), scoped to the ⌘C effect only.
3. **preventDefault only on a truthy resolved effect** (never on null), suppressed in
   `isEditable` (native ⌘C/⌘A/⌘R survive in inputs) and under `[role=dialog][aria-modal]`.
4. **Single-source `accel` field** on nav-items (mirrors the `seq` pattern); effect maps
   derive from it. Field named `accel`, NOT `metaKey` (collides with the DOM
   `metaKey: boolean` on the event type).

## Key Insight

**The mnemonic letters (D/I/R/A/C) are OS-reserved `Win+`/`Super+` combos on Windows/Linux
(Win+D=desktop, Win+R=run, Win+I=settings, Win+A=action-center), so a metaKey-bound
accelerator effectively fires only on macOS in practice** — the OS grabs those combos
before the page sees them elsewhere. Therefore the accelerator HINT must be **Apple-only**:
rendering "Ctrl+D" off-mac is a false affordance (the binding is metaKey-only and Ctrl
doesn't trigger it; and Super+D is OS-grabbed). The `g`-leader remains the honest
cross-platform path. This is why "put all shortcuts on Super" is an additive-on-mac layer,
not a replacement — surface that limitation in the UI rather than advertising a chord that
won't fire.

Corollary for a `single-user incident` UI change that overrides browser defaults: give the
override an escape hatch for the gesture it shadows (⌘C yields to an active selection), keep
the old binding as a live fallback, admin-gate the riskiest letter (⌘A→Analytics), and
retain the WCAG off-toggle. A select-all-yield for ⌘A does NOT map (⌘A's job is to CREATE a
selection), so that residual is accepted + bounded to admins rather than force-fit.

## Session Errors

- **`learnings-researcher` plan-phase agent never emitted a completion notification**
  (forwarded from session-state.md). Recovery: its findings (vitest paths, `tsc` form,
  `waitFor` mechanics) were grounded independently and folded into the plan. Prevention:
  tolerated by design — the planning flow falls back to direct file reads; not a blocker.
  Same known infra flake noted in the sibling glyph-fix session
  ([[2026-07-02-platform-glyph-fix-must-sweep-all-render-sinks]]).
