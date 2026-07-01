#!/usr/bin/env bash
# Enumerates open remote GitHub PRs and classifies each into one of six drain
# tiers (ready-green, needs-lockfile-fix, needs-conflict-resolution,
# needs-review, drafts, broken), emitting a tier-grouped report.
#
# Usage:
#   triage-prs.sh [--format text|json] [--fixture <path>]
#
# --fixture is test-only: reads the PR-list JSON from a file instead of `gh`.
#   The fixture must be the exact shape of
#   `gh pr list --state open --json number,title,headRefName,isDraft,mergeable,reviewDecision,labels,author,createdAt,statusCheckRollup`.
#
# Classification is first-match-wins in this priority order:
#   1. drafts                     isDraft == true            (author-owned WIP)
#   2. broken                     CONFLICTING AND >=3 failing checks
#   3. needs-conflict-resolution  CONFLICTING
#   4. needs-lockfile-fix         has `dependencies` label AND >0 failing checks
#   5. needs-review               has `bot-fix/review-required` label
#                                 OR reviewDecision == REVIEW_REQUIRED
#   6. ready-green                MERGEABLE AND 0 failing checks
#   7. needs-review               (fallback: UNKNOWN-mergeable / un-reviewed)

set -euo pipefail

FORMAT="text"
FIXTURE=""

usage() {
  cat <<'EOF'
Usage: triage-prs.sh [--format text|json] [--fixture <path>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)   FORMAT="$2";  shift 2 ;;
    --fixture)  FIXTURE="$2"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not found on PATH." >&2; exit 1; }

# --- Acquire the PR-list JSON ------------------------------------------------
if [[ -n "$FIXTURE" ]]; then
  [[ -f "$FIXTURE" ]] || { echo "ERROR: fixture not found: $FIXTURE" >&2; exit 1; }
  PR_JSON="$(cat "$FIXTURE")"
else
  command -v gh >/dev/null 2>&1 || { echo "ERROR: gh not found on PATH." >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "ERROR: gh is not authenticated (run 'gh auth login')." >&2; exit 1; }
  # Two-stage gh --json | jq (never `gh --jq` with --arg — learning
  # 2026-04-15-gh-jq-does-not-forward-arg-to-jq).
  PR_JSON="$(gh pr list --state open --limit 200 \
    --json number,title,headRefName,isDraft,mergeable,reviewDecision,labels,author,createdAt,statusCheckRollup)"
fi

# --- Classify ---------------------------------------------------------------
# Emits a flat array of {number,title,author,mergeable,tier}. Failing/pending
# check counts are derived from statusCheckRollup (conclusion for check-runs,
# state for legacy statuses).
CLASSIFIED="$(jq '
  def fails: [ .statusCheckRollup[]? | (.conclusion // .state)
               | select(. == "FAILURE" or . == "ERROR" or . == "CANCELLED" or . == "TIMED_OUT") ] | length;
  def pending: [ .statusCheckRollup[]? | (.status // .state)
               | select(. == "IN_PROGRESS" or . == "QUEUED" or . == "PENDING" or . == "WAITING") ] | length;
  def haslabel($n): any(.labels[]?; .name == $n);
  [ .[] | . as $pr | ($pr | fails) as $f | ($pr | pending) as $p |
    {
      number: .number,
      title: .title,
      author: (.author.login // "unknown"),
      mergeable: (.mergeable // "UNKNOWN"),
      failing: $f,
      pending: $p,
      tier: (
        if .isDraft == true then "drafts"
        elif .mergeable == "CONFLICTING" and $f >= 3 then "broken"
        elif .mergeable == "CONFLICTING" then "needs-conflict-resolution"
        elif ($pr | haslabel("dependencies")) and $f > 0 then "needs-lockfile-fix"
        elif ($pr | haslabel("bot-fix/review-required")) or .reviewDecision == "REVIEW_REQUIRED" then "needs-review"
        elif .mergeable == "MERGEABLE" and $f == 0 then "ready-green"
        else "needs-review"
        end
      )
    }
  ]' <<<"$PR_JSON")"

# --- Emit -------------------------------------------------------------------
# Stable tier order for the grouped output.
TIER_ORDER='["ready-green","needs-lockfile-fix","needs-conflict-resolution","needs-review","broken","drafts"]'

if [[ "$FORMAT" == "json" ]]; then
  jq -n --argjson prs "$CLASSIFIED" --argjson order "$TIER_ORDER" '
    reduce $order[] as $t ({}; . + { ($t): [ $prs[] | select(.tier == $t) ] })
  '
  exit 0
fi

# text format
echo "=== Open PR triage ==="
total="$(jq 'length' <<<"$CLASSIFIED")"
echo "Open PRs: $total"
echo ""
jq -r --argjson order "$TIER_ORDER" '
  . as $prs
  | $order[] as $t
  | ([ $prs[] | select(.tier == $t) ]) as $g
  | "## \($t) (\($g | length))",
    ( $g[] | "  #\(.number)  \(.title)  [@\(.author), mergeable=\(.mergeable), fail=\(.failing), pending=\(.pending)]" ),
    ""
' <<<"$CLASSIFIED"
