# Tasks: zot pull token off terraform's argv (item 2 of #9757)

Plan: `knowledge-base/project/plans/2026-10-20-fix-zot-pull-token-off-terraform-argv-plan.md`. PR body says `Ref #9757`; never a closing keyword. Do not edit anything under `apps/web-platform/infra/**` or `.github/workflows/apply-web-platform-infra.yml` (either fires the production apply). Pathspec commits only; no `git stash`; never print a secret value or a hash of one.

## Phase 0: Re-verify the premise (no edit)

- [ ] 0.1 `git fetch origin main`; confirm exactly 4 `zot_pull_token=${ZOT_PULL}` lines in `.github/workflows/inngest-provision-rehearsal.yml` and re-run the `-var` name census; stop and re-plan if a fifth site or another credential-named `-var` appeared
- [ ] 0.2 `gh pr view 10566` and `gh pr view 10546`: if either merged, rebase and re-diff the `EXPECTED_TESTS` region

## Phase 1: Guard first (RED) — stage S9 in `tests/scripts/test-argv-bearer-sweep.sh`

- [ ] 1.1 Append S9 after the S8 `echo "=== stage S8 ... done ==="` line and before the `# VERDICT` block; reuse `assert_fixture_dir`, `row`, `fatal`, `s3_body`, `s6_edit`; call `assert_fixture_dir` before every fixture write; no `producer | grep -q` pipes; stub verbs limited to `doppler` and `terraform`
  - [ ] 1.1.1 Scanner `scan.py` (python3 -I): S8 exclusion predicate, extensions `.yml .yaml .sh .bash` plus `.md` under `plugins/`, continuation join, comment skip, verb-free anchored option regex `(?<![\w-])-var(?:=|\s+)["']?NAME=` (must not match `tf-var -- \` or `-var-file`), name arm only (the value-side arm was cut at plan review; blind spot recorded)
  - [ ] 1.1.2 Floor `S9_VAR_FLOOR` only (RED phase: unchanged-tree count minus 4; confirmed in Phase 2), identity row I1 (rehearsal workflow records), static row I2 over all four steps (one `export TF_VAR_zot_pull_token=` of the read variable, positioned BEFORE the `doppler run` line, bare `--preserve-env` kept)
  - [ ] 1.1.3 Executed rows for the two destroy bodies only (selectors `Teardown only (recovery arm)` and `Terraform destroy (everything`): stub `doppler` (403 model on the PRD pairing; `run` injects nothing), stub `terraform` (records argv and `TF_VAR_zot_pull_token`); verdict helper `s9_judge_run` naming the failing clause (canary in no argv, TF_VAR equals canary, `rehearsal_run_id=<id>` by value; no mask assertions); destroy-step-count row
  - [ ] 1.1.4 Mutation rows of Guard 1 (7) and Guard 2 (5), one site per mutation type, the undoctored-GREEN control for `s9_judge_run` plus fabricated controls only for clauses no mutation reaches, must-PASS inputs (including `tf-var -- \`, `-var-file`, and a secret-reading file with a clean `-var`), scratch-base GREEN control; target about 300 lines for the stage
- [ ] 1.2 Run S9 on the unchanged workflow: the S9 real-tree rows must be RED naming the four workflow lines (save those rows' output; the suite total is red for unrelated reasons until `EXPECTED_TESTS` is bumped in 2.3)

## Phase 2: Convert the four sites (GREEN)

- [ ] 2.1 In each of the four steps add `export TF_VAR_zot_pull_token="$ZOT_PULL"` directly after the `::add-mask::` line; delete the `-var "zot_pull_token=${ZOT_PULL}"` line and the dangling trailing backslash; keep the read (with `DOPPLER_TOKEN_PRD`) and bare `--preserve-env`; no `--only-secrets`
- [ ] 2.2 Header comment above the phase-A plan step: keep "not reachable across roots" (accurate: terraform roots); change only the Doppler-scope sentence to one measured sentence (403 was on `soleur/prd`; `prd_terraform` lists `ZOT_PULL_TOKEN` with an equal value; the explicit read stays pending the option-B issue); avoid the substrings `ssh ` and `ssh-key` and the literal `get ZOT_PULL_TOKEN -p soleur-registry`
- [ ] 2.3 Measure `S9_VAR_FLOOR` on the converted tree and set it; bump `EXPECTED_TESTS` to the measured green total (`840 + S9 rows`) and add its ledger comment line
- [ ] 2.4 Run the infra suite read-only (`bash apps/web-platform/infra/inngest-provision-rehearsal.test.sh`): unchanged-green

## Phase 3: Affected-test edge

- [ ] 3.1 Add `.github/workflows/inngest-provision-rehearsal.yml` to `AFFECTED_TESTS_SCRIPTS_ARGV_BEARER_SWEEP_PATHS` in `scripts/lib/test-affected-paths.sh` in a new S9 comment block
- [ ] 3.2 Measure with `bash scripts/test-all.sh --print-selection --paths=...` (detached): the workflow path selects `tests/scripts/argv-bearer-sweep` after the edit and not before; `scripts/lib/test-affected-paths.sh` selects the same set before and after

## Phase 4: Doc fix

- [ ] 4.1 `plugins/soleur/skills/deploy/references/hetzner-setup.md` line 17: replace `-var="hcloud_token=<your-token>"` with `read -rs TF_VAR_hcloud_token; export TF_VAR_hcloud_token` before the `terraform apply`; `git grep -n 'hcloud_token=' -- plugins/` empty

## Phase 5: Architecture record

- [ ] 5.1 Via `soleur:architecture`, append `### 2026-10-20 follow-ups: terraform -var credentials (#9757 item 2)` to ADR-280: the rule, S9, its stated blind spots, open option B, in about five lines; no new ordinal
- [ ] 5.2 Re-run `bash plugins/soleur/test/c4-count-parity.test.sh` (green at plan time)

## Phase 6: Verification (detached, logs under /var/tmp, rc files, Monitor until-loops)

- [ ] 6.1 `bash tests/scripts/test-argv-bearer-sweep.sh` green, `0 failed`, `EXPECTED_TESTS` equals the measured total
- [ ] 6.2 Commit, then recompute `PJ_TRIPLES` per the recipe in `.claude/hooks/grep-q-pipe-guard.test.sh` (expect 288); only if it moves, add the exempt rows and update the pin, then run that guard
- [ ] 6.3 `bash plugins/soleur/test/fixture-relative-assert.test.sh` equal to its baseline (regenerate only if S9 truly adds a row, same commit; PR 10546 also edits that baseline)
- [ ] 6.4 `bash scripts/guard-vacuity-floor.test.sh`; `python3 scripts/lint-guard-contract.py`; workflow lints (actionlint where installed, shellcheck on extracted bodies)
- [ ] 6.5 Diff-scope check: no `apply-web-platform-infra.yml`, no `tests/scripts/lib/destroy-guard-filter-web-platform.jq`, no `apps/web-platform/infra/**` outside `inngest-provision-rehearsal/`, `rung2-rehearsal/`, `git-data-root-key/`; `git diff --numstat` of the sweep script shows one deleted line

## Phase 7: Tracking and hand-off

- [ ] 7.1 File the option-B issue (drop the explicit `ZOT_PULL_TOKEN` reads, rely on `prd_terraform` inheritance; flip evidence: a measured read with the CI service token's scope; milestone from the roadmap; `Ref #9757`)
- [ ] 7.2 PR body: `Ref #9757`, measured findings, the `Ruled by CTO agent` lines, the no-apply statement, the option-B issue number; semver label handling via `soleur:ship` (the doc line is under `plugins/soleur/**`)
- [ ] 7.3 After merge: tick item 2 on #9757 with a `_Landed: PR #<n>_` note and the pending-verification sentence (next rehearsal dispatch's phase-A plan succeeds); #9757 stays open
