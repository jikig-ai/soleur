# Tasks: inngest-provision-failure Sentry alert (#9176)

Plan: `knowledge-base/project/plans/2026-09-30-feat-inngest-provision-failure-sentry-alert-plan.md`

## Phase 1: Setup (RED)

- [ ] 1.1 Create `apps/web-platform/test/sentry-inngest-provision-failure-alert-op-contract.test.ts`,
  modeled on `sentry-image-freshness-alert-op-contract.test.ts`. The file carries rows T1–T8 from
  the plan.
- [ ] 1.2 Keep the test app-local. It reads only `../infra/...`, so do NOT add it to
  `REPO_WIDE_SUITES`.
- [ ] 1.3 Run it on the unchanged tree and confirm it is RED (T1: resource absent).

## Phase 2: Core Implementation (GREEN)

- [ ] 2.1 Append `sentry_alert.inngest_provision_failure` to `apps/web-platform/infra/sentry/issue-alerts.tf`
  after `image_freshness_mismatch`, with its comment block. The rule uses `stage in` +
  `detail nc`, `all`, `value = 0`, and `frequency_minutes = 120`.
- [ ] 2.2 Add `"inngest-provision-failure"` to `alert-reference.json`, keeping keys sorted and
  conditions in `sort_by(tostring)` order (`detail` first). Validate with the projection jq
  (`--arg side reference`).
- [ ] 2.3 Update the README counts: 37 → 38 (both the total and the `sentry_alert` count),
  35 → 36, and 34 → 35. Add `#9176` to the issue list and to the history paragraph.
- [ ] 2.4 Run the new vitest (GREEN), T25 (`apps/web-platform/scripts/sentry-monitors-audit.test.sh`),
  `terraform fmt -check`, and `terraform validate` (`init -backend=false`).

## Phase 3: Docs

- [ ] 3.1 Runbook `inngest-server.md`:
  - Update the stage-table rows.
  - Add an `inngest-provision-failure` page-reading block, with:
    - a `why=` map, including a catch-all row for any other stage;
    - read commands for both stages;
    - the note that a degraded host pages once;
    - the throttle masking window;
    - the quiet lever. Change it only through Terraform (`enabled = false` plus reference regen),
      never in the UI.
  - Add stage rows for `bootstrap-exit-<rc>` and `bootstrap-failure-journal`, plus a `life.txt`
    recipe variant that prints `.detail`.
- [ ] 3.2 ADR-257: add in-place `Superseded 2026-09-30 (#9176)` pointers under Decision 5 and under
  the "Non-pull failures do not page" consequence.
- [ ] 3.3 In `model.c4`, change "34 of the 36" to "35 of the 37", then run
  `bash scripts/regenerate-c4-model.sh` and commit `model.likec4.json`.

## Phase 4: Testing and Ship

- [ ] 4.1 Run mutation rows M1–M8 and H1–H3 locally, and confirm each reddens, or stays green for
  H2, as the plan states.
- [ ] 4.2 Push, then confirm CI `plan_pr` shows the reference gate green, CREATE = exactly the new
  rule, and destroy = 0.
- [ ] 4.3 PR body:
  - First line: "Merging auto-applies one additive Sentry alert rule (`apply-sentry-infra.yml`), and
    nothing else."
  - `Closes #9176`.
  - Note that the rule arms dark until the next inngest-host-replace.
  - DC-1 (degraded bootstrap paging).
- [ ] 4.4 Post-merge:
  - Check that the `apply-sentry-infra.yml` run for the merge SHA succeeds.
  - Run the AC-post-2 live projection diff against `alert-reference.json`. It is read-only and
    uses `SENTRY_ISSUE_RO_TOKEN`.
