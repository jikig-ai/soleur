#!/usr/bin/env bash
# (#8097) Did the synthetic SEND_FAILED row traverse web-1 AND page?
#
# WHAT IT PROVES. apply-web-platform-infra.yml creates the Better Stack Logs alert
# `soleur-monitor-send-failed-prd` (betterstack-logs-alerts.tf) in its main apply, then its
# SSH-provisioned apply fires terraform_data.send_failed_alert_probe (server.tf), which runs
# `logger -p user.crit -t disk-monitor 'SOLEUR_DISK_MONITOR_SEND_FAILED … synthetic=1 probe_rev=<rev>'`
# on web-1. This script reads back, in ORDER, so each verdict names ONE cause:
#
#   (1) the alert exists live and is not paused    (GET telemetry.betterstack.com/api/v2/alerts)
#   (2) web-1 is shipping AT ALL over the window    (web-1-SCOPED positive control — source
#       2457081 is shared with the inngest host, so an unscoped control would be satisfied by
#       inngest rows while web-1's Vector is dead; ADR-197)
#   (3) the synthetic row is in the warehouse       (hot ∪ 14-day archive, keyed on
#       `synthetic=1 probe_rev=<rev>` with <rev> read from the checkout — the sweeper runs under
#       `env -i` with no Terraform, so the rev cannot be derived any other way)
#   (4) an incident fired for it                     (GET uptime.betterstack.com/api/v2/incidents,
#       matched on `name` OR `cause`, anchored on the ROW's own dt − 600 s)
#
# Closure of #8097 is THIS script's verdict, not the merge: the PR body carries `Ref #8097`.
#
# EXIT CONTRACT (sweep-followthroughs.sh):
#   0   PASS              verdict=pass                     -> the sweeper CLOSES #8097
#   3   CANNOT ESTABLISH  verdict=unknown | channel_dark   -> retry next sweep (the instrument
#                                                             did not answer, or web-1 is dark —
#                                                             not a finding about THIS chain)
#   5   ACTION REQUIRED   verdict=alert_absent | alert_paused | row_absent |
#                                 row_present_no_incident  -> the sweeper comments; a human reads
#                                                             the cause once. NO script files an
#                                                             issue (none has GH_TOKEN).
#   78  xtrace refusal (#7797)
#   exit 1 is NEVER used: to the sweeper 1 is FAIL, which reopens a human-closed issue.
#
# Test seam: SEND_FAILED_PROBE_BQ overrides the betterstack-query.sh path; SEND_FAILED_PROBE_TF
# overrides the .tf the rev is read from. `curl` is PATH-shimmed by the harness.
# Observability layer: 6 (sweeper workflow run log + the tracker issue comment the sweeper posts).
# RETIREMENT: once #8097 is closed by a sweeper PASS, `closed_precheck` never runs this again;
# the script stays as the reproduction. Re-verification = bump local.monitor_send_failed_probe_rev
# and merge (one synthetic page, by design).
# cq-test-fixtures-synthesized-only: no live response is captured into this file.

set -uo pipefail

# REFUSE TO RUN UNDER xtrace WITH A LIVE CREDENTIAL BOUND (#7797). The sweeper publishes stdout
# verbatim into a public GitHub issue comment. `case "$-" in *x*)` tests whether tracing is ON
# rather than enumerating the eight ways to turn it on.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}${BETTERSTACK_API_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BQ="${SEND_FAILED_PROBE_BQ:-${REPO_ROOT}/scripts/betterstack-query.sh}"
TF="${SEND_FAILED_PROBE_TF:-${REPO_ROOT}/apps/web-platform/infra/betterstack-logs-alerts.tf}"

ALERT_NAME="soleur-monitor-send-failed-prd"
# The alert's incident_cause PREFIX (betterstack-logs-alerts.tf) — the second incident key.
# Whether a Logs-alert incident carries the alert name in `name` is unproven; `cause` is a string
# the .tf controls, so it is matched too. Keep this literal in sync with the .tf.
CAUSE_PREFIX="SOLEUR_*_SEND_FAILED / _REFUSED row from a web-1 monitor unit"
WEB1_HOST="soleur-web-platform"
WINDOW_DAYS=14
INCIDENT_SLACK_S=600
ALERTS_HOST="telemetry.betterstack.com"
INCIDENTS_HOST="uptime.betterstack.com"

