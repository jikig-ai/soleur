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
6. **A post-DISMISS / post-event absence wait is NON-vacuous when presence is proven first — but it must still carry the file's load-tolerant `{ timeout }`.** Unlike the poll-driven case in Insight 3, a `fireEvent.click(dismiss)` → `await vi.waitFor(() => expect(queryByTestId(x)).toBeNull())` is anchored by the preceding `await findByTestId(x)` (the node IS present at wait-start, so tick 1 can legitimately fail). The remaining trap is the budget: a NEW `vi.waitFor` site inherits vitest's 1000 ms default, re-arming the very worker-starvation flake the file's other waits override with `{ timeout: 10_000 }`. When converting a bare absence assertion in a file that already standardizes on a load-tolerant `vi.waitFor` timeout, carry that `{ timeout }` to the new site. **Why:** #5234 — two orthogonal review agents (test-design + pattern-recognition) independently flagged the two new dismiss-poll sites for omitting `{ timeout: 10_000 }`; fixed inline before merge.
7. **A positive settle signal must come strictly AFTER the state change being asserted, and presence and absence must use the same selector.** A callback fired from inside an async transition (`onChanged`) precedes the commit of updates made in that transition's synchronous prefix (`setActionError(null)`), so it is the wrong anchor for an absence check on them; wait on the effect itself. The absence wait is only non-vacuous if presence was proven with the same selector (`findByRole("alert")`, not `findByText`), or renaming the role leaves it green. Repro: 40 busy-loop burners on a 16-core host failed the un-waited form 11 of 15 runs; the fixed form passed 25 of 25. **Why:** #9126 — the mechanism is written up once, in the plan for that issue.

## Session Errors

1. **Planning subagent ran without the Task tool** — plan-review and deepen-plan research executed as inline passes instead of parallel agents. Recovery: inline self-review still caught an AC error (signature-verify count 5/5 → actual 6/6) before implementation. **Prevention:** pipeline-context adaptation worked as designed; the deepen-plan inline fallback is adequate for small plans — no change needed.
2. **Foreground `sleep 30` blocked by hook** while waiting on a background test run. Recovery: relied on the harness's background-task completion notification. **Prevention:** never poll a harness-tracked background task — the notification re-invokes the session; just end the segment.
3. **7 of 10 review agents hit the session usage limit** mid-review. Recovery: the review skill's rate-limit fallback gate (proceed with any substantive coverage) + inline gap-fill of the missed dimensions (quality/simplicity/history were low-risk: the deepen-pass had already live-verified citations, and the diff was 4 small test files). **Prevention:** existing gate is sufficient; for large/risky diffs, prefer re-running the missed agents after the limit resets instead of inline gap-fill.
4. **New comment restated a stale drifting count** ("473 files", actual 760) copied from an older comment in the same repo. Recovery: caught at review by agent-native-reviewer; fixed in e1c874253 by referencing `vitest.config.ts` instead. **Prevention:** Key Insight 4 — cite the canonical source for any fact that drifts.
5. **(#9126) A compound Bash call mixed `rm -rf` with a kill-by-worktree-cwd loop.** The hook rejected the whole call, so nothing ran; the loop would also have killed the invoking shell. Recovery: `plugins/soleur/scripts/lib/proc.sh kill_mine <pattern>`. **Prevention:** stop runs with `proc.sh`, delete single files with `rm -f`.
6. **(#9126) The first `git commit` sat behind lefthook's affected-test battery for 6+ minutes, and the background notification read "exit code 0" while HEAD had not moved.** Recovery: operator authorized a bypass; committed with `LEFTHOOK_EXCLUDE=bun-test` (other hooks ran) and read `COMMIT_RC` plus `git log`. **Prevention:** existing guidance (work SKILL, `LEFTHOOK_EXCLUDE=bun-test` first) is sufficient.
7. **(#9126) A `sed` tick of plan checkboxes matched three of four because one label carried extra text.** Recovery: listed the boxes after the edit and fixed the fourth. **Prevention:** after any scripted multi-edit, assert the artifact changed (already in work SKILL).
8. **(#9126) My own single-axis mutation (delete the clear) missed the role-selector gap that the test-design seat found.** Recovery: fixed inline with `findByRole`, re-ran both mutants. **Prevention:** Insight 7; the review skill already asks to enumerate battery axes.
9. **(#9126) `git diff --stat origin/main` listed 6 files under `apps/` because the branch base was stale.** Recovery: re-derived against `git merge-base origin/main HEAD`. **Prevention:** three-dot diff or merge-base (already in review SKILL).

## Tags

category: test-failures
module: apps/web-platform/test
