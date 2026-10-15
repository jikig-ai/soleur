#!/usr/bin/env bash
# Retention and freshness probe for the egress audit rollup (#9545, ADR-288).
#
# Prints exactly `OK` on stdout and exits 0 only when:
#   1. no row in public.workspace_egress_audit_rollup has last_seen older than 35 days
#      (the daily pg_cron sweep keeps 30; a row past 35 means the sweep has stopped), and
#   2. when EGRESS_AUDIT_EXPECT_COLLECTION=1: either the newest bucket_start is at most 75
#      minutes old, or the egress gateway log shows no decision of a canary workspace
#      (EGRESS_AUDIT_CANARY_WORKSPACES, comma-separated ids) between 60 and 35 minutes ago.
#      Timing: a bucket lands about 31 minutes after its start (15-minute bucket, 15-minute
#      reduce expiry, flush and batch), so the newest landed bucket is 31-46 minutes old in
#      steady state, and an event older than 35 minutes must already be in a landed bucket
#      whose start is at most 75 minutes old. Failed-authentication rows (status 407) are not
#      ingested and are not counted. Run it only after the 60-minute window has elapsed since
#      collection was enabled: right after enabling, the window still holds gateway events from
#      before the enable, which the app (correctly) dropped, and the probe would false-fail.
# Any unavailable read is a failure (exit 1), never a pass; missing credentials or, when
# freshness is asserted, a missing or malformed canary list exit 2.
#
# Freshness is NOT asserted by default: while the pipeline is dark (collection off for every
# external workspace) the table is legitimately empty, and a stale-table alarm would be a
# standing false alarm. Set EGRESS_AUDIT_EXPECT_COLLECTION=1 once a workspace is enabled.
#
# Run (credentials from Doppler, never printed):
#   doppler run -p soleur -c prd -- bash scripts/egress-audit-retention-check.sh
# Freshness with collection enabled also reads the gateway log, which needs the Better Stack
# query credential (prd_terraform); GW_QUERY_CMD overrides the command (tests).
# NOT scheduled anywhere yet: until it runs on a schedule this is a manual probe, and
# scheduling it is a precondition of enabling collection for any workspace (ADR-288).
set -uo pipefail

# Refuse to run under shell tracing while a live credential is set: `set -x` would trace the
# service-role key into whatever collects the output. `$-` tests whether tracing is ON.
case "$-" in
  *x*)
    if [ -n "${SUPABASE_SERVICE_ROLE_KEY:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="${SUPABASE_URL:-${NEXT_PUBLIC_SUPABASE_URL:-}}"
KEY="${SUPABASE_SERVICE_ROLE_KEY:-}"
if [[ -z "$URL" || -z "$KEY" ]]; then
  echo "UNAVAILABLE: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required (run under: doppler run -p soleur -c prd -- ...)" >&2
  exit 2
fi
command -v jq >/dev/null 2>&1 || { echo "UNAVAILABLE: jq is required" >&2; exit 2; }

MAX_ROW_AGE_S=$((35 * 86400))
MAX_BUCKET_AGE_S=$((75 * 60))
NOW="$(date -u +%s)"

# rest_get <query-string>: prints the JSON body, returns non-zero on any transport or HTTP error.
# The key travels in a stdin curl config, never on argv.
rest_get() {
  local resp code
  resp="$(printf 'header = "apikey: %s"\nheader = "Authorization: Bearer %s"\n' "$KEY" "$KEY" |
    curl --disable --noproxy '*' --silent --show-error --max-time 20 -K - -w '\n%{http_code}' "${URL%/}/rest/v1/workspace_egress_audit_rollup?$1")" || return 1
  code="${resp##*$'\n'}"
  [[ "$code" == 200 ]] || { echo "UNAVAILABLE: REST API answered HTTP $code" >&2; return 1; }
  printf '%s' "${resp%$'\n'*}"
}

to_epoch() { date -u -d "$1" +%s 2>/dev/null; }

FAILED=0
fail() { echo "FAIL: $1" >&2; FAILED=1; }

