#!/usr/bin/env bash
# Follow-through verification for #8706 — web-1's luks-monitor.timer was never installed.
#
# WHAT IT PROVES. Before #8706 the only luks-monitor rows in Better Stack came from the daily
# workspaces-luks-verify.yml job (it ships its own copy of luks-monitor.sh over SSH), which kept the
# shared heartbeat up while the host timer did not exist. #8706 installs the units through
# terraform_data.luks_monitor_install. This probe closes #8706 only on evidence that the HOST TIMER
# fires nightly: three CONSECUTIVE UTC dates each carrying a host-unit `OK:` row in the 00 UTC hour.
#
# THE PREDICATE: the conjuncts of logtail_exploration_alert.luks_monitor_host_timer_dark exactly
# (luks-monitor-host-timer-8706.test.sh extracts them from betterstack-logs-alerts.tf and compares
# the sets), plus the hour:
#   SYSLOG_IDENTIFIER = 'luks-monitor'           scopes the scan;
#   _SYSTEMD_UNIT     = 'luks-monitor.service'   excludes the verify job's SSH-session rows (the
#                                                masking defect) — the unit's stdout copy of each
#                                                line always carries it;
#   message LIKE '%OK: /mnt/data is LUKS-backed%' excludes FAIL (...) and helper rows;
#   host_name         = 'soleur-web-platform'    web-1 only (web-2 ships to the same source);
#   toHour(dt, 'UTC') = 0                        keeps timer-fired runs and drops a Persistent=true
#                                                catch-up after a reboot. It drops the install-time
#                                                kick too UNLESS the SSH apply itself lands in the
#                                                00 UTC hour; then that kick counts as one night.
# Three consecutive nights, not one, so a single night (or that one kick) cannot close it alone.
#
# RETIREMENT: once #8706 is closed, delete this script, its suite
# (luks-monitor-host-timer-8706.test.sh), its run_suite line in scripts/test-all.sh, and the
# directive on #8706. After a PASS the sweeper keeps re-running closed trackers for a while, and a
# single night that misses the 00 UTC hour (a reboot catch-up) would read as FAIL and reopen it.
#
# POSITIVE CONTROL FIRST. Zero web-1 luks-monitor rows of ANY kind in the last 36 h means the log
# channel is dark (Vector/Better Stack), not that the timer failed: the verify job writes rows
# daily. That is reported as exit 2, never as FAIL and never as PASS. 36 h, not the whole window, so
# a pipeline outage in the last day or two reads as TRANSIENT rather than as a failed timer.
#
# OUTPUT RULES. The sweeper posts this output into a public issue comment: dates and counts only,
# never a row's message, host, or any credential.
#
# Exit semantics (scripts/sweep-followthroughs.sh contract):
#   0 = PASS       (HOST_TIMER_PASS nights=3 — three consecutive qualifying UTC dates; close #8706)
#   1 = FAIL       (channel live, fewer than three consecutive qualifying nights; leave open)
#   2 = TRANSIENT  (creds not injected, query/auth/parse failure, or the channel is dark)
#
# Read-only: never mutates GitHub or the host.
#
# Required env (read by scripts/betterstack-query.sh): BETTERSTACK_QUERY_HOST,
#   BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD. Optional test seam:
#   LUKS_HOST_TIMER_BQ (path to a betterstack-query.sh stand-in).
#
# Directive for #8706:
#   <!-- soleur:followthrough script=scripts/followthroughs/luks-monitor-host-timer-8706.sh earliest=<merge+3d> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE with a live credential set (#7797): tracing prints expanded commands,
# and this output is posted into an issue comment. `${VAR:+x}` tests non-emptiness without
# expanding the value. In the prologue, so it also covers the suite's `source` of this file.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}${BETTERSTACK_QUERY_USERNAME:+x}${BETTERSTACK_QUERY_HOST:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (BETTERSTACK_QUERY_*). Unset it to trace safely (see #7797).\n' >&2
      exit 78
    fi
    ;;
esac

WINDOW_DAYS=5
REQUIRED_NIGHTS=3

# longest_consecutive_run — PURE. stdin: YYYY-MM-DD dates, one per line, any order, duplicates
# allowed, blank lines ignored. stdout: the length of the longest run of consecutive calendar days
# (0 for no dates). Returns 1 (printing nothing) on any line that is not a real calendar date, so a
# malformed row can never be counted as a night.
longest_consecutive_run() {
  local line epoch day prev="" run=0 best=0
  local days=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    epoch="$(date -u -d "${line}T00:00:00Z" +%s 2>/dev/null)" || return 1
    # Round-trip: GNU date normalises some out-of-range dates instead of refusing them.
    [[ "$(date -u -d "@$epoch" +%F 2>/dev/null)" == "$line" ]] || return 1
    days+="$((epoch / 86400))"$'\n'
  done
  while IFS= read -r day; do
    [[ -z "$day" ]] && continue
    if [[ -n "$prev" && "$day" -eq $((prev + 1)) ]]; then run=$((run + 1)); else run=1; fi
    [[ "$run" -gt "$best" ]] && best="$run"
    prev="$day"
  done < <(printf '%s' "$days" | sort -n -u)
  printf '%s\n' "$best"
}

