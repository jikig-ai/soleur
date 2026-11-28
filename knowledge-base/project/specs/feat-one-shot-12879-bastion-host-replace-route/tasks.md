# Tasks: feat-one-shot-12879-bastion-host-replace-route

Plan: `knowledge-base/project/plans/2026-11-28-feat-bastion-host-replace-route-plan.md`.
Issue: #12879 (`Ref`, not `Closes`). Draft PR: #13111. Follow-ups: #13113 (heartbeat), #13116 (key
rotation), #13117 (lost-state recovery).

## 1. Setup

- [ ] 1.1 `git fetch origin main` and rebase; if #12958 merged, rebase onto it.
- [x] 1.2 Record `wc -c .github/workflows/apply-web-platform-infra.yml` (baseline 489,485 on 2026-11-28).

## 2. Byte relocation (its own commit, Q4b: #8385's first slice)

- [x] 2.1 For each candidate input-block comment (manual-rerun, expected_registry_store_volume_id,
  web_host_key, FIELD LABEL, expected_luks_volume_id, image_tag), grep the suites for its phrases.
- [x] 2.2 Relocate verbatim, largest first, only as much as reaching 488,000 needs, into
  `apply-web-platform-infra-job-rationale.md`. Use ADR-231's format: keep each block's first line, its
  test-anchored lines and a `# Rationale: ... §<name>` pointer. The measured estimate is 3,375 B freed
  from all six blocks. If the measured net misses 488,000, stop and report; do not start another
  relocation round. Verify each kept anchor by deleting it and running its consumer.
- [x] 2.3 Prove the commit is comment-only: the `yaml.safe_load` parses are exactly equal and the
  `actionlint` findings are unchanged (AC2).

## 3. Shared gate checks (its own commit, R3/R3b)

- [x] 3.1 Extract the birth gate's create-side checks into `tests/scripts/lib/bastion-gate-common.sh`.
- [x] 3.2 Make the R3b harness change:
  - [x] The `gmut` helper takes a target file.
  - [x] `scratch_gate` also copies `bastion-gate-common.sh`.
  - [x] Both gates source the common file from their own directory.
  - [x] `GMUT` stays at 11.
- [x] 3.3 `bash tests/scripts/test-bastion-host-birth-gate.sh` passes with no row, verdict or message
  changed (AC3). If one has to change, stop and copy the checks instead.

## 4. Tests first

- [x] 4.1 Write `tests/scripts/test-bastion-host-replace-gate.sh`. It covers:
  - [x] the Guard 1 matrix, plus the Deepen-Plan additions:
    - the three-way pin split;
    - the NIC and attachment `before` pins;
    - the per-address action table;
    - a new list member planned `update`;
    - the key planned `create`;
    - an exact name mismatch;
    - `SYNTHETIC-KEY-MARKER` never appearing in output;
    - an ABORT substring on every RED row;
    - the gate-mutation rows;
    - the R3b behaviour rows plus the call-site mutant;
  - [x] the plan-chain and order rows of Guard 2;
  - [x] a fixture type self-check (string `before.id`, numeric API id, `[null]`/`[true]` attachment);
  - [x] a literal `MIN_CASES` floor.

  H2 is dropped.
- [x] 4.2 In `terraform-target-parity.test.ts`:
  - [x] Add the new callee to `MAIN_ROOT_TF_WORKFLOWS` and the caller job to `stripDispatchJobs`.
  - [x] Run the existing bastion block over both routes.
  - [x] Add the Guard 2 rows.
- [x] 4.3 `heartbeat-reprovision-parity.test.ts`: `hasReplaceLine` strips comments (Guard 3). Add a
  trailing-comment row (RED) and a `${#` row (PASS).
- [x] 4.4 Add rows to `test-bastion-boot-verify.sh`:
  - [x] the replace-label text;
  - [x] the #9421 target;
  - [x] the pre-apply id set, on the cancel path, the failed-apply path and the positive control (the
    curl fake asserts the id in the POST URL);
  - [x] a missing set on the replace label, which fails closed;
  - [x] `old_untouched`;
  - [x] `comment_result` posted, failed and no_token;
  - [x] `_bbv_servers_doc` HTTP non-200 and non-array bodies;
  - [x] `bastion_birth_readiness`.

## 5. Gate and libraries

- [x] 5.1 Write `tests/scripts/lib/bastion-host-replace-gate.sh`, covering the three-way pin with
  `tostring`, the replace and recovery arms, and the refusals.
