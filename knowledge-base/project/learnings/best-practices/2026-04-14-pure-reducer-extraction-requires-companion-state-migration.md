---
module: Chat
date: 2026-04-14
problem_type: best_practice
component: frontend_stimulus
symptoms:
  - "Extracted pure reducer still mutates a React ref from inside a setState updater"
  - "Reducer returns a `timerAction` contract that the hook silently ignores"
  - "Two parallel decision tables for the same event taxonomy drift over time"
  - "TS errors in tests surface only at review time because vitest type-checks test files lazily"
  - "4 review agents independently flagged the same purity-drift pattern"
root_cause: logic_error
resolution_type: code_fix
severity: medium
tags: [react, reducer, state-machine, purity, chat, websocket, strict-mode, typescript]
---

# Pure Reducer Extraction Requires Companion-State Migration

## Problem

PR #2209 extracted the chat streaming state machine out of `useWebSocket` into
`lib/chat-state-machine.ts` as a pure `applyStreamEvent(prev, activeStreams, event)`
function. The test suite switched from a shadow `processEvents` copy to importing
the production reducer, closing the drift gap that motivated the extraction
(issue #2124). One component of the state — the `activeStreams: Map<leaderId, idx>`
tracking in-flight streams — stayed as a `useRef`, mutated inline from the
`setMessages` updater:

```ts
// apps/web-platform/lib/ws-client.ts
setMessages((prev) => {
  const result = applyStreamEvent(prev, activeStreamsRef.current, msg);
  activeStreamsRef.current = result.activeStreams;  // side effect in reducer
  return result.messages;
});
```

Four of nine review agents (architecture, performance, code-quality, pattern)
independently flagged the same shape of problem:

1. **React 18/19 concurrent rendering + StrictMode** may invoke the setState
   updater multiple times before commit. Each replay mutates the ref; the second
   replay reads the already-mutated `activeStreams` and can compute wrong
   message indices. The reducer is pure by signature but not by call-site.
2. The reducer declared a `timerAction` return field, was tested against it,
   but the hook **ignored the returned value** and re-derived the same decision
   from `msg.type` in a parallel `if/else` ladder. Two decision tables for the
   same event taxonomy → guaranteed drift when a new event type is added.
3. `activeLeaderIds` (derived from `activeStreams.keys()`) was kept as a
   separate React state and updated manually by the hook — and only for 3 of
   the 5 event types. Hidden drift window.
4. Two TypeScript compile errors in the modified tests (`MockTextMessage`
   missing `state` field, `ws-protocol.test.ts` still asserting a removed
   `tool` field) passed vitest locally because vitest type-checks tests lazily,
   but would have failed CI. Caught only when a review agent ran
   `npx tsc --noEmit` explicitly.

## Root Cause

**Half-extraction is strictly worse than no extraction.** When a pure reducer
operates on state that mixes React state (`messages`, via `useState`) with
ref-backed state (`activeStreams`, via `useRef`), the call site must thread
both through the same update boundary. Using a functional `setState` for
`messages` but mutating `activeStreamsRef.current` inside the updater
simulates the old imperative style — every correctness guarantee the pure
reducer extraction was meant to give is forfeit at the call site.

The root pattern: `activeStreams` is **companion state** to `messages` (the
reducer reads and writes both). Companion state must be managed by the same
update primitive. In React, that means both live inside a single
`useReducer` call, or both live inside a single `useState` wrapping an object
`{ messages, activeStreams }`.

## Solution

Two complementary fixes, applied in PR #2209 and follow-ups:

### 1. Consume the reducer's declared intent (applied inline, #2216)

Capture the `timerAction` inside the setState updater and apply it after the
state commits. Safe under StrictMode because the reducer is pure — both
invocations return the same action.

```ts
let action: ReturnType<typeof applyStreamEvent>["timerAction"];
setMessages((prev) => {
  const result = applyStreamEvent(prev, activeStreamsRef.current, msg);
  activeStreamsRef.current = result.activeStreams;
  action = result.timerAction;
  return result.messages;
});
if (action?.type === "reset") resetLeaderTimeout(action.leaderId);
else if (action?.type === "clear") clearLeaderTimeout(action.leaderId);
else if (action?.type === "clear_all") clearAllTimeouts();
```

The `if/else` ladder in the hook that re-derived the same decision from
`msg.type` is gone — the reducer is now the single source of truth for
timer lifecycle.

### 2. Migrate `activeStreams` into reducer state (deferred, #2217)

Full fix requires `useReducer` with a combined `{ messages, activeStreams }`
state shape. Kept as a follow-up issue because it's a larger refactor than
the 7-issue scope of PR #2209 allowed — but correctness-adjacent, should
land before additional features build on the current pattern.

### 3. Add `npx tsc --noEmit` to the work-phase quality gate

Vitest type-checks test files lazily, so TS errors in tests can pass the
full test suite locally. A standalone `tsc --noEmit` pass catches them in
the work phase instead of letting review agents surface them during the
review round-trip.

## Key Insight

When extracting a pure reducer from a React hook, **all state the reducer
reads and writes must migrate to the reducer's state boundary in the same
change**. A hybrid extraction — pure function + mutable ref — compounds risk
rather than reduces it:

- It advertises purity the call site doesn't honor.
- It leaves StrictMode/concurrent-rendering hazards exactly where they were.
- It produces a declared contract (reducer return values) that nothing
  enforces — tests pin the contract, production re-derives it, and drift
  happens silently.

**Rule of thumb for the next extraction:** if the reducer's return type
includes more than just the next state (e.g., `timerAction`, `commands`,
`effects`), either consume every field at the call site or delete it from
the return type. Never ship a contract the consumer ignores.

And a corollary: if the author finds themselves writing a code comment like
*"simpler than threading X through the setState closure"*, pause. Either
capture X to a local variable inside the updater (safe under purity
assumptions) or remove X from the API. The comment is the review finding.

## Cross-References

- Related (purity drift pattern): first documented variant in this codebase.
- Related (TOCTOU in async boundaries):
  [`2026-03-20-websocket-first-message-auth-toctou-race.md`](../2026-03-20-websocket-first-message-auth-toctou-race.md)
  — same family: "don't mutate session state across an async boundary";
  purity-drift is the reducer version.
- PR: #2209
- Closes: #2124, #2125, #2135, #2136, #2137, #2138, #2139, #2216
- Follow-up tracking: #2217 (`useReducer` migration for companion state),
  #2218-#2225 (related polish and UX decisions surfaced in review).

## Session Errors

**TS compile errors in tests surfaced only at review time, not during
implementation** — `MockTextMessage` in `test/chat-page.test.tsx:10` lacked
the new optional `state?` field, and `test/ws-protocol.test.ts:305` still
asserted on `msg.tool` after the field was removed from the `WSMessage.tool_use`
union. The full vitest suite passed locally both times — it only typechecks
on actual test module load, which happens lazily and tolerates the errors
given the test paths. `npx tsc --noEmit` is the cheap strict-check.
**Recovery:** fixed both errors inline and committed before ship
(`bc367c55`). **Prevention:** add `npx tsc --noEmit` to the work skill's
Phase 3 quality-check list alongside the test-suite run.

**Half-extraction pattern surfaced as 4-agent pile-on** — architecture,
performance, code-quality, and pattern-recognition reviewers all independently
flagged the reducer returning `timerAction` that the hook ignored. One
reviewer would have filed it; four reviewers filing the same finding is the
signal. **Recovery:** fixed inline as #2216; deferred the deeper fix
(`useReducer` migration) to #2217 to stay within PR scope. **Prevention:**
the work skill should note that any reducer-extraction PR should plan for
companion-state migration in the same PR, or explicitly defer it with a
linked issue BEFORE review spawns.

## Tags

category: best-practices
module: chat
