# Decision challenges (persisted, not decided) — #9776

Pipeline mode: the plan's `## Decisions held for the operator` items are not mid-pipeline pauses. The plan default is kept for each and
persisted here so `ship` Phase 6 renders them into the PR body. A security or feasibility regression would halt before merge instead.

| # | Held decision | Default kept in this PR | Who can change it |
|---|---|---|---|
| 1 | Cut or keep the Phase 6 follow-through probe | Keep (two windows, call-count floor) | Operator |
| 2 | GraphQL equivalents of the `gh` family (`deleteRef`, `deleteRepository`, `updateRef`) join the classifier | No: near-miss telemetry plus a named ADR-284 residual (CPO4-R1 sends widening back to the CPO) | CPO |
| 3 | Down-scope the hosted installation token (drop `administration: write`) | Not in this PR; ADR-284 alternative worth measuring | CTO / operator |
| 4 | Per-turn auto-deny after a Reject | Not built; deny text says not to retry (CPO4-R2) | Operator, after telemetry |
| 5 | Card sentence "this is not the autonomous-mode acknowledgement" | Not added (card wording beyond CLO C4 is the CLO's); AC-21 pins the behaviour | CLO |
| 6 | Pre-authorised revert if the post-deploy dev probe (CLO C9) fails | A failed probe means an immediate revert PR, decided by the operator then | Operator |
| 7 | Trim the mutation matrix | Keep as ruled (cost bound only) | CTO |
| 8 | Drop the 30 s negative resolver cache | Keep (in the CTO ruling) | CTO |
| 9 | CPO4-R5 words the storm rule as a share of one workspace's hosted Bash CALLS; that denominator is pino INFO and is not shipped to Better Stack | The soak probe measures a stand-in (share of one repo's asks that one rule accounts for, behind a 20-ask floor) and says so; ADR-284 records it | CPO |
| 10 | A force push with no named destination (`git push -f`, `git push --force-with-lease origin`) always asks, which over-asks on rebase-and-force-push workflows | Keep the CTO ruling (it may overwrite the default branch); the probe reports the `git-force-implicit` share so the cost is measured | CTO / CPO, after the soak numbers |
| 11 | A non-owner workspace member can approve a card (the same as every other gate); the outcome line carries `approverRole` | Keep; the probe reports member approvals; revisit when a workspace with more than one active member uses autonomous mode | CPO |
| 12 | A revert inside the soak window leaves acknowledgements written while the copy was live | The revert runbook supersedes (never edits) any acknowledgement row written during the window, as the PR #9792 C2 step does, before the copy is restored | CLO / operator |