# 1. Retention: the oldest row must be younger than 35 days.
body="$(rest_get 'select=last_seen&order=last_seen.asc&limit=1')" || exit 1
oldest="$(printf '%s' "$body" | jq -er 'if type == "array" then (.[0].last_seen // "") else error("not an array") end' 2>/dev/null)" || {
  echo "UNAVAILABLE: the oldest-row read did not return a JSON array" >&2
  exit 1
}
if [[ -n "$oldest" ]]; then
  oldest_epoch="$(to_epoch "$oldest")" || { echo "UNAVAILABLE: unparseable last_seen" >&2; exit 1; }
  age=$((NOW - oldest_epoch))
  if [[ "$age" -gt "$MAX_ROW_AGE_S" ]]; then
    fail "oldest row is $((age / 86400)) days old (limit 35): the retention sweep has stopped"
  fi
fi

# 2. Freshness, only when collection is expected.
if [[ "${EGRESS_AUDIT_EXPECT_COLLECTION:-0}" == "1" ]]; then
  # The gateway-activity query is scoped to the canary workspaces: while only a canary is enabled,
  # the gateway also logs every other workspace's traffic, which the app (rightly) drops, and
  # counting it would alarm on a healthy pipeline.
  CANARY_RAW="${EGRESS_AUDIT_CANARY_WORKSPACES:-}"
  if [[ -z "$CANARY_RAW" ]]; then
    echo "UNAVAILABLE: EGRESS_AUDIT_EXPECT_COLLECTION=1 needs EGRESS_AUDIT_CANARY_WORKSPACES (comma-separated workspace ids)" >&2
    exit 2
  fi
  canary_or=""
  canary_in=""
  IFS=',' read -ra CANARY_IDS <<< "$CANARY_RAW"
  for id in "${CANARY_IDS[@]}"; do
    if [[ ! "$id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
      echo "UNAVAILABLE: EGRESS_AUDIT_CANARY_WORKSPACES holds a value that is not a lower-case workspace id" >&2
      exit 2
    fi
    canary_or="${canary_or:+$canary_or OR }raw LIKE '%${id}%'"
    canary_in="${canary_in:+$canary_in,}${id}"
  done
  # Freshness is read for the canary workspaces only: once another workspace has fresh rows, a
  # table-wide newest bucket would mask a dead canary.
  body="$(rest_get "select=bucket_start&workspace_id=in.(${canary_in})&order=bucket_start.desc&limit=1")" || exit 1
  newest="$(printf '%s' "$body" | jq -er 'if type == "array" then (.[0].bucket_start // "") else error("not an array") end' 2>/dev/null)" || {
    echo "UNAVAILABLE: the newest-bucket read did not return a JSON array" >&2
    exit 1
  }
  fresh=0
  if [[ -n "$newest" ]]; then
    newest_epoch="$(to_epoch "$newest")" || { echo "UNAVAILABLE: unparseable bucket_start" >&2; exit 1; }
    [[ $((NOW - newest_epoch)) -le "$MAX_BUCKET_AGE_S" ]] && fresh=1
  fi
  if [[ "$fresh" -eq 0 ]]; then
    # Stale or empty: acceptable only if the gateway log shows nothing to ingest. Unknown is a failure.
    gw_sql="SELECT count() AS n FROM remote(\$BS_TABLE) WHERE dt > now() - INTERVAL 60 MINUTE AND dt <= now() - INTERVAL 35 MINUTE AND raw LIKE '%requested_host%' AND JSONExtractString(raw, 'CONTAINER_NAME') = 'soleur-egress-gw' AND match(raw, 'status[^0-9a-zA-Z]{1,12}(200|403|502|503|504)') AND (${canary_or}) FORMAT JSONEachRow"
    if [[ -n "${GW_QUERY_CMD:-}" ]]; then
      gw_out="$("$GW_QUERY_CMD" "$gw_sql" 2>/dev/null)" || gw_out=""
    else
      gw_out="$(doppler run -p soleur -c prd_terraform -- "$ROOT/scripts/betterstack-query.sh" "$gw_sql" 2>/dev/null)" || gw_out=""
    fi
    n="$(printf '%s' "$gw_out" | jq -er '.n' 2>/dev/null)" || n=""
    if [[ ! "$n" =~ ^[0-9]+$ ]]; then
      fail "could not read the gateway log to tell an idle gateway from a broken ingest"
    elif [[ "$n" -gt 0 ]]; then
      fail "no rollup bucket in the last 75 minutes while the gateway logged $n canary-workspace decisions 35-60 minutes ago: ingest is not landing"
    fi
  fi
fi

if [[ "$FAILED" -ne 0 ]]; then exit 1; fi
echo "OK"
