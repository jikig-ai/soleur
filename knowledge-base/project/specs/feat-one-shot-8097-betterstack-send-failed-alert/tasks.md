# Tasks: page on `SOLEUR_*_SEND_FAILED` / `SOLEUR_*_REFUSED` rows (Better Stack Logs alert, #8097)

Plan: `knowledge-base/project/plans/2026-09-12-feat-betterstack-send-failed-alert-rule-plan.md`
Branch: `feat-one-shot-8097-betterstack-send-failed-alert` — issue #8097 (PR body uses `Ref #8097`; closure is the follow-through's verdict).

## Phase 0: Preconditions (verify before any edit)

- [ ] 0.1 `gh issue view 8097 --json state` → `OPEN`.
- [ ] 0.2 Add `logtail = { source = "BetterStackHQ/logtail", version = "~> 11.2" }` + `provider "logtail" { api_token = var.betterstack_api_token }` to `apps/web-platform/infra/main.tf`; run `cd apps/web-platform/infra && terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`; confirm the new `betterstackhq/logtail` lockfile block (`version = "11.2.0"`, 2 `h1:`) and that every sibling block is byte-unchanged.
- [ ] 0.3 `terraform init -backend=false -input=false && terraform validate` green with the exact static `escalation_target` block written (null-sibling ternary, no `dynamic`).
- [ ] 0.4 Canonical triplet plan (`export AWS_*` from Doppler `prd_terraform`; `terraform init -input=false`; `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan -target=logtail_exploration.monitor_send_failed -target=logtail_exploration_alert.monitor_send_failed`) → exactly `2 to add`, data source resolves `id = "2457081"`. No apply from the workstation.
- [ ] 0.5 ADR ordinal probe across ALL `origin/*` refs (plan §Phase 0) → ADR-218 provisional; re-run at /ship.
- [ ] 0.6 Read `plugins/soleur/test/terraform-target-parity.test.ts` (name list + `TEST_FLOOR`), `scripts/lint-orphan-test-suites.test.sh`, `apps/web-platform/infra/web-host-provisioner-parity.test.sh` header, `.github/workflows/infra-validation.yml` `deploy-script-tests` job + `paths:` filters.

## Phase 1: RED — drift guard first

