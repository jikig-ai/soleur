# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-25-fix-zot-pull-mutation-harness-row-misroute-plan.md
- Status: complete

### Errors
None

### Decisions
- The root cause is SIGPIPE (rc 141) under `pipefail` in two early-exit pipelines, not shared TMPDIR, fixed paths or row order. Site A is the battery row scorer; site B is the Guard 1b `sed | awk exit` arm splitter in cloud-init-inngest-bootstrap.test.sh.
- The fix stays out of run-registered-suites.sh, so it has no file overlap with sibling draft #8763.
- Both pipes are removed, not retried: the `failed_on` capture-then-match scorer, awk reading the file directly, and herestring `wf_block` checks.
- Deterministic RED: a self-test with a ~1.26 MB log, plus a must-PASS padded row. BATTERY_MIN_ROWS goes 60 to 61. Both files are added to the grep-q-pipe-guard zero-drift list.
- Sibling batteries with the same scorer bug are deferred to a tracking issue; decision-challenges.md records it.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; learnings-researcher, repo-research-analyst, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, cto, test-design-reviewer
