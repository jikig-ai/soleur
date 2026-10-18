# Tasks: record the second wipe_check in the LUKS cutover runbook

Plan: knowledge-base/project/plans/2026-10-18-docs-record-second-wipe-check-in-luks-cutover-runbook-plan.md
Runbook: knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md

## Phase 1: Setup

- 1.1 Re-read run 39136900735 (conclusion failure, step Host-side wipe assertion (W7)) and copy the wipe-assert line byte for byte from `gh run view 39136900735 --log`.
- 1.2 Re-read `gh run list --workflow git-data-cutover.yml`: no wipe, wipe_finish or snapshot_clear dispatch; the read date goes into the Status sentence (mandatory).

## Phase 2: Core Implementation (one file, Edit tool, anchors quoted from the live file)

- 2.1 E1: rewrite only the `Update (2026-10-18, measured):` sentence in the Status paragraph (two runs, both refused; no wipe, wipe_finish or snapshot_clear; addendum 2 spent; fields not reached; list unchanged).
- 2.2 E2: add the indented `Superseded 2026-10-18, as to run 39136900735 only` blockquote beneath the wipe_check bullet (blank line before it); do not edit the bullet.
- 2.3 E3: replace the `Not proven: that hooks is the off-list entry` bullet with the measured finding (line, run URL, table reading, not an emptiness reading, allowlist unchanged, refusal stands; what hooks holds stays not proven).
- 2.4 E4: add the indented `Superseded 2026-10-18 (run 39136900735)` blockquote beneath the `Nothing here dispatches a run` bullet (no blank line before it); cite addendum 2 item 1, not an owner-named attribution.

## Phase 3: Testing

- 3.1 `node_modules/.bin/markdownlint` on the runbook: 0 errors.
- 3.2 `python3 scripts/lint-infra-no-human-steps.py` on the runbook: rc 0.
- 3.3 Run git-data-wipe-access.test.sh and git-data-cutover-access.test.sh; confirm unchanged.
- 3.4 Diff checks: only the two listed lines deleted; posted line byte-identical; widened word grep (plan AC 5) over all added files, PR body and commit messages, with a negative control; no listing name besides hooks; no `lock_residue=`/`store_root_repos=` value anywhere; no `Verdict map` hunk.
- 3.5 Write the one learning file; PR description maps each new claim to its measurement, uses `Ref #10138` and `Ref #6897`, flags owner-posting status, and states the CTO/CLO rulings in flight are not recorded.
- 3.6 PR #10506: the owner's approval for the runbook to carry the posted line is inferred from the owner's request to take the open steps (plan AC 8); flagged in the PR body for confirmation.
