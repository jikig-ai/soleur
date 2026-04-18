---
name: RED-verification must distinguish gated from ungated state
description: A release-discipline test must exercise the gate by force; trivial pass in the no-gate state is a false RED
type: test-design
tags: [testing, tdd, concurrency, vitest, red-green-refactor]
pr: "#2576"
---

# RED-verification must distinguish gated from ungated state

## Problem

Implementing a concurrency gate around `runQpdf()` (closes #2472), I wrote four
RED tests before the GREEN semaphore landed. Running them in the no-gate state,
only 3 of 4 tests failed. The other two — "releases slot on spawn_error" and
"releases slot on non_zero_exit" — passed in the no-gate state:

```ts
const p1 = linearizePdf(...); // first call errors out
const p2 = linearizePdf(...); // held open
const p3 = linearizePdf(...); // should wait behind the gate

await vi.advanceTimersByTimeAsync(0);
const r1 = await p1;
expect(r1.ok).toBe(false);

await vi.advanceTimersByTimeAsync(0);
expect(mockSpawn).toHaveBeenCalledTimes(3);
```

Without a gate, all three calls spawned immediately and `mockSpawn` reached 3
the same way it would reach 3 with a gate (after p1's error released a slot
and p3 entered). The test's final-state assertion was tautological relative
to the invariant it was supposed to prove.

## Root Cause

The test verified the **final state** (3 spawns) but not the **gating
behavior** that connected "slot released" to "queued call proceeded." In the
ungated world there's no queue — so "p3 got past the gate" is trivially true.
The test discipline ("assert on mutation, not pre-state" — see
`cq-mutation-assertions-pin-exact-post-state`) is easy to break for
concurrency primitives where the invariant is *sequencing*, not a final value.

## Solution

Restructure release-discipline tests to use a `holdOpen: true` pattern with
**manual event emission** and a **two-point assertion**:

```ts
const children: Array<ReturnType<typeof fakeChild>> = [];
mockSpawn.mockImplementation(() => {
  const c = fakeChild({ holdOpen: true });
  children.push(c);
  return c;
});

const p1 = linearizePdf(...);
const p2 = linearizePdf(...);
const p3 = linearizePdf(...);

await vi.advanceTimersByTimeAsync(0);
expect(mockSpawn).toHaveBeenCalledTimes(2); // GATE MUST HOLD p3

children[0].emit("close", 3, null); // fire error branch
await vi.advanceTimersByTimeAsync(0);
expect(mockSpawn).toHaveBeenCalledTimes(3); // RELEASE MUST LET p3 IN
```

The two assertions bracket the release event: the first proves the gate
existed and held, the second proves release fired. Without a gate, the first
assertion fails immediately (count = 3 before the event). Without release,
the second assertion fails (count stays 2 after the event). Each assertion
fails under a specific regression class.

## Key Insight

For gating/sequencing primitives, **a final-state assertion alone cannot prove
the primitive works** — it can only prove the outcome ended up correct, which
is usually achievable without the primitive. RED must assert the
**intermediate state that only the primitive produces**. For a semaphore,
that's "count is bounded while slots are held." For a lock, that's "second
acquire is pending while first holds." For a queue, that's "ordering survives
concurrent pushes."

A quick heuristic: if your RED test passes on `main` with the primitive
removed, the test isn't testing the primitive — it's testing something the
primitive happens to coincide with.

## Prevention

- When writing RED tests for concurrency, locks, queues, or any ordering
  primitive: add a pre-release assertion that would fail without the gate
  AND a post-release assertion that would fail without release.
- Always RED-verify. This session's `vitest run` after writing the tests is
  what caught the issue — two of four tests passed in the no-gate state,
  which was the signal to restructure.
- Pattern to steal: `mockImplementation(() => fakeChild({ holdOpen: true }))`
  plus manual `child.emit(...)` for each event type the gate should
  release on (`close 0`, `close N`, `error`, timeout-via-fake-timers).

## Session Errors

**Weak RED-verification on release-discipline tests** —
Recovery: restructured from "3 concurrent calls + await p1 + assert count=3"
to "3 calls + assert count=2 + emit event + assert count=3."
Prevention: add to `work` skill TDD Gate (bullet): "RED-verify must
distinguish gate-absent from gate-present. If a test passes in the
pre-implementation state, the test doesn't exercise the invariant —
restructure before claiming RED."
