# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-30-ci-path-gate-self-test-mutation-batteries-on-prs-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None. Deferral issues could not be written by the plan subagent; they are task 5.3 in tasks.md.

### Decisions
- Gate via `_diff_touches --pr-gated` call-site opt-in, active only when CI set and GITHUB_EVENT_NAME == pull_request; push/merge_group/dispatch/monitor stay full.
- Five batteries gated; orphan-process-reaper-mutations deferred (already has an edge array).
- ADR-262 (provisional number) amends ADR-181 and ADR-242; names four residuals.
- Guard 2 (subject-set closure lint) and ci-battery-gate-replay.sh kept against reviewer advice; recorded in decision-challenges.md.
- Post-planning re-probe (linked, body-open, anchor over planned files): no collisions; two stale 2026-09-21 drafts touch shared files but differ in scope.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan and their research/review agents.

## Work Phase
- Status: complete (committed and pushed; PR #9324)
- Guard suite `scripts/test-all-pr-battery-gate.test.sh`: 75 assertions, 26 mutants caught, RED against main's runner (Phase 1.2 evidence).
- Verification: a first `--full` run was killed at ~80% after surfacing four real defects of this branch (probe xtrace guard, floor counter shape, a tag-array path the lint sandbox does not materialise, two shard-totality mutation anchors) plus a local-only missing PyYAML. A second `--full` was refused rc=4 (four sibling full-gate runs from another session), so the fixed tree was verified with the consumer suites: orphan linter, shard-totality (+mutations), runtime-coverage, fanout-suite-scope, guard-vacuity-floor, battery-tag-authorship, test-all-group-affected, test-all-affected, both lint-orphan battery halves, c4-count-parity, coverage-notice harness. CI's required `test` runs the full battery on this PR (it edits the runner, so every battery runs).
- Deferral tracker: #9340 (one consolidated issue, meta/machinery).
- Post-merge: annotate #9323 with the followthrough directive (`earliest` = merge + 7 d, `secrets=GH_TOKEN`) once the probe exists on main.
