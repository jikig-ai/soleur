#!/usr/bin/env bash
# (#11631) Feeder for the two archive-fed dead-man heartbeats that replaced the native logs alerts
# `luks_monitor_host_timer_dark` (window 97200 s, once-a-day row) and `claude_cost_capture_dark` (window 86400 s):
#
#   luks-monitor-host-timer -> betteruptime_heartbeat.luks_monitor_host_timer  (soleur-luks-monitor-host-timer-prd)
#   claude-cost-capture     -> betteruptime_heartbeat.claude_cost_capture      (soleur-claude-cost-capture-prd)
#
# A heartbeat is beaten ONLY while the target's own predicate (moved verbatim from the retired alert, minus its
# window conjunct) finds a qualifying row inside the old window in the Better Stack Logs HOT arm (remote()) UNION
# the ARCHIVE arm (s3Cluster). The native luks alert could not see its once-a-day row (incident 1023423999, #11048,
# read `Current value: 0` through 33 healthy nights; the cost marker is NOT once-a-day: it fires a few times a day,
# n=4 in 24 h), so this reads the archive itself. A spurious beat hides exactly
# what the control exists to find, so a withheld beat is the signal: the heartbeat times out and pages.
#
# THE PROPERTY. A request reaches a heartbeat URL only when ALL of these hold:
#   1. the archive query, run with the target's own window and predicate, answered a positive count n
#      (the window lives ONLY in the SQL text; there is deliberately no client-side age check and no clock);
#   2. the heartbeat resolves UNIQUELY by exact name, with a strictly shaped Better Stack ping URL and a paused
#      attribute that is a JSON boolean;
#   3. the heartbeat is NOT paused. While it is paused the verdict is qualifying_row_heartbeat_paused and nothing
#      is sent: the response to a beat sent to a paused heartbeat is undocumented, so this file never depends on it.
# There is exactly ONE call site that can reach a heartbeat URL (beat_once), and this file has NO failure arm: a
# missing row is reported by NOT beating, never by pinging a fail endpoint.
#
# EXIT CONTRACT. Exit 0 means exactly {beat, qualifying_row_heartbeat_paused}. The one other zero is `--selftest`
# (an argument no workflow passes). Every other outcome withholds the beat and exits non-zero: 3 the dead-man's
# input is absent or could not be read (no_qualifying_row, query_failed), 4 the beat could not be delivered or
# the heartbeat could not be resolved (beat_failed), 64 usage, 78 tracing refused. The EXIT trap rewrites any status
# outside that set to 3, and rewrites a 0 that no verdict produced to 3 as well: a fall-off that exited 0 would post
# a Sentry `ok` for a run that decided nothing.
#
# TRUST BOUNDARY. The beat property rests on the authenticity of the rows in the shared Logs source: anyone who
# holds the Logs ingest token can forge a row that satisfies a predicate and keep a heartbeat fed. The predicates
# narrow what counts (tag, unit, host, message; marker key, component, source) but cannot tell a forged row from a
# real one. This control detects a dark emitter or shipper, not a hostile writer.
#
# BEAT BUDGET. Both heartbeats use period 3600 + grace 7200: the page threshold is 10800 s. The workflow runs this
# hourly WHEN the web watchdog clock delivers it (WATCHDOG_DISPATCH_TABLE); the `schedule:` fallback alone
# (one run every 2-7 h, measured) cannot hold the budget, and a dark clock shows as a missed Sentry check-in.
#
# Secrets (repo secrets, read only): BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD
# (the Logs warehouse) and BETTERSTACK_API_TOKEN_READONLY (the uptime API, GET only: a leak cannot pause, edit or
# delete anything, but it CAN read the heartbeats' ping URLs, which are beat capabilities; the read-only scope
# bounds the blast radius, it does not remove it). A ping URL is a bearer secret: it travels on curl's stdin config
# and is NEVER printed.
#
# Usage: deadman-heartbeat-feeder.sh <target> | --selftest   (--selftest needs no network and no credentials)
#
# Harness: apps/web-platform/test/infra/deadman-heartbeat-feeder.test.sh. Arming (the unpause) is NOT done here:
# see "Arming the dead-man heartbeats (#11631)" in
# knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md.
set -uo pipefail

