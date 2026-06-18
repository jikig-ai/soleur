---
title: "A drag-vs-double-click guard protects an impossible DOM event; its test gives false confidence"
date: 2026-06-18
category: best-practices
module: apps/web-platform/components/dashboard/rail-resize-handle.tsx
tags: [react, pointer-events, dblclick, tdd, vacuous-test, ui-chrome]
pr: 5522
---

# Learning: a drag-vs-double-click guard often protects an event that cannot fire

## Problem

Adding a "double-click the resize handle to collapse the sidebar" accelerator, the
first implementation guarded against accidental collapse during a drag: it tracked
max pointer travel during the gesture (`travel` ref) and, in `onDoubleClick`,
returned early if `travel > 5px`. A unit test "proved" the guard by firing
`pointerDown → pointerMove(100px) → doubleClick` and asserting collapse did not fire.

`code-quality-analyst` flagged it P2: the test passes for the **wrong reason**, and
the guard is effectively dead code.

## Root cause

In the DOM, `dblclick` fires only after **two `click` events** at the same target.
A `click` fires on `pointerup` only if the pointer did **not** move past the
browser's small click threshold during the press. A genuine resize drag, by
definition, moves the pointer — so it emits **no `click`**, hence **no `dblclick`**,
hence `onDoubleClick` **never fires after a real drag**. The guard protected an
event that cannot occur.

Worse, the guard's mechanism is also self-defeating for the case it claims to handle:
a real double-click is two full `pointerdown`/`pointerup` cycles, and `travel` is
reset to 0 on every `pointerdown` — so by the time `handleDoubleClick` runs, `travel`
reflects only the *second* tap's micro-movement, never the preceding drag. The test
only went green because it fired a synthetic sequence (a `pointerMove` with **no
intervening second `pointerdown`**) that a real browser never produces.

## Solution

Removed the `travel` ref, the `DRAG_THRESHOLD_PX` constant, and the guard. Kept the
genuinely useful no-op-commit skip (`if (latest !== startWidth) onCommit(...)`).
`handleDoubleClick` now just calls `onCollapse?.()`. The AC6 test was rewritten to
model reality: drive the full drag gesture (`pointerDown → pointerMove → pointerUp`)
**without** a `doubleClick` and assert collapse never fires — because a drag emits no
dblclick. Net: less code, honest test, identical user-facing behavior.

## Key Insight

Before writing a guard that distinguishes gesture A from gesture B on the same
element, confirm both gestures can actually emit the event you are guarding. If a
`fireEvent.doubleClick(...)`-style test must hand-assemble an event sequence the real
DOM never produces in order to exercise the guard, the guard is testing fiction —
delete it rather than ship false confidence. (The plan's AC6 note had already warned
"verify empirically whether a drag can even produce `onDoubleClick`… do not ship the
guard unproven" — the lesson is to *act* on that probe before, not after, review.)

## Session Errors

- **Bash CWD non-persistence** — `cd apps/web-platform && …` errored `no such file`
  when CWD had already persisted into that dir from a prior call. Recovery: use a
  bare relative path or an absolute `cd`. Prevention: in a multi-call pipeline, prefer
  absolute paths or `cd <abs> && <cmd>` in one call (already a documented work-skill rule).
- **Plan body described the non-chosen variant** — the planning subagent's
  "Implementation Phases" were written for FR3-Literal while the operator chose
  FR3-Alternative. Recovery: locked the decision into the plan + session-state before
  /work and implemented the chosen variant. Prevention: when a plan embeds an operator
  decision, record the choice + active/dropped ACs at the top before implementing.
- **QA structural gate: dev server `Missing SUPABASE_URL`** — the Playwright
  `webServer` runs bare `npm run dev` with no Doppler injection, so it crashes at boot
  locally. Recovery: run the gate as `doppler run -p soleur -c dev -- playwright test …`
  so the webServer child inherits the env. Prevention: CI sets Supabase env at the job
  level (unaffected); for local Step 2.6 runs, doppler-wrap the playwright invocation.
- **QA: `chrome-headless-shell` not installed** — `browserType.launch: Executable
  doesn't exist`. Recovery: `playwright install chromium-headless-shell` (one-time;
  cached after). Prevention: none needed.