- [x] 5.2 Write `scripts/lib/bastion-birth-readiness.sh` (F1), with `bastion_birth_readiness <label>`.
- [x] 5.3 Edit `scripts/lib/bastion-boot-verify.sh`:
  - [x] the live recovery text;
  - [x] the replace-label clause;
  - [x] the old-id fourth argument;
  - [x] the comment target, which becomes #9421;
  - [x] the heartbeat pointer, which becomes #13113;
  - [x] `_bbv_poweroff [pre-ids]`, which refuses any pre-apply id;
  - [x] `comment_result`;
  - [x] `_bbv_servers_doc`, a single `bc_curl` Hetzner reader that requires HTTP 200 and `.servers|arrays`.

## 6. Workflows

- [x] 6.1 Write `.github/workflows/bastion-host-replace.yml` with these properties:
  - [x] `workflow_call` only, no `concurrency:`, and `environment: web-platform-infra-apply`;
  - [x] steps in this order: interlock, live-id read, plan (with the conditional `replace_args`),
    gate, stock, the summary (`always()`), TOCTOU, apply, boot-verify with the old id, cancel
    power-off, pin read-back, then the dispatch summary;
  - [x] every mutating step guarded with `inputs.plan_only != true`;
  - [x] a job-level `if: github.ref == 'refs/heads/main'`;
  - [x] the plan files written under `umask 077` in a `$RUNNER_TEMP` mktemp directory, each line of every `private_key_*` field (openssh, pem, pem_pkcs8)
    masked, and the directory deleted on `always()`;
  - [x] TOCTOU re-checks identity through `bastion_replace_identity`;
  - [x] the always-run summary computes the next-dispatch line (`none`, the new id, the same pin, or unread).
- [x] 6.2 Edit `apply-web-platform-infra.yml`:
  - [x] Check GitHub's dispatch-input limit first.
  - [x] Add the `expected_bastion_server_id` input and the `bastion-host-replace` option.
  - [x] Update the three descriptions.
  - [x] Add the thin caller after `bastion_host_create`.
- [x] 6.3 Edit `bastion-host-create.yml`:
  - [x] Turn the interlock step into a source-and-call (F1).
  - [x] Pass the pre-apply id set to boot-verify and the cancel power-off.
  - [x] Branch the summary on `comment_result`, naming #9421 and #13113.
  - [x] Print the server id in the pin read-back.

## 7. Census, registration, records

- [x] 7.1 Run the reusable-caller census grep (plan Phase 5.1). Then edit the suites that go red:
  - [x] `PLAN_ONLY_JOBS`
  - [x] `soleur-host-bootstrap-observability.test.sh`
  - [x] `kernel-currency.test.sh`
  - [x] `bastion-runcmd-rehearsal.test.sh`
  - [x] `test-argv-bearer-sweep.sh`
  - [x] `bastion-lint.py`, if it reds
- [x] 7.2 Registration:
  - [x] Add the `run_suite` line inside `want_scripts`.
  - [x] Add the `test-affected-paths.sh` edges.
  - [x] Check `--enumerate scripts` and `lint-orphan-test-suites.sh`.
- [x] 7.3 Add the ADR-327 addendum (2026-11-28, step 2b), covering the precedent departures, the
  owner-only reviewer, the pre-apply id set and the #12867 downtime revisit. Add the ADR-231 addendum
  (Q4b: first slice, minimum relocation, the counter tripped, and the next PR must take the split).
- [x] 7.4 Correct `bastion-host.md` at lines 7, 12, 48, 57, 61, 67, 71 and 84. Add two sections:
  "Replacing the bastion" and "Recovering a failed replace".
- [x] 7.5 Edit the `model.c4` descriptions, then run the C4 suites.

## 8. Verify

- [x] 8.1 Run all named suites, `workflow-file-size`, `actionlint`, `shellcheck` and
  `lint-infra-no-human-steps.py --changed`.
- [ ] 8.2 Check that `wc -c` is at most 488,000 after the final rebase (AC1).
- [ ] 8.3 Put the following in the PR body:
  - `Ref #12879`, `Ref #9421` and `Ref #12008`;
  - the done-when checklist, with item 2 left as an Operator Hold;
  - the workflows the merge triggers, and what each one will do.

## 9. Operator Holds (post-merge, never in this PR)

- [ ] 9.0 Operator item: schedule #8385 (split the apply workflow) before the next route that adds to it.

- [ ] 9.1 The bastion birth, after #12942, on the owner's go.
- [ ] 9.2 A `plan_only` dispatch of `bastion-host-replace` against the born bastion, on the owner's
  typed go naming the exact command. Close #12879 on its PASS.
