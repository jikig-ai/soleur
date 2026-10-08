# Learning: the "one definition of the rule" selected a different row than its sibling, and my prose claimed more than the code enforced

## Problem
PR #9751 (Ref #9372, #6931) replaced web-2's "survives a reboot" evidence rule with "this instance's fresh
boot formatted or opened the volume" (owner principle: a host is replaced, not rebooted). The first cut
shipped a shared predicate `w2l_ready_arm` documented as "the one definition of the rule". An 11-seat review
and two targeted fix rounds found, with sandbox runs:

- The predicate selected the newest WELL-FORMED host row; its sibling `w2l_ready_verdict` judges the newest
  row of ALL rows. A newer malformed or foreign row hid an older good one in the verdict but not in the
  predicate. Safe only because both callers run the verdict first, which the comment did not say.
- The ADR addendum said "a replaced instance emits a newer readiness row and the soak restarts". True for the
  grader's soak scan; false for the marker writer (a present marker is kept on the newest probe row alone, and
  the readiness POST is best-effort). Several seats reproduced the counter-case.
- The addendum deferred stale operator-facing strings (`web2-rebirth.sh`, the rebirth workflow header) with
  "their suites pin the string". The pin covered only the string's prefix; the stale tail was unpinned.

## Solution
- `w2l_ready_arm` now takes the newest of all rows, then applies host/kind and a known-arm filter, so it can
  never accept where the verdict is RED (3,000-case differential fuzz: 0 disagreements).
- Prose scoped to what the code enforces: instance identity is a weak anchor (AP-027 advisory), a present
  marker is not a #6931 PASS, keeps its predecessor's age, and no longer evidences reopen.
- Stale strings fixed in the same PR, with the pin widened to assert the new text and the absence of the old.

## Key Insight
Two functions that both answer "which row is newest" are a divergence waiting for a third caller; name the
selection once, or write the precondition ("only after a GREEN verdict") next to the definition. And a
deferral justified by "a test pins it" must name WHAT is pinned: a prefix pin proves the prefix.

## Session Errors
- **Worktree detached unnoticed; `git push origin HEAD` failed behind a `grep`/`tail` filter** — Recovery: `git branch -f` + checkout + push; verified with `git ls-remote`. **Prevention:** after every push compare `git ls-remote origin <branch>` with `git rev-parse HEAD`; never filter a push's stderr. Cause of the detach unverified.
- **Guessed a ratchet suite path (rc 127)** — **Prevention:** locate with `git ls-files | grep` before running.
- **Chained foreground suites hit the 600 s tool timeout** — **Prevention:** `run_in_background` plus Monitor for >5 min chains.
- **Stop hook blocked closing text twice (promise without action)** — **Prevention:** arm the Monitor or run the command in the same turn, or state `<stop>BLOCKED:</stop>`.
- **Overclaimed prose in the ADR addendum / "pinned" deferral** — **Prevention:** for each causal or universal sentence a diff adds, run the command that falsifies it before review (work-skill rule); name what a pin covers.
- **Forwarded:** GitHub 500s on writes (Monitor retries); hook-blocked commands; told the user a soak gate needed approval when it did not (corrected); Monitor expiry delayed noticing a merge ~10 h (re-arm on expiry).

## Tags
category: logic-errors
module: web2-luks-evidence
