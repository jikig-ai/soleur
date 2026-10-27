# Tasks: destroy the retired plaintext git-data volume through Terraform (Option B)

Plan: knowledge-base/project/plans/2026-10-26-feat-git-data-plaintext-volume-terraform-destroy-plan.md

## Phase 0: Offline experiment and read-only confirmations

- [x] 0.1 Scratch-dir `terraform_data` experiment: `-target` on an orphan and on an address absent from config and state; record exit code, warning text, `resource_changes` shape on an empty plan, `action_reason`; state the terraform version(s) used
- [x] 0.2 Re-read the live volume read-only (id 106867358, name, server 170370833, LUKS 107140231 on the same server)
- [x] 0.3 Run the baseline suites on the unmodified tree
- [x] 0.4 Grep: `git-data-cutover.yml` and its `rollback` mode never reference the plaintext volume

## Phase 1: Guard first (TDD)

- [x] 1.1 Write `tests/scripts/test-git-data-plaintext-destroy-gate.sh` (M1-M12 RED, P1-P5 green, type-faithful fixtures, `return 0` mutation RED, helper positive controls, workflow run-block rows, probe rows against a curl shim) — RED first
- [x] 1.2 Write `tests/scripts/lib/git-data-plaintext-destroy-gate.sh` (`local plan_json`, preamble anchored calls, one `jq -n`, exact action lists, ids via `tostring`, attachment bound to the LIVE server id passed as `$3`)
- [x] 1.3 Register the test in `scripts/suite-durations.tsv` and `scripts/suite-shard-legs.tsv`
- [x] 1.4 `test-plan-gate-preamble.sh` green

## Phase 2: HCL removal and workflow

- [x] 2.1 `git-data.tf`: delete the volume and attachment; literal `"106867358"` with comment and `SOLEUR-DEBT:` marker; refresh stale comments; check `git_data_volume_size`
- [x] 2.2 `apps/web-platform/infra/git-data-plaintext-volume-state.sh` (read-only probe)
- [x] 2.3 `.github/workflows/git-data-plaintext-volume-destroy.yml`: `validate` job, `destroy` job (environment, both concurrency groups, tf-var plumbing, keygen, pre-plan read, already-gone short-circuit, plan, gate, apply, read-back `success() || failure()`, cleanup `always()`)
- [x] 2.4 `terraform validate`; actionlint via `scripts/lint-workflows.sh`

## Phase 3: Keep guards green

- [x] 3.1 `terraform-target-parity.test.ts`: `MAIN_ROOT_TF_WORKFLOWS` + count bump; pins describe block. The two `OPERATOR_APPLIED_EXCLUSIONS` entries are KEPT (the replace and birth parity tests still require them)
- [x] 3.2 `test-git-data-wipe-wedge.sh`: `WEDGE_ADDRS`, F1/F2 live checks, stale header
- [x] 3.3 `encryption-posture-ledger.json`: KEEP the row (it carries the lint-enforced 2026-11-12 expiry until the record PR), update its evidence/reevaluate text and the rehearsal row prose
- [x] 3.4 Census `DISPATCH_GATED_DESTROYS` added per CTO (rows g4-15..g4-29, 457 assertions); rung2-rehearsal, census, workflow-file-size, c4-count-parity, lint-encryption-posture, replace/birth gate suites run; fixed only what turned red. The affected gate was budget-deferred (rc=6): CI is authoritative for the long-running consumers

## Phase 4: Records and follow-ups

- [x] 4.1 Runbook section (order, probe, window, drift issue, host-lost paragraph, retention and disclosure timing, recovery)
- [x] 4.2 ADR-239 DRAFT amendment (PENDING CLO ATTESTATION; claim limits once)
- [x] 4.3 File follow-up issue: gate retirement + `id = ""` host replace (milestone, date, owner)
- [x] 4.4 File follow-up issue: post-destroy record PR + deleting the one-shot workflow
- [ ] 4.5 Dated items on #6897 (2026-11-02, 2026-11-09 checkpoint, 2026-11-12): written into ADR-239 Amendment 2026-10-26 items 6-7 and the runbook; posting them on #6897 is an OWNER/follow-through action named in the PR body, not done by this PR

## Phase 5: Review, PR, stop

- [x] 5.1a 12-seat `soleur:review` round 1 and CTO/CLO rulings applied (live by-name server/LUKS ids, apply-step re-gate, main-only guard, shape=gone read-back, runbook/ADR/ledger/plan reconciliation)
- [ ] 5.1 Verification pass, `soleur:qa`, compound
- [ ] 5.2 READY PR with green CI, no auto-merge, `## Owner actions` (flip retry → conditional rotate → merge → dispatch within ~24h of the merge)
