---
name: rAF batching + dead-ref cleanup hazards
description: Two recurring hazards when introducing rAF-coalesce in existing components — fake-timer tests don't auto-advance rAF, and ref removals leave orphaned cleanup references.
category: runtime-errors
module: testing
date: 2026-04-17
pr: 2500
---

# rAF batching and dead-ref cleanup hazards

## Problem

PR #2500 introduced a single-slot rAF coalesce for `setPill` in
`apps/web-platform/components/kb/selection-toolbar.tsx` (#2389) and
retired a `quoteRafRef` that was no longer needed in
`apps/web-platform/components/chat/chat-input.tsx` (#2387).

Two session errors surfaced from the refactor:

1. **rAF + fakeTimers breakage (6 tests)** — `selection-toolbar.test.tsx`
   uses `vi.useFakeTimers({ shouldAdvanceTime: true })`. After the rAF
   wrap landed, assertions like
   `screen.getByRole("button", { name: /quote in chat/i })` failed with
   `expected null to be truthy`. Root cause: `shouldAdvanceTime: true`
   advances the clock only when the event loop is idle; `act()` wraps a
   synchronous operation, so the assertion runs before the rAF
   callback fires. Fake timers mock `requestAnimationFrame` too — a
   fact previously documented in
   `knowledge-base/project/learnings/test-failures/2026-04-17-vitest-getTimerCount-counts-requestAnimationFrame.md`.

2. **Dead-ref cleanup (31 tests)** — `chat-input.tsx` had a residual
   `quoteRafRef = useRef(...)` that was never assigned but was still
   referenced inside the effect's cleanup block:

   ```ts
   if (quoteRafRef.current !== null) {
     cancelAnimationFrame(quoteRafRef.current);
     quoteRafRef.current = null;
   }
   ```

   Removing the declaration left the cleanup referencing an undeclared
   binding. TS/vite transformed the file without complaint; every
   sidebar test that unmounted the component then crashed at runtime
   with `ReferenceError: quoteRafRef is not defined`.

## Solution

### 1. rAF-flush in test helpers

Update any helper that triggers the rAF-scheduled setter to advance a
frame before the test asserts on DOM state:

```ts
// apps/web-platform/test/selection-toolbar.test.tsx
const FRAME_MS = 20;

function setSelection(node: Node, text: string) {
  // … dispatch selectionchange …
  vi.advanceTimersByTime(FRAME_MS);
}
```

Document the coupling inline so a future retune of the rAF budget (or
a switch to `queueMicrotask`) surfaces the test-side dependency.

### 2. Ref-removal discipline

When removing a `useRef` declaration, grep every usage in the same
file and its effect closures before deleting:

```bash
rg "<ref-name>\.current" <file>
```

If the cleanup block has a stale check, delete it in the same edit.
TS `noEmit` catches the missing identifier, but if the file is
re-exported through a barrel it can slip through — always run the
targeted test suite immediately after the edit, not at the end of the
sprint.

## Key Insight

Adding a rAF-coalesce to an existing component is not just a
"one-line" refactor: it is a new timer-like dependency that every
existing test of that component inherits. Treat rAF introduction as
a breaking test-change and sweep the consuming test files in the
same commit.

Ref-removal is the inverse sharp edge: tree-shaken transpilers will
not flag an orphaned cleanup reference to a removed declaration until
the component actually unmounts in a test. Always grep the cleanup
return before deleting a ref.

## Session Errors

- **rAF test breakage (6 failures)** — Recovery: added
  `vi.advanceTimersByTime(FRAME_MS)` inside the `setSelection` test
  helper. Prevention: skill instruction in `work` Phase 2 TDD Gate —
  "When introducing rAF/microtask batching to a component that has an
  existing test suite, in the same edit, sweep test helpers that drive
  the component and add a frame-advance call before assertions."
- **Dead-ref cleanup (31 failures)** — Recovery: removed the 4-line
  cleanup block that referenced `quoteRafRef`. Prevention: AGENTS.md
  Code Quality rule — "Before removing a `useRef` declaration, grep
  for all `<ref-name>.current` usages in the same file (including
  inside effect cleanup returns). TS strict mode does NOT catch
  unreferenced cleanup closures at build time; the crash surfaces at
  unmount-in-test."
- **Bash CWD drift (2 occurrences)** — Recovery: re-chained from the
  worktree absolute path. Prevention: already covered by
  `cq-for-local-verification-of-apps-doppler` — no new rule needed.
- **TaskCreate schema not loaded** — Recovery: proceeded without
  TaskCreate (used `tasks.md` as the tracking document). Prevention:
  already covered by the ToolSearch protocol — no new rule needed.

## Tags

category: runtime-errors
module: testing
module: react-hooks
pr: 2500
