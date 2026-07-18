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
# a PRE-deploy baseline (n_tup_upd + n_tup_ins + capture timestamp + the
# stats_reset it was taken under, 2026-07-18) and compute a TRAFFIC-NORMALIZED
# ratio, NOT an absolute rate:
#     ratio = n_tup_upd_delta / n_tup_ins_delta   (updates per slot acquisition)
# n_tup_ins on user_concurrency_slots is one INSERT per slot acquire (~ per
# session start); n_tup_upd is dominated by the touch_conversation_slot
# heartbeat UPDATE. So updates-per-acquisition ≈ heartbeats-per-session =
# session_duration / heartbeat_interval — DOUBLING the interval (30s→60s) HALVES
# this ratio, independent of traffic volume. An absolute-rate metric would
# confound "heartbeat halved" with "traffic changed" (performance-oracle P2);
# the ratio is traffic-invariant. baseline_ratio is over the full history
# (mostly 30s heartbeat); post_ratio is over the post-deploy window (60s).
# PASS when post_ratio <= PASS_FRACTION × baseline_ratio. This pipeline
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
BASELINE_UPD=7635
BASELINE_INS=538
BASELINE_ISO="2026-07-18T08:43:40Z"
BASELINE_STATS_RESET_EPOCH=$(date -u -d "2026-02-12T23:53:40Z" +%s 2>/dev/null) || {
  echo "TRANSIENT: could not parse baseline stats_reset" >&2
  exit 2
}
# PASS when the post-deploy updates-per-acquisition ratio is <= 75% of the
# pre-deploy ratio. The heartbeat halving targets ~50%, but n_tup_upd also
# carries the acquire ON CONFLICT DO UPDATE + downgrade-sweep writes (unaffected
# by the interval), so 0.75 is a robust "clear reduction" ceiling that "≈ halves"
# comfortably clears while tolerating variable session-duration mixes.
PASS_FRACTION_X100=75
MIN_WINDOW_WEEKS_X100=90 # require >= 0.90 weeks of post-deploy window before judging
MIN_POST_ACQUIRES=20     # require >= 20 slot acquisitions in the window for signal

QUERY="SELECT t.relname AS relname, t.n_tup_upd AS n_tup_upd, t.n_tup_ins AS n_tup_ins, \
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
CUR_INS=$(printf '%s' "$BODY" | jq -r '.[0].n_tup_ins')
STATS_RESET=$(printf '%s' "$BODY" | jq -r '.[0].stats_reset // empty')
if ! [[ "$CUR" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: non-numeric n_tup_upd (got '${CUR:-}')" >&2
  exit 2
fi
if ! [[ "$CUR_INS" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: non-numeric n_tup_ins (got '${CUR_INS:-}')" >&2
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

if [[ "$CUR" -lt "$BASELINE_UPD" ]]; then
  echo "TRANSIENT: current n_tup_upd ($CUR) < baseline ($BASELINE_UPD), unexplained reset — retry" >&2
  exit 2
fi
if [[ "$CUR_INS" -lt "$BASELINE_INS" ]]; then
  echo "TRANSIENT: current n_tup_ins ($CUR_INS) < baseline ($BASELINE_INS), unexplained reset — retry" >&2
  exit 2
fi

now_epoch=$(date -u +%s)
baseline_epoch=$(date -u -d "$BASELINE_ISO" +%s 2>/dev/null) || {
  echo "TRANSIENT: could not parse baseline capture timestamp" >&2
  exit 2
}

post_window_secs=$(( now_epoch - baseline_epoch ))
post_weeks_x100=$(( post_window_secs * 100 / 604800 ))
if [[ "$post_weeks_x100" -lt "$MIN_WINDOW_WEEKS_X100" ]]; then
  echo "TRANSIENT: post-deploy window too short (${post_weeks_x100}/100 weeks) — retry next sweep" >&2
  exit 2
fi

# Traffic-normalized ratio = updates per slot acquisition (x1000 for integer precision).
# baseline over the full history; post over the post-deploy window's DELTAS.
post_upd_delta=$(( CUR - BASELINE_UPD ))
post_ins_delta=$(( CUR_INS - BASELINE_INS ))
if [[ "$post_ins_delta" -lt "$MIN_POST_ACQUIRES" ]]; then
  echo "TRANSIENT: only ${post_ins_delta} slot acquisitions in the post window (< ${MIN_POST_ACQUIRES}) — insufficient signal, retry" >&2
  exit 2
fi
if [[ "$BASELINE_INS" -le 0 ]]; then
  echo "TRANSIENT: non-positive baseline acquisition count" >&2
  exit 2
fi

baseline_ratio_m=$(( BASELINE_UPD * 1000 / BASELINE_INS ))
post_ratio_m=$(( post_upd_delta * 1000 / post_ins_delta ))
ceiling_m=$(( baseline_ratio_m * PASS_FRACTION_X100 / 100 ))

echo "concurrency-slot WAL backoff soak: post_window=${post_weeks_x100}/100 weeks, post_acquires=${post_ins_delta}"
echo "  baseline: upd/ins ratio=$(( baseline_ratio_m / 1000 )).$(( baseline_ratio_m % 1000 )) (updates per acquisition)"
echo "  post:     upd/ins ratio=$(( post_ratio_m / 1000 )).$(( post_ratio_m % 1000 )) (ceiling $(( ceiling_m / 1000 )).$(( ceiling_m % 1000 )) = ${PASS_FRACTION_X100}% of baseline)"

if [[ "$post_ratio_m" -le "$ceiling_m" ]]; then
  echo "PASS: updates-per-acquisition dropped to <= ${PASS_FRACTION_X100}% of baseline — heartbeat backoff confirmed (traffic-normalized)"
  exit 0
fi

echo "FAIL: updates-per-acquisition still above ${PASS_FRACTION_X100}% of baseline — heartbeat backoff not confirmed" >&2
exit 1
