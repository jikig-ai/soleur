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
# Verdict command (run ≥24h after the vinngest deploy lands). The UNION is NOT optional and the
# earlier form here omitted it: `remote($BS_TABLE)` alone is ONLY the ~40-minute hot window, so
# a 3-day query silently returns one partial day. Measured 2026-08-11 — the hot-only form
# returned `{"day":"2026-08-11","c":546}` against a 25,000 threshold, reading as a comfortable
# pass, while the true figure was ~22,464/day. It undercounts ~40x, always in the PASS
# direction, which on an operator-confirmed probe means the human is handed a forged pass by
# their own instructions. betterstack-query.sh documents this in its header; its --since/--grep
# mode unions both tables for exactly this reason and only the raw-SQL path leaves it to you.
#   doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
#     "SELECT toDate(dt) AS day, count(*) AS c FROM ( \
#        SELECT dt FROM remote(\$BS_TABLE) \
#          WHERE dt >= now() - INTERVAL 3 DAY AND raw LIKE '%\"namespace\":\"host\"%' \
#        UNION ALL \
#        SELECT dt FROM s3Cluster(primary, \$BS_TABLE_S3) \
#          WHERE dt >= now() - INTERVAL 3 DAY AND raw LIKE '%\"namespace\":\"host\"%' \
#      ) GROUP BY day ORDER BY day FORMAT JSONEachRow"
#   PASS iff the first full post-deploy day shows c <= 25000 (baseline ~196k).
#
# Status 2026-08-11: re-measured at 22,464/day on 08-09 and 08-10 — the remediation works, and
# the 2026-06-10 RESULT line on #5110 is stale rather than wrong. #5110 stays CLOSED
# (NOT_PLANNED, which the sweeper's closed-set skips by design), so this probe is dormant.
#
# Exit semantics (scripts/sweep-followthroughs.sh):
#   0 = PASS (close), 1 = FAIL (comment + leave open), * = TRANSIENT (retry)

set -uo pipefail

# soleur:followthrough betterstack-quota-verdict-5105

# HARDCODED, not searched. `gh issue list --search "<filename>"` is hijackable: GitHub issue
# search matches COMMENT bodies as well as issue bodies, and `.[0]` is relevance-ordered — verified
# live, searching `infra-config-activation-7220.sh` returns #7297 FIRST, and #7297's body does not
# contain that string at all. So any user commenting this filename on another follow-through issue
# can steer the probe at a tracker that already carries a member-authored `RESULT: PASS`, while the
# sweeper still acts on THIS one. The `--state open` form also could not find #5110 (closed), so
# the search was already inert. See #7448.
ISSUE=5110
if [[ -z "$ISSUE" ]]; then
  echo "TRANSIENT: could not locate tracking issue for betterstack-quota-verdict-5105" >&2
  exit 2
fi

# AUTHOR FILTER — load-bearing, and NOT optional. `jikig-ai/soleur` is a PUBLIC repo with issues
# open to the world, and this probe's exit code makes the sweeper act on the tracker. An unfiltered
# `.comments[].body` therefore accepts a verdict from ANY authenticated GitHub user: one HTTP POST
# of `RESULT: PASS` was enough. See #7448.
COMMENTS=$(gh issue view "$ISSUE" --json comments --jq '.comments[] | select(.authorAssociation == "OWNER" or .authorAssociation == "MEMBER" or .authorAssociation == "COLLABORATOR") | .body' 2>/dev/null) || {
  echo "TRANSIENT: gh issue view failed for #$ISSUE" >&2
  exit 2
}

# LAST verdict wins. Two independent greps with PASS first let an early PASS outrank a later
# FAIL, so a regression recorded after a pass could never reopen the tracker. The `$` anchor is
# this probe's own stricter contract (a bare verdict, no trailing text) and is deliberately kept.
last="$(printf '%s\n' "$COMMENTS" | grep -E '^RESULT: (PASS|FAIL)$' | tail -1)"
if [[ "$last" == "RESULT: PASS" ]]; then
  exit 0
fi
if [[ "$last" == "RESULT: FAIL" ]]; then
  echo "FAIL: operator recorded RESULT: FAIL — quota remediation insufficient, re-open per AC12" >&2
  exit 1
fi
echo "FAIL: no RESULT verdict comment yet on #$ISSUE" >&2
exit 1
