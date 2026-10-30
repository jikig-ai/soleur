---
title: "fix(observability): replace the once-a-day dead-man logs alerts with archive-fed Better Stack heartbeats"
date: 2026-10-30
slug: deadman-heartbeats-fed-from-archive
branch: fix-observable-deadman-11631
issue: 11631
type: fix
priority: p1-high
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# fix(observability): replace the once-a-day dead-man logs alerts with archive-fed Better Stack heartbeats

Ref #11631 (also the root of the stuck incidents mirrored as #11048 and #11049). Never `Closes`: the PR does not
close the issue, because unpausing the heartbeats and resolving two Better Stack incidents are owner-gated.

## Overview

Two native Better Stack logs alerts, `soleur-luks-monitor-host-timer-dark-prd` (query window 97200 s) and
`soleur-claude-cost-capture-dark-prd` (86400 s), wait for a row that arrives once a day. The live incident
`1023423999` reads `Current value: 0` through 33 nights of passing rows, so the alerts cannot see their row
(the "evaluated over the hot window only" reading is INFERRED, not proven; this design does not depend on it).
The binding CTO ruling (2026-10-30) replaces both with `betteruptime_heartbeat` objects fed hourly by a scheduled
GitHub workflow that reads the archive itself (`remote()` UNION `s3Cluster`) and beats a heartbeat only when a
qualifying row exists inside the old alert's window. No host change; no logs alert above `query_period` 900.

The plan keeps to the ruling and adds only what the repo's own gates force (each is listed with its reason in
`## Scope Check`): a watchdog-dispatch row (CTO-ruled fork, see below), a Sentry cron monitor, `arming_pending`
manifest declarations, the census `INTENDED_DESTROYS` entries, CI registration, and C4/ADR/runbook upkeep. The
unsigned A6 draft in the worktree rides along untouched.

## Research Insights

### Premise validation (Phase 0.6)

- #11631 is OPEN (title matches); #11048 and #11049 are OPEN `[ci/betterstack-incident]` mirror issues. PR #11653
  is this branch's own draft PR (the collision pre-check's one PR hit); the two foreign `test-all.sh` processes
  belong to an unrelated worktree.
- Every cited file exists on this branch: both alerts and their SQL locals in `betterstack-logs-alerts.tf`
  (the `claude_cost_capture_dark` pair after `claude_cost_daily_burn`, and the `#8706` section with `luks_monitor_host_timer_dark`), `betteruptime_heartbeat.inngest_server_probe` in `uptime-alerts.tf`, the manifest row
  at `heartbeat-manifest.ts` (`inngest_server_probe`), the four `-target` lines at
  `apply-web-platform-infra.yml` (the four `-target=logtail_exploration*.{claude_cost_capture_dark,luks_monitor_host_timer_dark}` lines), the stale comment in `workspaces-luks.tf` beginning "The runtime proof that the timer fires is".
- Stale ruling premise found: `scripts/followthroughs/luks-monitor-host-timer-8706.sh` (the pattern the ruling
  cites for measuring archive lag) was DELETED by #10371 per its own `RETIREMENT:` line. Recover the shape from
  `git show cef65a5003^:scripts/followthroughs/luks-monitor-host-timer-8706.sh`; do not expect the file.
- ADR corpus check: ADR-218 (native logs alerts are Terraform-managed) classes both alerts as "absence alarms";
  nothing rejects a heartbeat instead. ADR-248 (watchdog dispatch clock) states GitHub `schedule:` delivers one run
  every 2-7 h and fixes it with a web-server clock; its 2026-10-11 amendment admits a workflow that feeds an
  absence-alerted dead-man heartbeat. ADR-117 (executable heartbeat arming) governs the manifest.
- **Measured 2026-10-30 (read-only `gh run list --event schedule`, 59 gaps each):** hourly `0 * * * *` cron delivery
  for `scheduled-prod-version-drift.yml` and `scheduled-zot-restart-loop.yml`: min 7232 s / 7277 s, median
  15361 s / 16727 s, p90 22911 s / 23118 s, max 25229 s / 25096 s. The ruling's "schedule + workflow_dispatch only"
  trigger cannot hold a 7200 s (luks) or 10800 s (cost) page budget. Ruled by the CTO agent (see
  `decision-challenges.md`): add a `WATCHDOG_DISPATCH_TABLE` row, `intervalMinutes: 60`.
- **Measured 2026-10-30 (read-only `gh run list --workflow scheduled-zot-restart-loop.yml --event workflow_dispatch`, 79 gaps):**
  the watchdog-dispatched path an hourly row actually uses: consecutive run-creation gaps min 0 s (a duplicate
  dispatch), median 3600 s, p90 3639 s, max 3680 s. Adding the measured job-queue tail (max 2438 s, ADR-248) bounds
  beat-to-beat spacing near 6100 s against the 7200 s luks budget (period 3600 + grace 3600): about 1100 s of margin.
  Phase 0 re-measures `workflow_dispatch` gaps and queue; if the observed beat-to-beat maximum exceeds 6500 s, widen
  the luks grace to 7200 (a ruling-sanctioned widening; it costs about one hour of detection on a 27 h window).
- Archive ingestion lag is UNMEASURED (ruling risk). The retired follow-through measured presence, not lag; Phase 0
  below measures it read-only.

### Property list and cut list (Phase 0.6b)

Properties the issue and ruling ask for:

1. A dead or failing nightly host check pages the owner within about the old window plus 1-2 h, from a signal the
   evaluator can see.
2. A healthy night keeps the heartbeat green (no page on a healthy host, no stuck incident).
3. The feeder never keeps a heartbeat alive without a qualifying row (a spurious beat hides exactly what the
   control exists to find) and never beats `/fail`.
4. The two old logs alerts stop existing and no logs alert is ever created with a window above 900 s again.
5. Nothing in the PR touches the host (`luks-monitor.*`, `server.tf`, `cloud-init.yml`).
6. Unpausing, incident resolution, merge and any vendor write stay with the owner.

Mechanisms named in the ask, each against `origin/main`:

| Mechanism | Property | Existing cover |
|---|---|---|
| Heartbeat per dead-man | 1, 2 | `inngest_server_probe` is the exact template (grepped `uptime-alerts.tf`) |
| Feeder script reading the archive | 1, 3 | `scripts/inngest-probe-heartbeat-feeder.sh` is the model; its row predicate is a different signal, so no reuse beyond the shape |
| Hourly workflow + Sentry check-in | 1 | `scheduled-inngest-probe-heartbeat.yml` is the model |
| Delete four resources | 4 | none; this is the removal |
| No-logs-alert-above-900 sentinel | 4 | none (grepped `apps/web-platform/test/infra/*`: per-alert pins only) |
| Host-side ping / hourly host row | 1 | REJECTED by the ruling (needs a `user_data` change = host replace) |

Cut list: none to cut from the ask. Not planned (YAGNI): a `doppler_secret` per heartbeat URL (ruling: optional; the
feeder resolves the URL through the read-only API by exact name, so no consumer would exist); a second feeder
script per target (see `decision-challenges.md`).

### Institutional learnings applied

- `2026-10-11-a-control-that-fails-early-proves-nothing-about-the-checks-after-it.md`: one landing assertion per
  check, one control per check; the harness grades each mutant for its predicted reason.
- `2026-07-18-shared-delivery-substrate-and-reused-heartbeat-url-masking.md`: one heartbeat per dead-man (two
  here), never a shared one; the shared `workspaces_luks` heartbeat cannot tell the host timer from the verify
  job, which is why it is not reused.
- `2026-06-02-verify-terraform-target-set-not-header-prose.md`: the apply `-target` list is an unguarded drift
  surface; assert the two new heartbeat targets and the four retained destroy targets with a test, not a header.
- `2026-06-02-sentry-cron-margin-must-absorb-gha-dispatch-jitter.md` and ADR-248: why the watchdog row exists.
- `2026-10-28-a-comment-sweep-that-names-every-site-still-misses-one.md`: grep the old names and phrasings
  (`luks_monitor_host_timer_dark`, `claude_cost_capture_dark`, `host-timer-dark`, `cost-capture-dark`,
  `27 h`, `97200`) repo-wide before declaring the sweep done.
- `2026-10-12-a-record-pr-for-an-arm-must-sweep-the-claim-and-pin-the-runtime-value.md`: manifest guards assert on
  the imported `MANIFEST`, and a runbook arm block longer than the 30-minute Monitor cap is detached under `setsid`.

## Research Reconciliation — Spec vs. Codebase