# XTRACE REFUSAL (#7797). Tracing echoes a command after expansion, so under bash -x a credential reaches the
# transcript the moment it is bound.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}${BETTERSTACK_QUERY_USERNAME:+x}${BETTERSTACK_QUERY_HOST:+x}${BETTERSTACK_API_TOKEN_READONLY:+x}" ]; then
      printf 'deadman-feeder: target=none verdict=xtrace_refused refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

# Wall time since start, in milliseconds, from the shell's own EPOCHREALTIME (no external clock, no date): it rides
# on the beat and withhold markers so growth in the archive scan cost is visible before it nears the job timeout.
T0_US="${EPOCHREALTIME-}"; T0_US="${T0_US//[.,]/}"
elapsed_ms() {
  local now="${EPOCHREALTIME-}"; now="${now//[.,]/}"
  if [[ "$now" =~ ^[0-9]{10,}$ && "$T0_US" =~ ^[0-9]{10,}$ ]]; then printf '%s' $(((now - T0_US) / 1000)); else printf 'na'; fi
}
TARGET_LABEL="none"
marker() { # <verdict> [k=v ...]
  printf 'deadman-feeder: target=%s verdict=%s%s\n' "$TARGET_LABEL" "$1" "${2:+ $2}"
}

# Set to 1 immediately before the three legitimate exits of status 0, and nowhere else.
DECIDED=0
# The helper's stderr lands here and is never relayed; the EXIT trap removes it.
tmp_err=""
cleanup_tmp() { if [[ -n "$tmp_err" ]]; then rm -f -- "$tmp_err"; fi; }
# NEVER an unexplained 0. Every status outside the contract, and a 0 that no verdict produced, is rewritten to 3.
# Each allowed status is spelled out as a literal so the harness's static allowlist can read every one.
on_exit() {
  local rc=$?
  cleanup_tmp
  case "$rc" in
    0) if [ "$DECIDED" = 1 ]; then exit 0; fi ;;
    3) exit 3 ;;
    4) exit 4 ;;
    64) exit 64 ;;
    78) exit 78 ;;
  esac
  marker "trap_remapped" "rc=$rc"
  echo "CANNOT BEAT: the feeder ended on a status outside its contract; nothing was decided. This says nothing about the checked host."
  exit 3
}
trap on_exit EXIT

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUERY="$REPO_ROOT/scripts/betterstack-query.sh"
# One page of 250 is enough today. When the API reports a further page the feeder fails safe as beat_failed
# (paged=1) rather than trust a page-1 answer. Follow pagination.next here if the account ever grows.
API_URL="https://uptime.betterstack.com/api/v2/heartbeats?per_page=250"
URL_RE='^https://uptime\.betterstack\.com/api/v1/heartbeat/[A-Za-z0-9]+$'
TOKEN_RE='^[A-Za-z0-9._~+/=-]{20,}$'
# newest is informational: it is printed only in this exact shape, with the space made an underscore so the
# marker line stays one token per field.
NEWEST_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:.]{8,16}$'

# TLS/DNS environment that can substitute the trust store or the resolver for this file's own credentialed
# curls (parity with scripts/betterstack-query.sh, #7873): --disable and --noproxy do not cover it.
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS
# A fixed collation and character class: [0-9] must not depend on the caller's locale.
export LC_ALL=C

# ── THE TARGET TABLE ─────────────────────────────────────────────────────────────────────────────
# Predicates are the retired alerts' WHERE conjuncts, moved verbatim minus the window conjunct (the window is
# the SQL's own, below). Each is ONE physical line. They are read by name by the harness.
TARGETS="luks-monitor-host-timer claude-cost-capture"

