---
title: Two independent review seats reported a committed suite RED on fixtures they rebuilt themselves
date: 2026-11-08
category: review-patterns
tags: [review-panel, false-positive, fixture-verification, tr, assertion-vocabulary]
---

## Problem

During PR #12354's review panel, two seats (pattern-recognition-specialist,
data-integrity-guardian) independently filed a P1: the committed
`regenerate-shard-manifest.test.sh` Z8 fixture was claimed to seed `m-thin-e`
in **all five** run TSVs, which would make the "under-sampled (2/5)" negative
arm false and the suite RED as committed. Both seats said they ran the
generator on the fixture and saw `PRICE_DRIFT_ROW … 5/5`.

But the committed suite had just run **green 142/142** — and one `grep -n
'm-thin-e'` showed the label in exactly two timing files (run1, run2).

## Solution

Both seats had reconstructed the fixture in their own scratch dirs rather than
reading the committed test file verbatim — and in reconstruction they wrote
`m-thin-e` into every run TSV (the *simpler* shape: all six measured rows in
every file), then reported their reconstruction as a defect in the committed
diff. The committed fixture intentionally omits the row from runs 3–5.

Resolution discipline used: for every "the committed test is RED as
committed" claim, the lead re-verifies against `grep`/`git show` of the
*committed* file, not the seat's reproduction — a finding about a fixture is
only as strong as the file it was measured on (same class as
`knowledge-base/project/learnings/2026-09-10-…`: "a survivor list is only
true for the tree it was measured on").

## Key Insight

A review finding that asserts a state ("the suite is RED as committed") is
falsifiable by one read of the committed file — run the falsifier before
accepting the fix. Seats exploring in scratch dirs routinely substitute the
simpler shape for the real one; the report describes their fixture, not the
PR's. Two seats making the *same* wrong claim is stronger-looking but not
stronger — both reconstructed from the same wrong assumption, not
independently.

## Session Errors

1. `tr -cd '[:alnum:]_.-/()[]'` silently stripped hyphens: `-` inside the
   set formed a `.`–`/` range, mangling every label in the watch's findings
   (5 scenarios regressed). **Prevention:** in `tr` sets put `-` first or
   last; test the sanitizer on a real label (`f-meas-x`) before committing
   the allowlist.
2. The u1 negative check `!= *"wall deadline"*` failed on the fix's own
   marker text `wall deadline overridden by PBG_UNBOUNDED=1` — output
   vocabulary and assertion vocabulary must be disjoint. **Prevention:**
   key negative checks on the failure's unique shape (`wall deadline (Ns)
   ended`), never on a phrase the success path might echo.
3. `[[ -z "${VAR:-}" ]]` keyed a sweeper-channel refusal on *value*
   emptiness, but the launcher exports the var unconditionally (empty when
   the directive omits `earliest=`). **Prevention:** channel-detection
   checks use set-ness (`${VAR+x}`), not emptiness (`${VAR:-}`) — verify
   against the launcher's actual env-rebuild code, not the variable's
   semantics.
4. `git rebase --continue` blocked on `nvim` for COMMIT_EDITMSG in a
   non-interactive shell. **Prevention:** `GIT_EDITOR=true git rebase
   --continue` on any continuation that may open the message editor.
5. ADR-276 append-order conflict with #12329 (predicted in plan; resolved
   append-only, keep both sides). **Prevention:** for append-only log
   files, resolve conflicts by keeping both hunks; never pick one side.
6. Technical-ruling gate wrapper printed `GATE_RC=0` while the output
   carried 8 findings (real rc=1). **Prevention:** capture the script's
   exit code directly, never infer it from wrapped output.
7. `pgrep -f <pattern>` rejected as self-matching (the wrapper's own argv
   carries the pattern). **Prevention:** monitor by captured PID,
   `list_runs`/`kill_mine` from `proc.sh`, or file-side progress markers —
   never `pgrep -f` inside a bash -c wrapper.
8. (Subsumed): pre-rebase `mergeable=CONFLICTING` — same class as item 5;
   the false-P1 fixture claims are this document's Problem, not an error.

## Related

- `2026-09-10-every-assertion-i-wrote-to-prove-the-fix-was-satisfied-while-the-defect-was-live.md`
  (a survivor list is only true for the tree it was measured on)
- `2026-09-08-every-field-my-alarm-trusted-came-from-the-region-it-did-not-trust.md`
  (unvalidated report fields reaching consumers)