- [ ] 1.1 Write `apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh` per Guard 1 (predicate anchors after whitespace normalization; needle list parsed as a set == `{_SEND_FAILED, _REFUSED}`; four scripts' `emit_refusal()` contain `logger -p user.crit`; every FAILED/REFUSED literal matches a needle, every `*SKIPPED*` literal matches none; probe line in `server.tf` is `-p user.crit` + needle-matched; ≥ 6 marker floor; exactly one non-empty `sql_query`). Run → FAIL.
- [ ] 1.2 Wire it as a step in `infra-validation.yml`'s `deploy-script-tests` job (next to the provisioner parity guard); add `apps/web-platform/test/infra/**` to both `paths:` filters; `bash scripts/lint-orphan-test-suites.test.sh` green.

## Phase 2: Terraform — alert

- [ ] 2.1 `apps/web-platform/infra/betterstack-logs-alerts.tf`: `data "logtail_source" "vector_prd"` (by `table_name`), `locals.monitor_send_failed_sql` (heredoc, the live-probed predicate), `locals.monitor_send_failed_probe_rev = "1"`, `logtail_exploration.monitor_send_failed` (`name`, `chart line_chart`, `query sql_expression`, `variable source`, `team_name = "Your team"`), `logtail_exploration_alert.monitor_send_failed` (`exploration_id`, `name = "soleur-monitor-send-failed-prd"`, threshold `higher_than` 0, `check_period 60`, `query_period 300`, `confirmation_period 0`, `recovery_period 600`, `on_missing_data treat_as_zero`, `paused = false`, `email = true`, `incident_cause` with full GitHub runbook URL, `metadata.runbook`, static `escalation_target` ternary; NO `aggregation_interval`/`series_names*`/`source_variable`). Header comment: ADR-218, SKIPPED-exclusion rationale, 5-line "to add another Logs alert" checklist, "changed the SQL? bump the rev".
- [ ] 2.2 `.github/workflows/apply-web-platform-infra.yml` main plan allow-list: `-target=logtail_exploration.monitor_send_failed` + `-target=logtail_exploration_alert.monitor_send_failed` after `-target=betteruptime_team_member.ops`.
- [ ] 2.3 Guard 1 → GREEN; `bun test plugins/soleur/test/terraform-target-parity.test.ts` green (#5566 coverage).

## Phase 3: Terraform — probe + parity

- [ ] 3.1 `server.tf`: `terraform_data.send_failed_alert_probe` after `disk_monitor_install` (same multi-line connection block; `triggers_replace = local.monitor_send_failed_probe_rev`; one `remote-exec` line: `logger -p user.crit -t disk-monitor 'SOLEUR_DISK_MONITOR_SEND_FAILED channel=resend http_code=000 rc=7 synthetic=1 probe_rev=${local.monitor_send_failed_probe_rev}'`).
- [ ] 3.2 SSH apply list: `-target=terraform_data.send_failed_alert_probe` after `-target=terraform_data.inngest_consumer_probe_install`.
- [ ] 3.3 `terraform-target-parity.test.ts` name list/floor if exact; `web-host-provisioner-parity.test.sh` header 15 → 16; `infra-validation.yml` step name "(#7000 all 15 SSH provisioners)" → 16; both suites green.
- [ ] 3.4 `terraform fmt -check -recursive` + `terraform validate` green.

## Phase 4: Follow-through, self-health arm, runbook, ADR/C4

- [ ] 4.1 `scripts/followthroughs/send-failed-alert-probe-8097.sh`: ordered checks (alerts GET → `alert_absent`/`alert_paused`; positive control → `channel_dark`; 14-day hot ∪ archive readback keyed on `synthetic=1 probe_rev=<rev>` with `<rev>` grepped from the checkout, `host` reported; incidents GET matched on `name` OR `cause` anchored on the row's `dt` − 600 s; print `nonsynthetic_rows`, incident fields carried); exit 0 / 3 / 5 only (never 1).
- [ ] 4.2 `scripts/followthroughs/send-failed-alert-probe-8097.test.sh`: three stubbed cases (pass→0, channel_dark→3, one exit-5 verdict).
- [ ] 4.3 `plugins/soleur/scripts/reconcile-live-heartbeats.ts`: one `logs_alert` arm (GET `/api/v2/alerts`; absent or `paused` → `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH kind=logs_alert name=… paused=… reason=…`); one new case in `plugins/soleur/test/heartbeat-live-reconcile.test.ts`.
- [ ] 4.4 Runbook `knowledge-base/engineering/operations/runbooks/monitor-send-failed-alert.md` (step 0 `/soleur:go`; step 1 readback SQL; decode table; unit table; `synthetic=1` semantics; `host` vs stale `host_name`; auto-resolve ≠ fixed; `_HALT` does not page; re-fire = `probe_rev` bump, one page; `[ack-destroy]`; `paused_reason` + `kind=logs_alert` mismatch issue; no SSH). `python3 scripts/lint-infra-no-human-steps.py` on it.
- [ ] 4.5 `betterstack-log-query.md` §"Standing alarms": native-alert row + provider-gap correction.
- [ ] 4.6 ADR-218 via `/soleur:architecture` (decision, routing contract, `treat_as_zero`, `probe_rev` trigger, apply-path verification shape, `_HALT` exclusion + UC-1 pointer, opt-in policy for future PRIORITY-2 classes, one sentence on ADR-198's stale premise + deferral issue for `logtail_source`); ADR-096 amendment sentence; `model.c4` `betterstack` element one clause; C4 suites + `bash plugins/soleur/test/c4-count-parity.test.sh` green; `bash scripts/check-adr-ordinals.sh` green.
- [ ] 4.7 File the `logtail_source` deferral issue (`wg-when-deferring-a-capability-create-a`) and reference it from ADR-218.
- [ ] 4.8 Issue #8097 body: `<!-- soleur:followthrough script=scripts/followthroughs/send-failed-alert-probe-8097.sh earliest=<merge + 30 min> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD,BETTERSTACK_API_TOKEN -->` + `follow-through` label.

## Phase 5: Verification (pre-merge ACs)

- [ ] 5.1 AC1 guard green; all six mutation rows RED on a scratch copy, H2/H3 PASS (evidence in PR body).
- [ ] 5.2 AC2-AC8a per plan (`actionlint` on the two touched workflows; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`; `git diff --stat` on the lockfile shows additions only).
- [ ] 5.3 PR body `Ref #8097`; `decision-challenges.md` (UC-1, T-1, T-2) rendered by /ship Phase 6.

## Phase 6: Post-merge (automated)

- [ ] 6.1 AC9: apply run shows both `logtail_*` creations + the probe creation; `GET /api/v2/alerts` → `paused: false`; next untargeted drift plan `0 to change`.
- [ ] 6.2 AC10: sweeper runs the follow-through after `earliest=` → `verdict=pass` → #8097 closed. Otherwise #8097 stays open with the sweeper's ACTION REQUIRED / CANNOT ESTABLISH comment.
