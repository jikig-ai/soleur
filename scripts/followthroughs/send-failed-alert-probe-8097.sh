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
#   (2) web-1 is shipping AT ALL over the window,   (web-1-SCOPED positive control — source
#       and was still shipping RECENTLY             2457081 is shared with the inngest host, so an
#                                                    unscoped control would be satisfied by inngest
#                                                    rows while web-1's Vector is dead; and a control
#                                                    that only proves "shipped some time in 14 days"
#                                                    cannot tell a channel that died after the merge
#                                                    from a probe that never fired — ADR-197)
#   (3) the synthetic row is in the warehouse       (hot ∪ 14-day archive, keyed on
#       `synthetic=1 probe_rev=<rev>` with <rev> read from the checkout — the sweeper runs under
#       `env -i` with no Terraform, so the rev cannot be derived any other way)
#   (4) an incident fired for it                     (GET uptime.betterstack.com/api/v2/incidents —
#       newest-first — matched on `name` OR `cause`, anchored on the ROW's own dt − 600 s; the
#       read stops at the first page older than the anchor, so the account's growing incident
#       history can never push the answer past a page cap)
#
# The alert's identity (`name`, `incident_cause`) is READ FROM THE .tf, like the rev — a restated
# literal here would silently desync on a rename and turn every sweep into an ACTION REQUIRED.
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
# PUBLIC-COMMENT DISCIPLINE. The sweeper posts this script's stdout+stderr verbatim into a public
# issue comment. Every line printed below is therefore projected: credentials are scrubbed from
# any transport error before it is echoed (a ClickHouse 516 body names the query USER), incident
# objects are reduced to {id,name,cause,started_at,resolved_at} and windowed to the anchor, and
# a refused pagination URL is reported by host only.
#
# Test seam: SEND_FAILED_PROBE_BQ overrides the betterstack-query.sh path; SEND_FAILED_PROBE_TF
# overrides the .tf the rev/name/cause are read from. `curl` is PATH-shimmed by the harness.
# Observability layer: 6 (sweeper workflow run log + the tracker issue comment the sweeper posts).
# RETIREMENT: once #8097 is closed by a sweeper PASS, `closed_precheck` never runs this again;
# the script stays as the reproduction. Re-verification = bump local.monitor_send_failed_probe_rev
# and merge (one synthetic page, by design; see betterstack-logs-alerts.tf §CHANGED THE SQL).
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
# Same TLS-subversion prologue as betterstack-query.sh: none of these can re-point a Bearer
# request or leak its keys when the sweeper's `env -i` is absent (a local `doppler run`).
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS
# /tmp is a shared tmpfs on this machine class; the sweeper's `env -i` leaves TMPDIR unset.
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BQ="${SEND_FAILED_PROBE_BQ:-${REPO_ROOT}/scripts/betterstack-query.sh}"
TF="${SEND_FAILED_PROBE_TF:-${REPO_ROOT}/apps/web-platform/infra/betterstack-logs-alerts.tf}"

WEB1_HOST="soleur-web-platform"
WINDOW_DAYS=14
INCIDENT_SLACK_S=600
# A control whose newest row is older than this is a channel that stopped shipping AFTER the
# probe could have fired — reported as channel_dark, never as row_absent. web-1 ships ~1,400
# rows/h on this source (measured 2026-09-13), so 2 h of silence is not a quiet period.
CONTROL_FRESH_S=7200
ALERTS_HOST="telemetry.betterstack.com"
INCIDENTS_HOST="uptime.betterstack.com"
PAGE_CAP=50

emit() { printf 'SOLEUR_SEND_FAILED_ALERT_PROBE verdict=%s detail="%s"\n' "$1" "${2//\"/}"; }
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
if [[ ! -f "$TF" ]]; then
  transient "betterstack-logs-alerts.tf not found at ${TF}"
  emit unknown "tf-absent"
  exit 3
fi

# ── Identity, read from the checkout (comment lines dropped first — a `# was = "1"` note above
# the local must not win). Digits-only rev: it is interpolated into a ClickHouse LIKE.
tf_stripped="$(grep -vE '^[[:space:]]*#' "$TF")"
REV="$(printf '%s\n' "$tf_stripped" | grep -oE '^[[:space:]]*monitor_send_failed_probe_rev[[:space:]]*=[[:space:]]*"[0-9]+"' | grep -oE '"[0-9]+"' | tr -d '"' | head -1)"
if [[ -z "$REV" ]]; then
  transient "could not read a digits-only monitor_send_failed_probe_rev from ${TF}"
  emit unknown "probe_rev-unreadable"
  exit 3
