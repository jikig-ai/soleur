# Learning: React effect ordering changes when extracting components

## Problem

When extracting `KbChatContent` from `KbChatSidebar`, the "Continuing from" resumed-conversation banner stopped appearing. All tests that checked for the banner text failed with "Unable to find element with text: /Continuing from/".

The root cause was React's effect execution order: **child effects fire before parent effects**. In the original single-component structure, `ChatSurface` (child) called `setResumedBanner({ timestamp })` via `onThreadResumed`, and then `KbChatSidebar` (parent) ran a `contextPath` reset effect calling `setResumedBanner(null)`. The reset was a no-op because state was already `null` on mount — React de-duplicated the update.

After extraction, the reset effect moved into `KbChatContent` (now the direct parent of `ChatSurface`). The ordering became:

1. `ChatSurface` effect → `setResumedBanner({ timestamp })` (queued)
2. `KbChatContent` contextPath reset effect → `setResumedBanner(null)` (queued, overwrites)
3. React processes batch → result: `null`

The fix: skip the reset effect on initial mount using a `useRef` to track the previous `contextPath` value.

## Solution

```typescript
const prevContextPathRef = useRef(contextPath);
useEffect(() => {
  if (prevContextPathRef.current === contextPath) return; // skip initial mount
  prevContextPathRef.current = contextPath;
  setResumedBanner(null);
  setOpenedEmitted(null);
  historicalCountRef.current = 0;
}, [contextPath]);
```

## Key Insight

When extracting a child component from a parent, any `useEffect` that resets state on mount can silently overwrite state set by grandchild effects. React batches all state updates from a single `flushPassiveEffects` pass, and child effects fire before parent effects. A reset effect that was a no-op in the original structure (because initial state matched the reset value) becomes destructive when it fires after a child has already changed the state.

**Detection pattern:** If you extract a component and tests that check for state set by callbacks from child components start failing, look for `useEffect` blocks with `[dep]` dependency arrays that also fire on mount — they may be overwriting state set by child effects.

**Prevention:** Any `useEffect` that resets state on prop changes should use a ref guard to skip the initial mount, unless the reset is intentionally needed on first render.

## Session Errors

1. **Used v2/v3 react-resizable-panels API on v4** — Recovery: `tsc --noEmit` caught type errors, fixed props (`direction` → `orientation`, `autoSaveId` → `useDefaultLayout`, `onCollapse`/`onExpand` → `onResize`). Prevention: Always check the installed library version and read type definitions before using API from docs/training data.

2. **`visible={sidebarOpen}` bug on desktop** — Recovery: caught by pattern-recognition and architecture review agents. Prevention: When a prop represents different concepts on different platforms (mobile Sheet open state vs desktop panel visibility), derive separate values rather than reusing one.

3. **Conditional Separator broke library child-order** — Recovery: caught by performance and architecture review agents. Prevention: Always render all children of layout libraries (PanelGroup, etc.) and hide with CSS rather than conditional rendering.

4. **contextPath reset effect overwrote resumedBanner** — Recovery: added console.log debug traces to identify the overwriting effect, then added useRef mount guard. Prevention: see Key Insight above.

## Tags

category: ui-bugs
module: kb-layout, react-resizable-panels