# luks-monitor.service's own passing row: tag (luks-monitor.sh LOG_TAG / the unit's SyslogIdentifier), the unit
# journald stamps (the verify job's rows carry session-N.scope or no unit, so they can never keep this fed), the
# OK line luks-monitor.sh logs, and web-1's host_name (web-2 ships to the same Logs source).
def_pred() { local v; IFS= read -r -d '' v || true; printf -v "$1" '%s' "${v%$'\n'}"; }
def_pred LUKS_PRED <<'EOF'
JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'luks-monitor' AND JSONExtractString(raw, '_SYSTEMD_UNIT') = 'luks-monitor.service' AND JSONExtractString(raw, 'message') LIKE '%OK: /mnt/data is LUKS-backed%' AND JSONExtractString(raw, 'host_name') = 'soleur-web-platform'
EOF
# A cron cost marker with a non-null cost_usd (pino fields sit under raw.message; the key match keeps the
# SOLEUR_CLAUDE_COST_DAILY org-total rows out, component keeps an echoed issue body out, source LIKE 'cron:%'
# keeps founder BYOK sessions out) OR a credit-probe RED row (a dead Anthropic key is not a dark capture path).
def_pred COST_PRED <<'EOF'
((raw LIKE '%"SOLEUR_CLAUDE_COST":true%' AND JSONExtractString(raw, 'message', 'component') = 'claude-cost' AND JSONExtractString(raw, 'message', 'source') LIKE 'cron:%' AND JSONExtract(raw, 'message', 'cost_usd', 'Nullable(Float64)') IS NOT NULL) OR (JSONExtractString(raw, 'message', 'feature') = 'cron-anthropic-credit-probe' AND JSONExtractString(raw, 'message', 'op') IN ('anthropic-credit-exhausted', 'anthropic-key-invalid')))
EOF
# Counts-only diagnostics for a luks withhold (no row text is ever echoed): the same tag/unit/host with no
# message filter, and the same plus a FAIL row.
def_pred LUKS_ANY_PRED <<'EOF'
JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'luks-monitor' AND JSONExtractString(raw, '_SYSTEMD_UNIT') = 'luks-monitor.service' AND JSONExtractString(raw, 'host_name') = 'soleur-web-platform'
EOF
def_pred LUKS_FAIL_PRED <<'EOF'
JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'luks-monitor' AND JSONExtractString(raw, '_SYSTEMD_UNIT') = 'luks-monitor.service' AND JSONExtractString(raw, 'host_name') = 'soleur-web-platform' AND JSONExtractString(raw, 'message') LIKE 'FAIL (%'
EOF

# The target is matched by LITERAL EQUALITY against the table and never interpolated: the matched arm assigns
# constants (T, W, NAME, PRED), and nothing else of $1 reaches SQL, a marker, a path or a curl config.
T=""; W=""; NAME=""; PRED=""
select_target() {
  case "$1" in
    luks-monitor-host-timer)
      T="luks-monitor-host-timer"; W=97200; NAME="soleur-luks-monitor-host-timer-prd"; PRED="$LUKS_PRED" ;;
    claude-cost-capture)
      T="claude-cost-capture"; W=86400; NAME="soleur-claude-cost-capture-prd"; PRED="$COST_PRED" ;;
    *) return 1 ;;
  esac
  return 0
}

# The ONE place the SQL is assembled. The window conjunct is the single place time lives, in BOTH arms; the archive
# arm filters _row_type = 1. $BS_TABLE and $BS_TABLE_S3 are literal tokens the helper substitutes (S3 first).
SQL=""
build_sql() { # <window-seconds> <predicate> -> SQL
  local win="dt > now() - INTERVAL $1 SECOND AND dt <= now() + INTERVAL 300 SECOND"
  SQL='SELECT count() AS n, toString(max(dt)) AS newest FROM ('
  SQL+='SELECT dt, raw FROM remote($BS_TABLE) WHERE '"$win"
  SQL+=' UNION ALL '
  SQL+='SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1 AND '"$win"
  SQL+=') WHERE '"$2"' FORMAT JSONEachRow'
  # After assembly a dollar sign may appear ONLY as the two table tokens; anything else is a refusal.
  local rest="${SQL//\$BS_TABLE_S3/}"
  rest="${rest//\$BS_TABLE/}"
  if [[ "$rest" == *'$'* || "$SQL" == *$'\n'* ]]; then return 1; fi
  return 0
}

if [[ "$#" -ne 1 ]]; then
  marker "usage" "argc=$#"
  echo "usage: deadman-heartbeat-feeder.sh <target> | --selftest"
  exit 64
fi

if [[ "$1" == "--selftest" ]]; then
  # The table must be complete: every target resolves, its window is a bounded integer, its name and predicate are
  # non-empty, its SQL assembles; an unknown target is refused. No network, no credentials.
  st_ok=1
  for st_t in $TARGETS; do
    if ! select_target "$st_t" || [[ ! "$W" =~ ^[0-9]{1,6}$ ]] || [[ -z "$NAME" || -z "$PRED" || "$T" != "$st_t" ]] || ! build_sql "$W" "$PRED"; then
      st_ok=0
    fi
  done
  if select_target "no-such-target"; then st_ok=0; fi
  if [[ -z "$TARGETS" ]]; then st_ok=0; fi
  if [[ "$st_ok" != 1 ]]; then
    marker "query_failed" "reason=selftest_table_incomplete"
    echo "CANNOT BEAT: the target table is incomplete; nothing was decided."
    exit 3
  fi
  echo "deadman-feeder: selftest=ok"
  DECIDED=1
  exit 0