fi
MARKER="synthetic=1 probe_rev=${REV}"
# The alert block's `name` (the first `name =` after the alert resource header) and the prefix of
# its `incident_cause` up to the em-dash — the two keys the incident match uses.
alert_block="$(printf '%s\n' "$tf_stripped" | awk '/resource "logtail_exploration_alert" "monitor_send_failed"/{f=1} f{print} f&&/^}/{exit}')"
ALERT_NAME="$(printf '%s\n' "$alert_block" | grep -oE '^[[:space:]]*name[[:space:]]*=[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"/\1/')"
CAUSE_PREFIX="$(printf '%s\n' "$alert_block" | grep -oE '^[[:space:]]*incident_cause[[:space:]]*=[[:space:]]*"[^"]+"' | head -1 | sed -E 's/^[^"]*"//; s/"$//; s/ — .*$//; s/ +$//')"
if [[ -z "$ALERT_NAME" || -z "$CAUSE_PREFIX" ]]; then
  transient "could not read the alert name / incident_cause from ${TF} (name=${ALERT_NAME:-<empty>})"
  emit unknown "alert-identity-unreadable"
  exit 3
fi

WORK="$(mktemp -d -t sfa-probe.XXXXXXXX)" || { emit unknown "mktemp-failed"; exit 3; }
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

redact() { # scrub both halves of the ClickHouse Basic-auth pair from any text about to be printed
  local s="$1"
  s="${s//"$BETTERSTACK_QUERY_USERNAME"/<query-user>}"
  s="${s//"$BETTERSTACK_QUERY_PASSWORD"/<redacted>}"
  s="${s//"$BETTERSTACK_API_TOKEN"/<redacted>}"
  # A 516 body names the user inside the exception text even when the env value is not a
  # substring of it (a rotated name); collapse that clause regardless.
  printf '%s' "$s" | sed -E 's/DB::Exception: [^:]+: Authentication failed/DB::Exception: <query-user>: Authentication failed/g'
}

# ── Paged GET with an exact host pin on pagination.next (the token never leaves the host) ────
# Prints the concatenated `.data[]` objects to stdout as a JSON array. Returns 0, or non-zero with
# a reason on stderr; the caller maps every failure to exit 3 (an unanswered read is never a
# verdict, ADR-192/197). An optional stop epoch ends the walk once a page's OLDEST `started_at`
# predates it — the endpoints are newest-first, so everything after that page is irrelevant.
paged_get() { # <host> <path> [stop-epoch]
  local host="$1" url="https://$1$2" stop="${3:-}" page=0 body="$WORK/page.json" code rc oldest
  : > "$WORK/pages.ndjson"
  while [[ -n "$url" ]]; do
    page=$((page + 1))
    if [[ "$page" -gt "$PAGE_CAP" ]]; then printf 'pagination exceeded %s pages on %s\n' "$PAGE_CAP" "$host" >&2; return 1; fi
    case "$url" in
      "https://${host}/"*) ;;
      *) printf 'refusing off-host pagination.next (host=%s)\n' "$(printf '%s' "$url" | sed -E 's#^[a-zA-Z]+://([^/?@]*@)?([^/?#]*).*#\2#')" >&2; return 1 ;;
    esac
    rc=0
    # -g: no URL globbing (a `{a,b}` in pagination.next must not fan out); --max-redirs 0 for
    # explicitness (curl never follows without -L anyway).
    code="$(curl --disable --noproxy '*' -g -sS -m 20 --proto '=https' --max-redirs 0 -o "$body" -w '%{http_code}' \
      -H "Authorization: Bearer ${BETTERSTACK_API_TOKEN}" -H 'Accept: application/json' "$url")" || rc=$?
    if [[ "$rc" -ne 0 ]]; then printf 'curl exited %s on GET %s\n' "$rc" "${url%%\?*}" >&2; return 1; fi
    case "$code" in 2*) ;; *) printf 'HTTP %s on GET %s\n' "$code" "${url%%\?*}" >&2; return 1 ;; esac
    if ! jq -e '.data | type == "array"' "$body" >/dev/null 2>&1; then printf 'no data array in GET %s\n' "${url%%\?*}" >&2; return 1; fi
    jq -c '.data[]' "$body" >> "$WORK/pages.ndjson"
    if [[ -n "$stop" ]]; then
      oldest="$(jq -r '[.data[] | .attributes.started_at // empty | (try (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) catch empty)] | min // empty' "$body" 2>/dev/null)"
      if [[ "$oldest" =~ ^[0-9]+$ ]] && [[ "$oldest" -lt "$stop" ]]; then break; fi
    fi
    url="$(jq -r '.pagination.next // empty' "$body")"
  done
  jq -s '.' "$WORK/pages.ndjson"
}

# ── (1) The alert itself ───────────────────────────────────────────────────────────────────
if ! alerts="$(paged_get "$ALERTS_HOST" /api/v2/alerts 2>"$WORK/err")"; then
  transient "alerts read did not answer: $(redact "$(tr '\n' ' ' < "$WORK/err")")"
  emit unknown "alerts-read-failed"
  exit 3
