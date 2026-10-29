# Decision challenges — feat-one-shot-10932-restore-engine-exit1-header-row

Plan: `knowledge-base/project/plans/2026-10-29-chore-restore-engine-exit-1-header-row-plan.md`

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Q1: keep or drop the `grep -vx 1` ignore on both sides of W9's header-vs-emit comparison (and the header UNION {1} rule) once the header lists 1. | technical | Ruled by CTO agent, 2026-10-29: keep the ignore and change no test logic; reword `tests/scripts/lib/restore-engine-header.sh` lines 8-11 to say exit 1 is always exercised (header UNION {1}), the comparison still ignores 1 on both sides so a missing or extra header row for 1 is not caught, and the workflow arm is already on main (drop "tracked in #10932"); also drop the stale parenthetical in the A2 comment of `test-registry-pull-path-health.sh`. Dropping the ignore is a good follow-up but a separate change - it is test-logic and would widen item (a). |
| Q2: fix the runbook sentence "Its own header table does not yet list exit 1 (input faults, tracked on #10932)" in this PR? | technical | Ruled by CTO agent, 2026-10-29: yes, that one sentence in `registry-luks-recut-6929.md` and nothing else - it is false once the header row lands, the runbook is neither an apply trigger nor a battery path, and no test pins the phrase. Suggested wording: "Its own header table lists exit 1 (input faults), as does the restore step annotation and the row below." |
| Q3: floors and messages (`-ge 7`, "(1 + six header rows)", "fewer than 6 failure codes"). | technical | Ruled by CTO agent, 2026-10-29: leave both floors and every assertion untouched (the union with {1} keeps the count at 7 either way); reword only the stale messages - A2 to "(seven header rows, exit 1 included)", W9 to "fewer than 7"; `EXPECTED_ASSERTIONS=47` is unaffected. |
| Follow-up: drop the `grep -vx 1` ignore so a deleted header row for 1 goes red. | technical | Ruled by CTO agent, 2026-10-29: out of scope for this PR (follow-up candidate, rides with the residual list already open on #10932/#9757). |
| Brief-fenced items (#11312, #11379, #10924, #9757 itself; "Restore summary" step, computed `die "$x"`, W9 verdict swap, wording owned elsewhere). | operator (scope) | Out of scope per the operator's brief; not touched. |
