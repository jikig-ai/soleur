# Learning: a dispatcher's tests pinned source spelling, not wiring; and a pinned count had an ungated twin

## Problem

Follow-up (a) of the merge-queue decision record added an Inngest cron
(`cron-merge-queue-stall-dispatch`) that POSTs `workflow_dispatch` to the stall-probe workflow, plus a
dispatcher-fed Sentry monitor and the parity edits that a new monitor moves. It was green on a
23-test suite, a 6-row mutation battery (6/6 killed), `tsc`, every parity suite and semgrep. A
10-seat review panel then found 32 issues in the verification and the prose, not the feature:

- The mocked `Octokit` ignored its constructor arguments, so `new Octokit()` (no auth, every tick a
  404) stayed green; the mint and the request params were asserted, the wire between them was not.
- Registration anchors (`retries: 1`, the cron, the lane limits) were substring checks over the file,
  and the file header documents the same strings. `retries: 0` and an hourly cron both stayed green.
- The replay fake memoized resolved values only, so the mint-failure branch could not tell
  report-inside-step from report-outside-step.
- A `C4` count was bumped on one edge (`github -> sentry`: 62/45) while the `webapp -> sentry` edge in the
  same file still said 44. Three seats found it; the parity test did not gate that clause.
- A regex comment stripper written to fix the header problem deleted real code after a `"/*"` inside a
  string and kept trailing comments.

## Solution

- Capture the constructor options in the mock and assert `auth` equals the minted token, in the
  success and the failure test.
- Strip comments with the compiler (`ts.transpileModule(src, { compilerOptions: { removeComments:
  true } })`), then anchor on the emitted code and on whole option shapes
  (`{ scope: "fn", limit: 1 }`, `concurrency: [`), not on bare tokens.
- Make the replay fake memoize rejections too, and add the mint-failure replay test.
- Add a parity row (`C9`) in `c4-count-parity.test.sh` for the clause the PR had left stale; mutated
  the model to 44 and confirmed it fails with "edge `webapp -> sentry` is STALE (C9)".
- Retry a transient dispatch failure once inside the (never-throwing) dispatch step, and keep the
  catch total with a `safeMessage` helper.

## Key Insight

A suite for a *dispatcher* is mostly wiring (mint -> client -> request -> heartbeat, and which step
each side effect sits in). Mocks that ignore their inputs and anchors that read prose test the
spelling of the file, so the author's own mutation battery, which edits the lines the author was
thinking about, scores them as covered. The cheap check is to ask of every mock "what does this
ignore?" and of every `toContain` "does the file's header contain this string?". And a count that
appears on two edges of a model is two claims; gate both or derive one from the other.

## Session Errors

1. **Stale local `main` ref** (a `git grep ... main` for the precedent returned nothing). Recovery:
   read `HEAD`/`origin/main` after `git fetch`. **Prevention:** in a bare-repo layout probe with
   `HEAD` or `origin/main`, never the local `main` branch name (already a documented class).
2. **`*/` inside a `/** ... */` header** (`` `*/10` `` in prose) broke the esbuild transform.
   Recovery: reword. **Prevention:** already in the work skill; the compile error is immediate and
   self-explanatory, so no new gate.
3. **Non-atomic multi-edit Python batch**: an anchor assertion failed on the fourth edit after three
   had landed. Recovery: re-read the file, apply the rest. **Prevention:** assert all anchors before
   writing any, or write once at the end (the batch pattern in this session now does).
4. **A malformed mutant** (dropped `try {` left a dangling `catch`) produced "no tests" and rc=1, which
   a naive scorer counts as a kill. Recovery: redid it as a semantic mutation. **Prevention:** a
   scorer must require a failing test name, not just a non-zero exit (already in the review skill as
   "a crash is not a kill").
5. **The `webapp -> sentry` C4 edge kept the old count** after only the `github -> sentry` edge was
   edited. Recovery: 44 -> 45 and added parity row C9. **Prevention:** `c4-count-parity.test.sh` row
   C9 now gates it; when a count appears in two clauses, gate both.
6. **Tests pinning spelling, not wiring** (constructor args ignored, anchors satisfied by the header,
   rejected steps not memoized, Sentry options under-pinned). Recovery: rewrote the tests, then
   mutation-proved 19 new mutants. **Prevention:** the review skill already carries this class;
   the new evidence is that it recurred in a test written for the same PR that documented it.
7. **A regex comment stripper deleted real code**. Recovery: compiler-based stripping.
   **Prevention:** never strip comments with a regex in a test that guards for forbidden tokens.
8. **An unbounded `grep -n` over `model.c4`** printed multi-kilobyte lines. Recovery: `grep -o` with
   bounded context. **Prevention:** use `-o` with `.{0,60}` context on files with very long lines.
9. **Fix-round seat set narrowed from the script's 12 to 3 by judgment.** Recorded in the review
   summary; no failure resulted.

## Tags
category: test-failures
module: apps/web-platform/server/inngest
