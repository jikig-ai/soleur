#!/usr/bin/env bash
# Enumerates open remote GitHub PRs and classifies each into one of seven drain
# tiers (ready-green, ready-unarmed, needs-lockfile-fix, needs-conflict-resolution,
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
#   5. ready-unarmed              ready (non-draft) PR whose head verdict is no-run or
#                                 stalled and nothing else is failing: it was readied but
#                                 no full CI run exists (ADR-276 S3, #9728). Recovery:
#                                 `gh pr ready --undo <N>` then `gh pr ready <N>` (user token)
#   6. needs-review               has `bot-fix/review-required` label
#                                 OR reviewDecision == REVIEW_REQUIRED
#   7. ready-green                MERGEABLE AND 0 failing checks (not awaiting-approval)
#   8. needs-review               (fallback: UNKNOWN-mergeable / un-reviewed)
#
# Failing checks are counted from the NEWEST row per check name (a ready PR carries the
# draft run's rows AND the ready run's rows; counting both reads a decided PR as red). For a
# ready PR whose newest `test` row is red, plugins/soleur/scripts/ci-head-verdict.sh decides
# whether that row is the draft-era one: pending-full, no-run, stalled and awaiting-approval
# never count it failing; full-decided and n/a keep today's reading. A resolver that errors
# keeps today's reading too. Live mode calls the resolver for each non-draft PR with a failing
# `test` row; --fixture mode never does unless CI_HEAD_VERDICT_BIN is set (a test seam).

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

# --- Head verdicts (ADR-276 S3) ------------------------------------------------
# Candidates: non-draft PRs whose newest `test` row is failing. One resolver call each.
VERDICT_BIN="${CI_HEAD_VERDICT_BIN:-}"
if [[ -z "$VERDICT_BIN" && -z "$FIXTURE" ]]; then
  VERDICT_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" 2>/dev/null && pwd -P)/ci-head-verdict.sh"
fi
VERDICTS='{}'
if [[ -n "$VERDICT_BIN" && -r "$VERDICT_BIN" ]]; then
  CANDIDATES="$(jq -r '
    [ .[] | select(.isDraft != true) | . as $pr
      | ([ .statusCheckRollup[]? | select((.name // .context) == "test") ]
         | sort_by(.startedAt // "9999") | last // null) as $t
      | select($t != null and (($t.conclusion // $t.state) as $c
               | $c == "FAILURE" or $c == "ERROR" or $c == "CANCELLED" or $c == "TIMED_OUT"))
      | $pr.number ] | .[]' <<<"$PR_JSON")"
  for n in $CANDIDATES; do
    marker="$(bash "$VERDICT_BIN" verdict "$n" 2>/dev/null)" || true
    marker="$(grep -m1 '^SOLEUR_CI_HEAD_VERDICT ' <<<"$marker")" || continue
    st="${marker#*state=}"; st="${st%% *}"
    case "$st" in n/a|full-decided|pending-full|no-run|stalled|awaiting-approval) VERDICTS="$(jq -c --arg n "$n" --arg s "$st" '. + {($n): $s}' <<<"$VERDICTS")" ;; esac
  done
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
CLASSIFIED="$(jq --argjson verdicts "$VERDICTS" '
  # The NEWEST row per check name: a ready PR lists the draft run rows and the ready run rows.
  # A queued re-run has no startedAt yet, so a null sorts as the newest.
  def newest: [ .statusCheckRollup[]? ] | group_by(.name // .context // "") | map(sort_by(.startedAt // "9999") | last);
  # The draft-era `test` row is not a failure while the head verdict says a ready run is coming or missing.
  def softened($v): ($v == "pending-full" or $v == "no-run" or $v == "stalled" or $v == "awaiting-approval");
  def counted($v): [ newest[] | select(((.name // .context) == "test" and softened($v)) | not) ];
  def fails($v): [ counted($v)[] | (.conclusion // .state)
               | select(. == "FAILURE" or . == "ERROR" or . == "CANCELLED" or . == "TIMED_OUT") ] | length;
  def pending($v): [ counted($v)[] | (.status // .state)
               | select(. == "IN_PROGRESS" or . == "QUEUED" or . == "PENDING" or . == "WAITING") ] | length;
  def haslabel($n): any(.labels[]?; .name == $n);
  [ .[] | . as $pr | ($verdicts[(.number | tostring)] // "") as $v
    | ($pr | fails($v)) as $f | ($pr | pending($v)) as $p |
    {
      number: .number,
      title: .title,
      author: (.author.login // "unknown"),
      mergeable: (.mergeable // "UNKNOWN"),
      failing: $f,
      pending: $p,
      ci: $v,
      tier: (
        if .isDraft == true then "drafts"
        elif .mergeable == "CONFLICTING" and $f >= 3 then "broken"
        elif .mergeable == "CONFLICTING" then "needs-conflict-resolution"
        elif ($pr | haslabel("dependencies")) and $f > 0 then "needs-lockfile-fix"
        elif ($v == "no-run" or $v == "stalled") and $f == 0 then "ready-unarmed"
        elif ($pr | haslabel("bot-fix/review-required")) or .reviewDecision == "REVIEW_REQUIRED" then "needs-review"
        elif .mergeable == "MERGEABLE" and $f == 0 and $v != "awaiting-approval" then "ready-green"
        else "needs-review"
        end
      )
    }
    | if .tier == "ready-unarmed" then . + { recovery: "gh pr ready --undo \(.number) && gh pr ready \(.number)  (user token, never GITHUB_TOKEN)" } else . end
  ]' <<<"$PR_JSON")"

# --- Emit -------------------------------------------------------------------
# Stable tier order for the grouped output.
TIER_ORDER='["ready-green","ready-unarmed","needs-lockfile-fix","needs-conflict-resolution","needs-review","broken","drafts"]'

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
    ( $g[] | "  #\(.number)  \(.title)  [@\(.author), mergeable=\(.mergeable), fail=\(.failing), pending=\(.pending)\(if .ci != "" then ", ci=\(.ci)" else "" end)]",
             (if .recovery then "      recovery: \(.recovery)" else empty end) ),
    ""
' <<<"$CLASSIFIED"
