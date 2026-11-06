# Tasks — feat-one-shot-9061-drift-autoclose

Plan: `knowledge-base/project/plans/2026-10-27-fix-drift-autoclose-full-root-gate-plan.md`
Issues: closes #9061; comments (no close) on #10835, #10768.

## Phase 1 — Workflow gate

- [x] 1.1 In `.github/workflows/apply-deploy-pipeline-fix.yml`, insert step
  `Post-apply full-root drift plan` (`id: drift_plan`) immediately BEFORE the
  `Auto-close any open drift issues for this stack` step:
  - `if:` = `success() && env.PLAN_HAS_CHANGES == 'true' && (steps.infra_config_gate.outputs.verdict == 'verified' || steps.infra_config_gate_pass2.outputs.verdict == 'verified')`
  - `working-directory: ${{ env.INFRA_DIR }}`
  - `env:` DOPPLER_TOKEN / DOPPLER_PROJECT=soleur / DOPPLER_CONFIG=prd_terraform
  - `run:` — `set +e`; capture
    `PLAN_OUTPUT=$(doppler run --preserve-env --name-transformer tf-var -- terraform plan -detailed-exitcode -no-color -input=false -var="ssh_key_path=${CI_SSH_PUB}" 2>&1)`;
    `EXIT_CODE=$?`; `set -e`; write `exit_code=$EXIT_CODE` to
    `$GITHUB_OUTPUT`; `case` on exit code → `::notice::` (0/2) /
    `::error::` (other); append only `grep -E '^Plan: [0-9]+ to '` of the
    output to `$GITHUB_STEP_SUMMARY`. Never echo raw plan output (#11294).
  - Comment block above the step: THIRD EVIDENCE note per plan.
- [x] 1.2 Extend the close step's `if:` with
  `steps.drift_plan.outputs.exit_code == '0'` (before the verdict
  disjunction); extend its comment block to name the fresh-plan gate.
- [x] 1.3 `scripts/infra-drift-autoclose.sh` — update `do_close()` comment
  text to cite the fresh full-root plan ("a fresh full-root plan run by this
  job after the apply read no changes"); update the header decision-
  contract comment. No classifier or slug changes.

## Phase 2 — Tests (write RED first)

- [x] 2.1 `apps/web-platform/infra/infra-config-gate.test.sh` — AC18 EXPECT:
  update the `Auto-close any open drift issues for this stack` entry to the
  new `if:` and add a `Post-apply full-root drift plan` entry (same `if:`
  shape as the close step). Run: `bash apps/web-platform/infra/infra-config-gate.test.sh`.
- [x] 2.2 `scripts/infra-drift-autoclose.test.sh` — extend `wiring_check`
  (or a sibling assert in the same file): `drift_plan` exists as a step,
  precedes the close step, `run:` contains `plan -detailed-exitcode`, no
  `-target`, `working-directory` is `apps/web-platform/infra`, and it writes
  `exit_code` to `$GITHUB_OUTPUT`. Add the seeded-broken-fixture harness row
  (Guard-1 row 7). Run: `bash scripts/infra-drift-autoclose.test.sh`.
- [x] 2.3 Mutation spot-check: the Guard Contract matrix rows 1–6 each drive
  a suite RED before finalizing.

## Phase 3 — Issue bookkeeping (code-side only; no terraform against prod)

- [x] 3.1 PR body: `Closes #9061` ONLY — no `Closes`/`Fixes` for #10835 or
  #10768. Include the #10928 coordination note and the "#10678 owns the
  record" line.
- [x] 3.2 Post a comment on #10835 and #10768: residual is expected —
  `hcloud_server.inngest` replace is owned by the host-replace window
  (#10966 Guard 3 prework, epic #10390);
  `cloudflare_record.google_gws_recovery` resolves when PR #10678 merges;
  the new auto-close gate (#9061 fix) will close them only after a
  full-root plan reads clean.
- [x] 3.3 (Optional, note only) Cross-link on PR #10678 that its merge
  clears the record arm of the standing drift delta.

## Phase 4 — Verify

- [x] 4.1 `bash scripts/infra-drift-autoclose.test.sh` green.
- [x] 4.2 `bash apps/web-platform/infra/infra-config-gate.test.sh` green.
- [x] 4.3 YAML sanity: the workflow still parses (the test files parse it
  via pyyaml — a parse failure reds them).
- [x] 4.4 Confirm no raw plan output can reach logs (grep the new step's
  `run:` for unfiltered `PLAN_OUTPUT` echo).
