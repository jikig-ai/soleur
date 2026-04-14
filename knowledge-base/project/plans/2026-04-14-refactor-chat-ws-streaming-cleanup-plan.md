# refactor(chat): extract state machine, tighten WS event lifecycle, and optimize rendering

**Branch:** `feat-fix-chat-streaming-cleanup`
**Worktree:** `.worktrees/feat-fix-chat-streaming-cleanup/`
**Source:** PR #2115 post-merge review — 7 follow-up issues
**Closes:** #2124, #2125, #2135, #2136, #2137, #2138, #2139

## Enhancement Summary

**Deepened on:** 2026-04-14
**Sources consulted:**

- React 19.2.4 official docs via Context7 (`/websites/react_dev_reference_react`) — `memo`, `useReducer`, Strict Mode purity, reducer extraction
- WebSearch: "React 19 useReducer vs pure reducer extracted module WebSocket streaming state machine testing 2026"
- 4 highly-relevant project learnings in `knowledge-base/project/learnings/`:
  - `2026-04-02-defensive-state-clear-on-useeffect-remount.md` — "clear stale state before starting new state"
  - `2026-04-06-chat-page-test-determinism-and-coverage.md` — `waitFor` over `setTimeout` for negative assertions; exact-string `getByText`
  - `2026-04-12-testing-transient-react-state-in-async-flows.md` — controlling async resolution separately from state update
  - `2026-03-30-tdd-enforcement-gap-and-react-test-setup.md` — vitest + happy-dom config for `.tsx` tests
  - `2026-04-07-code-review-batch-ws-validation-error-logging-concurrency-comments.md` — silent-error-suppression anti-pattern
  - `2026-03-20-bun-segfault-leaked-setinterval-timers.md` — timer-leak hazard in tests

### Key Improvements Applied

1. **Recommend `useReducer`, not a hand-rolled pure reducer called via `setState`.** React's docs explicitly frame reducer extraction as a `useReducer` pattern — that gives us the testable module for free, reduces hook surface area, and is the React-idiomatic answer to #2124. The hand-rolled approach in the original plan works but is non-native.
2. **Reducer must stay pure under Strict Mode.** React 19 + Strict Mode double-invokes reducers during development. Any `Map` mutation in the reducer is a latent bug — the reducer must return a NEW `Map`, never mutate the ref'd one. Side effects (timeouts) are expressed as `TimeoutAction` commands returned from the reducer and applied by the hook in `useEffect` or immediately after `dispatch`.
3. **Clear stale UI state on reconnect**, not just refs (applies lesson from `2026-04-02-defensive-state-clear-on-useeffect-remount.md`). The reconnect fix for #2135 should also clear `lastError` / `disconnectReason` if they were set by a prior non-transient close, mirroring the existing `reconnect()` callback pattern.
4. **Test layer correction.** For #2136 timeout-guard test, use `vi.useFakeTimers()` + `vi.advanceTimersByTime(STUCK_TIMEOUT_MS)` rather than real setTimeout waits. Prevents racy tests and unnecessary slow suite. For `.tsx` component tests (#2137 memo), match the existing vitest config: `environmentMatchGlobs: [["test/**/*.tsx", "happy-dom"]]` — do not use `jsdom` (ESM compat issue documented in `2026-03-30-tdd-enforcement-gap-and-react-test-setup.md`).
5. **Memo shallow-compare is safe for our props.** React docs confirm `memo` uses `Object.is` shallow comparison. The `toolsUsed` array reference is only rebuilt for the bubble receiving a `tool_use` event; inactive bubbles keep their array reference across `setMessages` calls (because `[...prev]` clones the outer array but inner objects keep identity unless the reducer spreads them). No `arePropsEqual` custom comparator needed.
6. **Do not hoist the reducer to `useReducer`'s eager initializer** — pass `undefined` and use a lazy init if initial state is non-trivial. For this plan, initial state is `{ messages: [], activeStreams: new Map() }` — cheap enough to pass inline.
7. **Timer-leak test hygiene.** Per `2026-03-20-bun-segfault-leaked-setinterval-timers.md`: add `afterEach(() => { vi.clearAllTimers(); vi.useRealTimers(); })` in any test file that uses fake timers to prevent leaks between tests.

### New Considerations Discovered

- **Strict Mode concurrent rendering implication:** React 19's concurrent mode may call the reducer multiple times before committing. Tests that assume "dispatch once → one state transition" must use the committed state (via `useReducer`'s return value in a test-hook wrapper), not the reducer function output alone. The plan's pure-function tests are fine (they call the reducer directly — deterministic).
- **`toolsUsed` label change affects DB-persisted messages if ever added.** Currently `toolsUsed` is client-only (verified via grep — used only in `ws-client.ts` and `page.tsx`). If a future PR persists it to the `messages` table (e.g., for analytics), the schema must handle labels-not-raw-names. Note this in the PR body so the next dev doesn't design around raw names.
- **Empty-DONE chip UX:** Per `2026-04-07-code-review-batch-...` learning, pay attention to silent-error swallowing patterns. The empty-DONE chip displays `toolsUsed` when `content === ""` — if `toolsUsed` is also empty (no text AND no tools), the current code renders `<MarkdownRenderer content="" />` which shows nothing. This is fine (silent stream_end with nothing to show), but worth adding a `data-testid="empty-done"` for future debugging.

