---
category: test-failures
tags: [vitest, fake-timers, requestAnimationFrame, react, timer-leak]
date: 2026-04-17
---

# Learning: vitest `vi.getTimerCount()` counts rAFs, not just `setTimeout`

## Problem

Writing a RED test for a timer-leak fix in `chat-input.tsx` (#2384 5A). The
component's `insertQuote()` schedules a `setTimeout` (to clear a flash-ring
state) and a `requestAnimationFrame` (to focus the textarea). The plan
suggested:

```ts
for (let i = 0; i < 5; i++) {
  act(() => { handle.insertQuote("line " + i); });
}
expect(vi.getTimerCount()).toBe(1);  // expected 1 pending setTimeout
```

It failed with `expected 10 to be 1`. Five calls × two timers each (setTimeout
+ rAF) = 10 pending callbacks. Neither the plan author nor the initial test
author anticipated that vitest's `vi.useFakeTimers()` mocks
`requestAnimationFrame` by default — and `vi.getTimerCount()` returns the
total count across every kind of fake timer, not just `setTimeout`.

## Solution

Two complementary changes:

1. **Assert STABILITY, not an absolute count.** The fix prevents unbounded
   growth, so the right assertion is "count doesn't grow with repeated
   calls" — which is robust regardless of how many timer types the component
   schedules:

   ```ts
   act(() => { handle.insertQuote("first"); });
   const firstCount = vi.getTimerCount();  // baseline after one call
   for (let i = 0; i < 4; i++) {
     act(() => { handle.insertQuote("line " + i); });
   }
   expect(vi.getTimerCount()).toBe(firstCount);  // did NOT grow
   unmount();
   expect(vi.getTimerCount()).toBe(0);  // cleanup cancelled everything
   ```

2. **In the component, cancel BOTH timer types.** If the fix only cancels
   `setTimeout` but leaves `requestAnimationFrame` uncanceled, the stability
   assertion still fails (rAFs keep accumulating). Mirror every `setTimeout
   + clearTimeout` pair with a `requestAnimationFrame + cancelAnimationFrame`
   pair, and clear both in the effect's cleanup return:

   ```tsx
   const flashTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
   const quoteRafRef = useRef<number | null>(null);

   // Inside insertQuote:
   if (quoteRafRef.current !== null) cancelAnimationFrame(quoteRafRef.current);
   quoteRafRef.current = requestAnimationFrame(() => { ... });

   if (flashTimerRef.current !== null) clearTimeout(flashTimerRef.current);
   flashTimerRef.current = setTimeout(() => { ... }, 400);

   // Cleanup:
   return () => {
     if (flashTimerRef.current !== null) clearTimeout(flashTimerRef.current);
     if (quoteRafRef.current !== null) cancelAnimationFrame(quoteRafRef.current);
   };
   ```

## Key Insight

`vi.useFakeTimers()` with the default `toFake` list mocks every timer-like
API vitest knows about: `setTimeout`, `setInterval`, `setImmediate`,
`queueMicrotask`, `requestAnimationFrame`, `requestIdleCallback`, and
`process.nextTick`. `vi.getTimerCount()` returns a SUM across all of them.
If you want to count just `setTimeout`, pass `toFake`:

```ts
vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
```

…but that's usually the wrong escape hatch. The better move is to either:

- Write stability assertions that don't depend on absolute counts, or
- Cancel every kind of timer the component schedules, so the absolute count
  after cleanup really is 0.

Writing a test that expects `.toBe(N)` for an arbitrary N pins you to the
component's current schedule-pattern — any future refactor that adds a
well-behaved rAF or microtask will falsely "leak."

## Prevention

- When testing timer cleanup, default to **stability-based assertions**
  (count before N extra calls === count after) rather than **magnitude-based**
  (count === 1 specifically).
- Always assert `getTimerCount() === 0` AFTER unmount — that's the load-bearing
  invariant the test exists to protect.
- When writing the fix, treat `requestAnimationFrame` as a first-class timer:
  if the effect schedules one, the effect's cleanup return must cancel it.

## Session Errors

**Initial RED assertion prescribed by plan was too strict** — Recovery: switched
to stability-based assertion. Prevention: plan skills should call out that
`vi.getTimerCount()` is a sum across all fake-timer types when prescribing
test shapes.

**Test harness duplicated the exported handle interface** — `chat-input-quote.test.tsx`
declared a local `interface QuoteHandle { insertQuote: (text: string) => void }`
instead of importing `ChatInputQuoteHandle` from the component. Adding `focus()`
to the exported interface then silently broke `tsc --noEmit` via the duplicated
local type. Recovery: replaced the local interface with `type QuoteHandle =
ChatInputQuoteHandle`. Prevention: when a component exports an interface
that test harnesses consume, import it — don't shadow it — so adding methods
doesn't require parallel test-local updates.

**afterEach cleanup keyed on wrong attribute** — initially tagged cleanup with
"any [data-kb-chat] that has a data-testid", but the injected leftover's
testid was on the inner textarea, not the div. Recovery: tagged leftovers
with a dedicated `data-leftover-cleanup` attribute so cleanup never ambiguates
real component output from test fixtures. Prevention: when a test injects
DOM fixtures manually, tag them with a purpose-specific attribute (not a
generic one the real component also uses).

## Tags

category: test-failures
module: chat/chat-input, test-infrastructure
