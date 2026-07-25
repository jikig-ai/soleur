#!/usr/bin/env bash
# Follow-through verification for #6769 (post-merge soak of PR #6785).
#
# PR #6785 made the net-issue-flow gate BLOCKING at NET > 0 and raised the
# cost-of-filing auto-flip to <=100 lines / <=4 files. Both act on the RATE at
# which PRs file issues. Neither can be verified at merge time: the gate governs
# future PRs and cannot move a trailing window. This probe is the verification.
#
# Measured at merge (2026-07-20), 7d window:
#   269 issues created / 132 merged PRs = 2.04 filed per PR
#   125 closed / 132 = 0.95 closed per PR
#   queue growth +144/week, 1,042 open at enrollment
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (both criteria hold; sweeper closes #6769)
#   1 = FAIL       (a criterion is violated; sweeper comments, leaves open)
#   * = TRANSIENT  (GitHub API unreachable / malformed response; retry next sweep)
#
# Required env: GH_TOKEN (already wired at scheduled-followthrough-sweeper.yml)
#
# TWO criteria, deliberately. Criterion (a) alone is gameable: filed-per-PR
# improves when PR count rises with no change in filing behavior (a plan-review
# dissent raised exactly this). Criterion (b) is a raw count and is not gameable
# by splitting PRs. Resolved by ADDITION rather than substitution, so a real
# improvement must show up in both.
#
#   (a) filed-per-PR <= 0.95 over the trailing 7d
#       0.95 is not arbitrary: it is the measured closed-per-PR rate. Filing at
#       or below the rate you close at is exactly a flat queue. The originally
#       proposed target of 3.5 was already satisfied at 2.04 -- and at 1.22
#       throughout the period the queue grew to 1,024 -- so it could never have
#       detected this problem.
#
#   (b) total open issue count <= OPEN_AT_MERGE
#       GitHub cannot reconstruct a historical open-count, so the baseline MUST
#       be committed here at ship time or (b) is unverifiable forever.

set -uo pipefail
export LC_ALL=C

# Committed baseline -- captured at enrollment, 2026-07-20. Do not "refresh"
# this: a moving baseline makes the criterion self-satisfying.
OPEN_AT_MERGE=1042

TARGET_FILED_PER_PR="0.95"
SINCE="$(date -u -d '7 days ago' +%Y-%m-%d 2>/dev/null)" || exit 3
[[ -n "$SINCE" ]] || exit 3

q() { gh api -X GET search/issues -f q="$1" -f per_page=1 --jq '.total_count' 2>/dev/null; }

CREATED="$(q "repo:jikig-ai/soleur is:issue created:>=${SINCE}")"
CLOSED="$(q "repo:jikig-ai/soleur is:issue closed:>=${SINCE}")"
PRS="$(q "repo:jikig-ai/soleur is:pr is:merged merged:>=${SINCE}")"
OPEN_NOW="$(q "repo:jikig-ai/soleur is:issue is:open")"

for v in "$CREATED" "$CLOSED" "$PRS" "$OPEN_NOW"; do
  [[ "$v" =~ ^[0-9]+$ ]] || { echo "TRANSIENT: non-numeric count from search API"; exit 3; }
done

# A zero denominator is not a pass -- it means no PRs merged in the window,
# so the ratio is undefined and the soak has no signal yet.
if [[ "$PRS" -eq 0 ]]; then
  echo "TRANSIENT: 0 merged PRs in the 7d window; filed-per-PR undefined"
  exit 3
fi

RATIO="$(awk -v c="$CREATED" -v p="$PRS" 'BEGIN{printf "%.3f", c/p}')"
A_OK="$(awk -v r="$RATIO" -v t="$TARGET_FILED_PER_PR" 'BEGIN{print (r<=t)?1:0}')"
B_OK=0; [[ "$OPEN_NOW" -le "$OPEN_AT_MERGE" ]] && B_OK=1

echo "net-issue-flow soak (#6769), 7d window from ${SINCE}:"
echo "  created=${CREATED} closed=${CLOSED} mergedPRs=${PRS}"
echo "  (a) filed-per-PR = ${RATIO}  target <= ${TARGET_FILED_PER_PR}  -> $([[ "$A_OK" -eq 1 ]] && echo PASS || echo FAIL)"
echo "  (b) open = ${OPEN_NOW}  baseline at merge = ${OPEN_AT_MERGE}  -> $([[ "$B_OK" -eq 1 ]] && echo PASS || echo FAIL)"

if [[ "$A_OK" -eq 1 && "$B_OK" -eq 1 ]]; then
  echo "PASS: both criteria hold; the gate is measurably flattening the queue."
  exit 0
fi

echo "FAIL: the blocking gate has not flattened the queue on the measured window."
echo "  Do NOT close #6769 on this result. Either the gate is being overridden"
echo "  routinely (check bypass counts via scripts/rule-metrics-aggregate.sh for"
echo "  rule_id net-issue-flow), or filings are arriving through a merge surface"
echo "  the PreToolUse hook does not cover (web UI, native auto-merge, CI merges"
echo "  -- enumerated in ship/SKILL.md 'Reachability')."
exit 1
