# Merge queue canary log

Evidence for ADR-270 (merge queue with advisory CodeQL), tracked on #9454. One entry per canary; each canary PR is
docs-only and exists to exercise the queue or its admin bypass on `main`. Rows 4, 9 and 10 are measurements, not canary
PRs; their numbers live on #9482.

| Canary | Path | Recorded |
|---|---|---|
| 1 | Admin bypass: this file's PR merged with `gh pr merge --admin` past the queue rule | result on #9454 after the merge |
| 4 | Bot PR: the next `weakness-miner.yml` PR through the queue | pending, next fire 2026-10-11T06:00Z; result on [#9482](https://github.com/jikig-ai/soleur/issues/9482#issuecomment-5992118670) |
| 9 | Sync merges per merged human PR, before and after the queue (proxy for hook and fence sync pushes) | 2.50 before (n=40), 0.83 after (n=12); [#9482](https://github.com/jikig-ai/soleur/issues/9482#issuecomment-5992118670) |
| 10 | Stall-check dispatch spacing and runner-start latency | 10.0 min spacing (within 10 s), 4 to 5 s start (n=5); [#9482](https://github.com/jikig-ai/soleur/issues/9482#issuecomment-5992118670) |
