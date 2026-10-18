# Tasks: grep -q series Item G (`--ratchets` selector), recorded as not fixed

Plan: `knowledge-base/project/plans/2026-10-16-fix-grep-q-series-item-g-ratchets-selector-plan.md`
Ruling: Ruled by CTO agent, 2026-10-16: record as not fixed; no edit to `scripts/test-all.sh`. The pipe-guard gap is real (a first, invalid measurement said zero): follow-up #10447, and the false parts of the header are corrected here.

## Phase 1: Refresh the evidence (read-only)

- [x] 1.1 `git fetch origin main`; no `--ratchets` flag in `scripts/test-all.sh` on `origin/main`, no newer Item G comment on #9217.
- [x] 1.2 Measured the guard's whole population (98 producers, 97 owner suites), reading the selected bit with controls: 51 producers and 33 owner suites NOT selected (`selection-measurement.md`).
- [x] 1.3 CTO re-ruling after the corrected measurement: option C restored, header corrected inline; rows in `decision-challenges.md`.

## Phase 2: Follow-up issue

- [x] 2.1 Filed #10447 (`meta/machinery`, `type/chore`, `domain/engineering`, `priority/p3-low`, milestone `Post-MVP / Later`).

## Phase 3: Comment on #9217

- [x] 3.1 Comment body written with no unfilled slots.
- [x] 3.2 Posted on #9217; the issue stays open. Corrected after review: the first version said the gap measured zero; the comment now carries a dated correction and the corrected figures.

## Phase 4: Amend the guard header

- [x] 4.1 Edit the `STILL OPEN` and `THE PRE-PUSH AFFECTED GATE DOES NOT SELECT THIS GUARD` sentences in `.claude/hooks/grep-q-pipe-guard.test.sh` (comment lines only).
- [x] 4.2 `bash .claude/hooks/grep-q-pipe-guard.test.sh` exits 0 and `bash scripts/test-all.sh --print-selection` prints no `AFFECTED_FALLBACK`.
- [x] 4.3 Comment-only diff check from the plan's Acceptance Criteria.

## Phase 5: Ship and postmerge

- [ ] 5.1 Plan-defined gates: `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` and `npx markdownlint-cli2` over the plan, this file, `decision-challenges.md` and `selection-measurement.md`.
- [ ] 5.2 Ship: archive the knowledge-base artifacts, push, PR body with `Ref #9217` and the ruling line, merge.
- [ ] 5.3 After merge run `soleur:postmerge` for the PR. Do not emit the series DONE promise.
