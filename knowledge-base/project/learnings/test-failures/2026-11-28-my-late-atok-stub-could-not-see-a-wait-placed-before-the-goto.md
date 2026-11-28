---
title: My late-atok stub could not see a wait placed before the goto
date: 2026-11-28
category: test-failures
module: cloudflare-old-login-token-remint (Phase 5 browser bodies)
tags: [playwright, test-harness, mutation-testing, runbook, sha-pin]
issue: 12931
pr: 13110
---

# Learning: a race-fix stub must model the navigation that recreates the race

## Problem

The #12931 Phase 5 bodies (`p5-read.js`, `p5-mint.js`, `p5-revoke.js`) read `window.bootstrap.atok` right
after `page.goto(..., {waitUntil:'domcontentloaded'})`. The dashboard sets the atok about 283 ms after
DOMContentLoaded, so every signed-in run returned `{atok:false}`. The fix added one bounded
`page.waitForFunction(() => !!(window.bootstrap && window.bootstrap.atok), null, { timeout: 15000, polling: 100 }).catch(() => {})`
after each goto, with a node-harness `waitForFunction` stub that installs the atok after its first falsy poll,
rows L1-L3 and mutants XW1-XW4 that delete each wait.

Review found the verification, not the fix, was wrong in four ways, all green on a 232-assertion suite and a
76-assertion mutant battery:

1. The stub's `goto` only recorded the URL. Page state was built once, so a wait moved ABOVE the goto, or a
   second goto after the wait, passed every row. That is the original bug plus a 15 s delay.
2. None of `waitedOnce`'s four clauses (one wait, resolved, timeout bound, numeric polling) was backed by a
   mutant; `timeout: 15`, `polling: 'raf'`, a two-argument call and a condition true before the atok each
   passed the harness and were caught only by a byte-exact `WAIT_LINE` "lands" literal.
3. XH1, the guard on the new `sha256=<64 hex>` hold normalization, edited a hold line that carried no sha, so
   an over-wide `s/sha256=[0-9a-f]{64}.*/…/` normalization stayed green.
4. A runbook sentence I added ("take `<sha256>` from this runbook") let the runbook's value override the sha
   the operator's go quoted, which is the binding the go-time check exists for.

A sibling runbook (`cloudflare-account-migration.md`, revoke recipe step 3.1) carried the identical race as
prose: the fix had been applied to the instance, not the class.

## Solution

- The stub's `goto` drops `window.bootstrap` in late-atok worlds (a navigation is a new page), the late-atok
  page starts with no `bootstrap` key (so an unguarded condition throws, as in Playwright), and the wait
  installs `{atok}` only after a falsy poll.
- `waitedOnce` bounds the timeout to [1000, 30000] ms (not near the measured 283 ms), requires
  `0 < polling < timeout`, and probes the recorded condition on fresh contexts: false for `{}`,
  `{bootstrap:{}}`, `{bootstrap:{atok:''}}`, true for `{bootstrap:{atok:'x'}}`.
- Mutants XW5-XW12 back each clause and the mint/revoke `.catch` (M3 and R6 joined SCORED). XH1 now edits text
  after the sha on the sha-bearing revoke hold. XC1 requires every 64-hex value in the runbook to be a
  `<body> (sha256=<hex>)` citation.
- The printed go-time body check now compares the go-quoted sha with the runbook's section 5 value and stops
  with `reason=not-section5` when they differ.
- The account-migration recipe got the same wait.

## Key Insight

When a fix inserts an ORDERING step (a wait, a lock, a re-read), the property is "after the event that
recreates the hazard", and a stub that does not model that event re-creating the hazard cannot see the step
moved to the wrong side of it. Ask of every stub: which real operation resets the state my fix depends on, and
does my stub reset it? And when a mutant battery's only kill for a clause is a byte-exact "lands" literal, the
clause is unpinned: delete the assertion and see whether anything else reds.

## Session Errors

1. **`kill_mine` refused to stop the local infra run (`reason=same-process-group`).** Recovery: stopped it
   through its background task with TaskStop. **Prevention:** a run started by this session's Bash tool shares
   the harness's process group; stop it with TaskStop, and reserve `kill_mine` for runs started elsewhere.
2. **The affected gate exited rc=1 on `pencil-adapter-stub-repl.test.ts` timeouts.** Recovery: confirmed
   unrelated (no pencil file in the diff) and already tracked as #12853. **Prevention:** search for an existing
   tracker on the failing test name before re-running it.
3. **The local `test-all-infra-coverage-notice` run passed 20 minutes and was killed unresolved.** Recovery:
   the operator ruled CI gates that suite. **Prevention:** for a suite the diff cannot reach, let CI gate it
   rather than holding the pipeline on a local run.
4. **The L1 FAIL text was cut at 400 characters before naming the result.** Recovery: a short
   `must(r.success === true, ...)` pre-check. **Prevention:** a mutant's expected text must fit the harness's
   FAIL truncation; put a short assertion first.
5. **A one-off 63-hex check first targeted a section 5 line, not a hold, and measured nothing.** Recovery:
   re-targeted at a `- Hold:` line. **Prevention:** assert which line a one-off mutation changed before
   reading its verdict.
6. **The harness stub did not model navigation (review P1).** Recovery: as above. **Prevention:** the Key
   Insight question, asked when the stub is written.
7. **My runbook sentence overrode the go-quoted sha (review P2).** Recovery: the check command now compares
   both. **Prevention:** a sentence that changes which value a gate trusts goes into the gate's command, not
   prose beside it.
8. **The sibling account-migration runbook kept the race (review P2).** Recovery: same wait added.
   **Prevention:** grep the repo for the read pattern (`bootstrap.atok`) before calling a race fixed.
9. **The review scan gate was first fed paths on stdin and reported `skip files=0`.** Recovery: passed the
   paths as arguments. **Prevention:** `review-scan-gate.sh` takes paths as arguments; a `files=0` on a
   non-empty diff is a misuse, not a clean scan.
10. **`fix-round-seats.sh` was called from the wrong directory and with an invented `--tier` flag.** Recovery:
    the script lives in `plugins/soleur/skills/review/scripts/` and takes `--files` and `--finding-seats`.
    **Prevention:** run `--help` before passing flags.
11. **The bootstrap suite was started though it does not read either edited runbook.** Recovery: stopped
    it and ran the suites the grep named. **Prevention:** select suites by grepping for the edited path first.
12. **Run-health rows for the plan and work steps were not emitted (ledger shows `0d`, `review`, `qa`).**
    Recovery: none (the steps completed; the ledger under-reports). **Prevention:** emit the row at each step
    boundary, not at the end.
