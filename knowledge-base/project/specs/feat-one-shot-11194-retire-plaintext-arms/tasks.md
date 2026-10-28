# Tasks: retire the plaintext arms from the git-data host gates (#11194)

Plan: `knowledge-base/project/plans/2026-10-28-chore-retire-plaintext-arms-git-data-host-gates-plan.md`

PR-1 is this branch. PR-2 is a separate branch off `main`. Neither PR merges, dispatches, arms auto-merge or writes to Doppler.

## Phase 1: Fixtures and parity pins (RED first)

- [ ] 1.1 `tests/scripts/test-git-data-host-replace-gate.sh`: drop the retired attachment from `PASS_SET`/`ROT_PASS_SET`; delete T11, T2/T16, R5, PA3/PA3b/PA3c/PA4b plaintext rows and PM1; re-aim PM2/PM5 and the PA8/PM4 rows at the LUKS volume and attachment; keep every LUKS row
- [ ] 1.2 Generate retired-address rows from one array (create and delete, replace/rotate/birth), each pinned to its arm text, each with a `no-op` control that PASSes
- [ ] 1.3 `tests/scripts/test-git-data-host-birth-gate.sh`: remove the two addresses from the fixture builders, drop number words from titles, narrow volume checks to the LUKS volume, anchor the LUKS destroy row on "DATA VOLUME"
- [ ] 1.4 `tests/scripts/test-git-data-wipe-wedge.sh`: drop the retired attachment from `PASS_SET`, keep H2/SANCTIONED passing, fix comment, recount floor
- [ ] 1.5 `plugins/soleur/test/terraform-target-parity.test.ts`: remove the retired addresses from the replace and birth constants, replace `GIT_DATA_PRESERVED_VOLUMES` with a retired-absent assertion over both jobs' `-target`/`-replace` lines, drop the two `OPERATOR_APPLIED_EXCLUSIONS` entries, add the interlock wire pin for both jobs, derive counts from lists
- [ ] 1.6 `tests/scripts/test-git-data-birth-readiness-gate.sh`: interlock fixtures (non-empty literal, missing block, commented empty above non-empty, duplicate assignment, must-PASS cases)
- [ ] 1.7 Run the suites and confirm they are RED for the right reason

## Phase 2: Replace gate and post-apply assert

- [ ] 2.1 `git-data-host-replace-gate.sh`: remove the attachment from `def allow:`, delete `git_data_volume_destroyed` and `plaintext_attachment_recreated` (counter, extraction, numeric-assert args, echo, PASS terms), rewrite PASS/ABORT strings and header comments without number words
- [ ] 2.2 `git_data_host_post_apply_assert`: replace-only LUKS volume check via a plain `if`, rotate asserts no volume, drop the plaintext attachment from the loop, update echoes

## Phase 3: Birth gate, workflow, interlock

- [ ] 3.1 `git-data-host-birth-gate.sh`: remove both addresses from the allow-set, entailed loop and presence loop; narrow selectors/offender jq/ABORT text to the LUKS volume; delete number words
- [ ] 3.2 `apply-web-platform-infra.yml`: delete the three `-target` lines; fix operator-facing text in the replace job (rotate-abort error, post-apply comments, apply-failure annotations, header target list) and the create job prose; fix the `scripts/test-all.sh` run_suite comment
- [ ] 3.3 Add `git_data_plaintext_id_interlock` to `tests/scripts/lib/git-data-birth-readiness-gate.sh` and wire a step before the plan step in `git_data_host_replace` (skipped under `plan_only`) and `git_data_host_create`

## Phase 4: Floors and counters

- [ ] 4.1 Recount each floor with the Phase 4.1 arithmetic (runtime counts for the shell suites, `test(` declarations for `TEST_FLOOR`), keep the old slack, show before/after in the PR body
- [ ] 4.2 `grep -n "git-data-host-\|git-data-wipe-wedge" scripts/*.tsv tests/scripts/test-infra-privileged-tier-census.sh`; adjust only what moved
- [ ] 4.3 Make sure every surviving arm and the interlock has a mutation row whose `sed` changes the copy

## Phase 5: Docs, ADR, C4, ledger

- [ ] 5.1 Runbooks (`git-data-birth.md`, `apply-web-platform-infra-job-rationale.md`, `git-data-luks-cutover-5274.md`): final-state wording, interlock condition, dispatch sequence, `plan_only` verification, unrehearsed empty-id boot and #10296; anchored edits, heading list compared before/after
- [ ] 5.2 ADR-239 Amendment 2026-10-28 via `soleur:architecture`; `git-data.tf` header comment and marker trigger text (comment-only); `test-git-data-wipe-wedge.sh` comment
- [ ] 5.3 Ledger row `hcloud_volume.rehearsal`: retarget `reevaluate_when` to #11433, keep `expires_on`; run `python3 scripts/lint-encryption-posture.py`
- [ ] 5.4 `model.c4` description reworded to point at ADR-239; `bash scripts/regenerate-c4-model.sh`; run the c4 freshness and count-parity suites

## Phase 6: PR-2 (separate worktree/branch off main)

- [ ] 6.1 `git-data.tf`: `git_data_volume_id = ""`, delete the `SOLEUR-DEBT` marker and the literal comment
- [ ] 6.2 Run the infra suites that read the module call; fix only what is red
- [ ] 6.3 PR-2 body per plan Phase 6.3 (`Ref #11194`, first line "merging this PR alone changes no production resource", plan_only first, no end-to-end claim)

## Phase 7: Verify, review, hand off

- [ ] 7.1 Local suites and lints green; push; CI green on both PRs
- [ ] 7.2 `soleur:review` with `user-impact-reviewer`; fix findings in-branch
- [ ] 7.3 Mark both PRs ready; do not merge or dispatch; report both URLs
