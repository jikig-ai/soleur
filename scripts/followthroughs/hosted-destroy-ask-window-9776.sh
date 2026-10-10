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
# the same reason. Near-miss events are Sentry-only and are not read here. LIVENESS is not checked either: a lane that
# stopped emitting reads as a quiet window (the dev probe, CLO C9, is the liveness check).
#
# NOTIFY-ONLY probe: nothing here exits 0 or 1 (the sweeper's TRANSIENT sub-vocabulary, followthrough-convention.md):
#   2 = NOT YET           no threshold tripped (or no ask rows: a quiet window is expected at low volume)
#   3 = CANNOT ESTABLISH  bad argument, missing credential, failed query, an unparseable or truncated result, outcome
#                         lines with no matching ask lines, or a stored-shape drift
#   5 = ACTION REQUIRED   a revert or tune threshold tripped, or the clean 7d measurement is ready to record
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
# RETIREMENT (delete together when #9776 closes): this file, its .test.sh, its run_suite row in scripts/test-all.sh,
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

# One jq pass: decode `raw`, require the pino object under `.message` with a `decision` that starts with the marker.
# Output: decision <TAB> ruleId <TAB> repo <TAB> approverRole (sentinels, never empty: tab is IFS whitespace).
ROWS="$(printf '%s\n' "$OUT" \
  | jq -R -r --arg m "$MARKER" '
      fromjson? | (.raw // empty | fromjson? | .message | select(type == "object")) as $p
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
MENTIONS="$(printf '%s\n' "$OUT" | grep -c "$MARKER" || true)"
if (( TOTAL == 0 && MENTIONS > 0 )); then
  echo "CANNOT ESTABLISH: SHAPE_DRIFT — ${MENTIONS} row(s) mention $MARKER but none decodes as a lane row; the stored shape may have changed (re-measure it against a live row)."
  exit 3
fi
if (( TOTAL == 0 )); then
  echo "hosted destroy-ask window ${WINDOW}: asks=0 outcomes=0"
  echo "NOT YET: no ask rows in the window (expected at low volume; the lane's liveness is the dev probe, CLO C9)."
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
  echo "ACTION REQUIRED: the 7d window is clean. Record these numbers in the ADR-277 addendum (CPO3-R1 and #9603 wait on them); this probe does not close the tracker."
  exit 5
fi
echo "NOT YET: no 24h revert threshold tripped."
exit 2
