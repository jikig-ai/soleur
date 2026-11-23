# Tasks: fix(infra): admit the Cloudflare DNS import-normalize update in the migration gate

Plan: `knowledge-base/project/plans/2026-11-23-fix-cf-dns-import-normalize-gate-plan.md`.
Ref #12931 (no closing keyword). PR #13019. Stop at ready for the owner's review; do not merge.

Bounds for every task: no workflow dispatch, no Doppler write, no Cloudflare write endpoint, no
`terraform apply` (a loopback mock included), no SSH, and no token value printed.

## 1. RED tests

- [ ] 1.1 Add a gate-suite fixture builder that emits the measured key set with synthesized values, plus a live-record builder.
- [ ] 1.2 Add gate rows: admit, retry, mixed retry, each off-shape refusal, each live refusal, collect cases.
- [ ] 1.3 Add the Guard 1 mutation and harness rows.
- [ ] 1.4 Set `LIB_FN_COUNT` to the final derived count.
- [ ] 1.5 Move the job suite's `redirects-dns` record fixtures to the measured key set, and answer `dns_records/<id>` GETs from them in the curl stub.
- [ ] 1.6 Add a `timeout` PATH shim that logs argv and execs the real binary.
- [ ] 1.7 Add the job cases and the Guard 2 mutation and harness rows; re-anchor V6, V7 and V25 with the `apply-failed` edit.
- [ ] 1.8 Confirm the new rows fail against the current gate and job.

## 2. Gate (`tests/scripts/lib/cf-account-migrate-gate.sh`)

- [ ] 2.1 `cf_account_migrate_record_pins`, with the exact-count check.
- [ ] 2.2 `cf_account_migrate_live_collect`.
- [ ] 2.3 `_CFAM_NORMALIZE_JQ`: `cfam_norm_shape`, `cfam_fqdn`, `cfam_live_diff`, closed diagnostic tokens.
- [ ] 2.4 `cf_account_migrate_live_diff` entry point.
- [ ] 2.5 One `verdicts` evaluation, `norm`, the two refusals subtracting it (`--argjson norm` after the filter), the live-diff refusal, `norm_why` outside `violations`.
- [ ] 2.6 `import-normalize` lines on PASS only; update the header.

## 3. Job (`apps/web-platform/infra/scripts/cf-account-migrate-job.sh`)

- [ ] 3.1 `read_live_records` with one `read_end` deadline enforced outside `doppler run`.
- [ ] 3.2 Read all 26 on every `redirects-dns` plan, immediately before the phase gate.
- [ ] 3.3 Bounded apply only when a record was admitted: `tf_env timeout --foreground -s INT`, `apply-budget-exhausted`.
- [ ] 3.4 Post-apply re-read, `partial_apply_verdict`, `import-normalize-reread-failed`, the `reread=` field.
- [ ] 3.5 `live-read records=` and `import-normalize count=` lines; correct the `apply-failed` text; extend the header contracts.

## 4. Docs

- [ ] 4.1 Imports file header.
- [ ] 4.2 Runbook: Step 2 note, expected log, refusal list, Halt bullets including the restore path.
- [ ] 4.3 ADR-329: Decision bullet and Principle Alignment sentence.
- [ ] 4.4 Regenerate `plugins/soleur/test/fixture-relative-assert.baseline.txt` in the same commit as the source edits.

## 5. Verify and ship to ready

- [ ] 5.1 Run the AC9 suites. Give the job suite at least 15 minutes.
- [ ] 5.2 Run the AC10 census.
- [ ] 5.3 Put `[skip-web-platform-apply]` on its own line in a branch commit body, and confirm the `gh pr view 13019 --json commits` count prints 1 or more.
- [ ] 5.4 PR body: the production-deploy first line, `Ref #12931`, the merge constraint, the Unverified list, the hold rule.
- [ ] 5.5 Mark ready and stop. No auto-merge and no merge queue.
