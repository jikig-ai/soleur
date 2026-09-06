# Tasks — feat-one-shot-7826-sentry-adoption-cleanup

Plan: `knowledge-base/project/plans/2026-09-06-chore-sentry-adoption-cleanup-plan.md`
Closes #7826, #7829, #7834. (#7836 split to its own PR — see
`knowledge-base/project/plans/2026-09-06-chore-r2-rollback-runbook-repair-plan.md`.)

## Phase 0 — Measure before deleting (BLOCKING for #7826 only)

- [ ] 0.1 `terraform init -lockfile=readonly` in `apps/web-platform/infra/sentry` (leave the
      committed `.terraform.lock.hcl` unmodified)
- [ ] 0.2 **Limb 1a** — `terraform state list | grep -c '^sentry_alert\.'` → 27, and diff the 27
      state addresses against the 27 `resource "sentry_alert"` labels (must be empty both ways)
- [ ] 0.3 **Limb 1b** — `terraform state list | grep '^sentry_issue_alert\.'` returns exactly
      `auth_per_user_loop`, `git_data_boot_warning`, `sandbox_startup_failure`, and no address
      matching any of the 27 `removed{}` from-labels
- [ ] 0.4 **Limb 2** — run `scripts/sentry-alert-live-fidelity.sh`; record the verdict
- [ ] 0.5 If any limb fails: execute the abort contract — strip `7826` from the plan frontmatter
      `closes:` AND the PR body, post the measurement as a comment on #7826, continue with
      #7829 + #7834 only, and use the reduced AC set (AC7–AC12, AC15–AC16)

## Phase 1 — Cohort audit (re-confirm the plan-time measurement)

- [ ] 1.1 `grep -l 'uses: ./.github/actions/sentry-heartbeat' .github/workflows/*.yml` (11 steps
      across 10 workflows; the bare string `sentry-heartbeat` pulls 2 prose-only false members)
- [ ] 1.2 Per job, confirm: `continue-on-error: true` 11/11, `if:` contains `always()` 11/11,
      terminality NOT universal, step name `Sentry check-in (final)` 10/11

## Phase 2 — #7829 verification record

- [ ] 2.1 Add the comment above `resource "sentry_alert" "byok_cap_exceeded"` citing #7829, the
      **dated** M3 measurement (endpoint, `"raw":null` / `"schema":null`, the passing control on
      `/projects/jikigai-eu/web-platform/`), and the Rule 1 / Rule 2 split
- [ ] 2.2 Do NOT cite the line-150 comment — it belongs to `git_data_boot_warning`
- [ ] 2.3 Change no value. AC6 asserts `git diff … | grep -c '^[+-].*fallthrough_type'` → 0

## Phase 3 — #7834, contract-first and test-first

- [ ] 3.1 Add `sentry_cron_monitor "scheduled_sentry_alert_drift"` to `cron-monitors.tf`:
      `name = "scheduled-sentry-alert-drift"`, `crontab = "15 7 * * *"`, `timezone = "UTC"`,
      both thresholds 1, house attribute order
- [ ] 3.2 Pin `checkin_margin_minutes` / `max_runtime_minutes` explicitly (dispatch-hybrid
      generosity — siblings use 60/15 and 90/65); comment that `max_runtime_minutes` is inert for a
      single terminal heartbeat
- [ ] 3.3 Add `scheduled-sentry-alert-drift` to `NON_INNGEST_MONITORS` in
      `function-registry-count.test.ts` with the class rationale + why a dispatcher
      `SENTRY_MONITOR_SLUG` would be actively wrong
- [ ] 3.4 **Write the new parity assertions BEFORE the workflow step** and observe them RED against
      the real absence: cohort-wide `continue-on-error` + contains-`always()`, keyed on
      `uses: ./.github/actions/sentry-heartbeat`; this-workflow-scoped terminality, exact step name,
      and the `status:` step-id reference. Job-scoped and multi-heartbeat-aware.
- [ ] 3.5 Add the terminal `Sentry check-in (final)` step: `if: always()`,
      `continue-on-error: true`, `monitor-slug: scheduled-sentry-alert-drift`, allowlist status
      (`clean`/`drift` → `ok`, else `error`)
- [ ] 3.6 Add the drift backstop: `drift` + drift-filer step outcome `failure` → `status=error`
- [ ] 3.7 Delete the `NO SENTRY CRON HEARTBEAT` paragraph from the workflow header
- [ ] 3.8 Update the matching paragraph in `cron-sentry-alert-drift.ts`; state the manual-trigger
      limit (the monitor proves a run happened in the window, not that the schedule fired)

## Phase 4 — #7826 deletion, last

- [ ] 4.1 Delete from the banner *"Forget the legacy addresses WITHOUT destroying the live objects."*
      through EOF, including the preceding blank line. New last line = the closing `}` of
      `resource "sentry_alert" "zot_mirror_fallback_rate"` (which IS the final resource block)
- [ ] 4.2 Correct all three header claims: `ADOPTION MECHANISM` → past tense; delete *"stay in config
      until"*; fix the *"27 of the 29 … Two remain"* enumeration to three, naming
      `git_data_boot_warning`
- [ ] 4.3 Record in the header that each address's adopted live id now lives only in state and in the
      committed capture
- [ ] 4.4 Amend `ADR-031-sentry-as-iac.md`: past-tense *"the root is not reproducible from zero until
      they are removed"* and *"The blocks stay in config until the post-merge verification passes"*;
      dated note citing #7826
- [ ] 4.5 `apps/web-platform/infra/sentry/README.md` — `27 + 2` → `27 + 3`; resolve the file's
      existing self-contradiction against its own line 5
- [ ] 4.6 `scripts/sentry-issue-alert-create-tripwire.sh` — error text two → three, naming
      `git_data_boot_warning` (prose only; the guard gates on any create, not a count)
- [ ] 4.7 `terraform fmt`

## Phase 5 — Verification

- [ ] 5.1 Run the affected suites (`function-registry-count`, `sentry-monitor-iac-parity`)
- [ ] 5.2 `terraform fmt -check -recursive` over `apps/web-platform/infra/**`
- [ ] 5.3 Mutation matrix rows 3, 4, 5 (move / drop-`always()` / rename-`id`), each observed RED,
      then restored. Row 5 must red while 3 and 4 stay green
- [ ] 5.4 Harness: stub the slug extractor to `[]`, confirm the anti-vacuity case reds
- [ ] 5.5 Must-PASS control: `main-health-monitor.yml` passes every assertion old and new
- [ ] 5.6 Read `plan_pr`: assert the literal `Plan: 1 to add, 0 to change, 0 to destroy` **from a job
      that ran**; on `1 to change`, identify the resource rather than assuming a #7829 flip

## Phase 6 — Ship gates

- [ ] 6.1 AC7b — post the M3 evidence + verdict as a closing comment on #7829
- [ ] 6.2 AC18 merge gate — do NOT arm auto-merge until either (a) PR 7866 merged AND a
      `workflow_dispatch` of `apply-sentry-infra.yml` on main reports AC17 green with derived counts,
      or (b) `gh workflow run scheduled-sentry-alert-drift.yml` reaches a `clean` verdict.
      Merging 7866 alone fires NO apply (its file is outside the workflow's `paths:` filter)
- [ ] 6.3 If neither is available, HOLD and tell the operator with a named next action
