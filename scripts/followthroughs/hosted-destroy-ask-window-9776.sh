#!/usr/bin/env bash
# Follow-through probe for #9776 (epic #9601): are the hosted must-ask lane's post-deploy soak numbers inside the
# revert and tune thresholds of CPO4-R5 (ADR-284)? It reads the pino `decision:"destroy-ask*"` WARN lines the lane
# emits (apps/web-platform/server/destroy-ask-lane.ts) from Better Stack and prints COUNTS only.
#
#   --window 24h   the revert window: any `classifier-error` ask is a revert-or-fix-inside-24h signal, and one repo
#                  with at least MIN_REPO_ASKS asks of which one rule is more than 25 percent trips the storm proxy.
#   --window 7d    the tune window: `git-push-unknown-default` above 10 percent of asks, or `fail-closed-keyword` plus
#                  `raw-scan` above 25 percent of asks, means TUNE (not revert); a clean 7d window is the measurement
#                  CPO3-R1 and #9603 wait for, so it ends in ACTION REQUIRED (record the numbers in the ADR-277 addendum).
#
# WHAT THIS CANNOT MEASURE, AND SAYS SO. CPO4-R5 words the storm rule as a share of one workspace's HOSTED BASH CALLS.
# The per-call lines (`autonomous-bypass`, `user-approved`) are pino INFO and the app-container shipper drops INFO (WARN
# and above only, betterstack-log-query.md), so the denominator is not in the stored telemetry. The proxy used here is
# the share of ONE REPO's ASKS that one rule accounts for, behind a minimum-asks floor; it is a tripwire for "one rule is
# the whole ask stream", not the ruled metric. The ruled metric is NOT MEASURED anywhere (no Sentry rate stands in for
# it: the Sentry events are also capped per context). Outcome lines (approved, rejected, expired) are shipped at WARN for
# the same reason. Near-miss events are Sentry-only and are not read here.
#
# ISOLATION AND LIVENESS (#10054, measured 2026-10-12). (1) Every count below reads APP-CONTAINER rows only (decoded
# `raw` has CONTAINER_NAME == soleur-web-platform): a bare `--grep destroy-ask` also returns the Inngest host's journald
# copies of GitHub webhook payloads that QUOTE the marker (36 rows in 24h and 57 in 7d, measured 2026-10-12), which used
# to trip SHAPE_DRIFT on every sweep. A row is excluded only when it is POSITIVELY another service's: its `raw` decodes to
# an object whose CONTAINER_NAME is not the app container. A marker-mentioning row whose `raw` does not decode (truncated,
# non-JSON) cannot be classified, so it still counts toward SHAPE_DRIFT. The stored-row check (DECODABLE) is deliberately
# NOT isolated: it asks whether the body is stored rows at all, and a result holding only another service's rows is still
# stored rows. The raw-line truncation check stays on the RAW count, because contaminating rows fill the row limit
# before isolation and would otherwise let truncation evict real lane rows unnoticed. (2) A window with zero asks is only
# reported as quiet when a second read, over the SAME window and both Better Stack arms (one UNION count, not a per-arm
# proof), shows the app container shipping pino WARN lines: at least one in the window, at least one in the last
# LIVE_RECENT_HOURS hours (an ingest that went dark days ago has old rows only), and, for the 7d window, rows on at least
# LIVE_MIN_DAYS_7D distinct calendar days; otherwise it is CANNOT ESTABLISH (a dark channel reads like a quiet one). The
# liveness read is skipped when asks exist (the asks are themselves app-container WARN rows). That proves the CHANNEL,
# not the LANE: a lane re-inerted by a later change still reads quiet here. The dev probe (CLO C9) is the lane's
# liveness check and re-running it is a HUMAN step: sdk-bump-sandbox-gate.sh only demands a `sdk-bump-verified:` commit
# attestation on a lockfile SDK change, it does not run the probe and cannot see sandbox-option or hook changes (the
# causes of #10054); #10111 tracks automating it.
#
# THE WINDOW IS TRAILING (from the moment the sweeper runs), not anchored at the lane deploy T0: the sweeper's daily
# read starts at 18:00Z and omits the first hours after T0, and an early manual run includes the inert era. So a 7d
# verdict here is an ALARM, never the measurement; the measurement is an explicit [T0, T0+7d] read (ADR-284 Flip checklist).
# Known limit (pre-existing, #9977): the printed counts are exact integers in a PUBLIC comment; the CLO under-5 rule
# applies to what is RECORDED in the ADRs and the post-mortem.
#
# NOTIFY-ONLY probe: nothing here exits 0 or 1 (the sweeper's TRANSIENT sub-vocabulary, followthrough-convention.md):
#   2 = NOT YET           no threshold tripped (or no ask rows with a live channel: a quiet window is expected at low volume)
#   3 = CANNOT ESTABLISH  bad argument, missing credential, failed query, an unparseable or truncated result, outcome
#                         lines with no matching ask lines, a stored-shape drift, or zero asks with no proof the channel is live
#   5 = ACTION REQUIRED   a revert or tune threshold tripped, the clean 7d measurement is ready to record, or the 7d window
#                         read with zero natural asks on a live channel (confirm with an explicit [T0, T0+7d] read, then flip)
#  78 = xtrace refusal while a credential is set (#7797)
#
# THE SWEEPER POSTS THIS STDOUT AS A PUBLIC COMMENT: counts and rule ids only, never a repo name, a command or the
# query script's output (it can echo credentials on an auth failure).
#
# Required env (declare via the directive's secrets=): BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME,
# BETTERSTACK_QUERY_PASSWORD (wired in scheduled-followthrough-sweeper.yml).
#
# STORED SHAPE: measured 2026-10-10 on live app-container rows (a pino WARN line is stored as `raw` = a JSON string
# whose `.message` is the pino object, with `.level` 40 and `.msg`); NOT measured on a `destroy-ask` row, which cannot
# exist before the lane ships. A decode that finds marker-mentioning rows and none that decode is reported as
# SHAPE_DRIFT, never as "not yet".
#
# RETIREMENT (the flip PR deletes these together; ADR-284 "Flip checklist"): this file, its .test.sh, its run_suite row in scripts/test-all.sh,
# and the two tracker directives.
set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (see #7797).\n' >&2
      exit 78
    fi
    ;;
esac

readonly MIN_REPO_ASKS=20
readonly STORM_SHARE_PCT=25
readonly UNKNOWN_DEFAULT_PCT=10
readonly KEYWORD_RAW_PCT=25
readonly MARKER="destroy-ask"
readonly ROW_LIMIT=5000
readonly LIVE_RECENT_HOURS=3
readonly LIVE_MIN_DAYS_7D=6
# The app container serves users; the canary container (soleur-web-platform-canary) does not, and the match is exact.
readonly APP_CONTAINER="soleur-web-platform"

WINDOW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --window) WINDOW="${2:-}"; shift 2 ;;
    *) echo "CANNOT ESTABLISH: unknown argument (usage: --window 24h|7d)"; exit 3 ;;
  esac
