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
#      (exclude host metrics + journald noise), --no-archive (hot window only —
#      see below), --table / --table-s3 (override either table).
#
# HOT WINDOW vs ARCHIVE: mode 2 queries remote(<..._logs>) UNION ALL
# s3Cluster(primary, <..._s3>), because remote() alone is ONLY the hot window (~40
# minutes on 2026-07-15). Anything asking for a real soak span MUST include the archive
# arm or it gets a silently short answer. --no-archive opts out (hot-only, faster);
# do not reach for it to work around an archive error — the short answer is the bug.
# Raw SQL (mode 1) is verbatim: write the UNION yourself, using the $BS_TABLE and
# $BS_TABLE_S3 tokens (both are substituted).
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

# ARCHIVE table. `remote(..._logs)` is ONLY the hot window — on 2026-07-15 it held ~40
# MINUTES. Rows older than that live in the s3 archive and are invisible to remote(), so a
# hot-only query silently answers `--since 24h` with 40 minutes of rows: not an error, just
# a short answer. That is what kept #6288 open since 2026-07-10 — its soak gate needs
# ZOT_MIN_SOAK_SPAN_SEC=7200 (2h) of span and could never reach PASS through the keyhole,
# reporting "TRANSIENT: soak not yet filled" forever. Both halves are UNION ALL-combined per
# the runbook (betterstack-log-query.md §Query mechanics). Verified disjoint on 2026-07-15:
# 891 rows / 891 distinct / 0 dupes over 7d, archive ending 19:13:46 and hot starting
# 19:15:02 — so UNION ALL does not double-count (load-bearing: soak gates COUNT events).
#
# An explicit BS_TABLE_S3 (env OR --table-s3) always wins; S3_EXPLICIT records that so the
# post-flag re-derivation below cannot clobber it. Seeding the sentinel from the ENV here —
# not only from the flag — is load-bearing: otherwise `BS_TABLE_S3=other_s3` is accepted,
# silently ignored, and the caller gets rows from the DEFAULT archive with no error, because
# the derived name exists and the query succeeds. That is this script's own headline bug
# (asks for X, gets Y, exit 0) reintroduced one level down.
S3_EXPLICIT=0
[[ -n "${BS_TABLE_S3:-}" ]] && S3_EXPLICIT=1
export BS_TABLE_S3="${BS_TABLE_S3:-${BS_TABLE%_logs}_s3}"

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
  # $BS_TABLE_S3 MUST be substituted before $BS_TABLE: the latter is a prefix of the
  # former, so the reverse order would rewrite `$BS_TABLE_S3` into `<hot_table>_S3` —
  # a table that does not exist — and the caller would see a confusing UNKNOWN_TABLE
  # instead of their archive rows.
  sql="${1//\$BS_TABLE_S3/$BS_TABLE_S3}"
  run_sql "${sql//\$BS_TABLE/$BS_TABLE}"
  exit $?
fi

# --- Mode 2: convenience flags ---
SINCE="1h"; UNTIL=""; LIMIT=100; RAW_ONLY=0; NO_ARCHIVE=0
GREPS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) SINCE="$2"; shift 2 ;;
    --until) UNTIL="$2"; shift 2 ;;
    --grep)  GREPS+=("$2"); shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --raw-only) RAW_ONLY=1; shift ;;
    --no-archive) NO_ARCHIVE=1; shift ;;
    --table) BS_TABLE="$2"; export BS_TABLE; shift 2 ;;
    --table-s3) BS_TABLE_S3="$2"; S3_EXPLICIT=1; export BS_TABLE_S3; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 64 ;;
  esac
done

# Re-derive the archive name AFTER flag parsing so `--table` and `--table-s3` are
# order-independent: an explicit --table-s3 (or BS_TABLE_S3 env) always wins, whichever
# side it was passed on.
if (( ! S3_EXPLICIT )); then
  # Only the `_logs` suffix has a known `_s3` counterpart. The runbook documents `_metrics`
  # and `_spans` tables too; guessing `<name>_metrics_s3` for those would invent a table the
  # caller never named — silently querying the wrong source if it happens to exist. Demand
  # an explicit archive name instead of guessing.
  if [[ "$BS_TABLE" != *_logs ]]; then
    if (( NO_ARCHIVE )); then
      BS_TABLE_S3=""   # unused on this path; nothing to derive.
    else
      cat >&2 <<EOF
betterstack-query.sh: cannot derive an archive table from BS_TABLE='${BS_TABLE}'.

Only <name>_logs has a known <name>_s3 counterpart. For any other table, name the archive
explicitly or opt out of it:

  --table-s3 <archive_table>   (or BS_TABLE_S3=<archive_table>)
  --no-archive                 (hot window only — returns ~40 minutes; see the header)
EOF
      exit 64
    fi
  else
    BS_TABLE_S3="${BS_TABLE%_logs}_s3"
  fi
fi
export BS_TABLE_S3

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

# Hot window + s3 archive, UNION ALL-combined (runbook §Query mechanics). ORDER BY and
# LIMIT apply to the COMBINED set — pushing them inside either arm would truncate each
# half independently and interleave wrongly.
#
# LIMIT takes the NEWEST rows (inner ORDER BY dt DESC), then the outer ORDER BY dt ASC
# restores chronological output. Both halves are load-bearing:
#   - DESC inner: before the archive arm existed the window was structurally <=40 min, so
#     LIMIT effectively never bound and ASC+LIMIT was harmless. Against a real 24h window it
#     bites — the runbook's own `--since 48h --grep SOLEUR_CLAUDE_COST --limit 20` would
#     answer "show me recent costs" with the OLDEST 20 markers, i.e. ~48h stale. "Most
#     recent N" is what every caller of a log tail means.
#   - ASC outer: callers (and humans) read oldest->newest; flipping output order would be a
#     silent behavior change for anything parsing the stream positionally.
#
# FAIL LOUD, never silently hot-only: returning a short answer to `--since 24h` is the
# exact failure this fix exists to remove, and it is invisible at the call site (a caller
# counting events sees "not yet filled", not "your window was truncated"). If the archive
# arm errors, the whole query errors and the caller must opt out deliberately with
# --no-archive rather than be handed partial data it will read as complete.
if (( NO_ARCHIVE )); then
  run_sql "SELECT dt, raw FROM (
  SELECT dt, raw FROM remote(${BS_TABLE}) WHERE ${WHERE} ORDER BY dt DESC LIMIT ${LIMIT}
) ORDER BY dt ASC FORMAT JSONEachRow"
else
  run_sql "SELECT dt, raw FROM (
  SELECT dt, raw FROM (
    SELECT dt, raw FROM remote(${BS_TABLE}) WHERE ${WHERE}
    UNION ALL
    SELECT dt, raw FROM s3Cluster(primary, ${BS_TABLE_S3}) WHERE _row_type = 1 AND (${WHERE})
  ) ORDER BY dt DESC LIMIT ${LIMIT}
) ORDER BY dt ASC FORMAT JSONEachRow"
fi
