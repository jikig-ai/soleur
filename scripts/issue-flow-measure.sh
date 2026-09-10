#!/usr/bin/env bash
# issue-flow-measure.sh — the weekly measurement that makes the success
# criterion checkable, and makes a silently-failing gate visible.
#
# Emits FIVE separately-counted lines. They are never folded into a single
# pass/fail: a gate that failed OPEN must not read identically to a gate that
# passed, and counts 3 and 4 carry different remedies, so they are never summed.
#
# THE HEADLINE METRIC IS A PURE FILING COUNT WITH NO CLOSE TERM.
# An earlier draft reported a "filing rate with expiry closes excluded", which is
# incoherent -- filings-per-week is filed/weeks and closes never enter it. The
# operator's requirement is that expiry closes must not be able to mask a flat or
# rising filing rate; measuring the filing count DIRECTLY satisfies that by
# construction rather than by subtraction. Expiry closes are still reported, but
# against the open TOTAL, which is where they legitimately belong.
set -euo pipefail

REPO="${REPO:-jikig-ai/soleur}"
WEEKS="${WEEKS:-4}"

# GH_TOKEN is declared EXPLICITLY and must survive any `env -i` allowlist.
# A script that authenticates locally via ~/.config/gh and silently never runs
# in the sandbox is a documented failure mode in this repo, not a hypothetical:
# see the 2026-06-02 followthrough-gh-probe learning. Fail loudly instead.
if [[ -z "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]] && ! gh auth status >/dev/null 2>&1; then
  echo "FATAL: no GH_TOKEN/GITHUB_TOKEN and gh is unauthenticated." >&2
  echo "Refusing to emit a measurement that would silently read as zeros." >&2
  exit 2
fi

SINCE="$(date -u -d "${WEEKS} weeks ago" +%Y-%m-%d)"

api_count() { # $1 = query suffix
  gh api "search/issues?q=repo:${REPO}+$1" --jq '.total_count'
}

FILED="$(api_count "is:issue+created:>=${SINCE}")"
OPEN_TOTAL="$(api_count "is:issue+is:open")"

# Expiry closes are attributable via the sweeper's own stable COMMENT_MARKER,
# NOT via stateReason. stateReason is CURRENT-STATE ONLY: reopening sets it to
# `reopened` and the prior `not_planned` is gone, so the reopen-count detection
# -- the only signal that the sweeper closed something legitimate -- would be
# unimplementable against it. It is not attributable either: a human closing a
# machinery issue wontfix produces the identical value.
EXPIRY_CLOSED="$(api_count "is:issue+is:closed+label:%22meta/machinery%22+closed:>=${SINCE}")"
# REOPENS, not "touched". The previous query counted every OPEN machinery issue
# updated in the window -- comments, label edits, the backfill itself -- so the
# one signal that the sweeper closed something legitimate read permanently at
# ceiling. The header above argues correctly that stateReason cannot detect a
# reopen and that COMMENT_MARKER is the attributable signal, then did not use it.
# An issue is a reopen iff it carries the sweeper's marker AND is open now.
SWEEP_MARKER="soleur:auto-close-stale-scope-out"
REOPENED="$(gh api "search/issues?q=repo:${REPO}+is:issue+is:open+label:%22meta/machinery%22+%22${SWEEP_MARKER}%22+in:comments" --jq '.total_count' 2>/dev/null || echo "unavailable")"

# net-issue-flow visibility. A gate that fails open, and a gate that was
# overridden, must each be distinguishable from a gate that passed.
OVERRIDES="$(gh api "search/issues?q=repo:${REPO}+is:pr+is:merged+merged:>=${SINCE}+%22gate-override:+net-issue-flow%22" --jq '.total_count' 2>/dev/null || echo "unavailable")"

FILED_PER_WEEK=$(( FILED / WEEKS ))

# BASELINES ARE WINDOW-MATCHED, and that is load-bearing.
#
# Measured pre-merge on 2026-09-10, the trailing rate is NOT flat across window
# lengths: 4 weeks gives 338/4 = 84 per week, 8 weeks gives 977/8 = 122. So
# comparing a 4-week post-merge figure against a baseline derived from 8 weeks
# would declare success at 84 -- exactly the rate the repo was ALREADY running
# before this change. That is the second time the same error appeared in this
# work: the first was the write-up's 142 vs the live 122, and it is recorded
# here because a criterion its own starting state already satisfies measures
# nothing at all.
#
# Refusing an unmatched window is deliberate. A default would be silently wrong.
case "$WEEKS" in
  4) BASELINE_FILED_PER_WEEK=84 ;;
  8) BASELINE_FILED_PER_WEEK=122 ;;
  *)
    echo "FATAL: no pre-merge baseline recorded for a ${WEEKS}-week window." >&2
    echo "Baselines are window-matched (4w=84/wk, 8w=122/wk measured 2026-09-10)." >&2
    echo "Comparing across window lengths silently declares success at an" >&2
    echo "unchanged rate. Re-derive the baseline for this window first." >&2
    exit 2
    ;;
esac
BASELINE_OPEN_TOTAL=1455

echo "SOLEUR_ISSUE_FLOW_MEASURE window_weeks=${WEEKS} since=${SINCE}"
echo "1. filed=${FILED} filed_per_week=${FILED_PER_WEEK} baseline_per_week=${BASELINE_FILED_PER_WEEK}"
echo "2. expiry_closes=${EXPIRY_CLOSED} reopened_after_expiry=${REOPENED}"
echo "3. net_issue_flow_overrides=${OVERRIDES}"
# The fail-open marker (`net-issue-flow fail-open:`) is emitted into the
# HOOK-LOCAL incidents log, which a scheduled runner cannot see. Reported as
# explicitly UNAVAILABLE rather than as 0: an empty telemetry query is not
# evidence of absence until the channel is known to be instrumented for this
# reader, and a silent zero here would read as "the gate never failed open".
FAIL_OPEN_LOG=".claude/.rule-incidents.jsonl"
if [[ -r "$FAIL_OPEN_LOG" ]]; then
  FAIL_OPEN="$(grep -cF 'net-issue-flow fail-open:' "$FAIL_OPEN_LOG" || true)"
  FAIL_OPEN_SRC="local-incidents-log"
else
  FAIL_OPEN="unavailable"
  FAIL_OPEN_SRC="hook-local-log-not-readable-from-this-runner"
fi
echo "4. net_issue_flow_fail_open=${FAIL_OPEN} source=${FAIL_OPEN_SRC}"
echo "5. open_total=${OPEN_TOTAL} baseline_open_total=${BASELINE_OPEN_TOTAL}"

# The verdict line is ADVISORY and is printed AFTER the five counts, never
# instead of them. A reader must be able to see the inputs that produced it.
if [[ "$FILED_PER_WEEK" -lt "$BASELINE_FILED_PER_WEEK" ]]; then
  echo "VERDICT: filing rate BELOW baseline (${FILED_PER_WEEK} < ${BASELINE_FILED_PER_WEEK})"
else
  echo "VERDICT: filing rate NOT below baseline (${FILED_PER_WEEK} >= ${BASELINE_FILED_PER_WEEK})"
fi
