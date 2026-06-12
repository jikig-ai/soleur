---
title: "Tasks — Copy-all-to-clipboard button for the debug stream panel"
branch: feat-one-shot-debug-stream-copy-button
lane: single-domain
plan: knowledge-base/project/plans/2026-06-12-feat-debug-stream-copy-button-plan.md
---

# Tasks — Debug stream Copy button

Spec lacks a `spec.md`; lane defaulted from plan frontmatter (`single-domain`).

## Phase 1 — Tests first (RED)

- [ ] 1.1 Add the `navigator.clipboard` mock (`Object.defineProperty` +
  `vi.fn()` writeText, cleared in `beforeEach`) to
  `apps/web-platform/test/components/debug-stream-panel.test.tsx`.
- [ ] 1.2 Write T1 (redacted-not-raw): raw secret in body → `writeText` called
  once with text containing `[redacted-key]` and NOT the raw secret. Reuse the
  existing split-concatenation `ANTHROPIC` fixture.
- [ ] 1.3 Write T2 (withheld placeholder copies verbatim).
- [ ] 1.4 Write T3 (Copy click does not change toggle `aria-expanded`; toggle
  button has no `[data-testid="debug-stream-copy"]` descendant).
- [ ] 1.5 Write T4 (Copy `disabled` when `events.length === 0`; click does not
  call `writeText`). T5 fallback path optional.
- [ ] 1.6 Confirm RED: `cd apps/web-platform && ./node_modules/.bin/vitest run test/components/debug-stream-panel.test.tsx` fails on the new cases.

## Phase 2 — Implementation (GREEN)

- [ ] 2.1 Add module-level `serializeDebugEvents(events)` — kind label + optional
  label + `redactCommandForDisplay(event.body)` (NEVER raw); `body ? … : header`
  guard for empty bodies. Export it.
- [ ] 2.2 Add module-level `copyViaTextarea(text)` fallback (hidden textarea +
  `document.execCommand("copy")`, try/catch → boolean).
- [ ] 2.3 Add `copied` state, `copyTimer` ref, `copyAll` `useCallback`
  (clipboard-guard + try/catch + textarea fallback + 2s transient state), and a
  cleanup `useEffect` clearing the timer. Add `useCallback` to the React import.
- [ ] 2.4 Restructure the header row (lines 129–154) into a flex `<div>` holding
  the existing toggle `<button>` (now `flex-1`, holding label/count/disconnected)
  and a sibling group with the Copy `<button>` + the moved "Hide/Show · not saved"
  label. Copy gets `data-testid="debug-stream-copy"`, `disabled={events.length === 0}`,
  title tooltip, and header-matching `soleur-*` / `text-[10px]` / `font-mono` styling.
- [ ] 2.5 Confirm GREEN: vitest run above passes.

## Phase 3 — Verify

- [ ] 3.1 Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 3.2 `grep -n "@/server" apps/web-platform/components/chat/debug-stream-panel.tsx`
  returns no new lines (AC7 — pino client-bundle trap).
- [ ] 3.3 Confirm no nested `<button>` in the header (AC6).
- [ ] 3.4 Full debug-stream suite green (both `debug-stream-panel.test.tsx` and
  `debug-stream-panel-autoscroll.test.tsx` unaffected).
