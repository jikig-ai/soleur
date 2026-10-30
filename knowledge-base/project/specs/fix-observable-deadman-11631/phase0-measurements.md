# Phase 0 measurements — #11631 (read-only; recorded 2026-10-30 ~16:35-16:40 UTC)

Everything below was read with `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh '<SQL>'`
(the SQL in SINGLE quotes so only the helper substitutes `$BS_TABLE` / `$BS_TABLE_S3`) and read-only `gh run list` /
`gh api .../jobs`. No Better Stack, Doppler, Hetzner or GitHub write was made; no ping URL was touched; no row text was
copied anywhere (only aggregate counts and timestamps). The read credential WAS available, so the PR-body fallback
"predicate UNPROVEN against live" does not apply.

## 0.1 Live positive control (HARD GATE) — PASSED for both targets

The feeder's exact SQL shape (hot `remote()` UNION ALL `s3Cluster`, `_row_type = 1` on the archive arm, the window
bound in both arms, the predicate moved verbatim from the retired alert) was run with each target's real window.

| target | window | answer (one `JSONEachRow` line) |
|---|---|---|
| luks-monitor-host-timer | 97200 s | `{"n":1,"newest":"2026-10-30 00:04:56.747448"}` |
| claude-cost-capture | 86400 s | `{"n":4,"newest":"2026-10-30 09:01:33.703682"}` |
| luks-monitor-host-timer, 1 s window (empty) | 1 s | `{"n":0,"newest":"1970-01-01 00:00:00.000000"}` |
| claude-cost-capture, 1 s window (empty) | 1 s | `{"n":0,"newest":"1970-01-01 00:00:00.000000"}` |

So the predicate the old alert could not see (33 nights of `Current value: 0`) DOES match on the real archive: `n >= 1`
for both targets. Archive-only per-night presence of the luks row, last 5 days (counts only):
2026-10-26 n=1, 10-27 n=2, 10-28 n=1, 10-29 n=1, 10-30 n=1 (the 10-27 duplicate is a second passing row that night; the
count is a presence proof, not a per-night contract).

**Answer shape captured (used as the suite's fixture shapes).** On the live endpoint `n` arrives as a JSON NUMBER
(`"n":1`), not a quoted string, and `newest` carries a 6-digit fraction; an empty aggregate still returns ONE row with
`n:0` and the epoch `newest`. The plan's expectation of a quoted-string `n` (ClickHouse quotes 64-bit integers) did not
hold on this endpoint, but the feeder accepts both (`^[0-9]{1,18}$` on the string form, a non-negative integral number
otherwise); the suite exercises both (`okstr` stub mode for the quoted form).

**0.1 negative control (read-only, measured 2026-10-30 by the PR's lead agent over the trailing 27 h; recorded here
from that report, not re-run by the docs edit).** The positive control above proves the predicate MATCHES; it does
not prove the predicate EXCLUDES the look-alikes. In the last 27 h the luks OK identifier
(`SYSLOG_IDENTIFIER=luks-monitor`, message `OK: /mnt/data is LUKS-backed`) appears from three different emitters:

| | host_name | `_SYSTEMD_UNIT` | what it is | newest |
|---|---|---|---|---|
| (a) | `soleur-web-platform` | empty | the `workspaces-luks-verify` job's rows | 11:12 UTC |
| (b) | `soleur-web-2` | `luks-monitor.service` | web-2's own host timer | not recorded |
| (c) | `soleur-web-platform` | `luks-monitor.service` | web-1's host timer, the intended row | 00:04:56 UTC |

The predicate (`host_name` plus `_SYSTEMD_UNIT`) admits only (c). A predicate keyed on the message alone, or on the
unit alone, or on the host alone, would be kept fed by (a) or (b) while web-1's own timer is dead, so each of the
three conjuncts is load-bearing, and the suite's row-level fixtures (a web-2 row withholds; a verify-job row
without a unit withholds) model exactly (b) and (a).

Writers of the predicate fields (cited in the suite header and pinned by Guard 2): `host_name` is written by
`apps/web-platform/infra/vector.toml` (`.host_name = "@@HOST_NAME@@"`, rendered per host from `server.tf`: web-1 =
`soleur-web-platform`); `SYSLOG_IDENTIFIER=luks-monitor` is `luks-monitor.sh`'s `LOG_TAG` and the unit's
`SyslogIdentifier`, in the vector `host_scripts_journald` allowlist; `_SYSTEMD_UNIT=luks-monitor.service` is stamped by
journald from the unit that logged.

## 0.2 Archive freshness lag — 66 minutes, under the 2 h widening threshold

`SELECT dateDiff('second', max(dt), now()) ... FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1 AND dt > now() - INTERVAL 1 DAY`:

