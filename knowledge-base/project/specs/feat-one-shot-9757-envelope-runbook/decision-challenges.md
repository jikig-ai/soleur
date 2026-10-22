# Decision challenges (plan phase, 2026-10-22)

Headless plan run. No operator-direction challenge arose: the brief is fully specified and no reviewer finding argues for a different scope. Technical choices were resolved without an operator question.

| Item | Class | Ruling |
|------|-------|--------|
| Bring the runbook in by cherry-pick of `f0fe42d2b9` versus copy of the `/var/tmp` backup | mechanical | Both give identical bytes and the PR is squash-merged, so the outcome is the same. Plan prescribes copy-from-backup as primary (no dependency on the branch that Phase 4 deletes) with cherry-pick as fallback; the sha256 `1076fca7...4504` is the arbiter. Decided by planner, 2026-10-22: no CTO spawn, no fork in outcome. |
| `git branch -D` (force) for the scratch branch | mechanical | Required because the branch is unmerged by design; guarded by the clean-status check and the sha256-verified copy on this branch. Planner, 2026-10-22. |
| Skip the plan-review panel and external research | mechanical | Two-file docs change with a byte-pinned artifact; the premise validation above is the only research that carries information. Planner, 2026-10-22. |