## Summary

PR #2115 landed the 4-state chat message lifecycle (thinking → tool_use → streaming → done/error) and fixed a cumulative-vs-delta streaming protocol mismatch. Review surfaced 7 cleanup issues that fall into four themes: **testability** (#2124 state machine re-implemented in tests), **lifecycle correctness** (#2135 reconnect leaks, #2136 timeout clobbers progressed state), **protocol hygiene** (#2125 dead `partial` field, #2138 raw tool name leak), and **rendering** (#2137 O(n) re-render per token, #2139 7-branch fallback chain). All fixes touch the same four files and share the same test surface, so batching them into one PR keeps the changeset coherent and the review efficient.

Everything below is additive/restructuring — no behavior changes for the end user. The state machine extraction (#2124) is the largest mechanical change; the rest are targeted edits.

## Problem & Context

### The seven issues, grouped

**A. Testability (1)**

- **#2124** (P3) — `ws-client.ts` contains the state-machine inline in `useWebSocket`. The test file `ws-streaming-state.test.ts` re-implements `processEvents` as a shadow copy. Production drift is invisible to tests.

**B. Lifecycle bugs (2, both P2)**

- **#2135** — `connect()` does not clear `activeStreamsRef` or pending timeout timers before reconnecting. On transient WS drop, stale `leaderId → index` entries persist; incoming events on the new socket mutate wrong message slots.
- **#2136** — The 30s stuck-state timeout unconditionally sets `state: "error"`. If the bubble has already transitioned to `streaming` (or `done`) by the time the timer fires (race with a slow first token), the callback clobbers a legitimate state.

**C. Protocol hygiene (2)**

- **#2125** (P3) — `WSMessage.stream.partial` is carried over the wire but ignored on the client (replace semantics apply regardless). Misleads future readers.
- **#2138** (P2) — `tool_use` WS event carries both the raw SDK tool name (`Read`, `Bash`, `Grep`, ...) and a human-readable `label`. Only `label` drives UI. The `tool` field leaks internal taxonomy to WS intercept / devtools.

**D. Rendering (2)**

- **#2137** (P2) — Every `stream` event triggers `setMessages((prev) => [...prev])`, a full array copy. `MessageBubble` has no `React.memo`. At 10-50 tokens/s × 50+ messages, every bubble re-renders on every token.
- **#2139** (P3) — `MessageBubble` content uses a 7-branch `if/else` mixing state checks with fallback heuristics (`!messageState && content === "" && role === "assistant"` for history-loaded messages). History messages arrive from `/api/conversations/:id/messages` without a `state` field, and the fallback papers over that gap.

### Current code references (verified 2026-04-14)

- `apps/web-platform/lib/ws-client.ts:104-143` — refs + timeout helpers (where the state machine lives)
- `apps/web-platform/lib/ws-client.ts:175-465` — `connect()` callback (where reconnect cleanup is missing)
- `apps/web-platform/lib/ws-client.ts:215-405` — switch-on-msg.type state machine (what #2124 extracts)
- `apps/web-platform/lib/ws-client.ts:488-498` — history hydration (where `state: "done"` should be assigned for #2139)
- `apps/web-platform/lib/types.ts:63` — `WSMessage.stream` with `partial: boolean` (for #2125)
- `apps/web-platform/lib/types.ts:66` — `WSMessage.tool_use` with `tool: string` (for #2138)
- `apps/web-platform/server/agent-runner.ts:1104-1113` — server-side `tool_use` emission (for #2138)
- `apps/web-platform/server/agent-runner.ts:54-63` — `TOOL_LABELS` map (reused for #2138)
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:472-597` — `MessageBubble` (for #2137, #2139)
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:560-588` — 7-branch content chain (for #2139)
- `apps/web-platform/test/ws-streaming-state.test.ts:23-87` — shadow `processEvents` implementation (for #2124)

## Proposed Approach

### Overview

Split into five commits for reviewability (all squashed at merge). Order chosen so later commits build on earlier refactors without churn.

1. **Extract state machine** (#2124) — create `lib/chat-state-machine.ts`, port the switch logic, rewrite the test to import from production.
2. **Tighten lifecycle** (#2135, #2136) — reconnect cleanup + timeout guard.
3. **Protocol hygiene** (#2125, #2138) — document `partial`; strip `tool`, map server-side to label.
4. **Optimize rendering** (#2137) — `React.memo` on `MessageBubble`, verify callback stability.
5. **Simplify rendering chain** (#2139) — assign `state: "done"` on history load, collapse fallback heuristics.

### 1. Extract state machine (#2124)

**New file:** `apps/web-platform/lib/chat-state-machine.ts`

Extract a pure reducer. Two implementation approaches; **approach A (`useReducer`) is the recommendation** — it is React-idiomatic, eliminates the `activeStreamsRef` + `messages` state split, and gives tests a trivial import target.

#### Approach A (recommended): `useReducer` with pure reducer

```ts
// apps/web-platform/lib/chat-state-machine.ts
import type { ChatMessage } from "./ws-client-types";
import type { WSMessage } from "./types";

export interface ChatState {
  messages: ChatMessage[];
  // leaderId → index into messages
  activeStreams: Map<string, number>;
}

export type ChatAction =
  | { type: "ws_event"; event: WSMessage }
  | { type: "load_history"; messages: ChatMessage[] }
  | { type: "reset_connection" }
  | { type: "timeout_fired"; leaderId: string }
  | { type: "send_user_message"; content: string; attachments?: AttachmentRef[] }
  | { type: "gate_selected"; gateId: string; selection: string };

export const INITIAL_STATE: ChatState = {
  messages: [],
  activeStreams: new Map(),
};

export function chatReducer(state: ChatState, action: ChatAction): ChatState {
  switch (action.type) {
    case "ws_event":
      return applyWsEvent(state, action.event);
    case "load_history":
      return state.activeStreams.size === 0
        ? { ...state, messages: [...action.messages, ...state.messages] }
        : state;
    case "reset_connection":
      return { messages: state.messages, activeStreams: new Map() };
    case "timeout_fired":
      return applyTimeout(state, action.leaderId);
    // ... other actions
  }
}
```

**Critical — purity under Strict Mode (React 19):** React 19 concurrent rendering invokes reducers multiple times before committing. Never mutate `state.activeStreams` in place. Always:

```ts
// ❌ WRONG — mutates the Map
state.activeStreams.set(leaderId, idx);
return { ...state };

// ✅ CORRECT — returns a new Map
const streams = new Map(state.activeStreams);
streams.set(leaderId, idx);
return { ...state, messages: [...state.messages, newMsg], activeStreams: streams };
```

**Side effects (timeouts) handled in the hook**, not in the reducer. The reducer returns state only. After `dispatch`, the hook inspects the diff and schedules/cancels timers:

```ts
const [state, dispatch] = useReducer(chatReducer, INITIAL_STATE);

// Inside ws.onmessage handler:
const prevStreams = state.activeStreams;
dispatch({ type: "ws_event", event: msg });

// After dispatch, React re-renders with new state. In a useEffect tracking activeStreams,
// schedule/cancel timers based on which leaders are active:
useEffect(() => {
  for (const leaderId of state.activeStreams.keys()) {
    if (!timersRef.current.has(leaderId)) resetLeaderTimeout(leaderId);
  }
  for (const leaderId of timersRef.current.keys()) {
    if (!state.activeStreams.has(leaderId)) clearLeaderTimeout(leaderId);
  }
}, [state.activeStreams]);
```

This separates the pure state machine (testable in isolation) from the effectful timer management (testable via fake timers in the hook).

#### Approach B (fallback): pure function, called via `setState`

If the `useReducer` migration is judged too invasive (larger diff, touches every call site of `setMessages`), fall back to the approach in the original plan: export `applyStreamEvent(prev, activeStreams, event) → { messages, activeStreams, timeoutAction }`. Same testability; hook keeps `useState` + ref plumbing.

**Decision:** Start with Approach A. If the diff exceeds +250 lines in `ws-client.ts` or introduces hard conflicts with the other six fixes in this PR, fall back to Approach B and note it in the commit message. The testability outcome for #2124 is identical either way — it's an internal architecture choice.

#### Test migration (applies to both approaches)

Rewrite `apps/web-platform/test/ws-streaming-state.test.ts` to import either `chatReducer` (Approach A) or `applyStreamEvent` (Approach B) and drive it with the same event sequences. Delete the shadow `processEvents` function entirely. All 9 existing test cases must pass against the production reducer.

Example (Approach A):

```ts
import { chatReducer, INITIAL_STATE } from "../lib/chat-state-machine";

test("single agent lifecycle: thinking → streaming → done", () => {
  let state = INITIAL_STATE;
  for (const evt of [
    { type: "stream_start", leaderId: "cmo" },
    { type: "stream", content: "Hello", partial: true, leaderId: "cmo" },
    { type: "stream_end", leaderId: "cmo" },
  ]) {
    state = chatReducer(state, { type: "ws_event", event: evt });
  }
  expect(state.messages[0].state).toBe("done");
  expect(state.messages[0].content).toBe("Hello");
});
```

**DHH-check:** `useReducer` is not overengineering here — it's React's native pattern for "state that's updated in response to many different kinds of events" (quoted from React docs). The hand-rolled alternative in the original plan is fine but reinvents `useReducer` with extra plumbing. No XState, no Redux, no library — just React's built-in hook.

### 2. Reconnect cleanup (#2135)

**File:** `apps/web-platform/lib/ws-client.ts` — `connect()` callback (currently line 175)

Add at the top of `connect()`, before `setStatus("connecting")`:

```ts
// Clear stale state from any prior connection — incoming events on the new
// socket must not mutate wrong message indices. Applies the principle from
// knowledge-base/project/learnings/2026-04-02-defensive-state-clear-on-useeffect-remount.md:
// "clear stale state before starting new state" — symmetric across manual reconnect
// and automatic reconnect.
if (useReducerApproach) {
  dispatch({ type: "reset_connection" });
} else {
  activeStreamsRef.current.clear();
  setActiveLeaderIds([]);
}
clearAllTimeouts();
```

Update `clearAllTimeouts` in `connect`'s dependency array.

**Additional research insight (applies lesson from `2026-04-02-defensive-state-clear-...`):** The existing `reconnect()` callback at `ws-client.ts:573-579` clears `lastError` and `disconnectReason`. The automatic reconnect path in `connect()` already does not clear these — but on a successful transient reconnect, a stale error card could remain visible. Audit: the `useEffect` at line 508-524 clears `lastError` and `disconnectReason` on mount, but not on automatic mid-session reconnects. **Low priority but related — document and defer to a follow-up issue if the diff doesn't touch this path, do NOT scope-creep into this PR.**

**Test (new):** `test/ws-reconnect-cleanup.test.ts` — simulate events: `stream_start(cmo)` → socket drops → `connect()` called → verify `activeStreamsRef.size === 0` (or state.activeStreams.size === 0) and no timers pending. Use the extracted state machine test harness where possible.

### Research Insights — reconnect cleanup

**Best Practices:**

- Clear maps, sets, and timer refs on every connection-lifecycle boundary, not just mount/unmount. Transient reconnects are the forgotten boundary.
- Symmetric cleanup in both manual (`reconnect()`) and automatic (`connect()` on close) paths prevents drift.

**Edge Cases:**

- The `onclose` handler triggers a `setTimeout` → `connect()` cycle. If the timer fires but `mountedRef.current` is false (e.g., user navigated away), `connect()` is skipped. Good — no cleanup needed.
- A race where `connect()` starts a new socket before the old socket's `onmessage` finishes dispatching: the new cleanup clears `activeStreams` before the in-flight message handler completes its `setMessages` call. The message handler already checks `if (!mountedRef.current) return` — verify this check happens on every event type (currently yes, line 206).

**References:**

- `knowledge-base/project/learnings/2026-04-02-defensive-state-clear-on-useeffect-remount.md`
- `knowledge-base/project/learnings/2026-04-07-code-review-batch-ws-validation-error-logging-concurrency-comments.md` (silent error swallowing in reconnect paths)

### 3. Timeout state guard (#2136)

**File:** `apps/web-platform/lib/ws-client.ts` — `resetLeaderTimeout` closure (currently line 127-143)

Replace the inner callback:

```ts
const timer = setTimeout(() => {
  if (!mountedRef.current) return;
  const idx = activeStreamsRef.current.get(leaderId);
  if (idx === undefined) return;
  setMessages((prev) => {
    if (idx >= prev.length) return prev;
    const current = prev[idx];
    // Guard: only apply "error" if bubble is still in a transitional state.
    // If streaming/done/error already applied, the timeout is stale — no-op.
    if (current.state !== "thinking" && current.state !== "tool_use") {
      return prev;
    }
    const updated = [...prev];
    updated[idx] = { ...updated[idx], state: "error" };
    return updated;
  });
  activeStreamsRef.current.delete(leaderId);
  timeoutTimersRef.current.delete(leaderId);
}, STUCK_TIMEOUT_MS);
```

**Test (new):** extend `ws-streaming-state.test.ts` (or a new `ws-timeout-guard.test.ts`) — seed a message at index 0 with `state: "streaming"`, fire the timeout callback, assert state is still `"streaming"`.

### Research Insights — timeout guard

**Test technique (from `2026-04-12-testing-transient-react-state-in-async-flows.md` + `2026-04-06-chat-page-test-determinism-...`):**

Use `vi.useFakeTimers()` + `vi.advanceTimersByTime(STUCK_TIMEOUT_MS)` rather than wall-clock waits:

```ts
import { beforeEach, afterEach, describe, test, vi } from "vitest";

describe("timeout guard", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => { vi.clearAllTimers(); vi.useRealTimers(); }); // prevent timer leaks

  test("timeout does not clobber streaming state", () => {
    // ... dispatch stream_start, then stream event
    vi.advanceTimersByTime(STUCK_TIMEOUT_MS);
    // assert state still "streaming"
  });
});
```

**Timer-leak prevention:** `afterEach` with `vi.clearAllTimers()` is non-negotiable (see `2026-03-20-bun-segfault-leaked-setinterval-timers.md` — leaked timers caused bun test segfaults at ~1GB RSS). Same principle applies to vitest.

**Edge case:** If the guard is inside the `setTimeout` callback but the closure captures the OLD `state`, the check becomes stale. Use the state-machine reducer approach (dispatch `{ type: "timeout_fired", leaderId }`) so the reducer reads the committed state at fire-time, not the closure-captured state.

**References:**

- [React useReducer — pure reducer requirement](https://react.dev/reference/react/useReducer)

### 4. Document `partial` field (#2125)

**File:** `apps/web-platform/lib/types.ts:63`

Minimal change: add a TSDoc comment. Removing the field requires a server update and risks a protocol version skew during deploy. Documenting is zero-risk.

```ts
| { type: "stream"; content: string; partial: boolean; leaderId: DomainLeaderId }
```

becomes

```ts
| {
    type: "stream";
    content: string;
    /**
     * Server-side diagnostic: `true` for streamed deltas, `false` for the final
     * consolidated text on completion. The client uses replace semantics
     * regardless — it treats every `stream` event as a cumulative snapshot.
     * Do not branch on this field on the client.
     */
    partial: boolean;
    leaderId: DomainLeaderId;
  }
```

### 5. Strip raw tool name from `tool_use` (#2138)

**Server:** `apps/web-platform/server/agent-runner.ts:1104-1113`

```ts
} else if (block.type === "tool_use") {
  const toolName = (block as { name?: string }).name ?? "unknown";
  const label = TOOL_LABELS[toolName] ?? "Working...";
  sendToClient(userId, {
    type: "tool_use",
    leaderId: streamLeaderId,
    label,
    // NOTE: raw `tool` no longer sent — client consumes `label` only.
  });
}
```

**Types:** `apps/web-platform/lib/types.ts:66` — drop `tool: string` from the `tool_use` variant:

```ts
| { type: "tool_use"; leaderId: DomainLeaderId; label: string }
```

**Client:** `apps/web-platform/lib/ws-client.ts:247-266` — update the `tool_use` handler:

```ts
toolsUsed: [...(updated[toolIdx].toolsUsed ?? []), msg.label],
```

Previously `msg.tool` (raw name like "Read") was pushed to `toolsUsed`. Now `msg.label` ("Reading file...") is pushed. The empty-DONE chip at `page.tsx:577` displays the label — semantically clearer for users anyway.

**Migration note:** `toolsUsed` string shape changes from `["Read", "Bash"]` to `["Reading file...", "Running command..."]`. Update the test in `ws-streaming-state.test.ts` (test at line 116 and 228) accordingly — but only after the state machine extraction in step 1, so the test is modifying the production import, not a shadow.

### 6. Memoize MessageBubble (#2137)

**File:** `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:472`

Wrap the component:

```ts
const MessageBubble = React.memo(function MessageBubble({ /* props */ }) {
  // existing body
});
```

**Callback stability verification:**

- `getDisplayName` and `getIconPath` come from `useTeamNames()` — check that hook memoizes them. If not, wrap in `useCallback` at the call site.
- `toolsUsed` is a new array reference every `stream` event in the current code (because `[...(updated[toolIdx].toolsUsed ?? []), ...]`). This is fine — `React.memo` only needs to short-circuit on bubbles that *didn't* get a new array. Non-streaming bubbles keep their `toolsUsed` reference across renders.
- `attachments` is read from the message object; as long as the parent map doesn't clone the object, reference stays stable.

**Quick performance sanity check (not a formal benchmark, acceptance is "doesn't regress"):**

- Open chat with 20+ prior messages, stream a new assistant response, observe in React DevTools Profiler that only the active bubble re-renders during streaming (not all 20).

**Test (new):** `test/message-bubble-memo.test.tsx` — render a list with 3 `MessageBubble`s, update one prop of the middle bubble, assert the other two did not re-render (using `React.Profiler` or a render counter ref).

### Research Insights — MessageBubble memoization

**React 19 confirmation (via Context7 / react.dev/reference/react/memo):**

`memo` uses shallow comparison via `Object.is` on each prop. For each prop:

- `role`, `content`, `leaderId`, `showFullTitle`, `toolLabel` — primitives, always stable comparison.
- `messageState` — string union, stable comparison.
- `attachments` — array reference from the message object. Unless the reducer spreads the message object (which it does on state transitions for that specific bubble), reference is stable across renders of OTHER bubbles.
- `toolsUsed` — same as `attachments`. Reference only rebuilt on `tool_use` events for the specific active bubble.
- `getDisplayName`, `getIconPath` — from `useTeamNames()`. **Must verify stability.**

**Callback stability check (verified 2026-04-14):**

Read `apps/web-platform/hooks/use-team-names.tsx` lines 123-147. `getDisplayName`, `getBadgeLabel`, and `getIconPath` are already `useCallback`-wrapped with correct deps (`[names]`, `[iconPaths]`). **No changes needed to the hook.**

⚠️ **Unrelated finding (do NOT fix in this PR):** The context `value={{ ... }}` at `use-team-names.tsx:172-186` is a new object literal on every render. Every consumer of `useTeamNames()` re-renders when `TeamNamesProvider` re-renders, regardless of which fields they actually use. This is a separate optimization (wrap `value` in `useMemo`) and out of scope for this PR. Log as a follow-up issue after merge.

**Performance test strategy (from `2026-04-06-chat-page-test-determinism-...`):**

```tsx
// test/message-bubble-memo.test.tsx
test("memo prevents re-render of unchanged bubbles", async () => {
  const renderCounts = { 0: 0, 1: 0, 2: 0 };

  function CountingBubble(props: Props & { idx: number }) {
    renderCounts[props.idx]++;
    return <MessageBubble {...props} />;
  }

  const { rerender } = render(
    <>
      <CountingBubble idx={0} content="A" role="assistant" messageState="done" />
      <CountingBubble idx={1} content="B" role="assistant" messageState="streaming" />
      <CountingBubble idx={2} content="C" role="assistant" messageState="done" />
    </>
  );

  rerender(
    <>
      <CountingBubble idx={0} content="A" role="assistant" messageState="done" />
      <CountingBubble idx={1} content="B updated" role="assistant" messageState="streaming" />
      <CountingBubble idx={2} content="C" role="assistant" messageState="done" />
    </>
  );

  // Bubble 1 re-rendered (content changed); 0 and 2 did not
  expect(renderCounts[0]).toBe(1);
  expect(renderCounts[1]).toBe(2);
  expect(renderCounts[2]).toBe(1);
});
```

**Vitest config reminder (from `2026-03-30-tdd-enforcement-gap-and-react-test-setup.md`):**

- Use `happy-dom`, not `jsdom` (ESM compat issue).
- Use `esbuild: { jsx: "automatic" }`, not `@vitejs/plugin-react` (CJS config compat).
- Verify `apps/web-platform/vitest.config.ts` already has `environmentMatchGlobs: [["test/**/*.tsx", "happy-dom"]]` — if not, add it before writing the `.tsx` test.

**No custom `arePropsEqual` needed.** Our props are either primitives or references that are stable by default. Custom equality adds maintenance burden without measurable benefit.

**References:**

- [React memo reference](https://react.dev/reference/react/memo)
- [React useCallback reference](https://react.dev/reference/react/useCallback)

### 7. Assign `state: "done"` to history messages + simplify rendering (#2139)

**File:** `apps/web-platform/lib/ws-client.ts:488-498` — history hydration

```ts
const mapped: ChatMessage[] = history.map((m: { /* ... */ }) => ({
  id: m.id,
  role: m.role as "user" | "assistant",
  content: m.content,
  type: "text" as const,
  leaderId: m.leader_id ?? undefined,
  state: m.role === "assistant" ? "done" : undefined, // user messages don't need a state
}));
```

Assistant messages pulled from the DB are complete by definition — they were persisted by the server's `stream_end` path in `agent-runner.ts`.

**File:** `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:560-588` — collapse the conditional chain.

Before: 7 branches mixing state checks and fallback heuristics.
After: 5 clean state cases + `isUser` short-circuit + markdown fallback.

```tsx
// isUser takes precedence — user messages never have MessageState
if (isUser) {
  return <p className="whitespace-pre-wrap [overflow-wrap:anywhere]">{content}</p>;
}

switch (messageState) {
  case "thinking":
    return <ThinkingDots />;
  case "tool_use":
    return toolLabel ? <ToolStatusChip label={toolLabel} /> : <ThinkingDots />;
  case "streaming":
    return (
      <p className="whitespace-pre-wrap [overflow-wrap:anywhere]">
        {content}<span className="animate-pulse text-amber-500">&#x258C;</span>
      </p>
    );
  case "error":
    return <ErrorIndicator />; // extract the inline svg+text to a tiny sub-component
  case "done":
    if (content === "" && toolsUsed && toolsUsed.length > 0) {
      return <ToolUsageChip toolsUsed={toolsUsed} />; // extract the inline chip
    }
    return <MarkdownRenderer content={content} />;
  default:
    // Unreachable for assistant messages post-#2139: history load assigns "done".
    // Defensive fallback for any future WS event that creates a bubble without state.
    return <MarkdownRenderer content={content} />;
}
```

Extract `ErrorIndicator` and `ToolUsageChip` as small local sub-components (kept in the same file, not new files — they're cosmetic and tightly coupled).

**Why keep a `default` branch:** paranoia. If a future contributor adds a new event that pushes a bubble without a state, `MarkdownRenderer` with empty string is a safe no-op (shows nothing). Better than `undefined` returning `null`.

## Files to Modify

| File | Change | Issues |
| --- | --- | --- |
| `apps/web-platform/lib/chat-state-machine.ts` | **New** — pure reducer | #2124 |
| `apps/web-platform/lib/ws-client.ts` | State machine delegation, reconnect cleanup, timeout guard, history `state: "done"`, `msg.label` in `toolsUsed` | #2124, #2135, #2136, #2138, #2139 |
| `apps/web-platform/lib/types.ts` | TSDoc on `partial`, drop `tool` from `tool_use` | #2125, #2138 |
| `apps/web-platform/server/agent-runner.ts` | Strip `tool` from `tool_use` payload | #2138 |
| `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` | `React.memo(MessageBubble)`, rewrite rendering chain | #2137, #2139 |
| `apps/web-platform/test/ws-streaming-state.test.ts` | Import reducer, update `toolsUsed` expectations to labels | #2124, #2138 |
| `apps/web-platform/test/ws-reconnect-cleanup.test.ts` | **New** — assert refs cleared on reconnect | #2135 |
| `apps/web-platform/test/ws-timeout-guard.test.ts` | **New** — assert timeout skips progressed states | #2136 |
| `apps/web-platform/test/message-bubble-memo.test.tsx` | **New** — assert memo short-circuits | #2137 |

Total: 4 modified, 4 new (1 prod + 3 test).

## Acceptance Criteria

- [ ] `lib/chat-state-machine.ts` exports `applyStreamEvent` as a pure function
- [ ] `ws-streaming-state.test.ts` imports `applyStreamEvent` — no shadow `processEvents` function remains
- [ ] `ws-client.ts` hook calls `applyStreamEvent` instead of inline switch logic for streaming events
- [ ] `connect()` callback clears `activeStreamsRef.current`, calls `clearAllTimeouts()`, and resets `activeLeaderIds` at the top
- [ ] Timeout callback verifies `current.state === "thinking" || current.state === "tool_use"` before applying `"error"`
- [ ] `WSMessage.stream.partial` has TSDoc explaining client ignores it
- [ ] `WSMessage.tool_use` no longer declares `tool: string` — only `leaderId` and `label`
- [ ] `agent-runner.ts` emits `tool_use` with `label` only (no `tool` field)
- [ ] `toolsUsed` on the client contains labels (`"Reading file..."`), not raw names (`"Read"`)
- [ ] `MessageBubble` is wrapped in `React.memo`
- [ ] History-loaded assistant messages have `state: "done"`
- [ ] MessageBubble content chain has no `!messageState && ...` fallback — state-driven only, with a typed `switch` on `MessageState`
- [ ] All existing web-platform tests still pass
- [ ] New tests: reconnect cleanup, timeout guard, memo short-circuit — all green

## Test Scenarios

**Unit (state machine — rewritten existing tests + new):**

1. Single agent lifecycle: `stream_start → stream → stream → stream_end` produces 1 message with `state: "done"` and cumulative content.
2. Multi-agent independence: two `stream_start` events with different `leaderId` create two bubbles; events to each route correctly.
3. Replace semantics: 3 cumulative `stream` events with `"A"`, `"AB"`, `"ABC"` → final content `"ABC"` (regression for PR #2115's append bug).
4. Empty DONE: `stream_start → tool_use → tool_use → stream_end` (no `stream`) → `content === ""` and `toolsUsed.length === 2`.
5. State transitions are one-directional: captured states match `["thinking", "tool_use", "streaming", "done"]`.
6. **New — reconnect cleanup:** simulate `stream_start(cmo)` (activeStreams has 1 entry, timer pending) → call `connect()` → `activeStreamsRef.size === 0`, no timers pending.
7. **New — timeout guard:** seed bubble with `state: "streaming"` → fire the 30s callback → bubble state unchanged (still `"streaming"`).
8. **New — timeout fires on thinking:** seed bubble with `state: "thinking"` → fire callback → state `"error"`.

**Unit (rendering):**

9. **New — MessageBubble memo:** render 3 bubbles, trigger re-render on bubble #2 only, assert #1 and #3 did not re-render.
10. History-loaded assistant messages render via `MarkdownRenderer` (because `state: "done"`) without hitting the fallback branch.

**Integration (manual QA, not automated):**

11. Open existing conversation with 20+ messages, start a new turn, observe only the active bubble animates during streaming (no visible flicker on prior messages). Use React DevTools Profiler if in doubt.
12. Trigger a WS disconnect mid-stream (devtools → offline → online). Verify the new connection does not try to mutate the pre-disconnect bubble (no console warnings, no corrupted message state).
13. Browser devtools WebSocket inspector — confirm `tool_use` frames no longer contain a `"tool"` field.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal refactor with no user-visible behavior change, no product/marketing/legal/finance signal. The change is pure engineering hygiene targeting issues filed by code review. MessageBubble content rendering (#2139) reorganizes existing UI branches without altering what the user sees.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Reducer extraction introduces subtle behavior drift | Port the switch body verbatim first, verify all existing tests pass, then refactor signatures. Commit in isolation. |
| `toolsUsed` shape change (raw → label) breaks persisted data or downstream analytics | `toolsUsed` is client-only, not persisted. Verify with `grep -r "toolsUsed" apps/web-platform` — expect only `ws-client.ts` and `page.tsx`. No DB columns, no analytics events. |
| `React.memo` hides a callback-stability bug | Add the memo test (#9 above) that fails if a parent re-renders with a new callback reference. Make the failure loud. |
| Removing `tool` from WS protocol is a breaking change | Server and client deploy together (same monorepo, same docker image). No external consumers of the WS protocol. |
| History-loaded messages now have `state: "done"`, which may collide with "Checkmark on DONE" badge appearing on every historical bubble | Inspect `page.tsx:538-547` — the checkmark is only rendered when `isDone && role === "assistant"`. This is arguably correct behavior (completion indicator on completed responses), but visually different from current. **QA note:** screenshot before/after; if the user objects, wrap the checkmark in `showCompletionBadge` derived from "just completed in this session" rather than "state is done". Default: keep the badge on historical bubbles — it's semantically honest. |

**Flagged for user review during QA:** the checkmark-on-historical-messages behavior. If undesired, scope-creep a 5-line fix to distinguish "just-completed" from "loaded-from-history" (e.g., track a separate `Set<string>` of IDs that transitioned to done in this session).

## Alternative Approaches Considered

| Alternative | Reason rejected |
| --- | --- |
| Remove `partial` field from WS protocol instead of documenting it | Requires server change with zero client benefit. Adds deployment coupling risk. |
| Use XState or another state-machine library | Switch statement + Map is already adequate. A library would add a dep for 7 event types. DHH/YAGNI. |
| Skip #2139 — keep the 7-branch chain | The user explicitly requested it in the scope. Also: history-message detection via `!messageState` is the kind of implicit contract that breaks on refactor. |
| Split into 2-3 smaller PRs | All seven issues touch the same 4 files and share test infrastructure. Splitting would create merge queues on overlapping diffs. User explicitly asked for one PR. |
| Keep the shadow `processEvents` in tests but add a comment "source of truth" | Review's point stands — production drift is invisible. Extraction is worth the 1-hour cost. |

## Non-Goals / Out of Scope

- KB routes refactor (user stated follow-up PR)
- Leader/Dashboard polish (user stated follow-up PR)
- Rewriting the streaming protocol (cumulative snapshots vs deltas) — PR #2115 already settled this
- Performance benchmarking infrastructure (acceptance is "no visible regression", not "measured improvement")
- Server-side `tool_use` emission for tools beyond the `TOOL_LABELS` map (already handled with `"Working..."` fallback)

## Implementation Order (commits)

1. `refactor(chat): extract stream state machine to lib/chat-state-machine.ts` — #2124 + test rewrite
2. `fix(chat): clear active streams and timers on WS reconnect` — #2135 + test
3. `fix(chat): guard 30s timeout against state progression` — #2136 + test
4. `refactor(chat): strip raw tool names from tool_use WS events` — #2138 + types + server + client + test updates
5. `docs(chat): document dead partial field on WSMessage.stream` — #2125
6. `perf(chat): wrap MessageBubble in React.memo` — #2137 + test
7. `refactor(chat): simplify MessageBubble rendering chain, assign state:done on history load` — #2139

Squash on merge — final commit message:

```
refactor(chat): extract state machine, tighten WS event lifecycle, and optimize rendering

Closes #2124
Closes #2125
Closes #2135
Closes #2136
Closes #2137
Closes #2138
Closes #2139
```

## References

- PR #2115 (merged): feat(chat): 4-state message lifecycle with streaming protocol fix
- Issues: #2124, #2125, #2135, #2136, #2137, #2138, #2139
- Files: `apps/web-platform/lib/ws-client.ts`, `apps/web-platform/lib/types.ts`, `apps/web-platform/server/agent-runner.ts`, `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`, `apps/web-platform/test/ws-streaming-state.test.ts`
- Constitution: `knowledge-base/project/constitution.md`
- AGENTS.md rules applied: "Write failing tests BEFORE implementation code" (TDD gate), "In worktrees, run vitest via `node node_modules/vitest/vitest.mjs run`" (test runner)