| Ruling / brief claim | Reality | Plan response |
|---|---|---|
| "Workflow: `schedule` + `workflow_dispatch` only" feeds an hourly beat | GitHub delivers the hourly cron every 2-7 h (measured); a 7200 s budget is unreachable | CTO-ruled: add the `WATCHDOG_DISPATCH_TABLE` row; the workflow's triggers stay exactly `{schedule, workflow_dispatch}` as the table requires |
| Measure lag with `scripts/followthroughs/luks-monitor-host-timer-8706.sh` | File deleted by #10371 | Phase 0 uses the retired file's raw-SQL shape from git history |
| Files list omits the Sentry monitor, the watchdog row, the census and CI registration | `sentry-monitor-iac-parity.test.ts` fails a `monitor-slug:` with no `sentry_cron_monitor`; `execution-placement`/parity tests read the table; census G4c fails a deleted resource block with no `removed` block unless listed in `INTENDED_DESTROYS`; the apply destroy-guard demands `[ack-destroy]` | Added to Files to Edit with the failing gate named per item |
| `claude_cost_capture_dark` expectations in `inngest-step-524-alert.test.sh` (the ruling cites "~136-425"; locate by the symbol `claude_cost_capture_dark`) | Includes emitter-parity pins (arm B pinned to the credit probe's `CRON_NAME` and op union; marker literals) for the cost predicate | Drop the alert expectations, but MOVE the predicate and emitter pins into the new suite so the predicate is not lost |
| "Never edit them in place" (the alert blocks) | Comment lines inside the #8611 section (the header bullet "(3) claude_cost_capture_dark" and the comment above `claude_cost_daily_burn`'s `on_missing_data`) name `claude_cost_capture_dark` | Delete the blocks; touch only those two comment lines. The dated measurement comment inside the `inngest_luks_key_probe_fail` block (the other open PR's region; it names both retired alerts) stays untouched and is an allowed residual in the old-name sweep |
| Heartbeat rows `paused: true` | Live reconcile alarms `fed-but-paused` for a fed, paused heartbeat without `arming_pending` | Rows carry `arming_pending: { tracking_issue: 11631 }` |

## Open Code-Review Overlap

Two kinds of overlap were checked. Open PR **#11601** (`inngest_luks_key_probe_fail` emitter pinning) edits
`betterstack-logs-alerts.tf` around the `inngest_luks_key_probe_fail` block and its tests. This plan's edits to that
file are deletions of one local (`claude_cost_capture_dark_sql`), two resources (`claude_cost_capture_dark`), the `#8706` section, plus two
comment lines in the #8611 section: no hunk overlaps the `inngest_luks_key_probe_fail` block and its measurement comment. Disposition: **Acknowledge** (keep the hunks disjoint;
a rebase is mechanical). For open `code-review` issues, the implementer runs
`gh issue list --label code-review --state open --json number,title,body --limit 200` and a per-file
`jq --arg path` check over the Files lists at work time and dispositions any hit (fold in / acknowledge / defer) in
the PR body; none was checked at plan time because the GitHub API timed out during the planning run.

## Problem Statement

