#!/usr/bin/env bash
# Follow-through soak verification for the Supabase Disk-IO write-reduction PR
# (heartbeat backoff, migration 133 + SLOT_HEARTBEAT_INTERVAL_MS 30s->60s).
#
# Proves the slot heartbeat backoff actually reduced the WRITE RATE on
# user_concurrency_slots. The touch_conversation_slot UPDATE (the dominant
# writer) now fires every 60 s instead of 30 s, so its contribution to
# n_tup_upd should roughly halve.
#
# n_tup_upd (pg_stat_all_tables) is CUMULATIVE since stats_reset, so a single
# read cannot express a rate (AC12: a lone re-call can never "halve"). We embed
# a PRE-deploy baseline (count + capture timestamp + the stats_reset it was
# taken under, 2026-07-18) and compute:
#     baseline_rate = baseline_count / (baseline_captured - stats_reset)   [pre]
#     post_rate     = (current - baseline_count) / (now - baseline_captured) [post]
# PASS when post_rate has dropped meaningfully vs baseline_rate. Any residual
# pre-deploy writes in the post window only bias post_rate UP, never down — so a
# PASS is trustworthy and this gate cannot false-close. This pipeline
# auto-merges + deploys same-day, so baseline_captured ~= deploy time.
#
# If pg_stat_database.stats_reset differs from the baseline's (a Supabase
# restart zeroed the counters after the baseline), the cumulative delta is
# meaningless — we cannot reconstruct the pre-deploy rate, so we emit TRANSIENT
# and retry on the next sweep rather than risk a false verdict.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (post write-rate <= PASS_FRACTION x baseline rate)
#   1 = FAIL       (post write-rate still above the ceiling)
#   * = TRANSIENT  (API unreachable, auth/parse failure, counter reset, short window)
#
# Required env: SUPABASE_ACCESS_TOKEN (declared via the directive's secrets=).

set -uo pipefail

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "TRANSIENT: SUPABASE_ACCESS_TOKEN not set" >&2
  exit 2
fi

PROJECT_REF="ifsccnjhymdmidffkzhl"
API="https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query"

# Pre-deploy baseline for user_concurrency_slots (measured 2026-07-18 08:43 UTC,
# stats_reset 2026-02-12 23:53:40 UTC). See PR body.
BASELINE_COUNT=7635
BASELINE_ISO="2026-07-18T08:43:40Z"
BASELINE_STATS_RESET_EPOCH=$(date -u -d "2026-02-12T23:53:40Z" +%s 2>/dev/null) || {
  echo "TRANSIENT: could not parse baseline stats_reset" >&2
  exit 2
}
# PASS when the post-deploy weekly rate is <= 75% of the pre-deploy rate. The
# heartbeat halving targets ~50%, but n_tup_upd also carries the acquire
# ON CONFLICT DO UPDATE + downgrade-sweep writes (unaffected), so 0.75 is a
# robust "clear reduction" ceiling that "≈ halves" comfortably clears while
# tolerating variable connection patterns.
PASS_FRACTION_X100=75
MIN_WINDOW_WEEKS_X100=90 # require >= 0.90 weeks of post-deploy window before judging

QUERY="SELECT t.relname AS relname, t.n_tup_upd AS n_tup_upd, \
(SELECT stats_reset FROM pg_stat_database WHERE datname = current_database()) AS stats_reset \
FROM pg_stat_all_tables t \
WHERE t.schemaname = 'public' AND t.relname = 'user_concurrency_slots'"

PAYLOAD=$(jq -n --arg q "$QUERY" '{query: $q}')

RESP=$(curl -sS -w '\nHTTP_STATUS:%{http_code}' \
  -X POST "$API" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

HTTP_STATUS=$(printf '%s' "$RESP" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')
BODY=$(printf '%s' "$RESP" | sed '$d')

if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "201" ]]; then
  echo "TRANSIENT: Supabase query API returned $HTTP_STATUS" >&2
  printf '%s\n' "$BODY" | head -c 500 >&2
  exit 2
