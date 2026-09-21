# Tasks: fix(sentry) adopt the last two sentry_issue_alert rules as sentry_alert (#8451)

Plan: `knowledge-base/project/plans/2026-09-21-fix-sentry-alert-410-removed-api-migration-plan.md`

## Phase 1: RED guards (write before the code under test)

- [ ] 1.1 Guard 1 rows in `tests/scripts/test-sentry-alert-reference-gate.sh`. Add a parameterized `_rule` variant with `legacy_trigger_conditions`, native-form excluded, `trigger_conditions: null`, no `sensitive_values`, and a non-excluded legacy type that must error.
- [ ] 1.2 Guard 2 rows in `tests/scripts/test-sentry-alert-adoption-guards.sh`: update / create / replace on a legacy row (RED), second member, zero-rows floor, and import-no-op plus native-update must-PASS.
- [ ] 1.3 Guard 3 static assertions in `tests/scripts/test-sentry-full-root-apply.sh`: anchor count 2, single `terraform plan`, `rm -f`, `exit $rc`, a 410 branch per slice.
- [ ] 1.4 Guard 4 rows in `tests/scripts/test-sentry-alert-live-fidelity.sh` (`comparison: true`, `enabled: false`, missing action, detector, unknown frozen rule, zero-compared floor), plus the static literal-vs-capture assertions in the op-contract vitest.
- [ ] 1.5 Confirm every row is RED for the stated reason.

## Phase 2: Core implementation

- [ ] 2.1 `tests/scripts/lib/sentry-alert-projection.jq`: TF-side exclusion (native OR legacy ∩ `excluded`) placed BEFORE `canon | map(tf_rule)`; a non-excluded legacy type raises `error(...)`; update the `excluded` comment.
- [ ] 2.2 `scripts/sentry-issue-alert-create-tripwire.sh`: refuse `sentry_alert` create/update/replace whose after-legacy intersects `excluded` (single source or parity-pinned); reword the "exactly TWO" header and the `:88` message.
- [ ] 2.3 `scripts/sentry-alert-live-fidelity.sh`: frozen-rule pin over every excluded-type live workflow against the phase34 capture.
- [ ] 2.4 `apps/web-platform/infra/sentry/issue-alerts.tf`: two `removed{}` / `import{}` (566671, 669246) / `sentry_alert` triples with live-faithful values, `legacy_trigger_conditions`, `ignore_changes = all`, and INERT comments. The #6429 rationale goes directly above the sandbox resource header. Add the header supersession note. Run `terraform validate`.
- [ ] 2.5 `.github/workflows/apply-sentry-infra.yml`:
  - [ ] 2.5.1 Replace both retry ladders with a single attempt plus the anchor `# sentry-plan-410-handler (#8451)`, keeping `rm -f`, `tee`, `PIPESTATUS` and `exit $rc`; the 410 branch names the addresses (measured-only wording).
  - [ ] 2.5.2 Adoption-assert expected count `1` → `2` at both call sites.
  - [ ] 2.5.3 Rewrite the filer's "If the failure was a Sentry 410" paragraph; fix the "27 forgets" comment.
- [ ] 2.6 Prose: `scheduled-sentry-alert-drift.yml:15-20`, `assert-byok-rules-exist.sh:48-54`, the adoption-guards A7 comment, and `infra/sentry/README.md` `:5`, `:11`, `:23-24`.
- [ ] 2.7 `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts`: repoint the sandbox section; `issue_owners` / `ActiveMembers`; `ignore_changes = all` and legacy on both blocks; rewrite the `_scopeHeader` comment.
- [ ] 2.8 `scripts/followthroughs/sentry-provider-release-7985.sh`: PASS only when converted; FAIL "unblocked" when a release carries `0deba79` but the repo is not converted.
- [ ] 2.9 `git rm tests/scripts/test-sentry-brownout-retry.sh scripts/followthroughs/sentry-brownout-frequency-7650.sh`; drop the baseline line in `scripts/lint-shell-trace-credential-refusal.baseline.txt`.
- [ ] 2.10 ADR-031: add `Amendment (2026-09-21, #8451)` and superseded markers on the #7590 and #7650-Phase-2 amendments.

## Phase 3: Verification

- [ ] 3.1 Run the touched suites via `scripts/test-all.sh`, the apps/web-platform vitest op-contract file, and `c4-count-parity.test.sh`.
- [ ] 3.2 Run `actionlint`, `lint-diagnosis-claims.sh` and `workflow-file-size.test.ts`.
- [ ] 3.3 Census greps: `sentry_issue_alert|auth_per_user_loop|sandbox_startup_failure` (categories a-e), `brownout`, the deleted files, and the ladder tokens.
- [ ] 3.4 Record the pre-merge live `dateUpdated` for 566671 and 669246 in the PR body.
- [ ] 3.5 PR: a body line `[ack-destroy]` plus the scope sentence; `Closes #8451`; `Ref #8282`; `plan_pr` green without bypass.

## Phase 4: Post-merge (agent-run)

- [ ] 4.1 Merge ordering: no other Sentry-infra PR merges until this push apply succeeds.
- [ ] 4.2 The apply run succeeds: 2 imports, 2 forgets, adoption assert PASS, AC17 32/0, post-apply probe including Guard 4. #8282 is closed by the success step.
- [ ] 4.3 Live re-read: `dateUpdated` unchanged, comparisons intact. Otherwise take the p1 issue plus scripted PUT restore branch.
- [ ] 4.4 `gh issue edit 7985` (title and body with the atomic exit checklist); file the orphan-suite lint-gap issue.
