# Decision Challenges — feat-one-shot-ci-lever-residuals

Plan: `knowledge-base/project/plans/2026-11-07-chore-ci-lever-residuals-plan.md`

Technical rows below were ruled by `soleur:engineering:cto` in one batched spawn
from the pipeline parent on 2026-11-07 (the plan subagent, which cannot nest
spawns, had recorded them `pending - assumed`; the parent's ruling gate
discharged all six). Operator rows stand as recorded.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Drift-arm flag bound: `timed>=3`, ratio >=4x or <=0.25x in either direction, \|delta\| >= 120000 ms | technical | Ruled by CTO agent, 2026-11-07: confirm the bound (timed>=3, ratio >=4x/<=0.25x, \|delta\| >=120000ms) - flags both known-stale rows (43x/109x) while the audited ordinary band (+12%..+190%, max 2.9x) stays silent; floor rows alerted on ratio noise alone without the absolute floor; dissent recorded: heuristic, a 3.5x measured drift stays silent, symmetric with the floor arm's own coarse bound |
| #9323 convergence path: `PBG_UNBOUNDED=1` operator seam lifting the wall deadline for a local verdict run (vs marker-comment bypass vs download parallelization vs uncommitted one-off) | technical | Ruled by CTO agent, 2026-11-07: confirm `PBG_UNBOUNDED=1` far-future END bound - preserves `PBG_BUDGET_S<=300` byte-for-byte, unreachable in the sweeper env, keeps per-call 60s caps; starvation is structural (~20 runs x ~13 artifact reads cannot fit 270s); parallelization stays the contingency; dissent: none |
| #9323 close-on-PASS + probe retirement in this PR | technical | Ruled by CTO agent, 2026-11-07: confirm close + retire on PASS in this PR - all six retirement artifacts verified at cited locations; sweeper lists open trackers only so closing stops the NOT YET noise; dissent recorded: the retire arm must land in the same commit as the issue close (a probe deleted while the issue stays open is un-measurable) |
| Manifest regen (`suite-shard-legs.tsv` rebalance) deferred out of this PR | technical | Ruled by CTO agent, 2026-11-07: defer - post-refresh predicted max/mean = 1.264 < 1.30 flag bound (verified live: leg4 26.4min, leg6 29.9min); a regen re-seats unrelated drifted rows wholesale into a noisy generated diff; dissent recorded: leg6 runs 26% over mean, real but below the system's own bound |
| #9729 scope in this PR: evidence + re-ruling only, no activation machinery (no `[full]` marker, no admin-merge-ready read, no lock removal) | technical | Ruled by CTO agent, 2026-11-07: confirm evidence + re-ruling + ADR-276 amendment only - `[full]` is activation machinery bound to entry gate 1; a marker with no reader is half-activation; ADR-276 2026-10-16 item 5 sequences replay + re-ruling before any stage-2 build; dissent: none |
| S4 go/no-go re-ruling itself (confirm the computed verdict, incl. criterion-(c) grading in billed job-min per pull_request run and whether the advisory-ratchet ~3.4 billed min/run counts against it) | technical | Ruled by CTO agent, 2026-11-07: confirm - re-ruling owed and properly timed (strict zero 2026-11-05 met the 2026-10-16 entry condition); criterion (c) graded in billed job-min per pull_request run, advisory-ratchet ~3.4 billed min/run counts against it per the 2026-10-22 amendment; dissent recorded: the ratchet-required entry clause is satisfied-in-substance not literally (job advisory until PR3b) - a computed GO must restate PR3b's required-context flip as an unmet activation prerequisite; a computed NO-GO is a valid deliverable |
| S4 activation go-ahead (flip `CI_PR_AFFECTED`, admin-side control decision, narrow-bypass-actors vs detective probe) | operator (production-mutating) | pending — NOT requested in this PR by design; the issue's entry gate 2 and the budget owner's named-command go-ahead are the operator's |
| Retire-vs-schedule S4 if the re-ruling computes NO-GO again | operator (scope) | pending — surfaced on #9729 with the verdict; #10448's mandate ("complete the index or retire the stage") makes this the operator's call, never a silent close |
