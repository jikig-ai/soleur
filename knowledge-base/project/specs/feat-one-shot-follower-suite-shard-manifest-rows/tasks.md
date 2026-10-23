# Tasks: shard/duration manifest rows for the apply-delivery-gap follower suite

Plan: `knowledge-base/project/plans/2026-10-23-chore-apply-delivery-gap-follower-shard-manifest-rows-plan.md`
Ref #9454 only (no closing keyword). Do not touch `scripts/lib/test-affected-paths.sh`, the `*.tsv.n` files, the heavy tables,
#9482, #10245, #5840; do not close #9454.

## Phase 1: Evidence snapshot and tracking issue

- [ ] 1.1 `git fetch origin main`, then merge-main via `plugins/soleur/scripts/lib/session-state.sh with_lock <name> <timeout_s> -- <command>`
- [ ] 1.2 Record, with a UTC timestamp: `gh pr view 10891 --json state,mergeStateStatus --jq '"\(.state) \(.mergeStateStatus)"'`
- [ ] 1.3 Record, with a UTC timestamp: `python3 scripts/regenerate-shard-manifest.py --incremental | grep '^vs incumbent:'` (dry run, NO `--write`)
- [ ] 1.4 Unless #10891 already merged and 1.3 prints `0 new`: create the minimal tracking issue
  `chore(ci): verify apply-delivery-gap follower shard rows landed via #10891` (evidence, flip note, `Ref #9454`, milestone
  `Post-MVP / Later`)

## Phase 2: PR (plan-only)

- [ ] 2.1 Confirm `git diff --name-only origin/main...HEAD` is limited to planning artifacts, `session-state.md`, and the
  generated `knowledge-base/INDEX.md`
- [ ] 2.2 PR body: "no manifest rows added; carried by #10891", contains `Ref #9454`, no closing keyword, no SSH mention
- [ ] 2.3 Merge via the queue after `with_lock` merge-main; do not touch #9454, #9482, #10245, #5840

## Phase 3: Verification

- [ ] 3.1 `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch`
- [ ] 3.2 `git diff --quiet "$(git merge-base origin/main HEAD)" HEAD -- scripts/lib/test-affected-paths.sh scripts/suite-shard-legs.tsv.n scripts/suite-durations.tsv.n scripts/suite-shard-legs-heavy.tsv scripts/suite-durations-heavy.tsv` exits 0
- [ ] 3.3 `git status --short scripts/` prints nothing

## Contingency (flip note; not scheduled)

If #10891 is closed unmerged, or merged without the rows (the dry run still prints new labels): on a fresh merge-main run
`python3 scripts/regenerate-shard-manifest.py --incremental --write` (never by hand; takes all registered-untabled labels),
re-run the dry run and require `0 new`, then run `plugins/soleur/test/scripts-shard-manifest.test.sh`,
`scripts-shard-runtime-coverage.test.sh`, `scripts-shard-totality.test.sh`, `regenerate-shard-manifest.test.sh` and
`bash scripts/lint-orphan-test-suites.sh`. Regenerate, never hand-merge, on a TSV conflict.