emit() { printf 'SOLEUR_SEND_FAILED_ALERT_PROBE verdict=%s detail=%s\n' "$1" "$2"; }
transient() { printf 'TRANSIENT: %s\n' "$1" >&2; }
action() { printf 'ACTION REQUIRED: %s\n' "$1" >&2; }

# NOT `: "${VAR:?msg}"` — that aborts with status 1, which the sweeper reads as FAIL.
for _v in BETTERSTACK_API_TOKEN BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [[ -z "${!_v:-}" ]]; then
    transient "${_v} is not set in this environment; nothing is known about the chain"
    emit unknown "${_v}-unset"
    exit 3
  fi
done
if [[ ! -f "$BQ" ]]; then
  transient "betterstack-query.sh not found at ${BQ}"
  emit unknown "query-script-absent"
  exit 3
fi

# The rev, read from the checkout. Digits only — it is interpolated into a ClickHouse LIKE.
REV="$(grep -oE 'monitor_send_failed_probe_rev[[:space:]]*=[[:space:]]*"[0-9]+"' "$TF" 2>/dev/null | grep -oE '"[0-9]+"' | tr -d '"' | head -1)"
if [[ -z "$REV" ]]; then
  transient "could not read a digits-only monitor_send_failed_probe_rev from ${TF}"
  emit unknown "probe_rev-unreadable"
  exit 3
fi
MARKER="synthetic=1 probe_rev=${REV}"

WORK="$(mktemp -d -t sfa-probe.XXXXXXXX)" || { emit unknown "mktemp-failed"; exit 3; }
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

# ── Paged GET with an exact host pin on pagination.next (the token never leaves the host) ────
# Prints the concatenated `.data[]` objects to stdout as a JSON array. Returns 0, or non-zero with
# a reason on stderr; the caller maps every failure to exit 3 (an unanswered read is never a
# verdict, ADR-192/197).
paged_get() { # <host> <path>
  local host="$1" url="https://$1$2" page=0 body="$WORK/page.json" code rc
  : > "$WORK/pages.ndjson"
  while [[ -n "$url" ]]; do
    page=$((page + 1))
    if [[ "$page" -gt 20 ]]; then printf 'pagination exceeded 20 pages on %s\n' "$host" >&2; return 1; fi
    case "$url" in
      "https://${host}/"*) ;;
      *) printf 'refusing off-host pagination.next (%s)\n' "${url%%\?*}" >&2; return 1 ;;
    esac
    rc=0
    code="$(curl --disable --noproxy '*' -sS -m 20 --proto '=https' -o "$body" -w '%{http_code}' \
      -H "Authorization: Bearer ${BETTERSTACK_API_TOKEN}" -H 'Accept: application/json' "$url")" || rc=$?
    if [[ "$rc" -ne 0 ]]; then printf 'curl exited %s on GET %s\n' "$rc" "${url%%\?*}" >&2; return 1; fi
    case "$code" in 2*) ;; *) printf 'HTTP %s on GET %s\n' "$code" "${url%%\?*}" >&2; return 1 ;; esac
    if ! jq -e '.data | type == "array"' "$body" >/dev/null 2>&1; then printf 'no data array in GET %s\n' "${url%%\?*}" >&2; return 1; fi
    jq -c '.data[]' "$body" >> "$WORK/pages.ndjson"
    url="$(jq -r '.pagination.next // empty' "$body")"
  done
  jq -s '.' "$WORK/pages.ndjson"
}

# ── (1) The alert itself ───────────────────────────────────────────────────────────────────
if ! alerts="$(paged_get "$ALERTS_HOST" /api/v2/alerts 2>"$WORK/err")"; then
  transient "alerts read did not answer: $(tr '\n' ' ' < "$WORK/err")"
  emit unknown "alerts-read-failed"
  exit 3
fi
alert="$(printf '%s' "$alerts" | jq -c --arg n "$ALERT_NAME" '[.[] | select(.attributes.name == $n)] | first // empty | {name: .attributes.name, paused: .attributes.paused, paused_reason: .attributes.paused_reason}')"
if [[ -z "$alert" ]]; then
  action "alert ${ALERT_NAME} is not in the live list: the main apply never created it (or it was deleted vendor-side). Check the merge run's 'Terraform apply' step for logtail_exploration_alert.monitor_send_failed."
  emit alert_absent "name=${ALERT_NAME}"
  exit 5
