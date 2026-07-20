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
  #
  # `--limit 200` is a LOAD-BEARING BOUND (#6736), not just a paging preference. It is
  # the only cap on $PR_JSON, and $PR_JSON is by far the largest payload in this script:
  # `statusCheckRollup` alone carries one object per check run per PR. Measured on this
  # repo: 392,170 B at 20 open PRs, i.e. ~19.6 KB per PR.
  PR_JSON="$(gh pr list --state open --limit 200 \
    --json number,title,headRefName,isDraft,mergeable,reviewDecision,labels,author,createdAt,statusCheckRollup)"
fi

# --- Classify ---------------------------------------------------------------
# Emits a flat array of {number,title,author,mergeable,tier}. Failing/pending
# check counts are derived from statusCheckRollup (conclusion for check-runs,
# state for legacy statuses).
#
# ══ THE `<<<"$PR_JSON"` HERESTRING IS A LOAD-BEARING INVARIANT (#6736) ══
#
# $PR_JSON MUST reach jq via this herestring (or a pipe / file), and MUST NEVER be
# bound as `--argjson pr_json "$PR_JSON"`. A herestring is delivered on jq's STDIN
# through a pipe/tempfile and has no size limit; an --argjson binding makes it ONE argv
# argument, and the kernel caps a SINGLE argv argument at MAX_ARG_STRLEN = 131,072 B —
# verified by bisect on this host: 131,071 B passes, 131,072 B fails E2BIG. That is NOT
# `getconf ARG_MAX` (2,097,152 B here); a payload at 6% of ARG_MAX still dies.
#
# This is NOT a bound that is eroding toward a future failure — it is ALREADY 3× over.
# Measured on this repo: $PR_JSON is 392,170 B at 20 open PRs, 2.99 × MAX_ARG_STRLEN.
# Converting this herestring to --argjson does not degrade drain-prs at some later PR
# count; it breaks it on the next run, today, with `Argument list too long`. Even a
# single mid-size PR would exceed the ceiling on its own at ~19.6 KB/PR by PR #7.
#
# The `--argjson prs "$CLASSIFIED"` binding further down is SAFE and deliberately left
# alone: the projection above discards statusCheckRollup and keeps ~174 B/PR, measured
# 3,484 B at 20 PRs (2.7% of the ceiling). $CLASSIFIED is the collapse; $PR_JSON is the
# raw fan-out. Do not generalize from one to the other.
#
# Guarded by the argv-ceiling regression test in ../test/ — it drives this script with a
# synthesized >MAX_ARG_STRLEN fixture and asserts the fixture really exceeds the ceiling,
# so the test cannot silently degrade to vacuous.
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
