# Tasks: grep -q series Item G (`--ratchets` selector), recorded as not fixed

Plan: `knowledge-base/project/plans/2026-10-16-fix-grep-q-series-item-g-ratchets-selector-plan.md`
Ruling: Ruled by CTO agent, 2026-10-16: record as not fixed; split the pipe-guard lane gap into a follow-up. No edit to `scripts/test-all.sh`.

## Phase 1: Refresh the evidence (read-only)

- 1.1 `git fetch origin main`; confirm no `--ratchets` flag in `scripts/test-all.sh` on `origin/main` and no newer Item G comment on #9217.
- 1.2 Sample `bash scripts/test-all.sh --print-selection --paths=<path>` for at least six producer paths drawn from the guard's own derived pairs; record selected and not-selected counts, keeping only confirmed numbers.
- 1.3 Re-read `decision-challenges.md`; it already holds the three CTO rows and the plan-review taste items.

## Phase 2: File the follow-up issue

- 2.1 Confirm labels `meta/machinery`, `type/chore`, `domain/engineering`, `priority/p3-low` and milestone `Post-MVP / Later` exist.
- 2.2 `gh issue create` titled `grep -q pipe guard not selected by the pre-push lane for producer or owner-suite edits` with the Phase 1 sample, the 18 s runtime, the conditional lane-member proposal, the rejected edge-widening alternative, and `Ref #9217`.

## Phase 3: Comment on #9217

- 3.1 Write the comment body (ruling line `Ruled by CTO agent, 2026-10-16:`, reason, follow-up number, remaining items) to a file with no unfilled slots.
- 3.2 `gh issue comment 9217 --body-file <file>`; leave #9217 open.

## Phase 4: Amend the guard header

- 4.1 Edit only the `# STILL OPEN (listed, not planned here)` sentence in `.claude/hooks/grep-q-pipe-guard.test.sh`.
- 4.2 Run `bash .claude/hooks/grep-q-pipe-guard.test.sh` (rc 0) and `bash scripts/test-all.sh --print-selection` (no `AFFECTED_FALLBACK`).
- 4.3 Run the comment-only diff check from the plan's Acceptance Criteria.

## Phase 5: Ship and postmerge

- 5.1 Run the plan's own-invocation gates: `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` and `npx markdownlint-cli2` over the plan, this file and `decision-challenges.md`.
- 5.2 Commit and push; PR body uses `Ref #9217` and quotes the ruling line; mark ready and merge via the ship flow.
- 5.3 After merge run `soleur:postmerge` for the PR. Do not emit the series DONE promise.