fi

if ! select_target "$1"; then
  marker "usage" "target_len=${#1}"
  echo "usage: deadman-heartbeat-feeder.sh takes one known target or --selftest."
  exit 64
fi
TARGET_LABEL="$T"
if [[ ! "$W" =~ ^[0-9]{1,6}$ ]]; then
  marker "usage" "reason=window_shape"
  echo "CANNOT BEAT: the target window is not a bounded integer; this is a feeder bug."
  exit 64
fi

# Funnel counts, carried on every verdict line once the query has answered.
QN=""
QNEWEST="unparsed"
FUNNEL=""
fmarker() { marker "$1" "${2:+$2 }${FUNNEL:+$FUNNEL }elapsed_ms=$(elapsed_ms)"; }

# ── THE QUERY (chokepoint 1) ──────────────────────────────────────────────────────────────────────
# The helper's stdout is captured; its stderr goes to a temp file and is NEVER relayed (its --fail-with-body error
# bodies can carry a credential-bearing message). Only a class and a length are emitted. On a non-zero status the
# stdout is discarded unread. Answer contract: exactly ONE JSONEachRow object. An aggregate over an empty window
# still returns one row ({"n":0,...}); 64-bit integers may be quoted, so n arrives as a JSON number or a string.
# Zero lines, more than one line, a non-object, an `exception` key, a missing or non-numeric n is query_failed.
run_query() { # <window> <predicate> -> sets QN and QNEWEST; exits 3 query_failed on ANY fault
  local v
  for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
    if [[ -z "${!v:-}" ]]; then
      marker "query_failed" "reason=secret_unset"
      echo "CANNOT BEAT: $v is not set, so the Logs warehouse cannot be read. This says nothing about the checked host."
      exit 3
    fi
  done
  if [[ ! -x "$QUERY" ]]; then
    marker "query_failed" "reason=helper_missing"
    echo "CANNOT BEAT: scripts/betterstack-query.sh is missing or not executable."
    exit 3
  fi
  if ! build_sql "$1" "$2"; then
    marker "query_failed" "reason=sql_assembly"
    echo "CANNOT BEAT: the query text failed its own assembly check; this is a feeder bug."
    exit 3
  fi
  local raw qrc
  tmp_err="$(mktemp "${TMPDIR:-/tmp}/deadman-feeder-err.XXXXXXXX")" || tmp_err=""
  raw="$(unset BS_TABLE BS_TABLE_S3; "$QUERY" "$SQL" 2>"${tmp_err:-/dev/null}")"
  qrc=$?
  if [[ "$qrc" -ne 0 ]]; then
    local cls="http" blen=0
    if [[ -n "$tmp_err" && -r "$tmp_err" ]]; then
      blen="$(wc -c < "$tmp_err" | tr -d ' ')"
      if grep -qiE '401|403|auth|unauthori[sz]ed|forbidden|password' "$tmp_err" 2>/dev/null; then cls="auth"
      elif grep -qiE 'decode|parse|json' "$tmp_err" 2>/dev/null; then cls="decode"; fi
    fi
    cleanup_tmp; tmp_err=""
    marker "query_failed" "reason=helper_status status=$qrc class=$cls body_len=$blen"
    echo "CANNOT BEAT: betterstack-query.sh failed (status $qrc). Its output is withheld on purpose: a credential is bound in that process. This says nothing about the checked host."
    exit 3
  fi
  cleanup_tmp; tmp_err=""
  local lines
  lines="$(printf '%s\n' "$raw" | grep -c '[^[:space:]]' || true)"
  if [[ "$lines" != 1 ]]; then
    marker "query_failed" "reason=malformed lines=$lines"
    echo "CANNOT BEAT: betterstack-query.sh answered $lines non-empty line(s); exactly one aggregate row is required."
    exit 3
  fi
  local sel jrc
  sel="$(printf '%s\n' "$raw" | jq -r '
      if type != "object" or has("exception") or (has("n") | not) then "bad\t-"
      else (.n | if type == "number" then (if . == floor and . >= 0 and . < 1e15 then (. | floor | tostring) else "bad" end)
                 elif type == "string" then (if test("^[0-9]{1,18}$") then . else "bad" end) else "bad" end) as $n
        | (.newest // "" | if type == "string" then . else "" end) as $d
        | $n + "\t" + $d end' 2>/dev/null)"
  jrc=$?
  local nraw="${sel%%$'\t'*}" draw=""
  [[ "$sel" == *$'\t'* ]] && draw="${sel#*$'\t'}"
  # n > 0 is decided by a STRING test, never bash arithmetic (a value like 09 or an expression must not evaluate).
  if [[ "$jrc" -ne 0 || -z "$sel" || ! "$nraw" =~ ^[0-9]{1,18}$ ]]; then
    marker "query_failed" "reason=malformed_answer"
    echo "CANNOT BEAT: the aggregate answer could not be read as a count."
    exit 3
  fi
  QN="$nraw"
  if [[ "$QN" != 0 ]]; then QN="${QN#"${QN%%[!0]*}"}"; fi
  [[ -n "$QN" ]] || QN=0
  QNEWEST="unparsed"
  if [[ "$draw" =~ $NEWEST_RE ]]; then QNEWEST="${draw// /_}"; fi
  # An empty window answers the epoch row: there is no newest row, and saying so is clearer than a 1970 date.
  if [[ "$QN" == 0 ]]; then QNEWEST="none"; fi
}
count_query() { # <window> <predicate>
  run_query "$1" "$2"
  FUNNEL="n=$QN newest_dt=$QNEWEST"
}

# ── THE WITHHOLD (n == 0) ─────────────────────────────────────────────────────────────────────────
# For luks-monitor two counts-only diagnostics over the same window separate host-dark (any_rows=0), a FAIL row
# (encryption possibly not in effect: fail_rows>0) and a shipper outage; a diagnostic that cannot run reads
# `unknown` and never changes the verdict.
diag_count() { # <predicate> -> echoes a count or "unknown"
  local n
  n="$( (QN=""; run_query "$W" "$1" >/dev/null 2>&1; printf '%s' "$QN") 2>/dev/null)" || n=""
  [[ "$n" =~ ^[0-9]{1,18}$ ]] && printf '%s' "$n" || printf 'unknown'
}
withhold_no_row() {
  local extra=""
  if [[ "$T" == "luks-monitor-host-timer" ]]; then
    extra="any_rows=$(diag_count "$LUKS_ANY_PRED") fail_rows=$(diag_count "$LUKS_FAIL_PRED")"
  fi
  FUNNEL="n=$QN newest_dt=$QNEWEST${extra:+ $extra}"
  fmarker "no_qualifying_row"
  if [[ "$T" == "luks-monitor-host-timer" ]]; then
    echo "CANNOT BEAT: no qualifying row for $T in the last ${W}s (hot plus archive). The checked host, the log shipper or the Logs source is dark; that is what this heartbeat exists to report."
  else
    echo "CANNOT BEAT: no cost marker or credit-probe RED row for $T in the last ${W}s (hot plus archive). The cron cost-capture path, the log shipper or the Logs source may be dark; this line does not say which."
    echo "CANNOT BEAT: next action for $T: see the cost-marker section (Querying Anthropic cost markers) of knowledge-base/engineering/operations/runbooks/betterstack-log-query.md."
  fi
  exit 3
}

# ── HEARTBEAT RESOLUTION (chokepoint 2) ──────────────────────────────────────────────────────────
# GET only, with the read-only token, by exact name. curl reads the bearer from stdin (--config -) so it is never
# on argv; curl and jq stderr go to /dev/null.
HB_URL=""
HB_PAUSED=""
resolve_heartbeat() {
  local tok="${BETTERSTACK_API_TOKEN_READONLY:-}"
  if [[ -z "$tok" ]]; then
    fmarker "beat_failed" "reason=api_token_unset"
    echo "CANNOT BEAT: BETTERSTACK_API_TOKEN_READONLY is not set, so the heartbeat cannot be resolved. A qualifying row existed; this is a feeder credential fault."
    exit 4
  fi
  # No quote or newline can survive this shape, so none can add a curl directive.
  if [[ ! "$tok" =~ $TOKEN_RE ]]; then
    fmarker "beat_failed" "reason=api_token_malformed"
    echo "CANNOT BEAT: BETTERSTACK_API_TOKEN_READONLY does not have the shape of an API token."
    exit 4
  fi
  local body crc
  body="$(printf 'header = "Authorization: Bearer %s"\n' "$tok" \
    | curl --disable --noproxy '*' -fsS --max-time 20 --connect-timeout 10 --config - "$API_URL" 2>/dev/null)"
  crc=$?
  if [[ "$crc" -ne 0 ]]; then
    fmarker "beat_failed" "reason=api_unreadable curl_rc=$crc"
    echo "CANNOT BEAT: the Better Stack uptime API could not be read (transport status $crc), so the heartbeat was not resolved."
    exit 4
  fi
  local sel srx
  sel="$(printf '%s' "$body" | jq -r --arg n "$NAME" '
      [.data[]? | select(.attributes.name == $n)] as $m
      | if ($m | length) != 1 or ((.pagination.next // null) != null) then "count\t" + (($m | length) | tostring) + "\t" + (if ((.pagination.next // null) != null) then "1" else "0" end)
        else ($m[0].attributes) as $a
          | if ($a.paused | type) != "boolean" then "paused_shape\t-"
            else "ok\t" + ($a.paused | tostring) + "\t" + (($a.url // "") | tostring) end
        end' 2>/dev/null)"
  srx=$?
  if [[ "$srx" -ne 0 || -z "$sel" ]]; then
    fmarker "beat_failed" "reason=api_malformed"
    echo "CANNOT BEAT: the uptime API answer could not be read as a heartbeat list."
    exit 4
  fi
  case "$sel" in
    count$'\t'*)
      local cnt_rest="${sel#count$'\t'}"
      fmarker "beat_failed" "reason=heartbeat_not_unique matches=${cnt_rest%%$'\t'*} paged=${cnt_rest#*$'\t'}"
      echo "CANNOT BEAT: exactly one heartbeat named $NAME is required."
      exit 4 ;;
    paused_shape$'\t'*)
      fmarker "beat_failed" "reason=paused_not_boolean"
      echo "CANNOT BEAT: the heartbeat's paused attribute is absent or not a JSON boolean, so its state is unknown."
      exit 4 ;;
  esac
  HB_PAUSED="$(printf '%s' "$sel" | cut -f2)"
  HB_URL="$(printf '%s' "$sel" | cut -f3-)"
  # Also the injection guard for the curl config the beat is sent through.
  if [[ ! "$HB_URL" =~ $URL_RE ]]; then
    fmarker "beat_failed" "reason=url_shape"
    echo "CANNOT BEAT: the heartbeat's ping URL does not have the expected Better Stack shape."
    exit 4
  fi
}

# ── THE ONE BEAT CALL SITE ───────────────────────────────────────────────────────────────────────
# Success is a 2xx code only: -f does not fail a 3xx, and redirects are never followed; there is no retry (a 429
# or a stall is beat_failed). The URL is passed on stdin and is never printed.
beat_once() {
  local code crc
  code="$(printf 'url = "%s"\n' "$HB_URL" \
    | curl --disable --noproxy '*' -fsS --max-time 15 --connect-timeout 10 -o /dev/null -w '%{http_code}' --config - 2>/dev/null)"
  crc=$?
  if [[ "$crc" -ne 0 || ! "$code" =~ ^2[0-9][0-9]$ ]]; then
    fmarker "beat_failed" "reason=http_status http=${code:-none} curl_rc=$crc"
    echo "CANNOT BEAT: the heartbeat ping was not accepted (http ${code:-none}). A qualifying row existed; the feeder could not deliver."
    exit 4
  fi
  fmarker "beat" "http=$code"
  echo "fed: the heartbeat was beaten on a qualifying row."
  DECIDED=1
  exit 0
}

# ── MAIN ─────────────────────────────────────────────────────────────────────────────────────────
run_target() {
  count_query "$W" "$PRED"
  if [[ "$QN" == "0" ]]; then withhold_no_row; fi
  resolve_heartbeat
  if [[ "$HB_PAUSED" == "true" ]]; then
    fmarker "qualifying_row_heartbeat_paused"
    echo "healthy but unarmed: a qualifying row exists and the heartbeat is still paused, so nothing was sent."
    DECIDED=1
    exit 0
  fi
  beat_once
}
run_target
marker "unreachable"
echo "CANNOT BEAT: the decision flow fell through without a verdict. This is a feeder bug; nothing was decided."
exit 3