fi
if [[ "$(printf '%s' "$alert" | jq -r '.paused')" == "true" ]]; then
  reason="$(printf '%s' "$alert" | jq -r '.paused_reason // "n/a"' | tr '\n"' '  ')"
  action "alert ${ALERT_NAME} is PAUSED live (paused_reason=${reason}). A vendor auto-pause means the template SQL was rejected — fix betterstack-logs-alerts.tf and merge (the apply re-arms it)."
  emit alert_paused "name=${ALERT_NAME} paused_reason=${reason}"
  exit 5
fi

# ── Warehouse reads: hot window ∪ 14-day archive, always the same window ──────────────────
# A ClickHouse mid-stream exception arrives as a BARE line outside the JSONEachRow stream and
# curl --fail-with-body still returns 0 on the HTTP 200 carrying it (#7855 P1-B). So an answer is
# "every non-empty line is a JSON object"; anything else is a transport failure, never a verdict.
bq_answered() {
  local line
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "$line" == '{'* ]] || return 1
  done <<<"$1"
  printf '%s\n' "$1" | jq -e -s 'all(type == "object")' >/dev/null 2>&1
}
WINDOW="dt >= now() - INTERVAL ${WINDOW_DAYS} DAY"
UNION="SELECT dt, raw FROM remote(\$BS_TABLE) WHERE ${WINDOW}
       UNION ALL
       SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1 AND ${WINDOW}"
run_bq() { # <sql> -> stdout; returns 1 when the read did not answer
  local out rc=0
  out="$(bash "$BQ" "$1" 2>&1)" || rc=$?
  if [[ "$rc" -ne 0 ]] || ! bq_answered "$out"; then
    printf '%s' "$out" | tail -3 | tr '\n' ' ' > "$WORK/bq.err"
    return 1
  fi
  printf '%s' "$out"
}

# ── (2) Web-1-scoped positive control over the SAME window as (3) ─────────────────────────
if ! control="$(run_bq "SELECT count() AS n, min(dt) AS min_dt, max(dt) AS max_dt FROM (${UNION})
  WHERE JSONExtractString(raw, 'host') = '${WEB1_HOST}' FORMAT JSONEachRow")"; then
  transient "control read did not answer (rc/shape): $(<"$WORK/bq.err")"
  emit unknown "control-read-failed"
  exit 3
fi
control_n="$(printf '%s' "$control" | jq -r -s '.[0].n // 0')"
control_min="$(printf '%s' "$control" | jq -r -s '.[0].min_dt // "n/a"')"
control_max="$(printf '%s' "$control" | jq -r -s '.[0].max_dt // "n/a"')"
if [[ ! "$control_n" =~ ^[0-9]+$ ]] || [[ "$control_n" -eq 0 ]]; then
  transient "web-1 shipped zero rows in ${WINDOW_DAYS}d (control_rows_web1=${control_n}): web-1's Vector is dark, so nothing can be concluded about this chain. Not a finding about the probe."
  emit channel_dark "host=${WEB1_HOST} control_rows_web1=${control_n} window_days=${WINDOW_DAYS}"
  exit 3
fi

# ── (3) The synthetic row (LIKE prefilter, jq field anchor decides) ───────────────────────
if ! rows="$(run_bq "SELECT dt, JSONExtractString(raw, 'host') AS host, JSONExtractString(raw, 'message') AS msg FROM (${UNION})
  WHERE JSONExtractString(raw, 'PRIORITY') = '2' AND JSONExtractString(raw, 'message') LIKE '%${MARKER}%'
  ORDER BY dt DESC LIMIT 20 FORMAT JSONEachRow")"; then
  transient "readback did not answer: $(<"$WORK/bq.err")"
  emit unknown "readback-failed"
  exit 3
