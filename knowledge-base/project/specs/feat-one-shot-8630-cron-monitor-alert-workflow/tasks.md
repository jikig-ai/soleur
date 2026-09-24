# Tasks: route Sentry cron-monitor failures to an email alert workflow (#8630)

Plan: `knowledge-base/project/plans/2026-09-24-feat-route-cron-monitor-failures-to-email-alert-plan.md`

## Phase 0: Read-only measurement (no Sentry writes)

- [x] 0.1 Read all 59 monitors: status and per-environment `isMuted`. List the muted monitors and the
  unmuted monitors that are red now.
- [x] 0.2 For each muted environment, read the last 20 check-ins. Record the last `ok` and whether
  it is newer than the start of the incident.
- [x] 0.3 On one live cron event, confirm that `evidenceData.detector_id` equals the monitor's
  detector id. If it does not, STOP and return to plan review.
- [x] 0.4 Post M1-M11 and the Phase 0 data as a comment on #8630.

## Phase 1: Guards first (RED)

- [x] 1.1 Guard 1: create `apps/web-platform/test/server/inngest/sentry-cron-monitor-routing-parity.test.ts`.
  It covers matrix rows 1-4, 6, 7, 10 and 11 plus P1-P2 (including a single-line `monitor_ids`),
  through a pure `checkRouting(files)` function with line-anchored parsing, and a failure text that
  names the remedy. Run it RED against the current tree.
- [x] 1.2 Guard 2: add rows to `tests/scripts/test-sentry-alert-reference-gate.sh`:
  - rows 1-3 and 5 through `_red`, expecting rc 1 and the error text. Row 1 uses a reference
    projected from the null-carrying plan. Row 5 asserts the wrong "Set the attribute explicitly"
    hint is absent.
  - row 4 as a direct `jq`, expecting rc 5
  - P1-P2
  - raise `EXPECTED_TESTS`

  Then run it RED.
- [x] 1.2a Guard 3 rows in `tests/scripts/test-sentry-alert-adoption-guards.sh`: matrix rows 1-6
  and must-PASS rows P1-P2 for the address-aware binding gate. Run them RED.
- [x] 1.3 Class A tests in `apps/web-platform/scripts/sentry-monitors-audit.test.sh`:
  - invert T19 with a 1-of-2 fixture: the unrouted slug is listed, the routed one is not
  - add a case where the slug differs from `.name`
  - capture stderr to a file, and check the `::warning::` is there, not in the report, and not in
    the all-routed case
  - add a row for the muted-environment count
- [x] 1.4 Add the Phase 4.4 heartbeat row in `sentry-monitor-iac-parity.test.ts`. Select the step by
  job `drift-check` and name `Sentry check-in (final)`. Assert the `if:` equals the exact expression,
  and that the path is a `matrix.directory` entry.

## Phase 2: Core implementation (GREEN)

- [x] 2.1 Create `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`:
  - an empty `cron_monitor_alert_unrouted` map
  - `sentry_alert.cron_monitor_failure` with an inline `monitor_ids` list of 59 entries, generated
    by the §1.1 command
  - the three lifecycle triggers, `frequency_minutes = 1440`, and `conditions = []`
  - an email action with `issue_owners` and `ActiveMembers`
  - a header carrying the trigger rationale
- [x] 2.1a Guard 3: make `scripts/sentry-monitor-binding-gate.sh` address-aware.
  - `sentry_alert.cron_monitor_failure` must bind a non-empty set of the plan's
    `sentry_cron_monitor` ids, with no `1213799` and no `null`.
  - Every other rule still binds exactly `1213799`.
- [x] 2.2 Add the Guard 2 floor in `tests/scripts/lib/sentry-alert-projection.jq` `tf_rule`. Leave
  `def excluded` untouched. The message avoids the substring "unknown at plan time". Add a matching
  `case` arm in `scripts/sentry-alert-reference-gate.sh`.
- [x] 2.3 Class A in `sentry-monitors-audit.sh`:
  - list the unrouted slugs through `cron_detector_slugs`
  - count muted environments from the `monitors/` payload
  - add a stderr `::warning::` outside the report redirect
  - reword the report
- [x] 2.4 In `.github/workflows/scheduled-terraform-drift.yml`, change the final heartbeat to
  `if: always() && matrix.directory != 'apps/web-platform/infra/sentry'`.
- [x] 2.5 Run `terraform fmt -check` and `terraform validate` (`init -backend=false`) on the sentry root.

## Phase 3: Reference, counts and docs

- [x] 3.1 Push, download the `sentry-alert-reference-expected-<run>` artifact, and commit
  `alert-reference.json` (AC6: one added key).
- [x] 3.2 README:
  - change 33 to 34 `sentry_alert` rules
  - add a routing note to the 59-cron-monitors bullet
  - add an "Adding or removing a cron monitor" procedure using the two-PR rule, including recovery
    when a monitor is deleted outside Terraform
- [x] 3.3 Add a pointer paragraph to the `cron-monitors.tf` header (comments only).
- [x] 3.4 Bump `BASELINE_DECLARED_PROBES` from 24 to 25 in
  `plugins/soleur/test/preflight-discoverability-test.test.ts`, with a PLACEMENT/TRUTH/NO SUBSTITUTE
  comment.
- [x] 3.5 Phase 5 runbook edits:
  - `cloud-scheduled-tasks.md:527-529`: the claim becomes routed-but-muted
  - the §Alerting paragraph: add a sentence that a persistent failure emails once
  - fix any other hit about a muted monitor
- [x] 3.6 Fix the `model.c4:764` `sentry -> founder` edge prose, then run the c4-count-parity,
  c4-code-syntax and c4-render tests.
- [x] 3.7 Append the ADR-031 amendment (decisions only, with a link to the plan). The ADR diff must
  be additions only.
- [x] 3.8 Muted-monitor decisions: record them on #8630. If any monitor has recovered, file one
  "unmute" tracking issue and reference it as `Tracks #N`.

## Phase 4: Verification

- [x] 4.1 Before every push:
  - `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"`
  - `bash scripts/lint-diagnosis-claims.sh`
- [ ] 4.2 AC1-AC13 pre-merge checks. `plan_pr` must show exactly one create and no other change.
- [ ] 4.3 PR body: its first line is the production-mutation statement, it lists the edited runbook
  lines, and it references `Closes #8630`.
- [ ] 4.4 Post-merge checks:
  - AC14: the apply and the fidelity probe are green
  - AC15: Class A reads 0
  - AC16: a named watchdog fires within 24 h
  - AC17: dispatch the drift workflow once