fi
# First match wins on a duplicate name (the API lists newest-first; the reconcile arm keys a Map,
# i.e. last wins — a duplicate is itself a defect the arm reports as paused/absent per member).
if ! alert="$(printf '%s' "$alerts" | jq -c --arg n "$ALERT_NAME" '[.[] | select(.attributes.name == $n)] | first // empty | {name: .attributes.name, paused: .attributes.paused, paused_reason: .attributes.paused_reason}' 2>"$WORK/err")"; then
  transient "alerts list unparseable: $(redact "$(tr '\n' ' ' < "$WORK/err")")"
  emit unknown "alerts-parse-failed"
  exit 3
fi
if [[ -z "$alert" ]]; then
  action "alert ${ALERT_NAME} is not in the live list: the main apply never created it (or it was deleted vendor-side). Check the merge run's 'Terraform apply' step for logtail_exploration_alert.monitor_send_failed."
  emit alert_absent "name=${ALERT_NAME}"
  exit 5
fi
if [[ "$(printf '%s' "$alert" | jq -r '.paused')" == "true" ]]; then
  reason="$(printf '%s' "$alert" | jq -r '.paused_reason // "n/a"' | tr -d '\n' | tr '"' ' ')"
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
    redact "$(printf '%s' "$out" | tail -3 | tr '\n' ' ')" > "$WORK/bq.err"
    return 1
  fi
  printf '%s' "$out"
}
one_row() { # an aggregate query answers with EXACTLY one row; anything else is not an answer
  [[ "$(printf '%s' "$1" | jq -s 'length' 2>/dev/null)" == "1" ]]
}

# ── (2) Web-1-scoped positive control over the SAME window as (3) ─────────────────────────
if ! control="$(run_bq "SELECT count() AS n, min(dt) AS min_dt, max(dt) AS max_dt FROM (${UNION})
  WHERE JSONExtractString(raw, 'host') = '${WEB1_HOST}' FORMAT JSONEachRow")"; then
  transient "control read did not answer (rc/shape): $(<"$WORK/bq.err")"
  emit unknown "control-read-failed"
  exit 3
fi
if ! one_row "$control"; then
  transient "control read returned $(printf '%s' "$control" | jq -s 'length' 2>/dev/null || echo '?') rows, expected exactly 1 (an aggregate always answers with one row)"
  emit unknown "control-read-empty"
  exit 3
fi
control_n="$(printf '%s' "$control" | jq -r -s '.[0].n // 0')"
control_min="$(printf '%s' "$control" | jq -r -s '.[0].min_dt // "n/a"')"
control_max="$(printf '%s' "$control" | jq -r -s '.[0].max_dt // "n/a"')"
if [[ ! "$control_n" =~ ^[0-9]+$ ]] || [[ "$control_n" -eq 0 ]]; then
  transient "web-1 shipped zero rows in ${WINDOW_DAYS}d (control_rows_web1=${control_n}): web-1's Vector is dark, so nothing can be concluded about this chain. Not a finding about the probe."
  emit channel_dark "host=${WEB1_HOST} reason=no-rows control_rows_web1=${control_n} window_days=${WINDOW_DAYS}"
  exit 3
fi
control_max_epoch="$(date -u -d "${control_max} UTC" +%s 2>/dev/null || echo "")"
now_epoch="$(date -u +%s)"
if [[ -n "$control_max_epoch" ]] && (( now_epoch - control_max_epoch > CONTROL_FRESH_S )); then
  transient "web-1's newest row is ${control_max} (older than ${CONTROL_FRESH_S}s): the channel stopped shipping after that point, so an absent probe row would say nothing about the probe. Not a finding about the chain."
  emit channel_dark "host=${WEB1_HOST} reason=stale control_rows_web1=${control_n} control_max_dt=${control_max// /T} fresh_s=${CONTROL_FRESH_S}"
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
# The rev must be TERMINATED: `probe_rev=1` is a prefix of `probe_rev=12`.
row="$(printf '%s' "$rows" | jq -c -s --arg re "synthetic=1 probe_rev=${REV}($|[[:space:]])" '[.[] | select(.msg != null and (.msg | test($re)))] | first // empty')"
if [[ -z "$row" ]]; then
  action "the synthetic row (${MARKER}) is not in the warehouse although web-1 shipped ${control_n} rows in ${WINDOW_DAYS}d (newest ${control_max}). Candidate causes — this script cannot read the apply run (no GH_TOKEN) and does not pick one: (a) the SSH stage was green-skipped by the ssh_token_gate arm (#7539), so the probe never ran; (b) the main apply failed AFTER creating the exploration and the job stopped before the SSH step; (c) a journald PRIORITY / Vector Source-2 match fault on web-1 (the last unmeasured link). Check the merge run first; re-fire = bump probe_rev."
  emit row_absent "marker=${MARKER} control_rows_web1=${control_n} control_min_dt=${control_min// /T} control_max_dt=${control_max// /T}"
  exit 5
