---
title: "Hardcoded ⌘ modifier-glyph is a cross-platform display bug — sweep ALL render sinks"
date: 2026-07-02
category: best-practices
module: apps/web-platform/components/command-palette
tags: [display, cross-platform, keyboard-shortcuts, render-sink-sweep, multi-agent-review]
pr: "#5896"
---

# Learning: platform-glyph fix must sweep every user-facing render sink

## Problem

A request to "use the Super key for all shortcuts" was validated (plan phase, 6 agents)
as a cross-platform + a11y regression and the operator signed off on **Option A′**
instead: keep the collision-free `g`-leader, and fix the *real present bug* — the
key-hint glyph was hardcoded `⌘` even on Windows/Linux/ChromeOS, where users don't
have a `⌘` key. The plan scoped the fix to the command-palette surface
(`help-overlay.tsx`, `command-palette.tsx` via `buildCommands`, the `⌘B` literal).

## Solution

Added a pure, SSR-safe `platform.ts` (`isApplePlatform(nav?)` + `modChord`/`modShiftChord`)
and rendered `⌘` on Apple / `Ctrl(+Shift)+` elsewhere as a **display-time substitution**
— no change to the `seq` model or `formatSeqHint`, off hydrated state via the existing
init-default(false→Ctrl)-then-`useEffect`-sync pattern (one-directional correction, no
hydration mismatch). Resolver `mod = metaKey || ctrlKey` union untouched.

## Key Insight

**A hardcoded modifier glyph (`⌘`, `⌥`, `⌃`) shown to users is a cross-platform display
bug, and the fix must sweep EVERY user-facing render sink — not just the primary surface
the plan names.** This is the display-layer instance of the existing
`2026-06-04-redaction-fix-must-sweep-all-render-sinks-not-just-new-path` rule.

Multi-agent review reliably surfaces the missed siblings when the primary surface is
scoped: here, `pattern-recognition-specialist` + `code-quality-analyst` both independently
flagged two out-of-plan-scope sites hardcoding `⌘⇧L` (the KB quote-selection shortcut):
`kb/selection-toolbar.tsx` and `chat/kb-chat-content.tsx`. Fixing only the command-palette
path would have shipped an incomplete glyph fix that still shows `⌘` to Windows users on a
sibling shortcut. Cheapest gate at work-time: after wiring the helper, `grep -rn '⌘'
apps/web-platform/{components,app}` excluding comments/tests, and confirm every remaining
user-facing occurrence is either platform-aware or intentionally a comment.

Corollary (regex correctness): detect Apple with `/Mac|iPhone|iPad|iPod/i` over
`platform + userAgent` — the `Mac` token is **load-bearing for iPadOS**, which reports
`platform="MacIntel"` / UA "Macintosh" (desktop-class) and no longer emits `iPad`.

## Session Errors

- **Plan-phase research agents (`repo-research-analyst`, `learnings-researcher`) returned
  147-byte stubs (no completion).** Recovery: direct file reads gave a complete inventory,
  so the plan was grounded anyway. Prevention: tolerated by design — the planning subagent
  falls back to direct reads; not a blocker.
- **`nav-states` structural-UI Playwright gate failed at webServer boot (exit 1) on a
  resource-constrained local machine, before any assertion.** Recovery: discriminated as a
  pre-existing local-env flake per `2026-06-08-nav-states-structural-ui-gate-flakes-on-throttled-local`
  (diff touches no nav-states spec; the `layout.tsx` change is a tooltip string + state with
  zero CSS/structural impact; app boots + full vitest suite green). Prevention: CI's
  containerized `e2e` job is the authoritative gate — record + proceed, don't "fix" unrelated
  tests.
