#!/usr/bin/env bash
# (#9703) Feeder for betteruptime_heartbeat.inngest_server_probe: beat the heartbeat ONLY while a
# fresh host_role=dedicated SOLEUR_INNGEST_SERVER_PROBE row is confirmed in the Better Stack Logs
# warehouse. The heartbeat is the dead-man's-switch for the wrong-volume alert, which reads a silent
# probe pipeline as healthy (on_missing_data = "treat_as_zero"): a beat that outlives a dead probe
# would suppress exactly the alarm it exists to back.
#
# THE PROPERTY. A request reaches the heartbeat URL only when ALL of these hold:
#   1. the newest probe row from host soleur-inngest / soleur-inngest-prd whose FIRST host_role=
#      token is dedicated (selected by the shared emitter-plus-anchored-marker predicate,
#      scripts/lib/inngest-probe-row.sh) is at most FRESH_MAX_SECS old and not future-dated;
#   2. the heartbeat resolves UNIQUELY by exact name, with a strictly shaped Better Stack ping URL
#      and a paused attribute that is a JSON boolean;
#   3. the heartbeat is NOT paused. While it is paused the verdict is fresh_heartbeat_paused and
#      nothing is sent: the response to a beat sent to a paused heartbeat is undocumented, so this
#      file never depends on it.
# There is exactly ONE call site that can reach the heartbeat URL (beat_once), and every path to it
# passes the verdict logic above.
#
# EXIT CONTRACT. Exit 0 means exactly {beat, fresh_heartbeat_paused} for every run that can reach the
# heartbeat. The one other zero is `--selftest` (an argument no workflow passes; it prints no verdict).
# Every other outcome withholds
# the beat and exits non-zero: 3 cannot establish, 4 the beat could not be delivered, 64 usage, 78
# tracing refused. The EXIT trap rewrites any status outside that set to 3, and rewrites a 0 that
# did not come from a decided verdict to 3 as well: a fall-off that exited 0 would post a Sentry
# `ok` for a run that decided nothing.
#
# BEAT BUDGET. The heartbeat pages when no beat arrives for period + grace = 5400 s. The workflow
# runs this every 15 minutes WHEN the web watchdog clock delivers it (apps/web-platform/server/
# watchdog-dispatch-table.ts); the `schedule:` fallback alone (one run every 2-7 h) cannot hold the
# budget. The 4500 s freshness bound leaves about 14 minutes above the probe's hourly cadence (measured
# gaps 3599-3650 s) for ingest lag and clock skew; the first-sighting lag measured during the soak was
# under 2 minutes. The harness cross-checks the bound against the values this file does not own.
#
# CLOCK. "Now" is INNGEST_FEEDER_NOW (ISO-8601 UTC) when set, date -u otherwise. A set-but-malformed
# value is exit 3, never a wall-clock fallback.
#
# TEST SEAMS. INNGEST_FEEDER_NOW and INNGEST_PROBE_ROW_LIB exist for the harness only. A frozen clock or a
# permissive predicate library would authorize a beat on a dead probe, so the workflow unsets both before
# running this file and the harness pins that (a seam that is honoured in production must be sealed by
# its invoker).
#
# Secrets (repo secrets, read only): BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME,
# BETTERSTACK_QUERY_PASSWORD (the Logs warehouse) and BETTERSTACK_API_TOKEN_READONLY (the uptime API,
# GET only: a leak of it cannot pause, edit or delete anything, but it CAN read the heartbeat's ping URL,
# which is a beat capability (alarm suppression); the read-only scope bounds the blast radius, it does not
# remove it).
#
# Only argument: --selftest (no network, no credentials; loads the shared predicate and grades it).
#
# Harness: scripts/inngest-probe-heartbeat-feeder.test.sh. Arming (the unpause) is NOT done here:
# see knowledge-base/engineering/operations/runbooks/inngest-server.md, "Arming the probe heartbeat".
set -uo pipefail

# XTRACE REFUSAL (#7797). Tracing echoes a command after expansion, so under bash -x a credential
# reaches the transcript the moment it is bound.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}${BETTERSTACK_QUERY_USERNAME:+x}${BETTERSTACK_QUERY_HOST:+x}${BETTERSTACK_API_TOKEN_READONLY:+x}" ]; then
      printf 'inngest-probe-feeder: verdict=xtrace_refused refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

