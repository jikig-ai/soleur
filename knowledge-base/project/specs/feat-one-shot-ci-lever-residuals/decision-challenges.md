# Decision Challenges — feat-one-shot-ci-lever-residuals

Plan: `knowledge-base/project/plans/2026-11-07-chore-ci-lever-residuals-plan.md`

This harness has no subagent spawn capability, so technical rulings that would
normally be delegated to `soleur:engineering:cto` are recorded as
`pending - assumed: <default>` per the technical-ruling delegation rule. Where
the work phase can spawn the CTO agent (e.g., the S4 re-ruling confirmation),
the row names it.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Drift-arm flag bound: `timed>=3`, ratio >=4x or <=0.25x in either direction, \|delta\| >= 120000 ms | technical | pending - assumed: bound sized so the two known-stale rows (43x/109x) flag while the audit's ordinary drift band (+12%..+190%, max 2.9x) does not; >=3-of-5 samples suppresses one-run contention spikes |
| #9323 convergence path: `PBG_UNBOUNDED=1` operator seam lifting the wall deadline for a local verdict run (vs marker-comment bypass vs download parallelization vs uncommitted one-off) | technical | pending - assumed: seam (~15 lines + test rows) is the minimal auditable unblock; on PASS the probe retires per its own RETIREMENT block so the seam dies with it; FAIL leaves a working operator path; marker bypass rejected (changes verdict contract for a one-shot); parallelization kept as the contingency if the unbounded run still cannot converge |
| #9323 close-on-PASS + probe retirement in this PR | technical | pending - assumed: the probe's own RETIREMENT block prescribes the six-artifact removal; closing stops the sweeper (open trackers only) |
| Manifest regen (`suite-shard-legs.tsv` rebalance) deferred out of this PR | technical | pending - assumed: post-refresh predicted max/mean = 1.26 < the watch's 1.30 flag bound; regen re-seats unrelated drifted rows (noisy diff) and was not asked for; routine regen re-seats later |
| #9729 scope in this PR: evidence + re-ruling only, no activation machinery (no `[full]` marker, no admin-merge-ready read, no lock removal) | technical | pending - assumed: matches ADR-276's ordering (re-ruling precedes stage 2) and the non-activation discipline every S4 amendment restates |
| S4 go/no-go re-ruling itself (confirm the computed verdict, incl. criterion-(c) grading in billed job-min per pull_request run and whether the advisory-ratchet ~3.4 billed min/run counts against it) | technical | pending - assumed: computed verdict stands pending CTO-agent confirmation at work time if spawn is available (the 2026-10-16 NO-GO was CTO-confirmed; a re-ruling wants the same); the 2026-10-22 amendment already says the ratchet cost lowers the (c) measurement |
| S4 activation go-ahead (flip `CI_PR_AFFECTED`, admin-side control decision, narrow-bypass-actors vs detective probe) | operator (irreversible/production-mutating authorization) | pending — NOT requested in this PR by design; the issue's entry gate 2 and the budget owner's named-command go-ahead are the operator's |
| Retire-vs-schedule S4 if the re-ruling computes NO-GO again | operator (scope/priority) | pending — surfaced on #9729 with the verdict; #10448's mandate ("complete the index or retire the stage") makes this the operator's call, never a silent close |