`betterstack-logs-alerts.tf` carries two dead-man alerts whose rows arrive once a day while the evaluator's window
is only reliably populated for about an hour after a row lands. Result: the alert has read `Current value: 0` and
stayed red on a healthy host since 2026-09-27 (incident 1023423999, #11048), so its state carries no information and
a genuinely dark timer would be indistinguishable from today. The cost-capture sibling (#11049) has the same shape.

## Proposed Solution

```
nightly row --> Vector --> Better Stack Logs (hot ~1 h) --> s3 archive
                                      |                        |
     scheduled-deadman-heartbeat-feeder.yml (hourly, dispatched by the web-server watchdog clock)
        scripts/deadman-heartbeat-feeder.sh <target>
          1. raw SQL (mode 1) via scripts/betterstack-query.sh:
             remote($BS_TABLE) UNION ALL s3Cluster(primary,$BS_TABLE_S3) WHERE _row_type=1,
             window = the OLD alert window, predicate = the OLD alert predicate
          2. n == 0  -> WITHHOLD (exit 3), never /fail
          3. resolve heartbeat by exact name (read-only token); paused -> exit 0, send nothing
          4. beat the heartbeat URL once (2xx) -> exit 0
        sentry-heartbeat check-in (ok only on a deciding exit 0)
Better Stack: betteruptime_heartbeat.{luks_monitor_host_timer, claude_cost_capture}
              period 3600, grace 3600 / 7200, born paused, ignore_changes=[paused]
```

Detection latency: old window + about 1-2 h (27 h + 1-2 h for luks-monitor; 24 h + 2-3 h for cost-capture).
Archive-lag tolerance: for luks-monitor the previous night's row stays inside the 27 h window until at least 2.5 h
after a legitimate 24.5 h gap, so an ingestion lag below about 2.5 h cannot cause a false withhold; cost-capture
markers arrive many times a day. Phase 0 measures the lag and widens the grace only if it exceeds the margin.

## Technical Approach

### Feeder: `scripts/deadman-heartbeat-feeder.sh <target> | --selftest`

Targets (a table in the script; `--selftest` asserts the table is complete):

| target | heartbeat name | window (s) | predicate (moved verbatim from the deleted locals, minus the window conjunct) |
|---|---|---|---|
| `luks-monitor-host-timer` | `soleur-luks-monitor-host-timer-prd` | 97200 | `SYSLOG_IDENTIFIER='luks-monitor'`, `_SYSTEMD_UNIT='luks-monitor.service'`, message `LIKE '%OK: /mnt/data is LUKS-backed%'`, `host_name='soleur-web-platform'` |
| `claude-cost-capture` | `soleur-claude-cost-capture-prd` | 86400 | the `claude_cost_capture_dark_sql` WHERE: cost marker arm (key match, `component='claude-cost'`, `source LIKE 'cron:%'`, non-null `cost_usd`) OR credit-probe RED arm |

Query (raw SQL, mode 1; the helper substitutes `$BS_TABLE_S3` before `$BS_TABLE`):

```sql
SELECT count() AS n, toString(max(dt)) AS newest FROM (
  SELECT dt, raw FROM remote($BS_TABLE)
    WHERE dt > now() - INTERVAL <W> SECOND AND dt <= now() + INTERVAL 300 SECOND
  UNION ALL
  SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3)
    WHERE _row_type = 1 AND dt > now() - INTERVAL <W> SECOND AND dt <= now() + INTERVAL 300 SECOND
) WHERE <predicate> FORMAT JSONEachRow
```

Behavior and contract (modelled on `inngest-probe-heartbeat-feeder.sh`, which stays untouched):

- Marker lines `deadman-feeder: target=<t> verdict=<v> n=<n> newest_dt=<..> age_s=<..>` and `CANNOT BEAT: ...`; the
  raw query output is never echoed; helper stderr goes to a temp file and only a class and length are printed.
- Verdicts: `beat` (exit 0), `qualifying_row_heartbeat_paused` (exit 0, nothing sent), `no_qualifying_row` (exit 3,
  the dead-man's input is absent), `query_failed` (exit 3, the query could not be run or its answer could not be
  read), `beat_failed` (exit 4: heartbeat not unique, URL shape, paused not boolean, API or delivery fault),
  usage 64, xtrace refusal 78. The EXIT trap rewrites anything outside that set, and a 0 that no verdict produced,
  to 3. Exit 0 means exactly `{beat, qualifying_row_heartbeat_paused}`; `--selftest` is the one other zero.
- Answer contract: the helper prints exactly one `JSONEachRow` line. An aggregate over an empty window still
  returns ONE row: `{"n":"0","newest":"1970-01-01 00:00:00"}`; ClickHouse quotes 64-bit integers, so `n` arrives as a
  JSON string. The script accepts `n` as a string or number matching `^[0-9]+$`, checks `n > 0` BEFORE touching
  `newest`, and treats zero lines, more than one line, a non-object, or a non-numeric `n` as `query_failed`.
  `newest` is informational only (printed sanitized in the marker). There is deliberately no client-side age check:
  the SQL window (both `UNION ALL` arms) is the single place the window lives, pinned by the suite's SQL-text pins and
  proven live by Phase 0.1 (review cut a second chokepoint as unasked machinery).
- Transport: every curl carries `--max-time` and `--connect-timeout`, no `--retry`, and success is an explicit 2xx
  status check (a 3xx or 429 is `beat_failed`). Any value echoed into a marker or `::error::` line has CR/LF removed.
- Heartbeat resolution: GET `https://uptime.betterstack.com/api/v2/heartbeats?per_page=250` with
  `BETTERSTACK_API_TOKEN_READONLY` on curl stdin config, exact name, exactly one match, no further page, `paused` a
  JSON boolean, URL matching `^https://uptime\.betterstack\.com/api/v1/heartbeat/[A-Za-z0-9]+$`.
- ONE beat call site, `beat_once`, which has no `/fail` arm at all (a withheld beat times out and pages; a delivered
  `/fail` would be a different incident class the ruling forbids).
- No clock seam (nothing client-side depends on the clock); the same TLS/DNS env scrub as the sibling.

### Workflow: `.github/workflows/scheduled-deadman-heartbeat-feeder.yml`

`<!-- gate-override: new-scheduled-cron-prefer-inngest -->` header (ADR-248 second clause; the sibling's header is
the template; justification: the Better Stack heartbeat is the paging surface and an Inngest-fired or schedule-only
feeder would false-page). Triggers exactly `schedule: '0 * * * *'` and `workflow_dispatch: {}`; top-level
`concurrency: group: scheduled-deadman-heartbeat-feeder, cancel-in-progress: false`; `permissions: contents: read`;
one job, `timeout-minutes: 8`; one step that loops over both targets (`bash scripts/deadman-heartbeat-feeder.sh "$t"`)
with the sibling's marker-line discipline and exit-status-as-data capture (`|| rc=$?`); an `if: always()`
`./.github/actions/sentry-heartbeat` step, `monitor-slug: scheduled-deadman-heartbeat-feeder`, `ok` only when every
target exited 0 with a deciding verdict.

### Terraform

`uptime-alerts.tf`, two resources copied from `inngest_server_probe`: names `soleur-luks-monitor-host-timer-prd`
(grace 3600) and `soleur-claude-cost-capture-prd` (grace 7200), `period = 3600`, `paused = true`,
`lifecycle { ignore_changes = [paused] }`, `policy_id` gated on `var.betterstack_paid_tier`, `email = true`,
`push = true` (sibling parity, #11068). No `doppler_secret`.

`betterstack-logs-alerts.tf`: delete exactly `logtail_exploration` + `logtail_exploration_alert` for
`claude_cost_capture_dark` and `luks_monitor_host_timer_dark`, the locals `claude_cost_capture_dark_sql`,
`luks_monitor_host_timer_sql` and `luks_monitor_runbook_url`, and the whole `#8706` section comment; adjust the two
stale comment lines. `claude_cost_daily_burn` and `claude_spend_runbook_url` stay.

`apply-web-platform-infra.yml`: keep the four `-target=` lines (a bare `-target` on an address with no
configuration plans its delete, the #9062 precedent) and add `-target=betteruptime_heartbeat.luks_monitor_host_timer`
and `-target=betteruptime_heartbeat.claude_cost_capture`. The expected plan is 2 creates + 4 deletes; the destroy
guard demands a line `[ack-destroy]` in the merge commit message (prepared in the PR body; the PR is not merged
here). Whether the plan shows exactly those four deletes is UNVERIFIED until CI runs it; the PR body says so.

## Implementation Phases

### Phase 0: Read-only measurement (needs `doppler run -p soleur -c prd_terraform`, read-only)

0.1 **Hard gate before the feeder is declared done.** Run each target's exact SQL through `scripts/betterstack-query.sh`
with the SQL in SINGLE quotes so only the helper substitutes `$BS_TABLE` / `$BS_TABLE_S3` (a double-quoted SQL under
`doppler run -- cmd "..."` is expanded by the caller's shell to empty first). Expect `n >= 1` for luks-monitor (39
nightly rows from 2026-09-27) and cost-capture. The old alert read 0 through 33 healthy nights, so the predicate is
the one thing never proven live: capture the real one-line `JSONEachRow` answer for each target (and for an empty
window, e.g. a one-second window) and use those exact byte shapes as the suite's answer fixtures. Cite the writers of
`host_name` and `_SYSTEMD_UNIT` (the Vector transform in `apps/web-platform/infra/vector.toml` and the journald
fields) in the suite header. If no credential is available, the PR body states "predicate UNPROVEN against live" and
the PR stays draft.
0.2 Archive freshness lag: `SELECT now() - max(dt) FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1 AND dt > now() - INTERVAL 1 DAY`
(source-wide freshness; the source writes thousands of rows an hour, so this bounds the lag but is not a per-row
measurement). Record in the PR body. If the lag exceeds 2 h, widen grace (ruling-sanctioned) and say so. If Phase 0
is skipped, the lag claim reads "unmeasured at merge" and the arming precondition (two consecutive
`qualifying_row_heartbeat_paused` runs per target) is the lag gate.
0.3 Record the 27 h archive-scan latency in the PR body; add a cheap implied `raw LIKE` pre-filter only if it exceeds 30 s.
0.4 Re-measure watchdog `workflow_dispatch` gaps and queue per `## Research Insights`; widen the luks grace to 7200
if the beat-to-beat maximum exceeds 6500 s.
0.5 One-time verbatim-move check: diff each moved predicate against the deleted `*_sql` local (`git show origin/main:...`)
and record "identical minus the window conjunct" in the PR body. This is NOT a permanent suite check (the base text
disappears after merge).

### Phase 1: RED first (`cq-write-failing-tests-before`)

Write `apps/web-platform/test/infra/deadman-heartbeat-feeder.test.sh` against a missing feeder; it must be RED for
the right reason (script not found), then build the feeder (Phase 2) to GREEN. Contents: see `## Test Scenarios` and
the Guard Contract. The stub `betterstack-query.sh` in the fake tree is a small python evaluator for the SQL subset
the two predicates use (`JSONExtractString(raw, 'k'...) = / LIKE`, `JSONExtract(... 'Nullable(Float64)') IS NOT NULL`,
`IN (...)`, `AND`/`OR`/parentheses, the `dt` window against a frozen clock). It evaluates the SQL the feeder
actually sent, so a changed predicate changes the verdict; its limits are stated in the suite header (it is not
ClickHouse; Phase 0.1 is the live positive control).

### Phase 2: feeder script, then workflow, Sentry monitor, watchdog row

- `scripts/deadman-heartbeat-feeder.sh`; `.github/workflows/scheduled-deadman-heartbeat-feeder.yml`.
- `apps/web-platform/infra/sentry/cron-monitors.tf`: `sentry_cron_monitor.scheduled_deadman_heartbeat_feeder`,
  `name = "scheduled-deadman-heartbeat-feeder"`, `crontab = "0 * * * *"`, `checkin_margin_minutes = 60`,
  `max_runtime_minutes = 8` (floor `ceil(12 + 30 + 8) = 50`), with a comment block in the file's style.
  `cron-monitor-alerts.tf`: add the label to `cron_monitor_alert_unrouted` ("the Better Stack heartbeats are the
  paging surface; route after the first measured check-in (#11631)"). Applied by `apply-sentry-infra.yml`.
- `apps/web-platform/server/watchdog-dispatch-table.ts`: the CTO-ruled row, `intervalMinutes: 60`, eligibility
  string as ruled. `sentry-monitor-iac-parity.test.ts`: add the slug to the expected set (`expect(new Set(WATCHDOG_DISPATCH_TABLE.map(...)))`).
- `.github/workflows/infra-validation.yml`: a step running the new suite beside the other alert guards, and the
  `paths:` entries `scripts/deadman-heartbeat-feeder.sh`, `.github/workflows/scheduled-deadman-heartbeat-feeder.yml`
  (neither is under `apps/*/infra/**`; the file's own convention for such guard subjects).

### Phase 3: Terraform, apply targets, census

`uptime-alerts.tf` heartbeats; delete the alert blocks; `apply-web-platform-infra.yml` target additions;
`tests/scripts/test-infra-privileged-tier-census.sh`: add the four addresses to
`INTENDED_DESTROYS["apps/web-platform/infra"]` with `#11631` (G4c; they are not in `G4_PROTECTED`).
the `workspaces-luks.tf` comment ("The runtime proof that the timer fires is"): point at the heartbeat and the feeder.

### Phase 4: manifest and test rewrites

- `plugins/soleur/lib/heartbeat-manifest.ts`: rows `luks_monitor_host_timer` and `claude_cost_capture`:
  `arming: "external-probe"`, `paused: true`, `feeder: { kind: "cron", evidence: { file: ".github/workflows/scheduled-deadman-heartbeat-feeder.yml", pattern: "bash scripts/deadman-heartbeat-feeder.sh" } }`,
  `arming_pending: { tracking_issue: 11631 }`, `exempt_reason` naming the archive-reading feeder and why no host replace
  applies. Rewrite the `workspaces_luks` row comment (the line naming `logtail_exploration_alert.luks_monitor_host_timer_dark`) and `exempt_reason` clause that name the old alert.
- `apps/web-platform/infra/luks-monitor-install.test.sh`: rewrite Guard 1 (from `dark = block(alerts, "logtail_exploration", "luks_monitor_host_timer_dark")` through the `main_runs` target loop) to assert the heartbeat
  (resource exists, `period` 3600, `grace` 3600, `paused = true`, `ignore_changes = [paused]`, name, policy gate),
  that `logtail_exploration[_alert].luks_monitor_host_timer_dark` are ABSENT, that no logs exploration other than
  `workspaces_luks_deadman_fired` reads the luks-monitor tag, that the apply targets the heartbeat and keeps the two
  destroy targets, and that the runbook heading anchor resolves. Mutants (the `G1-*` rows): re-point 1-2/1-4/1-12/1-8/1-9/1-13
  at the heartbeat; MOVE predicate mutants (1-1, 1-5a, 1-6, 1-6b, 1-11, 1-H1, 1-H2) and the needle-vs-`luks-monitor.sh`
  pin (1-5b) to the new suite; keep 1-7, 1-10, 1-14..1-17 and the Row-10 starter scan.
- `apps/web-platform/test/infra/inngest-step-524-alert.test.sh`: drop every `claude_cost_capture_dark` expectation
  (the header bullet, the `names.count("claude_cost_capture_dark")` check, the `n != "claude_cost_capture_dark"` OR guard, the capture-dark window/operator/arm-B/emitter checks, the `HDARK` heredoc header, and the capture-dark mutants such as `Q2`), keep `claude_cost_daily_burn`, and re-check
  that the discovery floor ("fewer than 3") still holds with two explorations left plus the 524 one.
- `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`: comment-only name list (the line listing `luks_monitor_host_timer_dark`).
- Run `heartbeat-reprovision-parity.test.ts`, `heartbeat-live-reconcile.test.ts`, `sentry-monitor-iac-parity.test.ts`.

### Phase 5: docs, C4, ADRs

- Runbooks: `workspaces-luks-cutover-6604.md` (the "Better Stack logs alert `soleur-luks-monitor-host-timer-dark-prd`" bullet, the `### Host-timer liveness alert (#8706)` body, the "Closing #8706" paragraph), `betterstack-log-query.md` (the two standing-alarms entries: mark both retired, link the heartbeats),
  `inngest-server.md` ("How the external watchdogs are triggered" list and checklist item 4: add the new workflow
  and the margin; plus the ruling's note: after a host replace plus `op=resume`, the inngest server-probe heartbeat
  stays down up to about 1 h because the probe timer fires at boot+90 s then hourly, `OnUnitActiveSec=1h`; the 60 s
  `soleur-inngest-server-prd` heartbeat is the real serving signal).
- ADR amendments (dated, appended, not edited): ADR-218 (once-a-day absence alarms leave the native logs alerts;
  the 900 s ceiling sentinel; both alerts retired; names the heartbeats as successors so the historical ADR-117 and
  ADR-119 mentions of the alert stay readable) and ADR-248 (table row 5 and its eligibility reading). ADR-117,
  ADR-119 and the post-mortem are historical records and are left unedited.
- `model.c4` (+ regenerate `model.likec4.json` with `bash scripts/regenerate-c4-model.sh`): the `github -> sentry`
  edge counts `19 -> 20` workflows, `13 -> 14` schedule-fired, `Of 25 -> 26` cron monitors, `14 -> 15` check in from here
  (C6 and C9 unchanged at 11) and the new workflow in the list; the watchdog-dispatch sentence (the one listing `scheduled-inngest-health.yml every 15 min`) and the
  `github -> betterstack` edge (the one reading "Polls the SOLEUR_ZOT_DISK") name the new feeder.

### Phase 6: verification and PR body

Run the commands in `## Acceptance Criteria`. The PR body (written at ship, `Ref #11631`, no `Closes`) carries the
owner-gated appendix drafted in `## Owner-gated appendix`. Do not merge, do not arm auto-merge, do not dispatch any
workflow, do not unpause, do not resolve incidents.

## Files to Edit

- `apps/web-platform/infra/uptime-alerts.tf`
- `apps/web-platform/infra/betterstack-logs-alerts.tf`
- `apps/web-platform/infra/workspaces-luks.tf` (comment only)
- `apps/web-platform/infra/luks-monitor-install.test.sh`
- `apps/web-platform/infra/sentry/cron-monitors.tf`
- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`
- `apps/web-platform/server/watchdog-dispatch-table.ts`
- `apps/web-platform/test/infra/inngest-step-524-alert.test.sh`
- `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` (comment only)
- `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts`
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` (add the slug to `NON_INNGEST_MONITORS`, beside `scheduled-inngest-probe-heartbeat`)
- `apps/web-platform/scripts/sentry-monitors-audit.test.sh`, `apps/web-platform/scripts/sentry-monitors-audit.sh` addendum, `apps/web-platform/infra/sentry/README.md` (the `25 cron monitors` count becomes 26 at the content anchors T25 reads)
- `scripts/lib/test-affected-paths.sh` (a new `AFFECTED_*` array for the feeder script, workflow and suite, modeled on `AFFECTED_SCRIPTS_INNGEST_PROBE_HEARTBEAT_FEEDER_PATHS`)
- `plugins/soleur/lib/heartbeat-manifest.ts`
- `.github/workflows/apply-web-platform-infra.yml`
- `.github/workflows/infra-validation.yml`
- `tests/scripts/test-infra-privileged-tier-census.sh`
- `knowledge-base/engineering/architecture/diagrams/model.c4` and `model.likec4.json` (regenerated)
- `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md`
  and `ADR-248-watchdog-dispatch-clock-runs-in-the-web-server.md` (appended dated amendments)
- `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md`, `betterstack-log-query.md`, `inngest-server.md`

## Files to Create

- `scripts/deadman-heartbeat-feeder.sh`
- `.github/workflows/scheduled-deadman-heartbeat-feeder.yml`
- `apps/web-platform/test/infra/deadman-heartbeat-feeder.test.sh`
- `apps/web-platform/test/infra/logs-alert-query-period-ceiling.test.sh` (Guard 3)
- (carried, already in the worktree, not authored here) `knowledge-base/legal/audits/2026-10-30-inngest-a6-no-known-access-record.md` — keep `status: draft-unsigned`; `git add` it by explicit path; never sign or attest it.

**Must NOT appear in the diff:** anything under `luks-monitor.*` (`luks-monitor.sh/.service/.timer`), `server.tf`,
`cloud-init*.yml`; `apps/web-platform/infra/workspaces-luks-provision.sh` (it is baked into `user_data` via `server.tf`; its
stale comment about "the host-timer-dark alert" is a deliberately retained stale comment because editing it would
change `user_data` = a host replace); any logs alert above 900 s; `scripts/inngest-probe-heartbeat-feeder.sh`. (The suite
`luks-monitor-install.test.sh` is not a `luks-monitor.*` file; the ruling directs its rewrite.) A diff-scope AC
asserts this by `git diff --name-only origin/main...HEAD`.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/` (existing root, R2 backend already in place): two `betteruptime_heartbeat` resources
(provider `BetterStackHQ/better-uptime`, already pinned), four `logtail_exploration[_alert]` deletions
(provider `logtail`, already pinned). Sentry root: one `sentry_cron_monitor`. No new variable, no new secret, no
`doppler_secret` (the ping URL is read through the read-only API at run time).

### Apply path

(a) CI per-merge apply (`apply-web-platform-infra.yml`, hard `-target` list) creates the two heartbeats paused and
destroys the four logs resources; the Sentry root applies through `apply-sentry-infra.yml`. No host is touched; no
`terraform apply -replace`; no SSH. Blast radius: Better Stack objects only. During the window between the destroy
and the owner's arm there is no working dead-man for these two checks; the old alerts were already always-red and
carried no information, and the independent daily `workspaces-luks-verify` job and its Sentry monitor continue.

### Host fan-out

No `terraform_data` SSH provisioner is touched (`workspaces-luks.tf` is a comment-only edit), so
`plan-host-fanout.md` classification is "not applicable: no provisioner, no fleet sibling".

### Distinctness / drift safeguards

`ignore_changes = [paused]` (an unpause made through the Better Stack API must survive the next apply); heartbeat
names are exact-matched by the feeder (a rename without updating the script reds the suite); census
`INTENDED_DESTROYS` keeps the four deletes explicit; the `fed-but-paused` reconcile is silenced only through the
declared `arming_pending`.

### Vendor-tier reality check

`policy_id = var.betterstack_paid_tier ? betteruptime_policy.uptime[0].id : null` as the sibling does; a free-tier
account still creates the heartbeats. Logs alerts: the 900 s ceiling for alerts created since 2026-10-01 is the
measured reason heartbeats are used (see the table in `betterstack-logs-alerts.tf`).

## Observability

```yaml
liveness_signal:
  what: Better Stack heartbeats soleur-luks-monitor-host-timer-prd and soleur-claude-cost-capture-prd (period 3600; grace 3600 / 7200) plus the Sentry cron monitor scheduled-deadman-heartbeat-feeder
  cadence: hourly (watchdog clock slot; schedule fallback)
  alert_target: Better Stack escalation policy (team email and push) for the heartbeats; Sentry issue for a missed or error check-in (unrouted at first, the two-PR rule)
  configured_in: apps/web-platform/infra/uptime-alerts.tf and apps/web-platform/infra/sentry/cron-monitors.tf
error_reporting:
  destination: Sentry cron monitor check-in status error (no exception path; the feeder is a shell step)
  fail_loud: a deadman-feeder marker line with the verdict, a workflow ::error:: annotation, and the heartbeat timing out
failure_modes:
  - mode: no qualifying nightly row in the old window (host timer dark, luks FAIL row, Vector or Logs outage)
    detection: feeder verdict no_qualifying_row withholds the beat; the heartbeat times out
    alert_route: Better Stack heartbeat incident to the owner policy; Sentry error check-in
  - mode: feeder cannot run (clock dark on both hosts, workflow disabled, GitHub down)
    detection: heartbeat times out after period plus grace; Sentry missed check-in
    alert_route: Better Stack heartbeat incident; Sentry missed-check-in issue
  - mode: archive query or API fault (credential rotated, helper failure, heartbeat not unique)
    detection: verdict query_failed or beat_failed, exit 3 or 4, Sentry error
    alert_route: Sentry issue (unrouted initially); the heartbeat times out and pages if it persists
  - mode: spurious beat (SQL window or predicate widened)
    detection: the committed suite and its mutation rows; stale_row second chokepoint at run time
    alert_route: CI red before merge
logs:
  where: GitHub Actions run logs for the workflow (marker lines only, counts and verdicts, no row content); Better Stack heartbeat timeline
  retention: GitHub default run-log retention (90 days); Better Stack heartbeat history per plan
discoverability_test:
  command: bash scripts/deadman-heartbeat-feeder.sh --selftest
  expected_output: deadman-feeder: selftest=ok
```

## Task Design

```yaml
tasks:
  - task: scheduled-deadman-heartbeat-feeder (luks-monitor-host-timer and claude-cost-capture beats)
    trigger: watchdog dispatch clock workflow_dispatch each UTC hour slot (ADR-248); schedule 0 * * * * as fallback; manual workflow_dispatch
    services: reads the Better Stack Logs ClickHouse endpoint (hot plus s3 archive) and the Better Stack uptime API (read-only token); writes one GET to a heartbeat ping URL; writes a Sentry check-in
    next: nothing (a missing beat is the signal; Better Stack pages on timeout)
    human_reentry: gh workflow disable scheduled-deadman-heartbeat-feeder.yml stops the clock and the fallback; gh workflow run reruns it; the owner pauses or unpauses the heartbeat in Better Stack
    dedupe: the beat is idempotent by construction (a repeat beat inside one period only resets the same timer); the watchdog clock skips a slot already covered by a run created in that slot; no tracker issue is filed by this workflow
    source_dedupe: not a ticket source
```

## Encryption Posture

```yaml
at_rest:
  - store: none introduced (no volume, bucket, table, queue or log sink is created; heartbeat objects live in Better Stack and their URLs already live in Terraform state in the existing R2 backend)
    mechanism: provider-managed:existing R2 state backend, unchanged by this plan
    evidence: apps/web-platform/infra/main.tf backend block (unchanged)
    defends_against: n/a for this change (no new store)
    does_not_defend: a leaked state-bucket credential reads every heartbeat ping URL, which is a beat capability (alarm suppression)
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:no new store to verify
in_transit:
  - connection: workflow runner -> Better Stack Logs ClickHouse endpoint (scripts/betterstack-query.sh)
    enforced_at: scripts/betterstack-query.sh (https only; host pinned to *.betterstackdata.com; Basic auth on curl stdin config)
    tls: https, curl defaults (TLS 1.2 or newer)
    cert_verification: on
    does_not_defend: the pin accepts any Better Stack tenant host (documented residual, ADR-052); a leaked query credential reads all log rows
    disclosed_as: not-publicly-claimed
  - connection: workflow runner -> Better Stack uptime API (read-only GET) and heartbeat ping URL (GET)
    enforced_at: scripts/deadman-heartbeat-feeder.sh (https only; URL regex pinned; bearer on stdin config)
    tls: https, curl defaults (TLS 1.2 or newer)
    cert_verification: on
    does_not_defend: a leaked read-only token can read ping URLs (beat capability); the ping URL itself is a bearer secret
    disclosed_as: not-publicly-claimed
```

## Architecture Decision (ADR/C4)

### ADR

No new ordinal. Amend, by dated appended sections: **ADR-218** (decision: a once-a-day absence alarm cannot be a native
logs alert above the 900 s ceiling and is not reliably evaluable over the hot window; such dead-mans are
archive-fed heartbeats; both alerts retired; Alternatives: host-side ping and hourly host row, both rejected for
needing a `user_data` change); and **ADR-248** (table row 5, second clause). These are tasks of Phase 5, not follow-ups.

### C4 views

All three files read before concluding: `model.c4` (1048 lines), `views.c4` (142), `spec.c4` (54). Enumeration:
external human actor: the owner/operator receiving heartbeat incidents (already modeled via the
`betterstack -> slack -> founder` wake path); external systems: Better Stack (Logs + Uptime), Sentry, GitHub
(all modeled); data stores: none new; actor-to-surface access relationship: unchanged. No element or view line is
added, so `views.c4` and `spec.c4` do not change. The derived cardinalities and prose in `model.c4` DO change (see
Phase 5), validated by `plugins/soleur/test/c4-count-parity.test.sh` and `c4-model-freshness.test.sh`.

### Sequencing

The ADR amendments describe the target state and ship in this PR; nothing is deferred.

## Guard Contract

### Guard 1 — the feeder never authorizes a beat without a qualifying row

**Property.** A request reaches a heartbeat URL only when the archive query, run with the target's own window and
predicate, answered a positive count with a parsable `newest` no older than the window, and the heartbeat resolved
uniquely and unpaused; no code path sends `/fail`.

**Assembly.** The chokepoints are: (1) the SQL the script sends (window conjuncts in BOTH `UNION ALL` arms, the
`_row_type = 1` archive filter, the predicate); (2) the client age check (`stale_row`); (3) `resolve_heartbeat`;
(4) the single `beat_once` call site; (5) the EXIT trap; (6) the target table (every target has window, name and
predicate). Everything that can reach the heartbeat URL flows through `beat_once`; the suite greps the script for
any other `curl` and for the literal `/fail`. Members drift (a third target), so the suite derives the target set
from the script's table and checks the workflow loop, the manifest rows and the Terraform names against it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | drop the `dt > now() - INTERVAL` bound from the archive arm only | RED (the 28 h fixture beats, and the SQL-text pin names both arms) |
| 2 | drop the `_row_type = 1` filter | RED (SQL pin) |
| 3 | replace the hot arm with `--no-archive` or drop the `s3Cluster` arm | RED (SQL contains `s3Cluster`, never `--no-archive`) |
| 4 | make `n == 0` fall through to `beat_once` | RED (empty and no-row fixtures record a beat) |
| 5 | add a second `curl` call site or a `/fail` suffix | RED (single-call-site and no-`/fail` pins) |
| 6 | the EXIT trap lets an unknown status exit 0 | RED (trap_remapped fixture) |
| 7 | skip the paused check (beat while paused) | RED (paused fixture records a beat) |
| 8 | the guard's own dispatch: run the suite with the feeder pointed at an empty target table | RED (anti-vacuity: "0 targets checked" is a failure) |
| 9 | answer-contract fixtures: an empty-window row `{"n":"0","newest":"1970-01-01 00:00:00"}`, a string `n`, two lines, zero lines, a non-numeric `n` | RED when any is mis-graded (`n:"0"` must withhold, `n:"1"` must beat, the rest `query_failed`) |

**Harness rows.** (a) Edit the SUITE: change the stub evaluator so every row qualifies and ignores the window; the 28 h,
web-2 and verify-job fixtures must flip to FAIL, proving the fixtures can fail; (b) a must-PASS input that is NOT the canonical:
a 26 h-old luks row with reordered, reflowed predicate conjuncts (same set) still beats, and a 20 h-old cost row with
the credit-probe arm only still beats. A mutant counts only when it lands (diff changed) and reds for its predicted
reason (rc and verdict), never a crash.

**Anchor.** The stored values (window, predicate, name) live in the script and are compared by the suite against an
independent expected set frozen in the suite (set identity, never a `>= N` floor); an edit that changes both in one
diff proves consistency only. Integrity comes from (i) the emitter pins (`luks-monitor.sh` OK line;
`claude-cost-marker.ts` and the credit probe's `CRON_NAME`), (ii) the Phase 0.1 live positive control, whose captured
answer shapes are the fixtures, and (iii) the Phase 0.5 one-time verbatim-move check recorded in the PR body. There is
no permanent base-ref comparison: after this PR merges the deleted text is gone from `origin/main`, so such a check
would skip forever.

### Guard 2 — predicate fidelity with the emitters

**Property.** The luks predicate matches exactly the host timer's own passing row (identifier, unit, OK needle,
host), and the cost predicate matches exactly a cron cost marker with a non-null `cost_usd` or a credit-probe RED row.

**Assembly.** Both predicates in the script's table; the emitters: `apps/web-platform/infra/luks-monitor.sh` (OK
log line), the `_SYSTEMD_UNIT` and `host_name` conventions, `server/claude-cost-marker.ts`, `_cron-claude-eval-substrate.ts`
(`cron:${cronName}`), `cron-anthropic-credit-probe.ts` (`CRON_NAME`, op union). The evaluator runs both predicates
over synthesized rows: luks positives and negatives (a `soleur-web-2` row, a verify-job row with no `_SYSTEMD_UNIT`
or a `session-N.scope` unit, a `FAIL (...)` row, a helper row, wrong identifier); cost positives and negatives
(`_DAILY` org-total row, founder BYOK `source`, echoed issue body, null `cost_usd`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | drop the `_SYSTEMD_UNIT` conjunct | RED (verify-job row beats) |
| 2 | drop the `host_name` conjunct | RED (web-2 row beats) |
| 3 | reword the needle in the script only / in `luks-monitor.sh` only | RED (emitter parity, both directions) |
| 4 | join the unit conjunct with OR, or negate it | RED |
| 5 | add a second OR arm to the cost predicate | RED (exactly two arms) |
| 6 | drop `source LIKE 'cron:%'` or the `"SOLEUR_CLAUDE_COST":true` key match | RED (BYOK and `_DAILY` rows count) |
| 7 | the predicate extractor finds nothing (rename the table key) | RED (anti-vacuity floor on conjunct count) |

**Harness rows.** Evaluator-side edit: make the stub evaluate `LIKE` as always-true; the negative fixtures must FAIL.
Must-PASS non-canonical: luks conjuncts reordered and reflowed (same set) stay green (the retired G1-H2 row).

**Anchor.** As Guard 1; plus a printed note that the stub evaluator is not ClickHouse.

### Guard 3 — no logs alert above 900 s, and the two retired ones stay gone

**Property.** No `logtail_exploration_alert` in the root has `query_period` above 900 except the two live legacy
ones (`claude_cost_daily_burn`, `inngest_luks_wrong_volume`), and neither retired alert (nor its exploration) is
declared again.

**Assembly.** Every `logtail_exploration_alert` block across every `.tf` under `apps/web-platform/infra/`
(enumerated with `git ls-files`, not just `betterstack-logs-alerts.tf`; the other open PR adds blocks to the same
file), read after stripping `#` and `//` comments, `/* */` blocks and heredocs (the file holds `query_period`
values inside comments, e.g. a dated measurement table and `# query_period = 2592000`), `query_period` parsed per block
(an unparsable value is a failure, not a pass). Home: `apps/web-platform/test/infra/logs-alert-query-period-ceiling.test.sh`
(its own small suite, registered in `infra-validation.yml`); the two retired names; the apply workflow's four retained destroy
targets; the census `INTENDED_DESTROYS` entries.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | add an alert with `query_period = 3600` in `betterstack-logs-alerts.tf` | RED |
| 2 | add a second over-limit alert after a compliant first, in a different `.tf` file | RED (not first-hit) |
| 3 | rename an allowlisted alert to a new name at 86400 | RED (allowlist is by name, each with its own ceiling) |
| 4 | re-add `logtail_exploration.luks_monitor_host_timer_dark` | RED |
| 5 | remove one of the four retained `-target` lines | RED (the destroy would orphan) |
| 6 | the discovery finds zero alert blocks (rename the resource kind) | RED (anti-vacuity: floor on blocks seen, derived from a count of alert resources) |
| 7 | a `query_period = 86400` appearing only inside a comment or heredoc | GREEN (must-PASS: comments are not alerts) |
| 8 | a real over-limit block carrying a trailing comment | RED (still parsed) |

**Harness rows.** Suite edit: set the sentinel ceiling to 100000; mutation 1 must then go GREEN, proving the
sentinel reads the ceiling. Must-PASS non-canonical: a new alert at `query_period = 900` stays green.

**Anchor.** Allowlist entries are names with a ceiling each, kept in the suite; adding one requires editing the suite
in the same diff, which review sees. The base-ref set (alerts at `origin/main`) is printed so a weakening shows up as
a diff of printed names.

### Guard 4 — wiring parity across the surfaces that must agree

**Property.** The script's target table, the workflow loop, the manifest rows, the Terraform heartbeat names/periods/
graces, the apply `-target` list and the watchdog row describe the same two dead-mans.

**Assembly.** `scripts/deadman-heartbeat-feeder.sh` table; the workflow's loop list; `MANIFEST` (imported at runtime,
not source-grepped); `uptime-alerts.tf` blocks; `apply-web-platform-infra.yml` targets; `WATCHDOG_DISPATCH_TABLE`;
`cron-monitors.tf`; the existing parity suites that already quantify over these (`heartbeat-reprovision-parity`,
`heartbeat-live-reconcile`, `sentry-monitor-iac-parity`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | rename a heartbeat in Terraform only | RED (feeder lookup name) |
| 2 | change `grace` or `period` or flip `paused` or drop `ignore_changes` | RED |
| 3 | drop one target from the workflow loop | RED |
| 4 | remove a new heartbeat `-target` from the apply workflow | RED |
| 5 | change the watchdog row interval or remove the row | RED (existing parity test) |
| 6 | the discovery of Terraform heartbeats returns none | RED (anti-vacuity) |

Scope note: luks `period`/`grace`/`paused`/`ignore_changes` are pinned once, in the rewritten
`luks-monitor-install.test.sh`; this guard pins the cost-capture heartbeat's and the cross-surface names only.

**Harness rows.** Suite edit: delete the workflow-loop assertion; mutation 3 must go GREEN (proves that assertion is
the one catching it). Must-PASS non-canonical: reorder the loop targets.

**Anchor.** Parity across surfaces is consistency, not integrity; the independent anchor is the live reconcile's
`absent-live` / `fed-but-paused` classes against the real vendor state.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "replace the luks-monitor host-timer and claude-cost-capture logs alerts with Better Stack heartbeats fed by a scheduled workflow that reads the archive" [brief] | Phases 2-4, Guard 1-4 | mapped |
| 2 | "The BINDING ruling, file list, tests, exclusions and risks are in .../deadman-ruling.md — read it first and follow it exactly" [brief] | whole plan; deviations are listed in `## Research Reconciliation` and `decision-challenges.md` | mapped |
| 3 | "The worktree also holds one extra file to keep in the same PR: knowledge-base/legal/audits/2026-10-30-inngest-a6-no-known-access-record.md (status draft-unsigned; never sign or attest it)" [brief] | Files to Create (carried) | mapped |
| 4 | "one PR; do NOT merge it and do NOT arm auto-merge" [brief] | Phase 6; AC "PR open, auto-merge unarmed" | mapped |
| 5 | "do not unpause heartbeats, resolve Better Stack incidents, dispatch any apply workflow, or make any Hetzner/Doppler/Better Stack write" [brief] | Phase 6; Owner-gated appendix is text only | mapped |
| 6 | "PR body references use Ref #11631 (not Closes)" [brief] | Phase 6, AC | mapped |
| 7 | "plan so edits to that file are minimal and localized to the two deleted alert blocks" [brief] | `## Open Code-Review Overlap`; Terraform section | mapped |
| 8 | "Technical forks go to the CTO agent ... recorded as `Ruled by CTO agent, <date>: ...` rows in knowledge-base/project/specs/<branch>/decision-challenges.md" [brief] | `decision-challenges.md` | mapped |
| 9 | "Add `betteruptime_heartbeat.luks_monitor_host_timer` ... and `betteruptime_heartbeat.claude_cost_capture` to `apps/web-platform/infra/uptime-alerts.tf`" [doc ruling] | Terraform; Phase 3 | mapped |
| 10 | "Feeder: runs hourly; beats a heartbeat only if a qualifying row exists inside that alert's OLD window" [doc ruling] | Feeder; Guard 1 | mapped |
| 11 | "`plugins/soleur/lib/heartbeat-manifest.ts`: two rows, `arming: \"external-probe\"`, `paused: true`" [doc ruling] | Phase 4 | mapped |
| 12 | "Delete from `betterstack-logs-alerts.tf` the two `logtail_exploration` and two `logtail_exploration_alert` resources" [doc ruling] | Terraform; Phase 3 | mapped |
| 13 | "`apply-web-platform-infra.yml` (~lines 665-668) hard-`-target`s those four addresses: keep the destroy reachable and add the two new heartbeats" [doc ruling] | Terraform; Phase 3 | mapped |
| 14 | "Update stale references: `workspaces-luks.tf` (~229), the runbook anchor ... and `local.luks_monitor_runbook_url` text" [doc ruling] | Phase 3, Phase 5 | mapped |
| 15 | "Tests: new `apps/web-platform/test/infra/deadman-heartbeat-feeder.test.sh` ... Rewrite the `luks-monitor-install.test.sh` guards ... drop the `claude_cost_capture_dark` expectations ... Add a sentinel ... Run `heartbeat-reprovision-parity.test.ts`, ..." [doc ruling] | Phase 1, Phase 4, Guard 1-3 | mapped |
| 16 | "Prepare the exact incident-resolve command and the arm block with read-back as text in the PR body only" [doc ruling] | `## Owner-gated appendix` | mapped |
| 17 | "Runbook note to add: after a host replace plus `op=resume`, the inngest server-probe heartbeat stays down up to ~1 h" [doc ruling] | Phase 5 | mapped |
| 18 | "Must NOT appear in the PR: anything under `luks-monitor.*`, `server.tf`, `cloud-init.yml`; any logs alert above 900 s" [doc ruling] | Files to Create footer; AC diff-scope | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| uptime-alerts.tf heartbeats; betterstack-logs-alerts.tf deletions; manifest rows; apply targets; workspaces-luks.tf comment | "Add `betteruptime_heartbeat.luks_monitor_host_timer`" (asks 9, 11-14) | asked |
| scripts/deadman-heartbeat-feeder.sh; the workflow | "Workflow `.github/workflows/scheduled-deadman-heartbeat-feeder.yml`" (ask 10) | asked |
| deadman-heartbeat-feeder.test.sh; luks-monitor-install and inngest-step-524 rewrites; sentinel | ask 15 | asked |
| Runbook edits (6604, betterstack-log-query, inngest-server note) | ask 14 and 17 | asked |
| WATCHDOG_DISPATCH_TABLE row + sentry-monitor-iac-parity slug set | — | inferred — justification: CTO-ruled fork; measured schedule delivery cannot hold the page budget (decision-challenges.md) |
| `sentry_cron_monitor` + unrouted label | "the `sentry-heartbeat` check-in step" (ruling) | inferred — justification: `sentry-monitor-iac-parity.test.ts` fails a `monitor-slug:` with no monitor |
| `arming_pending` on the two rows | "born `paused = true`" (ruling) | inferred — justification: without it the nightly reconcile alarms `fed-but-paused` on every run |
| census `INTENDED_DESTROYS` entries | "keep the destroy reachable" (ask 13) | inferred — justification: G4c fails a deleted resource block with no `removed` block otherwise |
| infra-validation.yml step and paths | ask 15 | inferred — justification: an unregistered suite gates nothing (`lint-orphan-test-suites.sh`) |
| model.c4 counts + regeneration | — | inferred — justification: `c4-count-parity.test.sh` reds on the new workflow and monitor |
| ADR-218/248 amendments | — | inferred — justification: plan gate `wg-architecture-decision-is-a-plan-deliverable` (a decision reversal is a plan deliverable) |
| Phase 0 measurement | "measure lag between a row's `dt` and its appearance in the `s3Cluster` arm" (ruling) | asked |
| Guard 3 sentinel name-and-ceiling allowlist | "allowlisting only the live legacy ones (`claude_cost_daily_burn`, `inngest_luks_wrong_volume`)" | asked |

### Split Assessment

- Subsystems touched: 6 — `apps/web-platform`, `plugins/soleur`, `.github`, `scripts`, `tests`, `knowledge-base`
- Planned files: about 33 | Estimated changed lines: about 2300 (the suite and its mutation rows dominate)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — all three thresholds are exceeded, but the operator mandated "one PR" and the seam is unsafe: deleting the alerts without the heartbeats (or the reverse) leaves a window with a dead or duplicate control, and the heartbeats cannot be applied without the Sentry monitor, the watchdog row and the manifest rows that gates require. The only clean seam (docs and ADR upkeep) is small enough to stay.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The operator cannot tell from the alert whether web-1's nightly encryption self-check or the Anthropic cost telemetry went dark (the status quo for both today: both alerts are red on a healthy host), or is paged for a healthy host (noise). No end-user screen changes.
- **If this leaks, the user's data is exposed via:** nothing user-facing. The workflow handles aggregate counts and verdict strings only (no log row content is printed); it holds the existing read-only Better Stack API token (can read heartbeat ping URLs, an alarm-suppression capability) and the existing Logs query credentials, both already used by `scheduled-inngest-probe-heartbeat.yml`. No scope is added.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** not `single-user incident`, because the change cannot make today's state worse (both alerts are already always-red and informationless) and the independent daily `workspaces-luks-verify` check still covers the volume; not `none`, because a spuriously-green dead-man would mask encryption-at-rest regressions across every workspace, which is why Guard 1 exists.

## Acceptance Criteria

Pre-merge (agent-verifiable; each names its command):

- [ ] `bash apps/web-platform/test/infra/deadman-heartbeat-feeder.test.sh` passes; its fixtures include: a luks row 26 h old beats; 28 h old withholds; empty withholds; a `soleur-web-2` row withholds; a verify-job row without `_SYSTEMD_UNIT` withholds; a future-dated row withholds; the SQL contains `s3Cluster` and `_row_type = 1` and the suite never passes `--no-archive`; the withhold path never reaches a `/fail` request; cost-capture: 20 h old beats, 26 h old withholds. Every mutation row in Guards 1-4 goes RED for its predicted reason and every must-PASS row stays green.
- [ ] `bash apps/web-platform/infra/luks-monitor-install.test.sh` passes after the Guard 1 rewrite, with the heartbeat's `period`, `grace`, `paused`, `ignore_changes` asserted and the old alert asserted ABSENT.
- [ ] `bash apps/web-platform/test/infra/inngest-step-524-alert.test.sh` passes with no `claude_cost_capture_dark` reference and `claude_cost_daily_burn` still pinned.
- [ ] Old-name sweep: `git grep -nE "claude_cost_capture_dark|luks_monitor_host_timer_dark|host-timer-dark|cost-capture-dark" -- apps plugins scripts tests .github knowledge-base/engineering ':!knowledge-base/project'` returns exactly this residual set and no other hit: the four retained apply-workflow `-target` lines; the four census `INTENDED_DESTROYS` rows; the suites' ABSENT assertions; the dated measurement comment inside the `inngest_luks_key_probe_fail` block (left to avoid the #11601 hunk); `workspaces-luks-provision.sh` (retained stale comment); dated historical mentions in ADR-117, ADR-119, ADR-218, ADR-282, the post-mortem, `compound-promote-runbook.md` and the runbooks' "retired" notes. The check is count-based (an explicit expected-hit list), never "no output".
- [ ] `bash tests/scripts/test-infra-privileged-tier-census.sh` passes.
- [ ] `cd apps/web-platform && bunx vitest run test/server/inngest/sentry-monitor-iac-parity.test.ts` passes; `bun test plugins/soleur/test/heartbeat-reprovision-parity.test.ts plugins/soleur/test/heartbeat-live-reconcile.test.ts` pass.
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` and `bash plugins/soleur/test/c4-model-freshness.test.sh` pass after the count edits.
- [ ] `bash apps/web-platform/test/infra/logs-alert-query-period-ceiling.test.sh`, `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh`, `cd apps/web-platform && bunx vitest run test/server/inngest/function-registry-count.test.ts`, `bun test plugins/soleur/test/terraform-target-parity.test.ts` and `bash scripts/lint-orphan-test-suites.sh` pass.
- [ ] `actionlint .github/workflows/scheduled-deadman-heartbeat-feeder.yml .github/workflows/infra-validation.yml` is clean, and the suite's absence greps handle grep rc 2 (an unreadable file) as a failure, not as "absent".
- [ ] `bash scripts/deadman-heartbeat-feeder.sh --selftest` prints `deadman-feeder: selftest=ok` (identical to the Observability block's `expected_output`) and exits 0 with no network or credentials.
- [ ] `git diff --name-only origin/main...HEAD` contains nothing matching `luks-monitor\.(sh|service|timer)$`, `server\.tf`, `cloud-init` or `scripts/inngest-probe-heartbeat-feeder.sh`; the A6 file is present, `status: draft-unsigned`, with no signature or attestation text added.
- [ ] `cd apps/web-platform/infra && terraform fmt -check && terraform validate` (init with `-backend=false`) pass; no `logtail_exploration_alert` has `query_period` above 900 other than the two allowlisted legacy ones.
- [ ] `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-30-fix-deadman-heartbeats-fed-from-archive-plan.md` exits 0.
- [ ] The PR is open, with `Ref #11631` in the body (no `Closes`), auto-merge NOT armed, not merged, and the body's FIRST line reads: "Merging this runs the push-triggered `apply-web-platform-infra.yml`: 2 creates, 4 deletes, needs `[ack-destroy]`", followed by the owner-gated appendix.

Post-merge / owner-gated (not performed by this work; text in the PR body only):

- [ ] The merge commit message carries a line `[ack-destroy]` and the CI plan shows exactly 2 creates and 4 deletes (UNVERIFIED until CI runs it). Automation: withheld by explicit operator instruction (merge is the owner's).
- [ ] Arming precondition (and the archive-lag gate): at least two consecutive feeder runs report `qualifying_row_heartbeat_paused` for each target. Automation: the feeder itself produces the evidence; the arm is withheld by explicit operator instruction.
- [ ] The owner arms both heartbeats and resolves the two stuck incidents using the prepared commands. Automation: withheld by explicit operator instruction (brief: do not unpause heartbeats, do not resolve incidents).
- [ ] Cleanup after the first verified apply: remove the four retained `-target=` lines and the four census `INTENDED_DESTROYS` rows (tracked by an issue created at ship time with that re-evaluation criterion).

## Test Scenarios

1. Positive: luks row 26 h old, correct identifier/unit/needle/host -> `verdict=beat`, exactly one beat request.
2. Withhold: 28 h old; empty window (`n:"0"`, epoch `newest`); web-2 host; verify-job row (no unit); `FAIL (...)` row; future-dated (evaluator applies the `dt <= now()+300 s` bound); wrong identifier -> exit 3, zero beat requests, no `/fail`.
3. Cost: marker with non-null `cost_usd` and `cron:` source 20 h old -> beat; null `cost_usd`, `_DAILY` row, BYOK source -> withhold; credit-probe RED row alone -> beat.
4. Heartbeat faults: paused -> exit 0 `qualifying_row_heartbeat_paused`, no request; two matches / zero / `pagination.next` / `paused` not boolean / bad URL shape -> exit 4; beat answered 302 or 500 -> exit 4.
5. Hygiene: helper failure, zero/multiple lines and non-numeric `n` -> exit 3 (`query_failed`) with no raw output echoed; `bash -x` with a credential -> 78; unknown status rewritten to 3; a beat answered 429 with `Retry-After` or stalled past `--max-time` -> exit 4 with no retry.
6. Wiring (Guard 4): script table = workflow loop = manifest names = Terraform names; apply targets present; watchdog row present.
7. Sentinel (Guard 3) and the retired-name absence checks.

## Owner-gated appendix (draft text for the PR body; do not execute)

1. Merge note: put a line `[ack-destroy]` in the merge commit message (4 deletes are expected: two explorations, two alerts).
2. Post-apply read-only checks: the two heartbeats exist paused (`GET /api/v2/heartbeats` by exact name, id captured), the Sentry monitor exists, feeder runs show `qualifying_row_heartbeat_paused` for both targets for at least two consecutive hourly slots, and the Sentry check-ins are 2xx.
3. Arm block with read-back: the "Arming the probe heartbeat (#9703)" block in `inngest-server.md`, with only two parameters changed per heartbeat (`NAME` and the poll deadline `period + grace`; the id is resolved by exact name, not hard-coded) and the forced dispatch pointed at `scheduled-deadman-heartbeat-feeder.yml`. Read-back: runs created since `ARM_AT` report `verdict=beat` for the target, then a second `beat` one slot later, then the state `<id> up false 3600 <grace>`. Only then a record PR drops `arming_pending`. Detach under `setsid` when the budget exceeds the 30-minute Monitor cap.
4. Incident resolve (WRITE, owner token): `POST https://incidents.betterstack.com/api/v3/incidents/{incident_id}/resolve` with body `{"resolved_by": "<owner email>"}` and `Authorization: Bearer $BETTERSTACK_API_TOKEN` <!-- verified: 2026-10-30 source: https://betterstack.com/docs/uptime/api/resolve-an-ongoing-incident/ -->. Ids: luks-monitor `1023423999`; cost-capture id from the `<!-- betterstack-incident id=<n> -->` marker in the body of #11049 (`gh issue view 11049 --json body`). The token scope accepted by the v3 host is UNVERIFIED (the repo's reads use the v2 uptime host); read the incident back before and after. The incident mirror then closes #11048 and #11049. Deleting an alert may or may not resolve its open incident: unverified, hence the explicit resolve.

## Dependencies & Risks

- **Schedule delivery** (measured): mitigated by the CTO-ruled watchdog row; the `schedule:` cron is only the fallback.
- **Archive ingestion lag** unmeasured: Phase 0.2; the 27 h window leaves about 2.5 h of tolerance for luks-monitor.
- **Stub evaluator is not ClickHouse**: a predicate that the stub accepts and ClickHouse rejects (or the reverse) is possible; mitigated by Phase 0.1 (live positive control) and by keeping the predicate text identical to the one that ran in production as an alert.
- **Query cost**: a 27 h `s3Cluster` scan hourly; Phase 0.3 measures; `run_sql` has a 60 s cap.
- **Coverage gap** between the destroy and the owner's arm: stated above; accepted because the replaced controls were always-red and informationless. The Sentry monitor is unrouted by its own alert rule; a vendor-default workflow may still email on error-level issues (`sentry/vendor-default-workflows.json`), unverified.
- **Open PR #11601** edits the same `.tf` file: disjoint hunks.
- **Destroy guard** needs `[ack-destroy]` on the merge commit; the census needs the `INTENDED_DESTROYS` rows; if the CI plan shows more than the four expected deletes, stop and report.
- **The ADR-248 eligibility reading** ("a check on the substrate") was not verified by the CTO; the row stays regardless (false pages are the alternative).
- A new suite may need a row in the affected-index files (`scripts/ci-pr-affected-audit.accept.tsv`) or `suite-shard-legs.tsv` depending on the CI selector; run `bash scripts/lint-orphan-test-suites.sh` and the selector self-check, and add the row the tool names.
- Follow-ups (two GitHub issues created at ship time, each with a re-evaluation criterion and a milestone from `knowledge-base/product/roadmap.md`): (1) the ruling's key-continuity dead-man (probe bundle tracker) should reuse this feeder pattern; (2) remove the four retained destroy `-target` lines and census rows after the first verified apply. A deferral without an issue is invisible.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** The CTO agent authored the binding design (2026-10-30) and ruled the one added fork (trigger substrate: watchdog dispatch row) the same day; both are recorded in `decision-challenges.md`. Other domains: no product/UX surface (no UI file in the Files lists; the mechanical UI override does not fire), no marketing/sales/support/finance/operations change, and legal is limited to carrying an unsigned draft file untouched (no clause edited, no attestation). GDPR gate: no schema, auth, API route or personal-data surface is touched, no LLM or external-API processing of operator-session data is added, and the feeder prints counts only; skipped with that reason.

## References

- Issue #11631; mirrors #11048, #11049; precedent PRs: #9703 (inngest probe heartbeat feeder), #8495 (ADR-248 clock), #10390.
- `scripts/inngest-probe-heartbeat-feeder.sh`, `.github/workflows/scheduled-inngest-probe-heartbeat.yml`, `apps/web-platform/infra/uptime-alerts.tf` (`inngest_server_probe`).
- ADR-218, ADR-117, ADR-119, ADR-248; runbooks `workspaces-luks-cutover-6604.md`, `betterstack-log-query.md`, `inngest-server.md`.
- Retired probe shape: `git show cef65a5003^:scripts/followthroughs/luks-monitor-host-timer-8706.sh`.
