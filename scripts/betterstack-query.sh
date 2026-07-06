#!/usr/bin/env bash
# Query Better Stack Telemetry logs/metrics via the ClickHouse HTTP SQL API.
#
# Better Stack stores ingested logs in a ClickHouse warehouse queryable over
# HTTP with plain SQL. This is the ONLY way to read HISTORICAL logs
# programmatically — the `BETTERSTACK_LOGS_TOKEN` is INGEST-ONLY (write), and
# the `BETTERSTACK_API_TOKEN` (Telemetry mgmt API) covers source/connection
# metadata but NOT log content. Reading log rows needs a dedicated ClickHouse
# HTTP *connection* (a username/password pair distinct from both tokens).
#
# Provisioning (already done once via the Telemetry API, NOT the dashboard):
#   POST https://logs.betterstack.com/api/v1/connections
#     {"client_type":"clickhouse","team_ids":[<TEAM_ID>]}
#   → 201 returns {host, port, username, password, data_region}. Stored in
#   Doppler soleur/prd_terraform as BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}.
#   To re-mint: see knowledge-base/engineering/operations/runbooks/betterstack-log-query.md.
#
# Table identifier for the remote() function is `t<TEAM_ID>_<table_name>_logs`
# (team id, NOT source id — the docs' `t123456_...` placeholder is the team).
# Our source `soleur-inngest-vector-prd` (id 2457081, team 520508, table
# soleur_inngest_vector_prd_3) → remote(t520508_soleur_inngest_vector_prd_3_logs).
#
# Usage:
#   doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh "<SQL>"
#   doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep cron-roadmap-review
#
# Two modes:
#   1. Raw SQL (first positional arg is a SELECT …): runs it verbatim. Use the
#      $BS_TABLE env (exported by this script) for the remote() arg, e.g.
#      "SELECT dt, raw FROM remote($BS_TABLE) WHERE … LIMIT 50 FORMAT JSONEachRow"
#   2. Convenience flags (no SQL arg): --since <Nh|Nm|ISO>, --until <ISO>,
#      --grep <substr> (repeatable, OR-combined), --limit <N>, --raw-only
#      (exclude host metrics + journald noise).
#
# Output: JSONEachRow (one JSON object per line) on stdout. Errors to stderr.
set -uo pipefail

# Credential guard. These are Doppler-managed secrets that must be INJECTED into
# the env — this script does not read Doppler itself. A bare-shell run (no
# `doppler run` wrapper) trips this. The message is deliberately explicit that the
# fix is the invocation, NOT a missing capability: an agent that reads "unset" as
# "this session lacks Better Stack access" and gives up is the exact misdiagnosis
# this hint exists to prevent (see hr-observability-probe-transient-is-not-no-access).
if [[ -z "${BETTERSTACK_QUERY_HOST:-}" || -z "${BETTERSTACK_QUERY_USERNAME:-}" || -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]]; then
  cat >&2 <<'EOF'
betterstack-query.sh: BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} not set.

You are NOT missing Better Stack access — these creds live in Doppler and this
script needs them INJECTED. Re-run wrapped in `doppler run`:

  doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh <args>

e.g.  doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep <marker>

Do NOT conclude "no access / can't verify" from this message — the correct next
step is the doppler-wrapped re-run above. (Creds provisioning: see
knowledge-base/engineering/operations/runbooks/betterstack-log-query.md)
EOF
  exit 3
fi

# Table identifier — overridable for other sources via BS_TABLE.
export BS_TABLE="${BS_TABLE:-t520508_soleur_inngest_vector_prd_3_logs}"

run_sql() {
  # $1 = SQL. Credentials via Basic auth; never echoed.
  curl -sS --fail-with-body --max-time 60 \
    -u "${BETTERSTACK_QUERY_USERNAME}:${BETTERSTACK_QUERY_PASSWORD}" \
    -H 'Content-type: plain/text' \
    -X POST "https://${BETTERSTACK_QUERY_HOST}?output_format_pretty_row_numbers=0" \
    -d "$1"
}

# --- Mode 1: raw SQL ---
# Callers may write the literal token `$BS_TABLE` in their SQL; we substitute it
# here so the table identifier survives `doppler run -- ... "$BS_TABLE"` quoting
# (the env var would otherwise stay unexpanded inside the single-quoted arg).
if [[ $# -ge 1 && "$1" =~ ^[[:space:]]*(SELECT|WITH|SHOW)[[:space:]] ]]; then
  run_sql "${1//\$BS_TABLE/$BS_TABLE}"
  exit $?
fi

# --- Mode 2: convenience flags ---
SINCE="1h"; UNTIL=""; LIMIT=100; RAW_ONLY=0
GREPS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) SINCE="$2"; shift 2 ;;
    --until) UNTIL="$2"; shift 2 ;;
    --grep)  GREPS+=("$2"); shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --raw-only) RAW_ONLY=1; shift ;;
    --table) BS_TABLE="$2"; export BS_TABLE; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 64 ;;
  esac
done

# Build the WHERE clause. `dt` is the ClickHouse event-time column.
# --since accepts Nh / Nm / Nd (relative) or a literal 'YYYY-MM-DD HH:MM:SS'.
if [[ "$SINCE" =~ ^([0-9]+)([hmd])$ ]]; then
  unit="${BASH_REMATCH[2]}"
  case "$unit" in h) ivl="HOUR";; m) ivl="MINUTE";; d) ivl="DAY";; esac
  WHERE="dt >= now() - INTERVAL ${BASH_REMATCH[1]} ${ivl}"
else
  WHERE="dt >= '${SINCE}'"
fi
[[ -n "$UNTIL" ]] && WHERE="${WHERE} AND dt <= '${UNTIL}'"

if (( RAW_ONLY )); then
  # Exclude Vector host-metrics and journald supervisor noise — leaves app logs.
  WHERE="${WHERE} AND raw NOT LIKE '%\"namespace\":\"host\"%' AND raw NOT LIKE '%SYSLOG_IDENTIFIER%'"
fi

if (( ${#GREPS[@]} > 0 )); then
  ORS=""
  for g in "${GREPS[@]}"; do
    # Escape single quotes in the grep term for SQL.
    esc="${g//\'/\'\'}"
    ORS="${ORS}${ORS:+ OR }raw LIKE '%${esc}%'"
  done
  WHERE="${WHERE} AND (${ORS})"
fi

run_sql "SELECT dt, raw FROM remote(${BS_TABLE}) WHERE ${WHERE} ORDER BY dt ASC LIMIT ${LIMIT} FORMAT JSONEachRow"
