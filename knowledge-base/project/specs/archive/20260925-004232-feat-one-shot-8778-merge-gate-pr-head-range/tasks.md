# Tasks — #8778 pre-merge review-evidence gate reads the PR head

Plan: `knowledge-base/project/plans/2026-09-24-fix-pre-merge-review-gate-pr-head-range-plan.md`

## Phase 0 — Tests first (RED)

- [x] 0.1 `unset GH_REPO GH_HOST` in the `pre-merge-rebase.test.sh` preamble
- [x] 0.2 `install_gh_stub <dir> [mode]` heredoc stub (dispatch on `"$@"`, `gh.log`, real-`gh` contract, `STUB-MISS` rc 64)
- [x] 0.3 Fixture helper: bare origin + detached-HEAD root + `git worktree add` worktrees
- [x] 0.4 Cases T-PR1/1b/1c, T-PR-C, T-PR2, T-PR3, T-PR4, T-PR5, T-PR5b, T-PR6, T-PR7, T-PR8, T-PR9, T-PR10, T-PR11, T-PR12
- [x] 0.5 Run on the unmodified hook; record the expected RED set

## Phase 1 — Resolver and range (Guard 1)

- [x] 1.1 Resolver block (states L/O/P/N) after the `FETCH_OK` fetch
- [x] 1.2 Four evidence reads on `EVIDENCE_TIP` under one non-empty guard
- [x] 1.3 Single `$SCAN` PR-number extraction feeds Signal 3; remove the `$CMD` `head -1` path
- [x] 1.4 Deny reason names `RANGE_LABEL` + `RANGE_SOURCE`, adds the hollow-issue sentence

## Phase 2 — Sync targeting (Guard 2)

- [x] 2.1 P4 skip after the detached-HEAD exit, reported via `additionalContext`
- [x] 2.2 Header / `Determine working directory` comments

## Phase 3 — Meta-guards and suites

- [x] 3.1 `stub-argv-fidelity.test.sh` `EXPECTED_STUBS` 5 → 6
- [x] 3.2 `fixture-relative-assert.test.sh` (regenerate baseline only if red)
- [x] 3.3 AC10 command list green, `shellcheck` clean

## Phase 4 — Mutation spot-check

- [x] 4.1 Apply each Guard 1 / Guard 2 mutation-matrix row, confirm RED, restore; record in PR body

## Ship

- [x] 5.1 File the follow-up issues (#8790, #8791)
- [ ] 5.2 PR body: `Closes #8778`, follow-up links, mutation results