fi

if ! printf '%s' "$BODY" | jq -e 'type == "array" and length == 1' >/dev/null 2>&1; then
  echo "TRANSIENT: unexpected response shape" >&2
  printf '%s\n' "$BODY" | head -c 500 >&2
  exit 2
fi

CUR=$(printf '%s' "$BODY" | jq -r '.[0].n_tup_upd')
STATS_RESET=$(printf '%s' "$BODY" | jq -r '.[0].stats_reset // empty')
if ! [[ "$CUR" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: non-numeric n_tup_upd (got '${CUR:-}')" >&2
  exit 2
fi

# Counter-reset guard: if stats were reset after our baseline, the cumulative
# delta is meaningless and we cannot reconstruct the pre-deploy rate.
if [[ -n "$STATS_RESET" ]]; then
  reset_epoch=$(date -u -d "$STATS_RESET" +%s 2>/dev/null || echo "")
  if [[ -z "$reset_epoch" ]]; then
    echo "TRANSIENT: could not parse live stats_reset '$STATS_RESET'" >&2
    exit 2
  fi
  # Allow small clock jitter (60s) around the embedded baseline reset epoch.
  if [[ $(( reset_epoch > BASELINE_STATS_RESET_EPOCH ? reset_epoch - BASELINE_STATS_RESET_EPOCH : BASELINE_STATS_RESET_EPOCH - reset_epoch )) -gt 60 ]]; then
    echo "TRANSIENT: stats_reset changed since baseline (counters zeroed) — cannot compare rates, retry" >&2
    exit 2
  fi
fi

if [[ "$CUR" -lt "$BASELINE_COUNT" ]]; then
  echo "TRANSIENT: current n_tup_upd ($CUR) < baseline ($BASELINE_COUNT), unexplained reset — retry" >&2
  exit 2
fi

now_epoch=$(date -u +%s)
baseline_epoch=$(date -u -d "$BASELINE_ISO" +%s 2>/dev/null) || {
  echo "TRANSIENT: could not parse baseline capture timestamp" >&2
  exit 2
}

pre_window_secs=$(( baseline_epoch - BASELINE_STATS_RESET_EPOCH ))
post_window_secs=$(( now_epoch - baseline_epoch ))
if [[ "$pre_window_secs" -le 0 ]]; then
  echo "TRANSIENT: non-positive pre-deploy window" >&2
  exit 2
fi
post_weeks_x100=$(( post_window_secs * 100 / 604800 ))
if [[ "$post_weeks_x100" -lt "$MIN_WINDOW_WEEKS_X100" ]]; then
  echo "TRANSIENT: post-deploy window too short (${post_weeks_x100}/100 weeks) — retry next sweep" >&2
  exit 2
fi

# rate/week (x1000 for integer precision) = count * 604800 * 1000 / window_secs
baseline_rate_m=$(( BASELINE_COUNT * 604800 * 1000 / pre_window_secs ))
post_delta=$(( CUR - BASELINE_COUNT ))
post_rate_m=$(( post_delta * 604800 * 1000 / post_window_secs ))
ceiling_m=$(( baseline_rate_m * PASS_FRACTION_X100 / 100 ))

echo "concurrency-slot WAL backoff soak: post_window=${post_weeks_x100}/100 weeks"
echo "  baseline: count=${BASELINE_COUNT} rate=$(( baseline_rate_m / 1000 ))/wk"
echo "  post:     delta=${post_delta} rate=$(( post_rate_m / 1000 ))/wk (ceiling $(( ceiling_m / 1000 ))/wk = ${PASS_FRACTION_X100}% of baseline)"

if [[ "$post_rate_m" -le "$ceiling_m" ]]; then
  echo "PASS: user_concurrency_slots write rate dropped to <= ${PASS_FRACTION_X100}% of baseline — heartbeat backoff confirmed"
  exit 0
fi

echo "FAIL: user_concurrency_slots write rate still above ${PASS_FRACTION_X100}% of baseline — heartbeat backoff not confirmed" >&2
exit 1
