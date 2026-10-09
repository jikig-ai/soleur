# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-10-09-chore-grep-q-wave-b-s4-tests-dir-plan.md
- Status: plan written, measured on rehearsal clones, reviewed (3 seats) and deepened (gates 4.5 to 4.12 plus a test-design review); ready for work

### Errors

None.

### Decisions

- S4 owns one guard row (`tests/*`, 181 lines in 23 files: `tests/scripts/` 20 files / 171 lines, `tests/commands/` 3 files / 10 lines) and takes it to zero: the row is deleted, no counted pin remains.
- 155 lines by the codemod (76 default + 79 with `--reviewed-suspect` for six `tests/scripts` files whose comments only name SIGPIPE), 19 stub-heredoc lines by a throwaway regexp, 3 hand edits that change the shape (a `-m` here-string, a `-qc` cluster, a sed expression coupled to a converted line), 4 detector-fixture lines kept and marked `# sigpipe-demo: intentional`. `verify`: 174 verified, 7 hand-edited, 0 unexplained.
- The guard diff is the row deletion plus seven canary paths in the real-table probe (15 planted paths, literal 8 to 15); `SWEEP_PROBE_CHECKS` unchanged. Mutation-proved both ways: any excluded tests/ subtree and a resurrected row plus a covering hit are RED (both GREEN on the S3-form guard).
- Merge fires no path-filtered workflow (0 of 24 for 18 filtered push workflows); the runner and the affected index are not edited (no runner-parity check, no `AFFECTED_FALLBACK`); open PRs touch the edited files only via #9784 at distant hunks, which also adds three new early-exit pipes under `tests/`.
- All 23 owning suites and 5 adjacent ones read the same rc and final line on a real detached base clone and on the rehearsal.

### Components Invoked

soleur:plan, learnings-researcher, plan review (simplicity, correctness, overengineering), deepen-plan gates, test-design review of the guard matrix, rehearsal and mutation clones, codemod dry run and write, pair run of 28 suites, guard mutation battery, per-site observer mutants

### Plan file (deepened)

knowledge-base/project/plans/2026-10-09-chore-grep-q-wave-b-s4-tests-dir-plan.md
