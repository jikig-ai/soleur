# Tasks — fix(infra): web-1's luks-monitor.timer was never installed

Plan: `knowledge-base/project/plans/2026-09-27-fix-luks-monitor-host-timer-never-installed-plan.md`
Ref: #8706 (closed by the follow-through after three observed nights, not by the PR)

## Phase 0 — Preconditions

- [ ] 0.1 Re-read the root-cause evidence: `gh run view 36005279546 --log | grep -E 'timers listed|UnitFileState|ActiveState'`.
- [ ] 0.2 Better Stack's API docs list no min/max for `query_period` (checked 2026-09-27); keep 97200 unless the live API refuses it, then switch to 86400 + `confirmation_period = 7200` before merge.
- [ ] 0.3 Measure current floors before editing them: `web-host-provisioner-parity.test.sh` G2 block count, `terraform-target-parity.test.ts` SSH-provisioned count, `BASELINE_DECLARED_PROBES`.

## Phase 1 — Tests first (RED)

- [ ] 1.1 Create `apps/web-platform/infra/luks-monitor-install.test.sh` with Guard 1's static half (alert predicate, needle cross-checked against `luks-monitor.sh`'s `OK:` string), Guard 2 (installer: trigger/source set equality, arm-before-kick order, destinations equal to the cutover tail's, HCL-lexing extractor reused from an existing suite) and Guard 3 (census of env-file writers per provisioner block, following delivered scripts, floor 2; plus the plan's same-bytes procedure: extract the inline writer, decode HCL strictly, substitute a synthesized DSN, rewrite the path to scratch, run under `sh` and `umask 022`). Only rc 1 counts as a caught mutation; rc ≥ 2 is an instrument failure.
- [ ] 1.2 Register it in `apps/web-platform/infra/suite-shard-legs.tsv`; confirm it runs RED.

## Phase 2 — Terraform installer

- [ ] 2.1 Add `terraform_data.luks_monitor_install` to `apps/web-platform/infra/workspaces-luks.tf` (trigger = the four file hashes + DSN hash; `depends_on` token installer + `journald_persistent`; precondition = the `inngest-host.tf` expression, empty allowed; sibling `connection` + `script_path = "/root/tf-luks-monitor-%RAND%.sh"`; provisioners files-into-place → counts-only diagnostic → hardened DSN writer with exit codes 10-16 → diagnostic → chmod/daemon-reload/literal `systemctl enable --now luks-monitor.timer`/assert/kick → state print; comment naming the emit-hash cost).
- [ ] 2.1b Add the same `script_path` to `luks_monitor_token_install`'s connection (connection-only edit; does not re-fire it).
- [ ] 2.2 Add `-target=terraform_data.luks_monitor_install` to the SSH apply step of `.github/workflows/apply-web-platform-infra.yml`.
- [ ] 2.3 Bump `FLOOR_BLOCKS` (web-host-provisioner-parity) and `MIN_SSH_PROVISIONED` (terraform-target-parity) to the measured values with `#8706` comments.
- [ ] 2.4 Update `web-host-provisioner-parity-mutation.test.sh` row G2-3's expected text `swept only 2` → `swept only 3` and its comment (#8706).

## Phase 3 — Liveness alert

- [ ] 3.1 Add `local.luks_monitor_host_timer_sql`, `logtail_exploration.luks_monitor_host_timer_dark` and `logtail_exploration_alert.luks_monitor_host_timer_dark` to `apps/web-platform/infra/betterstack-logs-alerts.tf` under their own `# ── #8706:` section header, with a plain-language `incident_cause`.
- [ ] 3.2 Add both MAIN-plan `-target` lines to `apply-web-platform-infra.yml`.
- [ ] 3.3 Check Better Stack's first-evaluation behaviour for a new alert; re-run the pre-merge live probe (as written, control A, control B) and keep the output for the PR body.

## Phase 4 — Follow-through

- [ ] 4.1 Create `scripts/followthroughs/luks-monitor-host-timer-8706.sh` (positive control first, `toHour(dt, 'UTC') = 0` host-unit rows per UTC day, dates and counts only; prints `HOST_TIMER_PASS nights=3` and exits 0 only on 3 consecutive days; exit 2 on transient).
- [ ] 4.2 Run it locally with Doppler credentials; expect the positive-control line, a `FAIL` line, exit 1.
- [ ] 4.3 Bump `BASELINE_DECLARED_PROBES` in `plugins/soleur/test/preflight-discoverability-test.test.ts` with its required comment.

## Phase 5 — Records

- [ ] 5.1 ADR-119 addendum (2026-09-27): Terraform owns the monitor units, emit helper and the DSN line on web-1; §(e) mount-gate claim stands; immutable-redeploy deviation under ADR-154; proof-boundary qualification; split DSN ownership row; placement rationale; emit fallback; the never-executed arming line; precondition blast-radius choice; the dead-man gap (and file its tracking issue).
- [ ] 5.1b ADR-117 amendment: evidence in never-executed code as a third uncovered state; `terraform_data` + target-parity closes it.
- [ ] 5.1c `workspaces-luks-verify.yml`: one informational `systemctl show … luks-monitor.timer luks-monitor.service` line after the probe, outside the classifier; keep `workspaces-luks-verify-workflow.test.sh` green.
- [ ] 5.1d `workspaces-luks-emit.sh`: `SOLEUR_WORKSPACES_LUKS_EMIT_SKIPPED reason=no_dsn|send_failed` markers via `logger` (luks-monitor tag, existing tag convention); keep `vector-pii-scrub.test.sh` and `luks-monitor.test.sh` green.
- [ ] 5.2 `plugins/soleur/lib/heartbeat-manifest.ts`: `workspaces_luks` evidence → `workspaces-luks.tf` (pattern `systemctl enable --now luks-monitor.timer`, 1-2 code occurrences), comment, `exempt_reason`, and a decision on `arming_pending`.
- [ ] 5.3 Runbook `workspaces-luks-cutover-6604.md`: rewrite the "Two independent pushers" paragraph (link the ADR addendum), add 00:00-00:35 UTC to the token-rotation no-merge window, add the alert to failure signals with a three-branch no-SSH decode row, update the DSN-line text.
- [ ] 5.4 `runbooks/betterstack-log-query.md`: standing-alarm row.
- [ ] 5.5 `luks-monitor-token-refresh.sh`: comment pointer only.

## Phase 6 — Verify

- [ ] 6.1 Run every suite listed in the plan's Pre-merge Acceptance Criteria, plus `terraform validate`, `python3 scripts/lint-encryption-posture.py`, `bash plugins/soleur/test/c4-count-parity.test.sh`, and markdownlint on the edited docs.
- [ ] 6.2 PR body: first line says merging installs the probe on web-1 and creates the alert; `Ref #8706`; live-probe output; the floors/baselines moved; follow-through directive + label on #8706; render `decision-challenges.md`.
- [ ] 6.3 After merge (automated reads): apply log shows the unit loaded/enabled/active with a 00:00-00:30 UTC next elapse and the "after" diagnostic (`DOPPLER_TOKEN` 1, `SOLEUR_SENTRY_DSN` 1, 600, root); a host-unit `OK:` row within 15 minutes; any merge-time alert incident resolves; the next verify run prints `UnitFileState=enabled`.