fi
row="$(printf '%s' "$rows" | jq -c -s --arg m "$MARKER" '[.[] | select(.msg != null and (.msg | contains($m)))] | first // empty')"
if [[ -z "$row" ]]; then
  action "the synthetic row (${MARKER}) is not in the warehouse although web-1 shipped ${control_n} rows in ${WINDOW_DAYS}d. Candidate causes — this script cannot read the apply run (no GH_TOKEN) and does not pick one: (a) the SSH stage was green-skipped by the ssh_token_gate arm (#7539), so the probe never ran; (b) the main apply failed AFTER creating the exploration and the job stopped before the SSH step; (c) a journald PRIORITY / Vector Source-2 match fault on web-1 (the last unmeasured link). Check the merge run first; re-fire = bump probe_rev."
  emit row_absent "marker=${MARKER} control_rows_web1=${control_n} control_min_dt=${control_min} control_max_dt=${control_max}"
  exit 5
fi
row_dt="$(printf '%s' "$row" | jq -r '.dt')"
row_host="$(printf '%s' "$row" | jq -r '.host // ""')"
host_mismatch=0; [[ "$row_host" == "$WEB1_HOST" ]] || host_mismatch=1

# Real firings in the window (a real page that masks the verdict must be visible).
nonsynthetic="n/a"
if ns="$(run_bq "SELECT count() AS n FROM (${UNION})
  WHERE JSONExtractString(raw, 'PRIORITY') = '2' AND startsWith(JSONExtractString(raw, 'message'), 'SOLEUR_')
    AND multiSearchAny(JSONExtractString(raw, 'message'), ['_SEND_FAILED', '_REFUSED'])
    AND JSONExtractString(raw, 'message') NOT LIKE '%synthetic=1%' FORMAT JSONEachRow")"; then
  nonsynthetic="$(printf '%s' "$ns" | jq -r -s '.[0].n // "n/a"')"
fi

# ── (4) The incident ──────────────────────────────────────────────────────────────────────
if ! incidents="$(paged_get "$INCIDENTS_HOST" /api/v2/incidents 2>"$WORK/err")"; then
  transient "incidents read did not answer: $(tr '\n' ' ' < "$WORK/err")"
  emit unknown "incidents-read-failed"
  exit 3
fi
row_epoch="$(date -u -d "$row_dt" +%s 2>/dev/null || echo "")"
if [[ -z "$row_epoch" ]]; then
  transient "could not parse the row's dt (${row_dt}) as a time anchor"
  emit unknown "row-dt-unparseable"
  exit 3
fi
anchor=$((row_epoch - INCIDENT_SLACK_S))
# PROJECTED, never raw: the raw objects carry acknowledged_by / resolved_by / screenshot URLs and
# this stdout lands in a public issue comment.
projected="$(printf '%s' "$incidents" | jq -c '[.[] | {id, name: .attributes.name, cause: .attributes.cause, started_at: .attributes.started_at, resolved_at: .attributes.resolved_at}]')"
match="$(printf '%s' "$projected" | jq -c --arg n "$ALERT_NAME" --arg c "$CAUSE_PREFIX" --argjson a "$anchor" '
  [.[] | select((.name == $n) or ((.cause // "") | startswith($c)))
       | . + {epoch: ((.started_at // "1970-01-01T00:00:00Z") | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)}
       | select(.epoch >= $a)
       | . + {match: (if .name == $n then "name" else "cause" end)}]
  | sort_by(.epoch) | first // empty')"
if [[ -z "$match" ]]; then
  action "the synthetic row is stored (dt=${row_dt}) but no Better Stack incident matches the alert by name (${ALERT_NAME}) or cause prefix, started at or after dt-${INCIDENT_SLACK_S}s. Either the first evaluation after creation missed the row's bucket (re-fire = bump probe_rev) or the alert's email surface is not producing incidents. Alert: ${alert}. Incidents seen (projected): ${projected}"
  emit row_present_no_incident "marker=${MARKER} row_dt=${row_dt} host=${row_host} host_mismatch=${host_mismatch} control_rows_web1=${control_n} nonsynthetic_rows=${nonsynthetic}"
  exit 5
fi
incident_id="$(printf '%s' "$match" | jq -r '.id')"
incident_field="$(printf '%s' "$match" | jq -r '.match')"
emit pass "row_found=1 host=${row_host} host_mismatch=${host_mismatch} row_dt=${row_dt} control_rows_web1=${control_n} control_min_dt=${control_min} control_max_dt=${control_max} nonsynthetic_rows=${nonsynthetic} incident_id=${incident_id} incident_match=${incident_field} alert_paused=false"
exit 0
