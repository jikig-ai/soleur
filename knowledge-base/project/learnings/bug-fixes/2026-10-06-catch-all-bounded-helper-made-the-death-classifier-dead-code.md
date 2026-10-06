---
title: "The catch-all timeout wrapper made the page-death classifier dead code — a wedged-browser verdict read as a blocking FAIL"
date: 2026-10-06
category: bug-fixes
tags: [live-verify, playwright, timeouts, promise-race, verdict-honesty, test-vacuity]
module: apps/web-platform/scripts/live-verify/run.ts
issue: 9581
related: [7969, 8092, 5485]
---

# The catch-all timeout wrapper made the page-death classifier dead code

While fixing the "rail within budget" flake (#9581), `readOnce` wrapped
`locator.isVisible()` in a shared `bounded()` helper — `Promise.race` plus a
`catch { return fallback }` — so a wedged renderer could not stall the loop.
The *intent* was bounding the one unbounded read. The *effect* was that
`bounded()` converted EVERY rejection into the null fallback, so the enclosing
`catch` that ran `isClosedTargetError(err)` and produced the `"dead"` verdict
could never execute. A page that died mid-check — after at least one clean
read — polled out the window as `hidden` ticks and emitted `absent → RESULT:
FAIL → BLOCK=1`: the harness reporting a dead browser as a product regression,
the exact inversion the CANT-RUN taxonomy exists to prevent. The existing
"dead page" test still passed, because the `!sawCleanRead` backstop caught the
death-from-tick-0 fixture — a check that could not report read as one that had.

## Root cause

`bounded()` conflates two different needs: "bound this probe's wall time" and
"its outcome is diagnostic, so a throw is fine". For diagnostic field probes
(page state, rail counts) that conflation is harmless — a throw genuinely is
a fallback value. For a VERDICT-BEARING call, the rejection is information:
`isVisible()` throwing `TargetClosedError` is a different fact about the world
than `isVisible()` timing out, and flattening both into `null` destroys the
distinction before the classifier can see it.

## Fix

Race the call against a timeout *without* swallowing its rejection:

```ts
const v = await Promise.race([
  deps.railRow.isVisible(),
  new Promise<null>((resolve) => { timer = setTimeout(() => resolve(null), readMs); }),
]);
// timeout -> null sentinel -> missed tick; rejection -> catch -> classify
```

The same shape protects `page.reload()` — its own `timeout:` bounds the
navigation but not a wedged CDP transport, so the outer race is a backstop —
and `browser.close()` in `finally`, which was unbounded and could convert a
computed FAIL into CANT-RUN (or hang past the RESULT line entirely).

A second layer of the same honesty rule: `sawCleanRead` is *global*. A reload
that wedged the transport, followed by all-timeout phase-B reads, still
satisfied it and emitted `absent` — "did not appear" asserted on reads that
never executed in the window that counted. Track `cleanReadPostReload` and
emit `unverifiable` when the recovery draw ran but no post-reload read
settled.

## Prevention

- **A timeout wrapper that also swallows errors must never be applied to a
  call whose rejection carries classification information.** `bounded()` is
  for *diagnostic* reads. Verdict-bearing calls get a manual `Promise.race`
  so timeout (missed tick) and rejection (death class) stay distinguishable.
  The rule is now written into both race sites' comments in `run.ts`.
- **A verdict test must exercise the intended arm, not a fallback that
  coincidentally lands on the same verdict.** "Dead page → CANT-RUN" was
  green through `!sawCleanRead`; only the `throwAfter: {at:1}` fixture (clean
  read, then death) proves the `dead` classification. When a backstop and a
  classifier produce the same output, the pin needs a fixture that separates
  them.
- **Each regex arm gets its own fixture.** `has been closed` was masked by
  `TargetClosedError`-in-`name` on every existing case; `crashed` was missing
  entirely because Playwright's real strings are "Page crashed" / "Target
  crashed" / "Navigation failed because page crashed!" — verify classifier
  patterns against the vendored error inventory
  (`node_modules/playwright-core/lib/**`), not against the string you imagine.
- **A `budget:` escape hatch on a production seam needs a call-site pin.**
  The seam's constants only guard the default; a `budget: {totalMs:0}` at
  the call site compiles clean and shrinks the check to instant-FAIL. The
  pin suite asserts the call block carries no `budget` and — because a
  non-matching regex yields an empty block that trivially passes — asserts
  the block positively matched (`toContain("productionUrl")`).

## Session Errors

1. **`bounded()` applied to a verdict-bearing call made the `dead`
   classifier unreachable** — Recovery: manual `Promise.race` at both
   verdict-bearing sites (isVisible, reload) plus `browser.close()` bounded
   in `finally` — Prevention: the first Prevention bullet; review seats must
   ask "does the wrapper's catch-all erase a classification?".
2. **Ceiling figures drifted in the AC/docs (100s spec'd, 150s→165s
   shipped)** — Recovery: plan/tasks/session-state swept to 165s with the
   honest worst-case decomposition — Prevention: when a review changes a
   named constant, grep the constant's name across the spec dir as part of
   the fix commit.
3. **Fixture budget miscalc: the wedge test's `reloadMs+5s` backstop
   exceeded the FAST `totalMs`** — Recovery: the test's `totalMs` sized to
   the backstop (6s) so phase B still runs post-wedge — Prevention: when a
   fixture models a hang, compute its backstop against the test budget's
   `totalMs`, not just `reloadMs`.
4. **9-seat fix-round spawn tripped the model rate limit; 7 seats died** —
   Recovery: resumed in batches of 3-4 per Gate 2b after the reset window —
   Prevention: existing doctrine; space large fan-outs.
5. **Affected-battery advisory-lock contention queued >20 min behind sibling
   runs** — Recovery: operator authorized relying on CI; the targeted suite
   + tsc + eslint remained the local gate — Prevention: none needed
   (transient, per-run).
6. **One-off fixture typing/narrowing errors** (`{bogus:true}` into
   `unknown[]`; `reloadErr` assigned before union narrowing) — Recovery:
   `data: unknown` and a `kind === "appeared"` guard — Prevention: tsc
   caught both immediately; none.
