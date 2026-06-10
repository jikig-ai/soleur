# Learning: parallel-load test flakes — two distinct timeout mechanisms, and wait-on-absence assertions are vacuous without a settle anchor

## Problem

Two test files flaked under full-suite parallel load (`TEST_GROUP=webplat bash scripts/test-all.sh`, 760 files) while passing green in isolation and on main CI (#5113, observed by #5098):

1. `test/live-repo-badge.test.tsx` — a *different* J5 interstitial case failed each run (the signature of probabilistic CPU starvation, not ordering-dependent state leak).
2. `test/server/inngest/signature-verify{,-dev-mode}.test.ts` — 16 s test timeouts on the first test of each file.

The issue body's "component pool state leak" hypothesis was wrong — cross-file leak vectors were already closed by forks+isolate (#3817). Code-tracing found the real mechanisms.

## Solution

Two distinct root causes needed two distinct fixes:

- **H1 — intra-test wait budgets (1000 ms defaults) starve under contention.** #4128 raised `testTimeout` to 16 s but never aligned the *intra-test* ceilings: vitest's `vi.waitFor` defaults to 1000 ms AND RTL's `findBy*`/`waitFor` default to `asyncUtilTimeout: 1000`. **These are two separate mechanisms — `vi.waitFor` does NOT read RTL config.** Fix: global `configure({ asyncUtilTimeout: 10_000 })` in the component-project setup file (closes the class for ~500 RTL waits) PLUS per-call `{ timeout: 10_000 }` on `vi.waitFor` sites (vitest has no config knob for it).
- **H2 — cold import of a heavy module graph inside `it()` races `testTimeout`.** The signature-verify pair are the only tests importing the full 52-function Inngest route graph as a live module; the first `await import(...)` inside an `it()` paid the whole cold-import cost against the 16 s test budget. Fix: `beforeAll(async () => { await importRoute(); }, 60_000)` — re-attributes a known bounded one-time cost to an explicit hook budget (pdfjs-dist precedent, `pdf-text-extract.test.ts`, #4097 Fix 3). A hook-timeout failure also names the hook — a clearer signature than a flaky first-test timeout.

Review pass added three hardening fixes: a leak-guard drift row for the new `asyncUtilTimeout` line; a settle-flag anchor for the happy-path absence assertions; canonical-source reference instead of a restated suite count.

## Key Insight

1. **A "flaky test" symptom can have two unrelated mechanisms in one issue — falsify each against the error shape before fixing.** H1 predicts waitFor/findBy timeouts at ~1 s; H2 predicts `Test timed out in 16000ms` on the first test. Conflating them produces a fix that closes one mechanism and leaves the recurrence ambiguous.
2. **`vi.waitFor` (vitest) and `waitFor`/`findBy*` (RTL) have independent 1 s defaults and independent config surfaces.** A global RTL `asyncUtilTimeout` bump does NOT touch `vi.waitFor` call sites; per-call `{ timeout }` does NOT touch RTL waits. Any contention-tolerance fix must cover both or document why one side is out of scope.
3. **Wait-on-absence is vacuous:** `await vi.waitFor(() => expect(queryByTestId(x)).toBeNull())` passes on the FIRST tick (the element is absent before the async work resolves), so it never proves "absent AFTER the state commit." Anchor the wait on a positive settle signal — a `.finally(() => { settled = true; })` flag on the mocked response body — then assert absence.
4. **Never restate a drifting numeric fact (suite size, file count, registry size) in a new comment — reference the canonical source instead.** A copied count is stale the week after; two files in the same diff carrying contradictory counts confuses the next reader/agent.
5. **Timeout hierarchy must nest:** per-hook budget (60 s) > testTimeout (16 s) > intra-test wait ceiling (10 s). The 10 s < 16 s ordering is load-bearing — the failing wait throws its own diagnostic error before the generic test timeout fires, preserving error attribution.

## Session Errors

1. **Planning subagent ran without the Task tool** — plan-review and deepen-plan research executed as inline passes instead of parallel agents. Recovery: inline self-review still caught an AC error (signature-verify count 5/5 → actual 6/6) before implementation. **Prevention:** pipeline-context adaptation worked as designed; the deepen-plan inline fallback is adequate for small plans — no change needed.
2. **Foreground `sleep 30` blocked by hook** while waiting on a background test run. Recovery: relied on the harness's background-task completion notification. **Prevention:** never poll a harness-tracked background task — the notification re-invokes the session; just end the segment.
3. **7 of 10 review agents hit the session usage limit** mid-review. Recovery: the review skill's rate-limit fallback gate (proceed with any substantive coverage) + inline gap-fill of the missed dimensions (quality/simplicity/history were low-risk: the deepen-pass had already live-verified citations, and the diff was 4 small test files). **Prevention:** existing gate is sufficient; for large/risky diffs, prefer re-running the missed agents after the limit resets instead of inline gap-fill.
4. **New comment restated a stale drifting count** ("473 files", actual 760) copied from an older comment in the same repo. Recovery: caught at review by agent-native-reviewer; fixed in e1c874253 by referencing `vitest.config.ts` instead. **Prevention:** Key Insight 4 — cite the canonical source for any fact that drifts.

## Tags

category: test-failures
module: apps/web-platform/test