marker() { # <verdict> [k=v ...]
  printf 'inngest-probe-feeder: verdict=%s %s\n' "$1" "${2:-}"
}

# Set to 1 immediately before the two legitimate exits of status 0, and nowhere else.
DECIDED=0
# The helper's stderr lands here and is never relayed; the EXIT trap removes it.
tmp_err=""
cleanup_tmp() { if [[ -n "$tmp_err" ]]; then rm -f -- "$tmp_err"; fi; }
# NEVER an unexplained 0. Every status outside the contract, and a 0 that no verdict produced, is
# rewritten to 3. Each allowed status is spelled out as a literal so the harness's static allowlist
# can read every one. Installed directly after the xtrace refusal, before any other statement; the
# harness also forbids exec, kill and a second trap.
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
  echo "CANNOT BEAT: the feeder ended on a status outside its contract; nothing was decided. This says nothing about the Inngest store."
  exit 3
}
trap on_exit EXIT

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUERY="$REPO_ROOT/scripts/betterstack-query.sh"
# The helper's window must stay above FRESH_MAX_SECS plus ingest lag. --limit keeps the NEWEST rows
# (the helper orders its inner query by dt descending); this file sorts by dt itself.
WINDOW="2h"
LIMIT=500
# 4500 s = hourly probe (gaps 3599-3650 s measured) + about 14 min of slack for ingest lag and skew.
FRESH_MAX_SECS=4500
FUTURE_SLACK_SECS=300
# The dedicated Inngest host, as vector stamps it. Every host writes into one Logs source, so a row
# is only this host's measurement if BOTH match.
HOST="soleur-inngest"
HOST_NAME="soleur-inngest-prd"
# Must equal betteruptime_heartbeat.inngest_server_probe's name in apps/web-platform/infra/uptime-alerts.tf.
HEARTBEAT_NAME="soleur-inngest-server-probe-prd"
# One page of 250 is enough today; more than 250 heartbeats fails safe as beat_failed (resolution
# finds zero or an ambiguous match). Follow pagination.next here if the account ever grows.
API_URL="https://uptime.betterstack.com/api/v2/heartbeats?per_page=250"
URL_RE='^https://uptime\.betterstack\.com/api/v1/heartbeat/[A-Za-z0-9]+$'
TOKEN_RE='^[A-Za-z0-9._~+/=-]{20,}$'

# The ONE definition of a probe row (#8846): emitter AND anchored marker. Resolved from this file's
# repo root so a sandboxed copy reads its own tree; INNGEST_PROBE_ROW_LIB overrides it. The load
# contract (scripts/lib/inngest-probe-row.sh header): unset first so an inherited def never survives
# a source that failed or defined nothing; the selftest proves the loaded def; stderr stays visible.
# TLS/DNS environment that can substitute the trust store or the resolver for this file's own credentialed
# curls (parity with scripts/betterstack-query.sh, #7873): --disable and --noproxy do not cover it.
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS
# A fixed collation and character class: [0-9] and sort order must not depend on the caller's locale.
export LC_ALL=C
# The two test seams (a frozen clock, a substitute predicate library) would authorize a beat on a dead
# probe. The workflow unsets them; this refuses them inside Actions as well, so a stale export cannot
# reach a run there even if the workflow's unset were ever edited away.
if [[ "${GITHUB_ACTIONS:-}" == "true" ]] && { [[ -n "${INNGEST_FEEDER_NOW+x}" ]] || [[ -n "${INNGEST_PROBE_ROW_LIB+x}" ]]; }; then
  marker "query_failed" "reason=test_seam_in_ci"
  echo "CANNOT BEAT: a test seam (INNGEST_FEEDER_NOW or INNGEST_PROBE_ROW_LIB) is set inside GitHub Actions. It would let a frozen clock or a substitute predicate authorize a beat; nothing was decided."
  exit 3
