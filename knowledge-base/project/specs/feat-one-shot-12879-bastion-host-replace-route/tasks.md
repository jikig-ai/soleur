# Tasks: feat-one-shot-12879-bastion-host-replace-route

Plan: `knowledge-base/project/plans/2026-11-28-feat-bastion-host-replace-route-plan.md`.
Issue: #12879 (`Ref`, not `Closes`). Draft PR: #13111. Follow-ups: #13113 (heartbeat), #13116 (key
rotation), #13117 (lost-state recovery).

## 1. Setup

- [ ] 1.1 `git fetch origin main` and rebase; if #12958 merged, rebase onto it.
- [ ] 1.2 Record `wc -c .github/workflows/apply-web-platform-infra.yml` (baseline 489,485 on 2026-11-28).

## 2. Byte relocation (its own commit, Q4)

- [ ] 2.1 For each candidate input-block comment (manual-rerun, expected_registry_store_volume_id,
  web_host_key, FIELD LABEL, expected_luks_volume_id, image_tag), grep the suites for its phrases.
- [ ] 2.2 Relocate verbatim, largest first, into `apply-web-platform-infra-job-rationale.md`, leaving one
  pointer line each. Verify each kept anchor by deleting it and running its consumer.
- [ ] 2.3 Prove the commit is comment-only: the `yaml.safe_load` parses are exactly equal and the
  `actionlint` findings are unchanged (AC2).

## 3. Shared gate checks (its own commit, R3)

- [ ] 3.1 Extract the birth gate's create-side checks into `tests/scripts/lib/bastion-gate-common.sh`.
- [ ] 3.2 `bash tests/scripts/test-bastion-host-birth-gate.sh` passes with no assertion changed (AC3). If
  any assertion has to change, stop and copy the checks instead.

## 4. Tests first

- [ ] 4.1 Write `tests/scripts/test-bastion-host-replace-gate.sh`, covering the Guard 1 matrix and the
  H1-H4 rows, with real types: a string `before.id` and a numeric API id.
- [ ] 4.2 In `terraform-target-parity.test.ts`:
  - [ ] Add the new callee to `MAIN_ROOT_TF_WORKFLOWS` and the caller job to `stripDispatchJobs`.
  - [ ] Run the existing bastion block over both routes.
  - [ ] Add the Guard 2 rows.
- [ ] 4.3 `heartbeat-reprovision-parity.test.ts`: `hasReplaceLine` strips comments (Guard 3).
- [ ] 4.4 Add rows to `test-bastion-boot-verify.sh`: the replace-label text, the #9421 target, the old-id
  argument, and `bastion_birth_readiness`.

## 5. Gate and libraries

- [ ] 5.1 Write `tests/scripts/lib/bastion-host-replace-gate.sh`, covering the three-way pin with
  `tostring`, the replace and recovery arms, and the refusals.
- [ ] 5.2 Write `scripts/lib/bastion-birth-readiness.sh` (F1), with `bastion_birth_readiness <label>`.
- [ ] 5.3 Edit `scripts/lib/bastion-boot-verify.sh`:
  - [ ] the live recovery text;
  - [ ] the replace-label clause;
  - [ ] the old-id fourth argument;
  - [ ] the comment target, which becomes #9421;
  - [ ] the heartbeat pointer, which becomes #13113.

## 6. Workflows

- [ ] 6.1 Write `.github/workflows/bastion-host-replace.yml` with these properties:
  - [ ] `workflow_call` only, no `concurrency:`, and `environment: web-platform-infra-apply`;
  - [ ] steps in this order: interlock, live-id read, plan (with the conditional `replace_args`),
    gate, stock, the summary (`always()`), TOCTOU, apply, boot-verify with the old id, cancel
    power-off, pin read-back, then the dispatch summary;
  - [ ] every mutating step guarded with `inputs.plan_only != true`.
- [ ] 6.2 Edit `apply-web-platform-infra.yml`:
  - [ ] Check GitHub's dispatch-input limit first.
  - [ ] Add the `expected_bastion_server_id` input and the `bastion-host-replace` option.
  - [ ] Update the three descriptions.
  - [ ] Add the thin caller after `bastion_host_create`.
- [ ] 6.3 In `bastion-host-create.yml`, turn the interlock step into a source-and-call (F1).

## 7. Census, registration, records

- [ ] 7.1 Run the reusable-caller census grep (plan Phase 5.1). Then edit the suites that go red:
  - [ ] `PLAN_ONLY_JOBS`
  - [ ] `soleur-host-bootstrap-observability.test.sh`
  - [ ] `kernel-currency.test.sh`
  - [ ] `bastion-runcmd-rehearsal.test.sh`
  - [ ] `test-argv-bearer-sweep.sh`
  - [ ] `bastion-lint.py`, if it reds
- [ ] 7.2 Registration:
  - [ ] Add the `run_suite` line inside `want_scripts`.
  - [ ] Add the `test-affected-paths.sh` edges.
  - [ ] Check `--enumerate scripts` and `lint-orphan-test-suites.sh`.
- [ ] 7.3 Add the ADR-327 addendum (2026-11-28, step 2b).
- [ ] 7.4 Correct `bastion-host.md` at lines 7, 12, 48, 57, 61, 67, 71 and 84. Add two sections:
  "Replacing the bastion" and "Recovering a failed replace".
- [ ] 7.5 Edit the `model.c4` descriptions, then run the C4 suites.

## 8. Verify

- [ ] 8.1 Run all named suites, `workflow-file-size`, `actionlint`, `shellcheck` and
  `lint-infra-no-human-steps.py --changed`.
- [ ] 8.2 Check that `wc -c` is at most 488,000 after the final rebase (AC1).
- [ ] 8.3 Put the following in the PR body:
  - `Ref #12879`, `Ref #9421` and `Ref #12008`;
  - the done-when checklist, with item 2 left as an Operator Hold;
  - the workflows the merge triggers, and what each one will do.

## 9. Operator Holds (post-merge, never in this PR)

- [ ] 9.1 The bastion birth, after #12942, on the owner's go.
- [ ] 9.2 A `plan_only` dispatch of `bastion-host-replace` against the born bastion, on the owner's
  typed go naming the exact command. Close #12879 on its PASS.
