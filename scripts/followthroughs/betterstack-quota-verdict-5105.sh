#!/usr/bin/env bash
# Follow-through verification: Better Stack quota verdict (AC12, PR #5105).
#
# Operator-confirmed pattern: the AC12 query needs prd Doppler creds the
# sweeper sandbox does not have, so the operator (or an interactive session)
# runs the verdict query and posts `RESULT: PASS` / `RESULT: FAIL` on the
# tracking issue. This script reads the human verdict — it does not eyeball
# a dashboard (hr-no-dashboard-eyeball-pull-data-yourself compliant: the
# verdict itself comes from scripts/betterstack-query.sh).
#
# Verdict command (run ≥24h after the vinngest deploy lands):
#   doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
#     "SELECT toDate(dt) AS day, count(*) AS c FROM remote(\$BS_TABLE) \
#      WHERE dt >= now() - INTERVAL 3 DAY AND raw LIKE '%\"namespace\":\"host\"%' \
#      GROUP BY day ORDER BY day FORMAT JSONEachRow"
#   PASS iff the first full post-deploy day shows c <= 25000 (baseline ~196k).
#
# Exit semantics (scripts/sweep-followthroughs.sh):
#   0 = PASS (close), 1 = FAIL (comment + leave open), * = TRANSIENT (retry)

set -uo pipefail

# soleur:followthrough betterstack-quota-verdict-5105

ISSUE=$(gh issue list --label follow-through --state open \
  --search "betterstack-quota-verdict-5105.sh" \
  --json number --jq '.[0].number // empty' 2>/dev/null)
if [[ -z "$ISSUE" ]]; then
  echo "TRANSIENT: could not locate tracking issue for betterstack-quota-verdict-5105" >&2
  exit 2
fi

COMMENTS=$(gh issue view "$ISSUE" --json comments --jq '.comments[].body' 2>/dev/null) || {
  echo "TRANSIENT: gh issue view failed for #$ISSUE" >&2
  exit 2
}

if printf '%s\n' "$COMMENTS" | grep -qE '^RESULT: PASS$'; then
  exit 0
fi
if printf '%s\n' "$COMMENTS" | grep -qE '^RESULT: FAIL$'; then
  echo "FAIL: operator recorded RESULT: FAIL — quota remediation insufficient, re-open per AC12" >&2
  exit 1
fi
echo "FAIL: no RESULT verdict comment yet on #$ISSUE" >&2
exit 1