fi
unset INNGEST_PROBE_ROW_JQ INNGEST_PROBE_EMITTER INNGEST_PROBE_MARKER
_ipr_lib="${INNGEST_PROBE_ROW_LIB:-$REPO_ROOT/scripts/lib/inngest-probe-row.sh}"
# shellcheck source=scripts/lib/inngest-probe-row.sh
if ! source "$_ipr_lib" || ! declare -F inngest_probe_row_selftest >/dev/null || ! inngest_probe_row_selftest; then
  marker "query_failed" "reason=selector_unavailable lib=$_ipr_lib"
  echo "CANNOT BEAT: reason=selector_unavailable -- the shared probe-row predicate did not load or failed its selftest, so no row can be read as a measurement. This says nothing about the store."
  exit 3
fi

if [[ "$#" -ne 0 ]]; then
  if [[ "$#" -eq 1 && "$1" == "--selftest" ]]; then
    echo "inngest-probe-feeder: selftest=ok"
    DECIDED=1
    exit 0
  fi
  marker "usage" "argc=$#"
  echo "usage: inngest-probe-heartbeat-feeder.sh takes no arguments except --selftest (clock: INNGEST_FEEDER_NOW)."
  exit 64
fi

# ── CLOCK ────────────────────────────────────────────────────────────────────────────────────
if [[ -n "${INNGEST_FEEDER_NOW+x}" ]]; then
  NOW_EPOCH=""
  if [[ "$INNGEST_FEEDER_NOW" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    NOW_EPOCH="$(date -u -d "$INNGEST_FEEDER_NOW" +%s 2>/dev/null)" || NOW_EPOCH=""
  fi
  if [[ -z "$NOW_EPOCH" ]]; then
    marker "clock_malformed" "INNGEST_FEEDER_NOW=$(printf '%s' "$INNGEST_FEEDER_NOW" | tr -c 'A-Za-z0-9:.-' '?' | head -c 40)"
    echo "CANNOT BEAT: INNGEST_FEEDER_NOW is set but is not an ISO-8601 UTC instant (YYYY-MM-DDTHH:MM:SSZ). No fallback to the wall clock is taken."
    exit 3
  fi
else
  NOW_EPOCH="$(date -u +%s)"
fi

# Funnel counts, carried on every verdict line once the query has answered, so each competing cause
# (empty warehouse, host/role filter drop, stale-but-present row) is distinguishable from one line.
FUNNEL=""
fmarker() { marker "$1" "${2:+$2 }$FUNNEL"; }

# ── FRESHNESS (chokepoint 1) ─────────────────────────────────────────────────────────────────
# The helper's stdout is captured; its stderr goes to a temp file and is NEVER relayed (its
# --fail-with-body error bodies can carry a credential-bearing message). Only a class and a length
# are emitted.
check_freshness() {
  local v
  for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
    if [[ -z "${!v:-}" ]]; then
      marker "query_failed" "reason=secret_unset secret=$v"
      echo "CANNOT BEAT: $v is not set, so the Logs warehouse cannot be read. This says nothing about the store."
      exit 3
    fi
  done
  if [[ ! -x "$QUERY" ]]; then
    marker "query_failed" "reason=helper_missing"
    echo "CANNOT BEAT: scripts/betterstack-query.sh is missing or not executable."
    exit 3
  fi

  local raw qrc
  tmp_err="$(mktemp "${TMPDIR:-/tmp}/inngest-feeder-err.XXXXXXXX")" || tmp_err=""
  raw="$("$QUERY" --since "$WINDOW" --grep "$INNGEST_PROBE_MARKER" --limit "$LIMIT" 2>"${tmp_err:-/dev/null}")"
  qrc=$?
  if [[ "$qrc" -ne 0 ]]; then
    local cls="http" blen=0
    if [[ -n "$tmp_err" && -r "$tmp_err" ]]; then
      blen="$(wc -c < "$tmp_err" | tr -d ' ')"
      if grep -qiE '401|403|auth|unauthori[sz]ed|forbidden|password' "$tmp_err" 2>/dev/null; then cls="auth"
      elif grep -qiE 'decode|parse|json' "$tmp_err" 2>/dev/null; then cls="decode"; fi
    fi
    marker "query_failed" "reason=helper_status status=$qrc class=$cls body_len=$blen"
    echo "CANNOT BEAT: betterstack-query.sh failed (status $qrc). Its output is withheld on purpose: a credential is bound in that process. This says nothing about the store."
    exit 3
  fi

  local nonempty
  nonempty="$(printf '%s\n' "$raw" | grep -c '[^[:space:]]' || true)"
  if [[ "$nonempty" -eq 0 ]]; then
    FUNNEL="rows_total=0 rows_probe=0 rows_host=0 rows_dedicated=0 newest_dt=none lines=0"
    fmarker "no_rows" "window=$WINDOW"
    echo "CANNOT BEAT: zero $INNGEST_PROBE_MARKER rows in $WINDOW. The probe emitter, the journald allowlist, the sink or the warehouse is dark. That is what this heartbeat exists to report; it says nothing else about the store."
    exit 3
  fi

  # One jq pass over the decoded rows: for each row [probe, host, dedicated, dt]. Message text is
  # never carried out of jq. ANCHORED, NOT A BARE TOKEN: probe = the shared predicate (the probe's own
  # emitter AND a message that STARTS with the marker); host = both host fields; role = the FIRST
  # host_role= token (the same first-wins rule the field reader applies). dt is normalised ('T' to
  # ' ') and an absent one becomes '-' so no tab-separated field is ever empty.
  local sel jrc
  sel="$(printf '%s\n' "$raw" | jq -R -r --arg h "$HOST" --arg hn "$HOST_NAME" "$INNGEST_PROBE_ROW_JQ"'
      fromjson? | select(type == "object") | . as $o
      | ((.raw // "") | fromjson?) | select(type == "object")
      | [ (if ([select(inngest_probe_row)] | length) > 0 then 1 else 0 end),
          (if (.host == $h and .host_name == $hn) then 1 else 0 end),
          (if ((((.message // "") | tostring) | (capture("(?:^| )host_role=(?<r>[^ ]*)")? // {r: ""})).r) == "dedicated" then 1 else 0 end),
          ((($o.dt // "") | tostring | sub("T"; " ")) | if . == "" then "-" else . end)
        ] | @tsv' 2>/dev/null)"
  jrc=$?
  if [[ "$jrc" -ne 0 ]]; then
    marker "query_failed" "reason=selector_failed jq_rc=$jrc"
    echo "CANNOT BEAT: the probe-row selection (jq over the shared predicate) failed with status $jrc, so no row was graded. This says nothing about the store."
    exit 3
  fi
  if [[ -z "$sel" ]]; then
    marker "query_failed" "reason=malformed lines=$nonempty"
    echo "CANNOT BEAT: betterstack-query.sh answered $nonempty line(s) and none decoded as a warehouse row."
    exit 3
  fi

  # A dt is a candidate only in the warehouse's own shape (UTC, no zone offset, optional fraction, optional
  # trailing Z). Anything else (a zone offset would be read as UTC and could make a stale row look fresh)
  # is counted in dt_rejected and never decides.
  local dt_re='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z?$'
  local total=0 probe=0 host=0 ded=0 baddt=0 p h r d dts=""
  while IFS=$'\t' read -r p h r d; do
    total=$((total + 1))
    if [[ "$p" == 1 ]]; then
      probe=$((probe + 1))
      if [[ "$h" == 1 ]]; then
        host=$((host + 1))
        if [[ "$r" == 1 ]]; then
          ded=$((ded + 1))
          if [[ "$d" =~ $dt_re ]]; then
            dts+="$d"$'\n'
          else
            baddt=$((baddt + 1))
          fi
        fi
      fi
    fi
  done <<<"$sel"

  local newest="none"
  if [[ -n "$dts" ]]; then
    newest="$(printf '%s' "$dts" | LC_ALL=C sort -s | tail -1)"
  fi
  FUNNEL="rows_total=$total rows_probe=$probe rows_host=$host rows_dedicated=$ded newest_dt=$(printf '%s' "$newest" | tr -c 'A-Za-z0-9:. -' '?' | tr ' ' '_' | head -c 40) lines=$nonempty dt_rejected=$baddt"
  if [[ "$ded" -eq 0 ]]; then
    fmarker "no_rows" "window=$WINDOW role=dedicated"
    echo "CANNOT BEAT: no host_role=dedicated $INNGEST_PROBE_MARKER row from $HOST in $WINDOW (rows from other roles, hosts, emitters or quoting content were set aside). The probe pipeline for the dedicated host is dark; that is what this heartbeat exists to report."
    exit 3
  fi

  local dt_epoch=""
  if [[ -n "$dts" && "$newest" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
    dt_epoch="$(date -u -d "${newest:0:19}" +%s 2>/dev/null)" || dt_epoch=""
  fi
  if [[ -z "$dt_epoch" ]]; then
    fmarker "row_unusable" "field=dt"
    echo "CANNOT BEAT: the newest probe row carries no readable YYYY-MM-DD HH:MM:SS timestamp."
    exit 3
  fi
  AGE=$(( NOW_EPOCH - dt_epoch ))
  if (( AGE < -FUTURE_SLACK_SECS )); then
    fmarker "row_unusable" "field=dt_future age_s=$AGE"
    echo "CANNOT BEAT: the newest probe row is dated in the future. A row that never goes stale must not justify a beat."
    exit 3
  fi
  if (( AGE > FRESH_MAX_SECS )); then
    fmarker "producer_silent" "age_s=$AGE limit_s=$FRESH_MAX_SECS"
    echo "CANNOT BEAT: the newest dedicated probe row is ${AGE}s old (limit ${FRESH_MAX_SECS}s). A silent probe pipeline must never keep the heartbeat fed."
    exit 3
  fi
}

# ── HEARTBEAT RESOLUTION (chokepoint 2) ──────────────────────────────────────────────────────
# GET only, with the read-only token, by exact name. curl reads the bearer from stdin
# (--config -) so it is never on argv; curl and jq stderr go to /dev/null. This is the repo-script shape
# (token-shape guard + stdin config, like scripts/betterstack-query.sh), not scripts/lib/bearer-curl.sh:
# ADR-280 scopes that library to workflow-side call steps that cannot reach a repo script by path.
HB_URL=""
HB_PAUSED=""
resolve_heartbeat() {
  local tok="${BETTERSTACK_API_TOKEN_READONLY:-}"
  if [[ -z "$tok" ]]; then
    fmarker "beat_failed" "reason=api_token_unset"
    echo "CANNOT BEAT: BETTERSTACK_API_TOKEN_READONLY is not set, so the heartbeat cannot be resolved. The probe row was fresh; this is a feeder credential fault."
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
    | curl --disable --noproxy '*' -fsS --max-time 20 --config - "$API_URL" 2>/dev/null)"
  crc=$?
  if [[ "$crc" -ne 0 ]]; then
    fmarker "beat_failed" "reason=api_unreadable curl_rc=$crc"
    echo "CANNOT BEAT: the Better Stack uptime API could not be read (curl status $crc), so the heartbeat was not resolved."
    exit 4
  fi
  local sel srx
  sel="$(printf '%s' "$body" | jq -r --arg n "$HEARTBEAT_NAME" '
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
      echo "CANNOT BEAT: exactly one heartbeat named $HEARTBEAT_NAME is required."
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

# ── THE ONE BEAT CALL SITE ───────────────────────────────────────────────────────────────────
# Success is a 2xx code only: -f does not fail a 3xx, and redirects are never followed. The URL is
# passed on stdin and is never printed, so no ::add-mask:: line is needed.
beat_once() {
  local code crc
  code="$(printf 'url = "%s"\n' "$HB_URL" \
    | curl --disable --noproxy '*' -fsS --max-time 15 -o /dev/null -w '%{http_code}' --config - 2>/dev/null)"
  crc=$?
  if [[ "$crc" -ne 0 || ! "$code" =~ ^2[0-9][0-9]$ ]]; then
    fmarker "beat_failed" "reason=http_status http=${code:-none} curl_rc=$crc"
    echo "CANNOT BEAT: the heartbeat ping was not accepted (http ${code:-none}). The probe row was fresh; the feeder could not deliver."
    exit 4
  fi
  fmarker "beat" "http=$code age_s=$AGE"
  echo "fed: the heartbeat was beaten on a confirmed fresh dedicated probe row."
  DECIDED=1
  exit 0
}

# ── MAIN
AGE=0
check_freshness
resolve_heartbeat
if [[ "$HB_PAUSED" == "true" ]]; then
  fmarker "fresh_heartbeat_paused" "age_s=$AGE"
  echo "healthy but unarmed: a fresh dedicated probe row exists and the heartbeat is still paused, so nothing was sent."
  DECIDED=1
  exit 0
fi
beat_once
fmarker "unreachable"
echo "CANNOT BEAT: the decision flow fell through without a verdict. This is a feeder bug; nothing was decided."
exit 3
