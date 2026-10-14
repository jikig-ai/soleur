---
date: 2026-09-26
problem_type: test_failures
component: web-platform-testing
status: closed
tags: [playwright, timing, perf-probe, live-verify]
---

# Playwright `request.timing()` fields are relative to `startTime`, not epoch — and unpopulated at the `response` event

## Problem

`scripts/live-verify/perf-probe.ts` (#8978 Phase 0) captured the per-request
`/api/*` waterfall by reading `request.timing()` inside a `page.on("response")`
listener and computing `durationMs = t.responseEnd - t.startTime`. The live run
emitted `durationMs: 0` / `ttfbMs: 0` for every request — the waterfall the PR
claimed as a deliverable was silently empty.

## Root cause

Two unit-convention errors stacked:

1. `timing().startTime` is **absolute epoch ms** (~1.76e12); every other field
   (`responseStart`, `responseEnd`) is **ms RELATIVE to startTime**, with `-1`
   for unavailable — not zeroed. `responseEnd - startTime` is ≈−1.76e12, so a
   `Math.max(0, …)` clamp masked it as `0`. A "validity" check written as
   `t.responseEnd > t.startTime` was always false, which would have been the
   correct signal that the math was wrong — instead the code reported `0`
   rather than `-1` (unknown).
2. `timing()` is only fully populated at `requestfinished`; at the `response`
   event `responseEnd` hasn't landed yet — even correct subtraction reads
   `-1`. Capture per-request durations on `requestfinished` (or re-read timing
   there), and treat the response object via `req.response()`.

Review caught it because the fix's own comment claimed "zeroed fields" — a
wrong claim about the API's contract that invited a wrong fix. When an
instrument reads a platform timing API, pin the UNIT CONVENTION with a pure
exported helper + fixture test (`durationsFromTiming` + a table of
relative/-1 cases in `test/live-verify/perf-probe.test.ts`); a fixture built
from the docs would have failed the first version on sight.

## Solution

```ts
// timing() → { durationMs, ttfbMs }: all non-startTime fields are already
// ms-since-request-start; -1 means unavailable.
export function durationsFromTiming(t) {
  return {
    durationMs: t.responseEnd >= 0 ? t.responseEnd : -1,
    ttfbMs: t.responseStart >= 0 ? t.responseStart : null,
  };
}
// capture on page.on("requestfinished"), not "response"
```

## Session Errors

1. **`test-all.sh --affected` orphaned under lefthook** — a ~1.5 h gate run
   outlived its parent (lefthook killed), holding the repo-global flock and
   blocking subsequent commits; resolved by killing the orphan PID. Recurring
   risk: any in-flight gate that outlives its `git commit` parent wedges the
   queue silently.
   **Prevention:** check `ps --ppid`-orphaned `test-all` runs before blaming
   the flock; consider a parent-death watchdog in the runner.
2. **Bundled Playwright chromium missing on this host** (expected `1208`,
   cache holds `1232`) — worked around with
   `LIVE_VERIFY_BROWSER_PATH=/usr/bin/chromium` (system chromium + the
   run.ts Wayland args). Operator-tracked already (`yay -S google-chrome`).
   **Prevention:** the probe/run.ts already expose the override env; none.
3. **Convergent review finding — same primitive, divergent trust rules.** The
   session-JWT decode appeared twice with different acceptance rules (the
   route trusted `payload.email` unconditionally; `resolveIdentity` required
   `payload.sub === userId`). Five reviewers independently flagged the same
   divergence. **Prevention:** when a PR teaches the codebase a new local-
   verification primitive, write it once as a shared helper
   (`sessionJwtEmailForVerifiedUser`) — a second copy of security-adjacent
   logic will diverge.
4. **`git diff --cached` content vs running gate mismatch** — the in-flight
   `--affected` run read the live worktree while edits continued; mid-edit
   torn reads are a flake vector. **Prevention:** commit the stable slice
   first, or accept `--no-verify` + a single end-of-phase gate run (chosen).

## Prevention (workflow)

- Probe/diagnostic scripts that emit a RESULT line must bound every renderer
  call (`Promise.race` timeout on `page.evaluate` and waterfall settles) — a
  wedged renderer is a hypothesis the probe exists to separate, and an
  unbounded call produces NO output, the worst failure shape.
- Extension-of-surface changes (minted header reaching the render path)
  require re-running the guard's enumeration — `middleware-matcher-coverage`
  walked `route.ts` only; the new consumer lives in `layout.tsx`.