main() {
  # Explicit empty-checks, NOT ${VAR:?} (which aborts with status 1 = FAIL, the opposite of TRANSIENT).
  local v
  for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
    if [[ -z "${!v:-}" ]]; then
      echo "TRANSIENT: $v is not injected (declare it in the directive secrets= clause)" >&2
      exit 2
    fi
  done

  local repo_root bq
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  bq="${LUKS_HOST_TIMER_BQ:-$repo_root/scripts/betterstack-query.sh}"
  if [[ ! -f "$bq" ]]; then
    echo "TRANSIENT: betterstack-query.sh not found at $bq" >&2
    exit 2
  fi

  # Hot window + s3 archive (remote() alone is ~40 minutes). Raw-SQL mode substitutes the two
  # $BS_TABLE tokens; the archive arm is deduplicated with _row_type = 1.
  local src out rc
  src="(SELECT dt, raw FROM remote(\$BS_TABLE) WHERE dt > now() - INTERVAL ${WINDOW_DAYS} DAY
        UNION ALL
        SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1 AND dt > now() - INTERVAL ${WINDOW_DAYS} DAY)"

  # ---- 1. POSITIVE CONTROL: any luks-monitor row at all -------------------------------------------
  out="$(bash "$bq" "SELECT count() AS n FROM ${src}
    WHERE JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'luks-monitor'
      AND JSONExtractString(raw, 'host_name') = 'soleur-web-platform'
      AND dt > now() - INTERVAL 36 HOUR
    FORMAT JSONEachRow" 2>/dev/null)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "TRANSIENT: Better Stack positive-control query failed (exit $rc: creds / auth / network / query fault)"
    exit 2
  fi
  # A count() query returns exactly one row. UInt64 arrives quoted in JSONEachRow; accept either.
  local control
  control="$(printf '%s\n' "$out" | jq -R -r 'fromjson? | select(type == "object" and has("n")) | .n | tostring' 2>/dev/null | head -1)"
  if ! [[ "$control" =~ ^[0-9]+$ ]]; then
    echo "TRANSIENT: could not parse the positive-control count"
    exit 2
  fi
  echo "positive_control luks_monitor_rows=${control} window_hours=36"
  if [[ "$control" -eq 0 ]]; then
    echo "TRANSIENT: zero web-1 luks-monitor rows of any kind in 36h — the log channel is dark (the verify job writes rows daily), so the host timer cannot be judged either way"
    exit 2
  fi

  # ---- 2. Host-timer nights: host-unit OK rows in the 00 UTC hour, per UTC date --------------------
  out="$(bash "$bq" "SELECT toString(toDate(dt, 'UTC')) AS d, count() AS n FROM ${src}
    WHERE JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'luks-monitor'
      AND JSONExtractString(raw, '_SYSTEMD_UNIT') = 'luks-monitor.service'
      AND JSONExtractString(raw, 'message') LIKE '%OK: /mnt/data is LUKS-backed%'
      AND JSONExtractString(raw, 'host_name') = 'soleur-web-platform'
      AND toHour(dt, 'UTC') = 0
    GROUP BY d ORDER BY d FORMAT JSONEachRow" 2>/dev/null)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "TRANSIENT: Better Stack host-timer query failed (exit $rc: creds / auth / network / query fault)"
    exit 2
  fi
  # An EMPTY result (rc 0, no rows) is a real answer: zero qualifying nights. A NON-empty result
  # must parse completely — any line that is not a {d: YYYY-MM-DD, n: <int>} row is a shape fault.
  local line d n dates="" nights=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    d="$(printf '%s' "$line" | jq -r 'select(type == "object") | .d // empty | tostring' 2>/dev/null)"
    n="$(printf '%s' "$line" | jq -r 'select(type == "object") | .n // empty | tostring' 2>/dev/null)"
    if ! [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ && "$n" =~ ^[0-9]+$ ]]; then
      echo "TRANSIENT: unparseable host-timer row (expected {d, n}); refusing to count it"
      exit 2
    fi
    [[ "$n" -gt 0 ]] || continue
    echo "host_timer_day=${d} rows=${n}"
    dates+="${d}"$'\n'
  done <<<"$out"

  if ! nights="$(printf '%s' "$dates" | longest_consecutive_run)"; then
    echo "TRANSIENT: a host-timer date did not parse as a calendar date"
    exit 2
  fi

  if [[ "$nights" -ge "$REQUIRED_NIGHTS" ]]; then
    echo "HOST_TIMER_PASS nights=${REQUIRED_NIGHTS}"
    echo "PASS: luks-monitor.timer fired from luks-monitor.service on ${nights} consecutive UTC nights (00 UTC hour, OK row). Closing #8706."
    exit 0
  fi
  echo "FAIL: ${nights} consecutive host-timer night(s) of ${REQUIRED_NIGHTS} required in the last ${WINDOW_DAYS}d (luks-monitor.service OK rows in the 00 UTC hour). The channel is live (positive control above), so the host timer is not yet proven."
  exit 1
}

# Sourced by the test suite for longest_consecutive_run; executed by the sweeper.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