done
case "$WINDOW" in
  24h|7d) ;;
  *) echo "CANNOT ESTABLISH: --window must be 24h or 7d"; exit 3 ;;
esac

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
QUERY="${DESTROY_ASK_QUERY_SCRIPT:-$REPO_ROOT/scripts/betterstack-query.sh}"

if [[ ! -f "$QUERY" ]]; then
  echo "CANNOT ESTABLISH: the Better Stack query script is missing"
  exit 3
fi
for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [[ -z "${!v:-}" ]]; then
    echo "CANNOT ESTABLISH: $v is not set in the probe environment"
    exit 3
  fi
done

OUT="$(bash "$QUERY" --since "$WINDOW" --grep "$MARKER" --limit "$ROW_LIMIT" 2>&1)"
RC=$?
if (( RC != 0 )); then
  echo "CANNOT ESTABLISH: the Better Stack query exited $RC (output withheld — may contain credentials)"
  exit 3
fi

# One jq pass: decode `raw`, keep app-container rows only, require the pino object under `.message` with a `decision` that
# starts with the marker. Output: decision <TAB> ruleId <TAB> repo <TAB> approverRole (sentinels, never empty: tab is IFS
# whitespace). Isolation here is POSITIVE (decoded `raw` is an object whose CONTAINER_NAME is exactly $c); MENTIONS uses the
# complement (positively foreign rows are excluded, unclassifiable ones are kept), so the two predicates are a pair, not one.
ROWS="$(printf '%s\n' "$OUT" \
  | jq -R -r --arg m "$MARKER" --arg c "$APP_CONTAINER" '
      fromjson? | (.raw // empty | fromjson? | select(type == "object" and .CONTAINER_NAME == $c) | .message | select(type == "object")) as $p
      | select(($p.decision // "") | startswith($m))
      | select(($p.level // 40) >= 40)
      | "\($p.decision)\t\($p.ruleId // "-")\t\($p.repo // "-")\t\($p.approverRole // "-")"' 2>/dev/null \
  | LC_ALL=C sort || true)"

# A body that is not stored rows (an error object with exit 0, an HTML page) must not read as a quiet window, and a
# result at the row limit is truncated: either way the counts below would describe the wrong population.
OUT_LINES="$(printf '%s\n' "$OUT" | grep -c . || true)"
DECODABLE="$(printf '%s\n' "$OUT" | jq -R -r 'fromjson? | select(type == "object" and has("raw")) | 1' 2>/dev/null | grep -c . || true)"
if (( OUT_LINES > 0 && DECODABLE == 0 )); then
  echo "CANNOT ESTABLISH: the Better Stack query returned ${OUT_LINES} line(s) and none is a stored row (output withheld)."
  exit 3
fi
if (( OUT_LINES >= ROW_LIMIT )); then
  echo "CANNOT ESTABLISH: the result reached the ${ROW_LIMIT}-row limit, so the window is truncated and the counts are not trustworthy."
  exit 3
fi

TOTAL="$(printf '%s' "$ROWS" | grep -c . || true)"
# Stored rows that mention the marker and are NOT positively another service's (see the header): the app container's own
# rows and rows whose `raw` does not decode. Another service's rows quoting the marker are not a shape drift.
MENTIONS="$(printf '%s\n' "$OUT" \
  | jq -R -r --arg m "$MARKER" --arg c "$APP_CONTAINER" '
      fromjson? | select(type == "object" and has("raw")) | select((.raw | tostring) | contains($m))
      | (try (.raw | fromjson) catch null) as $o
      | select(($o | type) != "object" or $o.CONTAINER_NAME == $c) | 1' 2>/dev/null \
  | grep -c . || true)"
if (( TOTAL == 0 && MENTIONS > 0 )); then
  echo "CANNOT ESTABLISH: SHAPE_DRIFT — ${MENTIONS} row(s) mention $MARKER but none decodes as a lane row; the stored shape may have changed (re-measure it against a live row)."
  exit 3
fi
if (( TOTAL == 0 )); then
  # Zero asks is only a measurement when the channel is proven live over the same window (both Better Stack arms):
  # app-container pino rows at level 40 or above. The convenience flags cannot filter on container or level, so this is
  # one raw-SQL call through the same query script ($BS_TABLE and $BS_TABLE_S3 are substituted by it).
  case "$WINDOW" in 24h) IVL="24 HOUR" ;; *) IVL="7 DAY" ;; esac
  LIVE_PRED="JSONExtractString(raw, 'CONTAINER_NAME') = '${APP_CONTAINER}' AND JSONExtractInt(raw, 'message', 'level') >= 40"
  LIVE_SQL="SELECT count() AS n, countIf(dt >= now() - INTERVAL ${LIVE_RECENT_HOURS} HOUR) AS recent, uniqExact(toDate(dt)) AS days FROM (SELECT dt, raw FROM remote(\$BS_TABLE) WHERE dt >= now() - INTERVAL ${IVL} AND ${LIVE_PRED} UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1 AND dt >= now() - INTERVAL ${IVL} AND ${LIVE_PRED}) FORMAT JSONEachRow"
  LIVE_OUT="$(bash "$QUERY" "$LIVE_SQL" 2>&1)"
  LIVE_RC=$?
  if (( LIVE_RC != 0 )); then
    echo "CANNOT ESTABLISH: the channel liveness query exited ${LIVE_RC} (output withheld — may contain credentials); zero asks cannot be read as a quiet window."
    exit 3
  fi
  # Three non-negative integers or nothing: any other shape (garbage, a missing key, a float) leaves LIVE_FIELDS empty.
  LIVE_FIELDS="$(printf '%s\n' "$LIVE_OUT" \
    | jq -R -r 'fromjson? | select(type == "object") | [.n, .recent, .days] | map(tostring) | select(all(.[]; test("^[0-9]+$"))) | @tsv' 2>/dev/null \
    | head -1)"
  LIVE=""; LIVE_RECENT=""; LIVE_DAYS=""
  IFS=$'\t' read -r LIVE LIVE_RECENT LIVE_DAYS <<<"$LIVE_FIELDS"
  if ! [[ "$LIVE" =~ ^[0-9]+$ && "$LIVE_RECENT" =~ ^[0-9]+$ && "$LIVE_DAYS" =~ ^[0-9]+$ ]]; then
    echo "CANNOT ESTABLISH: the channel liveness query returned no parseable counts (output withheld); zero asks cannot be read as a quiet window."
    exit 3
  fi
  MIN_DAYS=1; [[ "$WINDOW" == "7d" ]] && MIN_DAYS="$LIVE_MIN_DAYS_7D"
  if (( LIVE == 0 )); then
    echo "CANNOT ESTABLISH: zero ask rows AND zero app-container pino WARN rows in the same ${WINDOW} window: the liveness check failed, so the channel is dark or the allowlist moved. An empty read here is not a quiet window."
    exit 3
  fi
  if (( LIVE_RECENT == 0 )); then
    echo "CANNOT ESTABLISH: zero ask rows and no app-container pino WARN row in the last ${LIVE_RECENT_HOURS} hours of the ${WINDOW} window: the channel may have gone dark. An empty read here is not a quiet window."
    exit 3
  fi
  if (( LIVE_DAYS < MIN_DAYS )); then
    echo "CANNOT ESTABLISH: zero ask rows and app-container pino WARN rows on only ${LIVE_DAYS} calendar day(s) of the ${WINDOW} window (need ${MIN_DAYS}): the channel was dark for part of it. An empty read here is not a quiet window."
    exit 3
  fi
  echo "hosted destroy-ask window ${WINDOW}: asks=0 outcomes=0 channel=live"
  if [[ "$WINDOW" == "7d" ]]; then
    echo "ACTION REQUIRED: the trailing 7d read shows 0 natural asks on a live channel; the soak did not exercise the lane. This trailing read is an alarm, not the measurement: confirm with an explicit [T0, T0+7d] read, then open the flip PR per ADR-284 'Flip checklist' (criterion 4, production arrival, needs the operator's decision). This n=0 statement is not a clean-lane claim; this probe does not close the tracker."
    exit 5
  fi
  echo "NOT YET: no 24h revert threshold tripped. 0 natural asks in the window (expected at low volume; the lane's liveness is the dev probe, CLO C9)."
  exit 2
fi

count() { printf '%s\n' "$ROWS" | awk -F'\t' -v d="$1" '$1 == d' | grep -c . || true; }
ASKS="$(count destroy-ask)"
APPROVED="$(count destroy-ask-approved)"
REJECTED="$(count destroy-ask-rejected)"
EXPIRED="$(count destroy-ask-expired)"
OUTCOMES=$(( APPROVED + REJECTED + EXPIRED ))
if (( ASKS == 0 && OUTCOMES > 0 )) || (( OUTCOMES > ASKS )); then
  echo "CANNOT ESTABLISH: ${OUTCOMES} outcome line(s) against ${ASKS} ask line(s): ask lines are missing from the stored telemetry, so every share below would be wrong."
  exit 3
fi
MEMBER_APPROVALS="$(printf '%s\n' "$ROWS" | awk -F'\t' '$1 == "destroy-ask-approved" && $4 == "member"' | grep -c . || true)"
rule_asks() { printf '%s\n' "$ROWS" | awk -F'\t' -v r="hosted-destroy-ask:$1" '$1 == "destroy-ask" && $2 == r' | grep -c . || true; }
CLASSIFIER_ERRORS="$(rule_asks classifier-error)"
UNKNOWN_DEFAULT="$(rule_asks git-push-unknown-default)"
IMPLICIT_FORCE="$(rule_asks git-force-implicit)"
KEYWORD_RAW=$(( $(rule_asks fail-closed-keyword) + $(rule_asks raw-scan) ))

# Per-repo storm proxy, over EVERY repo (not only the busiest): for each repo with at least MIN_REPO_ASKS asks, the
# largest single-rule share of its asks. TOP_* is the worst qualifying repo; zero when none qualifies.
TOP="$(printf '%s\n' "$ROWS" | awk -F'\t' -v min="$MIN_REPO_ASKS" '$1 == "destroy-ask" {n[$3]++; r[$3 SUBSEP $2]++}
  END {wn=0; ws=0
       for (j in r) {split(j, a, SUBSEP); if (n[a[1]] >= min) {sh=int(r[j] * 100 / n[a[1]]); if (sh > ws || (sh == ws && n[a[1]] > wn)) {ws=sh; wn=n[a[1]]}}}
       printf "%d\t%d\n", wn, ws}')"
TOP_REPO_ASKS="${TOP%%$'\t'*}"
TOP_SHARE="${TOP##*$'\t'}"

echo "hosted destroy-ask window ${WINDOW}: asks=${ASKS} approved=${APPROVED} rejected=${REJECTED} expired=${EXPIRED} classifier_errors=${CLASSIFIER_ERRORS} unknown_default=${UNKNOWN_DEFAULT} keyword_plus_raw=${KEYWORD_RAW} top_repo_asks=${TOP_REPO_ASKS} top_rule_share_pct=${TOP_SHARE} implicit_force=${IMPLICIT_FORCE} member_approvals=${MEMBER_APPROVALS}"

TRIPPED=""
if [[ "$WINDOW" == "24h" ]]; then
  (( CLASSIFIER_ERRORS == 0 )) || TRIPPED="$TRIPPED REVERT_OR_FIX:classifier_error(${CLASSIFIER_ERRORS})"
  if (( TOP_REPO_ASKS >= MIN_REPO_ASKS && TOP_SHARE > STORM_SHARE_PCT )); then
    TRIPPED="$TRIPPED REVERT_PROXY:one_rule_${TOP_SHARE}pct_of_one_repo_asks(${TOP_REPO_ASKS})"
  fi
else
  (( ASKS > 0 && UNKNOWN_DEFAULT * 100 > UNKNOWN_DEFAULT_PCT * ASKS )) && TRIPPED="$TRIPPED TUNE:unknown_default(${UNKNOWN_DEFAULT}/${ASKS})"
  (( ASKS > 0 && KEYWORD_RAW * 100 > KEYWORD_RAW_PCT * ASKS )) && TRIPPED="$TRIPPED TUNE:keyword_plus_raw(${KEYWORD_RAW}/${ASKS})"
fi

if [[ -n "$TRIPPED" ]]; then
  echo "TRIPPED:${TRIPPED}"
  echo "ACTION REQUIRED: a CPO4-R5 threshold tripped. This probe never closes the tracker; read ADR-284 (revert versus tune) and decide."
  exit 5
fi
if [[ "$WINDOW" == "7d" ]]; then
  echo "ACTION REQUIRED: the trailing 7d read is clean. Confirm with an explicit [T0, T0+7d] read, then record the numbers in the ADR-277 addendum per the ADR-284 'Flip checklist' (CPO3-R1 and #9603 wait on them); this probe does not close the tracker."
  exit 5
fi
echo "NOT YET: no 24h revert threshold tripped."
exit 2
