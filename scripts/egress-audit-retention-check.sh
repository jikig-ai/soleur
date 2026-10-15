#!/usr/bin/env bash
# Retention and freshness probe for the egress audit rollup (#9545, ADR-288).
#
# Prints exactly `OK` on stdout and exits 0 only when:
#   1. no row in public.workspace_egress_audit_rollup has last_seen older than 35 days
#      (the daily pg_cron sweep keeps 30; a row past 35 means the sweep has stopped), and
#   2. when EGRESS_AUDIT_EXPECT_COLLECTION=1: either the newest bucket_start is at most 40
#      minutes old, or the egress gateway log shows no workspace-attributed decision in the
#      last 40 minutes (nothing to ingest).
# Any unavailable read is a failure (exit 1), never a pass; missing credentials exit 2.
#
# Freshness is NOT asserted by default: while the pipeline is dark (collection off for every
# external workspace) the table is legitimately empty, and a stale-table alarm would be a
# standing false alarm. Set EGRESS_AUDIT_EXPECT_COLLECTION=1 once a workspace is enabled.
#
# Run (credentials from Doppler, never printed):
#   doppler run -p soleur -c prd -- bash scripts/egress-audit-retention-check.sh
# Freshness with collection enabled also reads the gateway log, which needs the Better Stack
# query credential (prd_terraform); GW_QUERY_CMD overrides the command (tests).
set -uo pipefail

# Refuse to run under shell tracing while a live credential is set: `set -x` would trace the
# service-role key into whatever collects the output. `$-` tests whether tracing is ON.
case "$-" in *x*) echo "refusing to run under shell tracing (set -x) with a service-role key" >&2; exit 2 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="${SUPABASE_URL:-${NEXT_PUBLIC_SUPABASE_URL:-}}"
KEY="${SUPABASE_SERVICE_ROLE_KEY:-}"
if [[ -z "$URL" || -z "$KEY" ]]; then
  echo "UNAVAILABLE: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required (run under: doppler run -p soleur -c prd -- ...)" >&2
  exit 2
fi
command -v jq >/dev/null 2>&1 || { echo "UNAVAILABLE: jq is required" >&2; exit 2; }

MAX_ROW_AGE_S=$((35 * 86400))
MAX_BUCKET_AGE_S=$((40 * 60))
NOW="$(date -u +%s)"

# rest_get <query-string>: prints the JSON body, returns non-zero on any transport or HTTP error.
# The key travels in a stdin curl config, never on argv.
rest_get() {
  local resp code
  resp="$(printf 'header = "apikey: %s"\nheader = "Authorization: Bearer %s"\n' "$KEY" "$KEY" |
    curl -sS --max-time 20 -K - -w '\n%{http_code}' "${URL%/}/rest/v1/workspace_egress_audit_rollup?$1")" || return 1
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
  body="$(rest_get 'select=bucket_start&order=bucket_start.desc&limit=1')" || exit 1
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
    gw_sql="SELECT count() AS n FROM remote(\$BS_TABLE) WHERE dt > now() - INTERVAL 40 MINUTE AND raw LIKE '%requested_host%' AND raw LIKE '%soleur-egress-gw%' AND match(raw, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}') FORMAT JSONEachRow"
    if [[ -n "${GW_QUERY_CMD:-}" ]]; then
      gw_out="$("$GW_QUERY_CMD" "$gw_sql" 2>/dev/null)" || gw_out=""
    else
      gw_out="$(doppler run -p soleur -c prd_terraform -- "$ROOT/scripts/betterstack-query.sh" "$gw_sql" 2>/dev/null)" || gw_out=""
    fi
    n="$(printf '%s' "$gw_out" | jq -er '.n' 2>/dev/null)" || n=""
    if [[ ! "$n" =~ ^[0-9]+$ ]]; then
      fail "could not read the gateway log to tell an idle gateway from a broken ingest"
    elif [[ "$n" -gt 0 ]]; then
      fail "no rollup bucket in the last 40 minutes while the gateway logged $n workspace-attributed decisions: ingest is not landing"
    fi
  fi
fi

if [[ "$FAILED" -ne 0 ]]; then exit 1; fi
echo "OK"
