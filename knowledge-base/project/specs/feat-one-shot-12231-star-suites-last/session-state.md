# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-06-perf-affected-gate-star-suites-last-and-replay-rebalance-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking. Foreign test-all.sh runs in sibling worktrees are a contention risk for cold readings; measure.sh aborts a reading started beside them.

### Decisions
- `*`-last via park-in-`_pj_fill`, release at drain; `SOLEUR_PJ_FIFO=1` stays strict FIFO.
- No order dependence among the six declared `*` suites.
- Replay rebalance gated by a paper check (predicted gain >= 30 s), else dropped as not landed.
- `Closes #12231` only if T1 is >= 100 s below the faster control; `Ref #12013` always. `budget_seconds` untouched.
- Follow-up filed: #12263.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; cto, dhh/kieran/simplicity/architecture/test-design reviewers, learnings-researcher.

cto_spawns=4
