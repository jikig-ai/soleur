# Tasks — fix(infra): web-1's luks-monitor.timer was never installed

Plan: `knowledge-base/project/plans/2026-09-27-fix-luks-monitor-host-timer-never-installed-plan.md`
Ref: #8706 (closed by the follow-through after three observed nights, not by the PR)

## Phase 0 — Preconditions

- [ ] 0.1 Re-read the root-cause evidence: `gh run view 36005279546 --log | grep -E 'timers listed|UnitFileState|ActiveState'`.
- [ ] 0.2 Check the Better Stack alert API docs for accepted `query_period` values; pick 97200 (or the 86400 + `confirmation_period = 7200` fallback) before writing the alert.
- [ ] 0.3 Measure current floors before editing them: `web-host-provisioner-parity.test.sh` G2 block count, `terraform-target-parity.test.ts` SSH-provisioned count, `BASELINE_DECLARED_PROBES`.

## Phase 1 — Tests first (RED)

- [ ] 1.1 Create `apps/web-platform/infra/luks-monitor-install.test.sh` with Guard 1's static half (alert predicate, needle cross-checked against `luks-monitor.sh`'s `OK:` string), Guard 2 (installer: trigger/source set equality, arm-before-kick order, destinations equal to the cutover tail's, HCL-lexing extractor reused from an existing suite) and Guard 3 (census of env-file writers + the inline DSN writer run against a synthesized temp file), about 18 mutation rows in total plus an anti-vacuity floor.
- [ ] 1.2 Register it in `apps/web-platform/infra/suite-shard-legs.tsv`; confirm it runs RED.

## Phase 2 — Terraform installer

- [ ] 2.1 Add `terraform_data.luks_monitor_install` to `apps/web-platform/infra/workspaces-luks.tf` (trigger = the four file hashes + DSN hash; `depends_on` token installer + `journald_persistent`; precondition = non-empty + the `inngest-host.tf` character-class DSN regex; sibling `connection`; provisioners files-into-place → inline DSN line writer → chmod/daemon-reload/enable/assert/kick → state print; comment naming the emit-hash cost).
- [ ] 2.2 Add `-target=terraform_data.luks_monitor_install` to the SSH apply step of `.github/workflows/apply-web-platform-infra.yml`.
- [ ] 2.3 Bump `FLOOR_BLOCKS` (web-host-provisioner-parity) and `MIN_SSH_PROVISIONED` (terraform-target-parity) to the measured values with `#8706` comments.

## Phase 3 — Liveness alert

- [ ] 3.1 Add `local.luks_monitor_host_timer_sql`, `logtail_exploration.luks_monitor_host_timer_dark` and `logtail_exploration_alert.luks_monitor_host_timer_dark` to `apps/web-platform/infra/betterstack-logs-alerts.tf` under their own `# ── #8706:` section header, with a plain-language `incident_cause`.
- [ ] 3.2 Add both MAIN-plan `-target` lines to `apply-web-platform-infra.yml`.
- [ ] 3.3 Check Better Stack's first-evaluation behaviour for a new alert; re-run the pre-merge live probe (as written, control A, control B) and keep the output for the PR body.

## Phase 4 — Follow-through

- [ ] 4.1 Create `scripts/followthroughs/luks-monitor-host-timer-8706.sh` (positive control first, `toHour(dt, 'UTC') = 0` host-unit rows per UTC day, PASS on 3 consecutive days, exit 2 on transient).
- [ ] 4.2 Run it locally with Doppler credentials; expect the positive-control line, a `FAIL` line, exit 1.
- [ ] 4.3 Bump `BASELINE_DECLARED_PROBES` in `plugins/soleur/test/preflight-discoverability-test.test.ts` with its required comment.

## Phase 5 — Records

- [ ] 5.1 ADR-119 addendum (2026-09-27): Terraform owns the monitor units, emit helper and the DSN line on web-1; placement rationale; emit fallback; the never-executed arming line; the dead-man gap (and file its tracking issue).
- [ ] 5.2 `plugins/soleur/lib/heartbeat-manifest.ts`: `workspaces_luks` evidence → `workspaces-luks.tf`, comment and `exempt_reason`.
- [ ] 5.3 Runbook `workspaces-luks-cutover-6604.md`: rewrite the "Two independent pushers" paragraph, add 00:00-00:35 UTC to the rotation no-merge window, add the alert to failure signals, update the DSN-line text.
- [ ] 5.4 `runbooks/betterstack-log-query.md`: standing-alarm row.
- [ ] 5.5 `luks-monitor-token-refresh.sh`: comment pointer only.

## Phase 6 — Verify

- [ ] 6.1 Run every suite listed in the plan's Pre-merge Acceptance Criteria, plus `terraform validate`, `python3 scripts/lint-encryption-posture.py`, `bash plugins/soleur/test/c4-count-parity.test.sh`, and markdownlint on the edited docs.
- [ ] 6.2 PR body: first line says merging installs the probe on web-1 and creates the alert; `Ref #8706`; live-probe output; the floors/baselines moved; follow-through directive + label on #8706; render `decision-challenges.md`.
- [ ] 6.3 After merge (automated reads): apply log shows the unit loaded/enabled/active with a 00:00-00:30 UTC next elapse; a host-unit `OK:` row within 15 minutes; any merge-time alert incident resolves.
