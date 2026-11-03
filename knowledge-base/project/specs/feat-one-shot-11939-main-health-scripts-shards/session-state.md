# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-03-fix-main-health-monitor-test-group-env-leak-plan.md
- Status: complete
- cto_spawns=1 (this session, test placement; the planning subagent ran its own CTO rulings, recorded in decision-challenges.md)

### Errors
None blocking. Planning subagent: a backgrounded test run lost its output-dir variable (re-run); `gh issue create` refused twice by a filing hook until `meta/machinery` was added and the body file written in a separate call; a `pkill -f` was blocked and replaced with `ps`. Parent: decision-challenges.md failed the ruling gate twice (a "Ruled by planner" row and an invalid category `priority/schedule`); fixed by a CTO ruling and `operator (priority)`.

### Decisions
- Root cause: the monitor sets `TEST_GROUP` as step env, ci.yml passes the group positionally; `scripts/test-all.sh` never un-exports it, so suite children inherit `TEST_GROUP=scripts`. Reproduced locally (28/0 unset, 23/5 set).
- Fix: runner-side `export -n TEST_GROUP` after group resolution; `main-health-monitor.yml` and its S2b pin untouched (a consumer reads the step-env echo).
- Regression rows go in `scripts/test-all-group-affected.test.sh` (CTO), row 1 plus must-PASS rows committed; other mutation rows driven by hand and recorded in the PR body.
- PR keyword: `Closes #11939` only if a branch dry run of the monitor is fully green, else `Ref #11939`. 0/50 blind spot tracked as #11953.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; agents: cto, learnings-researcher, repo-research-analyst, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer.
## Review ledger (panel 3dd091d255, fix 7a8aff49f3)
dedup: ~45 raw -> 12 unique. structural-cause roll-up: the guard (Part C) proved one sandbox path while the property spans the registration region, tee path, parallel launcher, other groups, CI=true and shards; plus stale prose saying the runner exports TEST_GROUP.
| defect key | seats | fix |
|---|---|---|
| stale 'runner exports TEST_GROUP' prose | arch, history, code-quality | comments reworded (7a8aff49f3) |
| suite header/banner omit Part C | pattern, code-quality, test-design | header+banner updated |
| Part C reach (groups, CI, shard, region/tee/parallel, floor, failure kind) | test-design, structural | C1b, C1b-ctl, C6-C8, floor, messages |
| P3 hardening (python -I, PROBE_DIR guard, B3 backticks, lib reuse) | security, pattern, code-quality | taken |
| plan citation/wording | history, code-quality | corrected |