fi
row_dt="$(printf '%s' "$row" | jq -r '.dt')"
row_host="$(printf '%s' "$row" | jq -r '.host // ""')"
host_mismatch=0; [[ "$row_host" == "$WEB1_HOST" ]] || host_mismatch=1
# The row's own dt is the time anchor for step (4) — computed BEFORE the incidents read so the
# read can stop at the first page older than it.
row_epoch="$(date -u -d "${row_dt} UTC" +%s 2>/dev/null || echo "")"
if [[ -z "$row_epoch" ]]; then
  transient "could not parse the row's dt (${row_dt}) as a time anchor"
  emit unknown "row-dt-unparseable"
  exit 3
fi
anchor=$((row_epoch - INCIDENT_SLACK_S))

# Real firings in the window (a real page that masks the verdict must be visible).
nonsynthetic="n/a"
if ns="$(run_bq "SELECT count() AS n FROM (${UNION})
  WHERE JSONExtractString(raw, 'PRIORITY') = '2' AND startsWith(JSONExtractString(raw, 'message'), 'SOLEUR_')
    AND multiSearchAny(JSONExtractString(raw, 'message'), ['_SEND_FAILED', '_REFUSED'])
    AND JSONExtractString(raw, 'message') NOT LIKE '%synthetic=1%' FORMAT JSONEachRow")" && one_row "$ns"; then
  nonsynthetic="$(printf '%s' "$ns" | jq -r -s '.[0].n // "n/a"')"
fi

# ── (4) The incident ──────────────────────────────────────────────────────────────────────
if ! incidents="$(paged_get "$INCIDENTS_HOST" /api/v2/incidents "$anchor" 2>"$WORK/err")"; then
  transient "incidents read did not answer: $(redact "$(tr '\n' ' ' < "$WORK/err")")"
  emit unknown "incidents-read-failed"
  exit 3
fi
# PROJECTED, never raw: the raw objects carry acknowledged_by / resolved_by / screenshot URLs and
# this stdout lands in a public issue comment. Windowed to the anchor and capped, so the account's
# whole outage history is never posted. A `started_at` the parser cannot read is a transport
# fault (exit 3), never a verdict.
if ! projected="$(printf '%s' "$incidents" | jq -c --argjson a "$anchor" '
  [.[] | {id, name: .attributes.name, cause: .attributes.cause, started_at: .attributes.started_at, resolved_at: .attributes.resolved_at}
       | . + {epoch: ((.started_at // "1970-01-01T00:00:00Z") | (try (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) catch null))}]
  | if any(.[]; .epoch == null) then error("unparseable started_at") else . end
  | [.[] | select(.epoch >= $a)] | .[:20]' 2>"$WORK/err")"; then
  transient "incident list unparseable: $(redact "$(tr '\n' ' ' < "$WORK/err")")"
  emit unknown "incident-parse-failed"
  exit 3
fi
if ! match="$(printf '%s' "$projected" | jq -c --arg n "$ALERT_NAME" --arg c "$CAUSE_PREFIX" '
  [.[] | select((.name == $n) or ((.cause // "") | startswith($c)))
       | . + {match: (if .name == $n then "name" else "cause" end)}]
  | sort_by(.epoch) | first // empty' 2>"$WORK/err")"; then
  transient "incident match failed: $(redact "$(tr '\n' ' ' < "$WORK/err")")"
  emit unknown "incident-match-failed"
  exit 3
fi
if [[ -z "$match" ]]; then
  action "the synthetic row is stored (dt=${row_dt}) but no Better Stack incident matches the alert by name (${ALERT_NAME}) or cause prefix, started at or after dt-${INCIDENT_SLACK_S}s. Either the first evaluation after creation missed the row's bucket (re-fire = bump probe_rev) or the alert's email surface is not producing incidents. Alert: ${alert}. Incidents since the anchor (projected, newest 20): ${projected}"
  emit row_present_no_incident "marker=${MARKER} row_dt=${row_dt// /T} host=${row_host} host_mismatch=${host_mismatch} control_rows_web1=${control_n} nonsynthetic_rows=${nonsynthetic}"
  exit 5
fi
incident_id="$(printf '%s' "$match" | jq -r '.id')"
incident_field="$(printf '%s' "$match" | jq -r '.match')"
emit pass "row_found=1 host=${row_host} host_mismatch=${host_mismatch} row_dt=${row_dt// /T} control_rows_web1=${control_n} control_min_dt=${control_min// /T} control_max_dt=${control_max// /T} nonsynthetic_rows=${nonsynthetic} incident_id=${incident_id} incident_match=${incident_field} alert_paused=false"
exit 0
