# Tasks — git-data-cutover mode=refs_assert (Ref #8211, closes #11431)

Plan: `knowledge-base/project/plans/2026-10-29-feat-git-data-cutover-refs-assert-plan.md`
Decision log: `knowledge-base/project/specs/feat-one-shot-11431-refs-assert/decision-challenges.md`

Hard rules for every task: touch none of the 17 hash-bound paths (plan "Hash-bound paths"); never dispatch a workflow,
write Doppler, run `flip.sh`, `git stash` or `git add -A`; run only the scoped suites listed in 5.x, never
`scripts/test-all.sh`; commits say `Ref #8211` with the trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## 0. Read first (no edits)

- 0.1 Read `case_parity` (P1-P4), `case_capture_census`, `case_verb_census`, `case_rb`, D-6, `WF-gating`, `N-body`/`N-exprs` and the AC9 flag-precheck pin in `apps/web-platform/infra/git-data-cutover-access.test.sh`.
- 0.2 Read `MODES`, the executed cutover confirm table, `WS-modes`, `G10-env-contract` in `apps/web-platform/infra/git-data-wipe-access.test.sh`.
- 0.3 Read `git-data-wipe-assert.test.sh` P1-P7 as the template for the new suite's parity rows.

## 1. RED tests

- 1.1 Create `apps/web-platform/infra/git-data-refs-assert.test.sh` with real-`git` fixtures (synthesized identifiers only).
  - 1.1.1 Happy path and the must-PASS non-canonical fixture (two namespaces, `heads/feature/x.y`, annotated tag, lock dotfiles, empty `lost+found`; namespaces=2, refs=3, heads=2).
  - 1.1.2 One row per refusal in the exit-code table, asserting the WHOLE output line: `refs_repo_absent`, `refs_repo_not_single` (two repos, symlink entry, file entry, symlinked `repositories`), `refs_none` (real never-pushed `git init --bare`; unborn HEAD; loose ref outside the namespace), `refs_no_branch_tip`, `refs_unreadable` (missing object, 201 refs, wrong-owner via `git` shim), `refs_shape_failed` (rc 27 and rc 96 suffix), `refs_bad_sha`.
  - 1.1.3 Runner-side rows: `cutover_frozen`, `old_store_unmounted`, `store_not_on_mapper`, `store_unverified`, `probe_failed rc=124/255`.
  - 1.1.4 Format pin and "drop `%(objecttype)`" mutation; stdin-delivery row (real `bash -s`, `git` shim that reads stdin); write-verb shims (one per verb); print scan over every row; script-table <-> Verdict-map parity row; exclusion-predicate parity row; "not in any `file()` binding" row; Guard 1 and Guard 2 matrices with landing assertions; `MIN_ASSERTIONS` floor via printf+exit.
- 1.2 Restate pins in `git-data-cutover-access.test.sh` (mode options 9 -> 10, AC9 flag-precheck pin, ordered steps/gating, G5 name allow-list and one more `gd_capture` site, N-body/N-exprs, floors) and `git-data-wipe-access.test.sh` (MODES, NOTIFY_MODES, confirm pair, WS-modes).
- 1.3 Add `scripts/lib/git-data-wipe-runs.test.sh` rows: `refs_assert` -> `other`, after-the-stamp ok, `refs_assertX` -> `unparseable`.

## 2. Host script and verb

- 2.1 Write `apps/web-platform/infra/git-data-refs-assert.sh` per the plan's "Host logic (security pass applied)" list: function-wrapped body, `exec` fd redirection, xtrace refusal, `RA_MOUNT` constant identity checks with before/after `stat` TOCTOU guard, ONE NUL-delimited typed `find` (count + name), `cd /`, absolute `env`/`git`, hardened env and `-c` flags, `3>&- 4>&-`, git stderr to a root-owned /dev/shm file with any non-empty stderr = rc 27, `shallow` file = rc 26, `%(*objecttype)` format, here-string parse, cap 2 numerically smallest heads shas by array slice, fail-closed self-check (rc 26), exit-code table with class column. Do not assign `STORE_DEVICE`, `STORE_VERIFIED`, `cutover_freeze`, `MOUNT_ROOT`, `GIT_DATA_ROOT`, `REPO_ROOT`.
- 2.2 Add `mode_refs_assert`, `_refs_emit`, `_refs_refuse`, the `MODE` validation word, the `refuse_legacy_modes` remedy words and the `main()` arm to `apps/web-platform/infra/git-data-cutover.sh` (copy `mode_wipe_assert`).

## 3. Workflow, classifier, ledgers

- 3.1 Edit `.github/workflows/git-data-cutover.yml`: option, confirm token, `FLAG_MODE` mapping, `Host-side refs assertion` step (id `refs`), `refs_class` job output, notify words and `case`, run summary, header.
- 3.2 Edit `scripts/lib/git-data-wipe-runs.sh` (regex, header lines 8 and 17).
- 3.3 Add the `PROMOTED_FILES` entry and `MIN_FIRING_SUITES` bump in `scripts/guard-vacuity-floor.test.sh`; add the shard row in `apps/web-platform/infra/suite-shard-legs.tsv`.
- 3.4 Re-measure `grep -c -e REFS_ASSERT_INCONCLUSIVE .github/workflows/git-data-cutover.yml` and restate the plan's Observability `expected_output` if it is not `2`.

## 4. Runbook and C4

- 4.1 Runbook `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`: new `### Reading REFS-CONFIRMED`; one-line links in R3, R6, Abort; r3-verdicts template; modes table; mode list near the top; downtime row; Verdict-map rows.
- 4.2 `model.c4` edge sentence; run `scripts/regenerate-c4-model.sh`.

## 5. Scoped verification

- 5.1 Run the Phase 5 command list (use `$(git merge-base origin/main HEAD)` for diff scope) from the plan (refs-assert suite, cutover-access, wipe-access, wipe-assert, wipe-runs, root-token census, cloudflare-token-drift, guard-vacuity-floor, lint-orphan-test-suites, c4 tests, actionlint, shellcheck, the lints, markdownlint, the precheck byte-unchanged check).
- 5.2 Restate floors from the printed totals; paste totals in the commit message.
- 5.3 Run AC1 (roster count 16 and empty intersection) before every commit.

## 6. Ship-time follow-through

- 6.1 Cite an existing tracker for "host replace -> rehearsal -> refs_assert" or add ONE comment on #8211 (includes the parked F17 dead end); the PR body opens with the apply-workflow note.
