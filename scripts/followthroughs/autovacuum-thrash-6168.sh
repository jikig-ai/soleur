#!/usr/bin/env bash
# Follow-through verification for #6168 (soak gate of PR #6164).
#
# Proves migration 123_tame_autovacuum_on_tiny_hot_tables actually reduced the
# autovacuum RATE on the three tiny public hot-update tables that were draining
# the prod Supabase Disk IO Budget.
#
# autovacuum_count (pg_stat_all_tables) is CUMULATIVE, so a single read cannot
# express a rate. We embed the pre-deploy baseline (count + timestamp captured
# 2026-07-07) and compute each table's weekly rate as
#     (current_count - baseline_count) / weeks_since_baseline.
# Any residual PRE-deploy vacuums in that window only push the measured rate
# UP, never down — so a PASS is trustworthy and this gate can never false-close.
# The average self-corrects downward each week as post-fix weeks accumulate.
#
# Supabase restarts reset pg_stat counters. If pg_stat_database.stats_reset is
# LATER than our baseline, the counters were zeroed after the baseline, so we
# treat current_count as "vacuums since stats_reset" and measure the window
# from stats_reset instead (baseline delta would be meaningless/negative).
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (every table's weekly rate < 15 → sweeper closes #6168)
#   1 = FAIL       (>=1 table still >= 15/week → sweeper comments, leaves open)
#   * = TRANSIENT  (API unreachable, auth/parse failure, insufficient window)
#
# Required env: SUPABASE_ACCESS_TOKEN (declared via the directive's secrets=).

set -uo pipefail

: "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN must be set}" 2>/dev/null || {
  echo "TRANSIENT: SUPABASE_ACCESS_TOKEN not set" >&2
  exit 2
}

PROJECT_REF="ifsccnjhymdmidffkzhl"
API="https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query"

# Pre-deploy baseline (7-day window, stats_reset 2026-06-30 12:40 UTC,
# measured 2026-07-07). See #6168 body.
BASELINE_ISO="2026-07-07T12:00:00Z"
declare -A BASELINE=(
  [user_concurrency_slots]=142
  [mint_rate_window]=50
  [runtime_mint_intent]=49
)
RATE_CEILING=15          # PASS when every table's weekly rate is below this
MIN_WINDOW_WEEKS_X100=90 # require >= 0.90 weeks of window before judging

QUERY="SELECT t.relname AS relname, t.autovacuum_count AS autovacuum_count, \
(SELECT stats_reset FROM pg_stat_database WHERE datname = current_database()) AS stats_reset \
FROM pg_stat_all_tables t \
WHERE t.schemaname = 'public' \
AND t.relname IN ('user_concurrency_slots','mint_rate_window','runtime_mint_intent')"

PAYLOAD=$(jq -n --arg q "$QUERY" '{query: $q}')

RESP=$(curl -sS -w '\nHTTP_STATUS:%{http_code}' \
  -X POST "$API" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

HTTP_STATUS=$(printf '%s' "$RESP" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')
BODY=$(printf '%s' "$RESP" | sed '$d')

# The Supabase Management query endpoint returns 200 OR 201 on success.
if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "201" ]]; then
  echo "TRANSIENT: Supabase query API returned $HTTP_STATUS" >&2
  printf '%s\n' "$BODY" | head -c 500 >&2
  exit 2
fi

# The query API returns a JSON array of row objects.
if ! printf '%s' "$BODY" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "TRANSIENT: unexpected response shape" >&2
  printf '%s\n' "$BODY" | head -c 500 >&2
  exit 2
fi

ROW_COUNT=$(printf '%s' "$BODY" | jq -r 'length' 2>/dev/null)
if [[ "$ROW_COUNT" != "3" ]]; then
  echo "TRANSIENT: expected 3 target tables, got ${ROW_COUNT:-?}" >&2
  exit 2
fi

STATS_RESET=$(printf '%s' "$BODY" | jq -r '.[0].stats_reset // empty')

now_epoch=$(date -u +%s)
baseline_epoch=$(date -u -d "$BASELINE_ISO" +%s 2>/dev/null) || {
  echo "TRANSIENT: could not parse baseline timestamp" >&2
  exit 2
}

# If stats were reset after our baseline, measure from the reset instead.
window_start_epoch="$baseline_epoch"
reset_after_baseline=0
if [[ -n "$STATS_RESET" ]]; then
  reset_epoch=$(date -u -d "$STATS_RESET" +%s 2>/dev/null || echo "")
  if [[ -n "$reset_epoch" && "$reset_epoch" -gt "$baseline_epoch" ]]; then
    window_start_epoch="$reset_epoch"
    reset_after_baseline=1
  fi
fi

window_secs=$(( now_epoch - window_start_epoch ))
# weeks * 100, integer math (no bc dependency under env -i).
weeks_x100=$(( window_secs * 100 / 604800 ))
if [[ "$weeks_x100" -lt "$MIN_WINDOW_WEEKS_X100" ]]; then
  echo "TRANSIENT: measurement window too short (${weeks_x100}/100 weeks) — retry next sweep" >&2
  exit 2
fi

worst_ok=1
echo "autovacuum-thrash soak (#6168): window=${weeks_x100}/100 weeks, ceiling=${RATE_CEILING}/wk, reset_after_baseline=${reset_after_baseline}"
for table in user_concurrency_slots mint_rate_window runtime_mint_intent; do
  cur=$(printf '%s' "$BODY" | jq -r --arg t "$table" '.[] | select(.relname == $t) | .autovacuum_count')
  if ! [[ "$cur" =~ ^[0-9]+$ ]]; then
    echo "TRANSIENT: non-numeric autovacuum_count for $table (got '${cur:-}')" >&2
    exit 2
  fi

  if [[ "$reset_after_baseline" -eq 1 ]]; then
    delta="$cur"                        # all counts are post-reset
  else
    base="${BASELINE[$table]}"
    if [[ "$cur" -lt "$base" ]]; then
      # Counter went backwards without a visible reset — cannot trust the delta.
      echo "TRANSIENT: $table count ($cur) < baseline ($base), unexplained reset — retry" >&2
      exit 2
    fi
    delta=$(( cur - base ))
  fi

  # rate/week = delta / weeks = delta * 100 / weeks_x100
  rate=$(( delta * 100 / weeks_x100 ))
  status="ok"
  if [[ "$rate" -ge "$RATE_CEILING" ]]; then
    status="ABOVE CEILING"
    worst_ok=0
  fi
  echo "  ${table}: count=${cur} delta=${delta} rate=${rate}/wk [${status}]"
done

if [[ "$worst_ok" -eq 1 ]]; then
  echo "PASS: all three tables vacuum < ${RATE_CEILING}/wk (was 49–142) — autovacuum thrash resolved"
  exit 0
fi

echo "FAIL: at least one table still vacuums >= ${RATE_CEILING}/wk" >&2
exit 1