- 16:36:19 UTC: archive newest `15:30:22`, lag **3957 s**; 16:36:30: lag **3968 s** (n = 90335 rows in the last day).
- The hot arm over the same minutes: newest 5 s old, OLDEST row `15:30:37` (span 3952 s). The archive's newest row
  (15:30:22) and the hot arm's oldest (15:30:37) meet within 15 s: there is no gap between the arms, so the UNION sees a
  continuous timeline.

Source-wide freshness bounds the lag; it is not a per-row measurement. Result: lag about 66 min, below the 2 h
threshold and below the 2.5 h tolerance the luks window leaves (27 h window vs a 24.5 h legitimate gap). No grace
widening is needed. The arming precondition (two consecutive `qualifying_row_heartbeat_paused` runs per target) stays the
lag gate in the live system.

## 0.3 27 h archive scan latency — 1.5 s

Wall time for the full luks query (27 h, both arms) 1528 ms; for the cost query (24 h) 1346 ms. Far under the 30 s
threshold, so NO implied `raw LIKE` pre-filter was added.

## 0.4 Watchdog dispatch gaps and runner queue — the CTO-ruled graces hold

`gh run list --workflow scheduled-zot-restart-loop.yml --event workflow_dispatch --limit 80` (79 consecutive
run-creation gaps): min 0 s (a duplicate dispatch), median 3600 s, p90 3640 s, max **3680 s**. Runner queue
(`created_at` to `started_at`, 40 most recent jobs of the same workflow): min 2 s, median 4 s, p90 135 s, max **786 s**
(the ADR-248 historical maximum is 2438 s and is the conservative figure used below).

Beat-to-beat bound with the conservative queue: 3680 + 2438 = about 6118 s while no slot is lost; one lost slot adds a
full 3600 s: **9718 s**. The page threshold is period + grace = 3600 + 7200 = **10800 s**, so one lost slot does not page a
healthy host. Stop condition (observed maximum plus one lost slot above 10800 s) NOT met.

## 0.5 Verbatim-move check — IDENTICAL for both predicates

Each predicate in `scripts/deadman-heartbeat-feeder.sh` (`LUKS_PRED`, `COST_PRED`) was diffed, after whitespace
normalisation (runs collapsed, no space inside parentheses), against the WHERE conjuncts after the
`dt BETWEEN {{start_time}} AND {{end_time}}` conjunct of the deleted locals
(`git show origin/main:apps/web-platform/infra/betterstack-logs-alerts.tf`, `luks_monitor_host_timer_sql` and
`claude_cost_capture_dark_sql`): `luks_monitor_host_timer_sql` IDENTICAL, `claude_cost_capture_dark_sql` IDENTICAL.
(One-time check; the base text disappears after merge, so there is no permanent suite check for it.)

## Elapsed-time notes

Wall times from Phase 0.3: 1528 ms (luks, 27 h, both arms) and 1346 ms (cost, 24 h). The feeder's marker lines now
carry `elapsed_ms=<n>` (added in review), so growth of the archive scan cost shows in the run logs without a new
measurement; the 30 s threshold from the plan remains the point at which a `raw LIKE` pre-filter is reconsidered.

## Decisions recorded where the plan left a fork (all within the plan's stated choices)

- Guard 3 allowlist ceilings are the LIVE values: `claude_cost_daily_burn` 86400 and `inngest_luks_wrong_volume` 5400
  (the plan names the two alerts but not the second one's ceiling; 5400 is what the file declares today).
- The suite `apps/web-platform/test/infra/deadman-heartbeat-feeder.test.sh` is not a `test-all.sh` registration
  (nothing globs `apps/web-platform/test/infra/`); it runs from `infra-validation.yml`.
  **Correction (review, 2026-10-30):** an earlier revision of this bullet said an
  `AFFECTED_APPS_WEB_PLATFORM_TEST_INFRA_DEADMAN_HEARTBEAT_FEEDER_PATHS` array in `scripts/lib/test-affected-paths.sh`
  records the declared edges. That array does NOT exist in the file (`grep -n DEADMAN scripts/lib/test-affected-paths.sh`
  finds nothing); it was drafted and not applied. Why it is not needed: the file's own header says its arrays are
  consumed by `scripts/test-all.sh` and `scripts/lint-orphan-test-suites.sh` to select REGISTERED suites, and this suite is
  not registered there, so an array for it would classify nothing. Its dependency edges are carried instead by the
  `pull_request` path filters of `infra-validation.yml`, which is what actually triggers the suite.
- The manifest wiring check reads the row text with python (the `infra-validation.yml` job has no bun) and, when `bun`
  exists, ALSO imports `MANIFEST` at runtime; the bun suites `heartbeat-reprovision-parity` and
  `heartbeat-live-reconcile` remain the authoritative import-level guards.
- The Guard 3 anti-vacuity count compares the lexed block parser against an independent prefix-match count taken over the
  comment- and heredoc-free text (a raw-text count would count `resource` lines inside heredocs and comments and make the
  must-PASS comment/heredoc row impossible).
