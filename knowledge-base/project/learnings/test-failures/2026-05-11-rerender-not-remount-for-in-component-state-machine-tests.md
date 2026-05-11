---
module: apps/web-platform
date: 2026-05-11
problem_type: test_failure
component: react_testing_library
symptoms:
  - "RED test passes without the fix (vacuous green)"
  - "Test claims to verify in-component state-machine behavior but resets the state under test on every fixture step"
  - "Bug recurs in production despite green CI"
root_cause: test_harness_resets_sut_under_test
severity: high
tags: [tdd, red-discipline, react-testing-library, rerender, in-component-state]
synced_to: [work]
related:
  - knowledge-base/project/learnings/test-failures/2026-04-18-red-verification-must-distinguish-gated-from-ungated.md
  - knowledge-base/project/learnings/test-failures/2026-04-22-red-test-must-simulate-suts-preconditions.md
---

# Use `rerender`, not `unmount` + remount, when the gate-under-test is in-component state

## Problem

PR #3558 added a dismiss button to the dashboard `<ErrorCard>`. The dismissal-key (`dismissedErrorKey`) lives in component-local `useState` inside `apps/web-platform/components/chat/chat-surface.tsx`. A multi-agent code review (git-history-analyzer) caught a bug the original RED tests missed: after a reconnect that nulls `useWebSocket.lastError`, the SAME `(code, message)` re-firing was silently suppressed because `dismissedErrorKey` survived the reconnect cycle while `lastError` did not.

Writing the regression test, the first attempt looked correct on the surface:

```tsx
const { unmount } = await renderChatPage();
await userEvent.click(screen.getByRole("button", { name: /dismiss/i }));
unmount();

// Reconnect: lastError nulls then re-fires identical
wsReturn.lastError = null;
const { unmount: unmount2 } = await renderChatPage();
unmount2();

wsReturn.lastError = { code: "key_invalid", message: "X", action: undefined };
await renderChatPage();
expect(screen.getByText("Invalid API Key")).toBeInTheDocument();
```

This **passes without the fix**, because `dismissedErrorKey` is component state — every `renderChatPage()` mounts a fresh component, and a fresh mount initializes `dismissedErrorKey = null`. The test was vacuous: it never exercised the "key persists across the WS state change" path that the real bug depended on.

## Solution

Use `result.rerender(<Component />)` to re-render the SAME mounted instance with new mock state. RTL's `rerender` preserves component state across re-renders — exactly what's needed when the gate-under-test lives in `useState`/`useRef`.

```tsx
const result = render(<mod.default />);

await userEvent.click(screen.getByRole("button", { name: /dismiss/i }));

// lastError nulls; component stays mounted; dismissedErrorKey persists.
wsReturn.lastError = null;
result.rerender(<mod.default />);
expect(screen.queryByText("Invalid API Key")).toBeNull();

// Identical shape re-fires. WITHOUT the null-edge reset, dismissedErrorKey
// still equals "key_invalid::X" and the card stays hidden — RED.
wsReturn.lastError = { code: "key_invalid", message: "X", action: undefined };
result.rerender(<mod.default />);
expect(screen.getByText("Invalid API Key")).toBeInTheDocument();
```

The fix lived in `chat-surface.tsx`:

```tsx
useEffect(() => {
  if (!lastError) {
    setDismissedErrorKey(null);
  }
}, [lastError]);
```

## Key Insight

**A test for an in-component state-machine invariant must drive the SUT through the state transitions WITHOUT remounting the SUT.** `unmount()` + `render()` is a fresh boot, not a state transition. Any in-component bookkeeping (`useState`, `useRef`, `useReducer`) gets wiped on remount, so a test that relies on remount to "advance" the world is testing the boot path, not the transition path.

This is the same class as `2026-04-18-red-verification-must-distinguish-gated-from-ungated`: the RED must produce different outcomes with vs. without the gate. When the gate IS the in-component state, only `rerender` exposes the gate.

## Prevention

- **Pre-commit gate (mental):** before committing a RED test that uses `unmount()` between mock mutations, ask "does the SUT carry state across this transition in production?" If yes, switch to `rerender`.
- **Plan-stage AC:** when the dismissal/gate is keyed on a derived value (`${code}::${message}`), the AC list MUST enumerate the same-key-after-clear case explicitly — "different code shows new card" is NOT a substitute for "same code re-shows after upstream clears."
- **Multi-agent review catches what RED-first misses:** the silent-suppression bug was found by `git-history-analyzer` precisely because RED-first focused on the cases enumerated in the plan. Treat plan ACs as a floor, not a ceiling — review-stage interaction-risk analysis is load-bearing.

## Session Errors

- **Vacuous RED via unmount+remount** — Recovery: caught by reasoning before commit, rewrote with `result.rerender()`. Prevention: add the heuristic above to the work skill's TDD-gate checklist.
- **Missed AC for same-shape rehydration** — Recovery: post-review fix + regression test. Prevention: when a discriminator key is used for dismissal/dedup, AC must include "same key after upstream clears."

## Cross-References

- `2026-04-18-red-verification-must-distinguish-gated-from-ungated.md` — sibling pattern; this learning extends the principle to in-component state.
- `2026-04-22-red-test-must-simulate-suts-preconditions.md` — adjacent (precondition simulation rather than state preservation).
- PR #3558 — branch `feat-one-shot-dashboard-error-close-button`. Fix at `apps/web-platform/components/chat/chat-surface.tsx`; regression test at `apps/web-platform/test/error-states.test.tsx`.
