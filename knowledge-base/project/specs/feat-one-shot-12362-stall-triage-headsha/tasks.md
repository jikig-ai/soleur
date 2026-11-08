# Tasks - feat-one-shot-12362-stall-triage-headsha

Plan: `knowledge-base/project/plans/2026-11-08-fix-merge-queue-stall-triage-headsha-plan.md`
Issue: #12362 (closes) · epic: #9927 (Ref only, stays open) · PR: #12378

## 1. Test first (RED)

- [x] 1.1 Add a new arm at the END of `structural_check` in `plugins/soleur/test/merge-queue-stall-check.test.sh`
  (reuse parsed `$f`): `jq -e` count of lines containing `gh run list ` and `--event merge_group` equals 1, then
  `capture("--json (?<f>[^ ]+)")` split on `,` with `any(.[]; . == "headSha")`; distinct REASON for count != 1,
  missing `--json`, and missing `headSha`; no `| grep -q`.
- [x] 1.2 No new S-row: `S0` runs the arm. Do not bump `EXPECTED_PASSES` yet.
- [x] 1.3 Run the suite (long timeout / Monitor, never sleep) on the UNMODIFIED workflow; capture output; confirm `S0`
  FAIL names `headSha`. Run the old probe `scripts/followthroughs/stall-triage-headsha-12350.sh`; expect exit 5.
- [x] 1.4 Add mutation rows MT1 (drop headSha, prose kept), MT2 (`headShaX`), MT3 (selector no longer matches),
  MT4 (second indented `gh run list ... --event merge_group` line inside the heredoc), MT5 (selector matches, no
  `--json` list) and must-pass row PT1 (headSha last). Labels are fresh; `M15` is taken.

## 2. The one-token fix (GREEN)

- [x] 2.1 `Edit` the Triage step 2 line in `.github/workflows/merge-queue-stall-check.yml`: insert `headSha,` after
  `headBranch,` in the `--json` list, anchored on the whole original list (not on `headSha`, which is in the prose).
- [x] 2.2 `git diff -U0 origin/main -- .github/workflows/merge-queue-stall-check.yml`: one `-`, one `+`, differing by `headSha,`.
- [x] 2.3 Re-run the suite; set `EXPECTED_PASSES` to the observed total (expected 166: MT1-MT5 + PT1); re-run to green.
- [x] 2.4 `gh run list --event merge_group --limit 1 --json databaseId,workflowName,headBranch,headSha,status,conclusion,createdAt,url` exits 0.
- [x] 2.5 Old probe now exits 0 on the fixed tree.

## 3. Retire the probe

- [x] 3.1 Census: `git grep -n 'stall-triage-headsha'` over scripts/plugins/tests/.github/knowledge-base/engineering;
  closed `follow-through` issues of the last 14 days (standalone `jq --arg`). Expect none.
- [x] 3.2 `git rm scripts/followthroughs/stall-triage-headsha-12350.sh`.
- [x] 3.3 `bash plugins/soleur/test/ship-followthrough-directive.test.sh`.

## 4. Pre-push verification (each its own Bash call)

- [x] 4.1 `python3 -I scripts/ci-pr-affected-replay.py ratchet` (update the accept tsv rows only if it requires).
- [x] 4.2 `bash plugins/soleur/test/fixture-env-adoption.test.sh`.
- [x] 4.3 `bash .claude/hooks/grep-q-pipe-guard.test.sh` (re-run twice on a flake before blaming the diff).
- [x] 4.4 Registration: `grep -n 'merge-queue-stall-check' scripts/suite-shard-legs.tsv`; `bash plugins/soleur/test/scripts-shard-totality.test.sh`.
- [x] 4.5 `python3 .github/scripts/check-workflow-duplicate-keys.py`; `python3 scripts/lint-guard-contract.py <plan>`.

## 5. Ship and merge (no agent `--admin`)

- [ ] 5.1 Separate `git add` and `git commit` calls; PR body `Closes #12362` + `Ref #9927` only; Decision Classes table from `decision-challenges.md`.
- [ ] 5.2 `gh pr view 12378 --json closingIssuesReferences` is exactly `[#12362]`.
- [ ] 5.3 Bare `gh pr merge 12378`; wait with `Monitor` (never Bash sleep).
- [ ] 5.4 Guard 1 evidence: `merge_group` `test`-leg run (or dispatch run) on the SHA; never a push-run of `ci.yml`.
- [ ] 5.5 After any merge from main: `python3 .github/scripts/check-workflow-duplicate-keys.py` before pushing.

## 6. Post-merge

- [ ] 6.1 Verify #12362 CLOSED by PR #12378.
- [ ] 6.2 `gh issue edit 12362 --remove-label follow-through` (reversible).
- [ ] 6.3 One Ref-only classification comment on #9927 via `--body-file`; #9927 stays OPEN, unedited, unlabelled.
- [ ] 6.4 Any operator note goes on existing #12272; never file a new `action-required`.
- [ ] 6.5 Read merged line 263 on `origin/main`: `headSha` present; probe file gone.
