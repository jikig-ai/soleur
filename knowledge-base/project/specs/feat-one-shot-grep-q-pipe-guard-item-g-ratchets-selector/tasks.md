# Tasks: grep -q series Item G (`--ratchets` selector), recorded as not fixed

Plan: `knowledge-base/project/plans/2026-10-16-fix-grep-q-series-item-g-ratchets-selector-plan.md`
Ruling: Ruled by CTO agent, 2026-10-16: record as not fixed; no edit to `scripts/test-all.sh`. Second ruling the same day: the pipe-guard gap measured zero, so no follow-up issue and the stale header sentence is corrected here.

## Phase 1: Refresh the evidence (read-only) — done

- [x] 1.1 `git fetch origin main`; no `--ratchets` flag in `scripts/test-all.sh` on `origin/main`, no newer Item G comment on #9217.
- [x] 1.2 Measured the guard's whole population (98 producers, 97 owner suites) with `--print-selection --paths=<path>`: all selected, 0 fallbacks (`selection-measurement.md`).
- [x] 1.3 Second CTO ruling: option C withdrawn, header sentence corrected inline; rows added to `decision-challenges.md`.

## Phase 2: (withdrawn) follow-up issue

- No issue is filed: the measured gap is zero.

## Phase 3: Comment on #9217

- [ ] 3.1 Write the comment body (ruling line `Ruled by CTO agent, 2026-10-16:`, reason, measured selection, remaining items) to a file with no unfilled slots.
- [ ] 3.2 `gh issue comment 9217 --body-file <file>`; leave #9217 open.

## Phase 4: Amend the guard header

- [x] 4.1 Edit the `# STILL OPEN (listed, not planned here)` and `# THE PRE-PUSH AFFECTED LANE DOES NOT SELECT THIS GUARD` sentences in `.claude/hooks/grep-q-pipe-guard.test.sh`.
- 4.2 Run `bash .claude/hooks/grep-q-pipe-guard.test.sh` (rc 0) and `bash scripts/test-all.sh --print-selection` (no `AFFECTED_FALLBACK`).
- 4.3 Run the comment-only diff check from the plan's Acceptance Criteria.

## Phase 5: Ship and postmerge

- 5.1 Run the plan's own-invocation gates: `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` and `npx markdownlint-cli2` over the plan, this file and `decision-challenges.md`.
- 5.2 Commit and push; PR body uses `Ref #9217` and quotes the ruling line; mark ready and merge via the ship flow.
- 5.3 After merge run `soleur:postmerge` for the PR. Do not emit the series DONE promise.
