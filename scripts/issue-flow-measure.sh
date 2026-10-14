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

# (#7797) Refuse to run under shell tracing while a live credential is set:
# `set -x` would trace GH_TOKEN into whatever collects this script's output, and
# this one runs inside a scheduled workflow whose logs are retained. The test is
# `case "$-" in *x*)` rather than an enumeration of the eight ways to enable
# tracing, two of which carry no `-x` token at all.
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}${GITHUB_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

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
# THE COVERED POPULATION. The filing gate is a PreToolUse hook plus the cron
# allowlist hook: it reaches agent-authored filings, not workflow-authored ones
# (`.github/workflows/*.yml` shelling `gh issue create` never traverses a hook).
# Counting all filings against the baseline hides an irreducible automation
# floor, so if the rate plateaus above it the backstop reads "the gate is being
# gamed" when the correct reading is "the gate never covered that traffic."
# Reported as its own line rather than subtracted, so the headline stays a pure
# count and the floor is visible instead of inferred.
FILED_AUTOMATION="$(api_count "is:issue+created:>=${SINCE}+author:app/github-actions")"
# THE SECOND FLOOR (ADR-216 addendum, "the run-report population"). Every cron whose
# run completion is verified by its own scheduled issue MUST file exactly one
# run-report per run; the gate reaches those filings (they traverse the cron
# allowlist hook) but cannot reduce them -- a run without its report is a
# heartbeat failure, not a saved filing. Counted by bot author + the OR-joined
# `scheduled-*` labels (comma-joined `label:` is OR, as in buildSearchQuery).
# Reported as its own line, never subtracted, for the same reason as 1b.
# Mirrors RUN_REPORT_CRONS in apps/web-platform/server/inngest/functions/_cron-run-reports.ts (parity: plugins/soleur/test/issue-flow-measure.test.sh)
RUN_REPORT_LABELS=(
  scheduled-architecture-diagram-sync
  scheduled-campaign-calendar
  scheduled-community-monitor
  scheduled-competitive-analysis
  scheduled-content-generator
  scheduled-growth-audit
  scheduled-growth-execution
  scheduled-legal-audit
  scheduled-roadmap-review
  scheduled-seo-aeo-audit
)
_rr_labels=""
for _l in "${RUN_REPORT_LABELS[@]}"; do _rr_labels+="${_rr_labels:+,}%22${_l}%22"; done
FILED_RUN_REPORTS="$(api_count "is:issue+created:>=${SINCE}+author:app/soleur-ai+label:${_rr_labels}")"
# EXIT 1 TAKERS. Filings that named the machinery ledger. `-label:keep-open`
# excludes the kill-switched standing measurement issue so the instrument never
# counts itself. No author filter: exit 1 is taken by interactive filers AND
# crons, and this line counts both.
FILED_MACHINERY="$(api_count "is:issue+created:>=${SINCE}+label:%22meta/machinery%22+-label:keep-open")"
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

# THE BASELINE IS DERIVED, WINDOW-MATCHED BY CONSTRUCTION.
#
# It used to be two hardcoded constants (4w=84, 8w=122) plus a refusal for any
# other window. The refusal was a correct guard on a hazard the constants
# themselves created: measured pre-merge the trailing rate is NOT flat across
# window lengths, so comparing a 4-week figure against an 8-week baseline would
# have declared success at 84 -- exactly the rate the repo was already running.
# Deriving it over the SAME window length, anchored to a fixed pre-merge date,
# removes the hazard class rather than guarding it: the window can never mismatch
# because both sides use $WEEKS, it works at any window, and it is deterministic
# because the anchor window is closed history.
BASELINE_ANCHOR="2026-09-10"
_bl_since="$(date -u -d "${BASELINE_ANCHOR} - ${WEEKS} weeks" +%Y-%m-%d)"
BASELINE_FILED="$(api_count "is:issue+created:${_bl_since}..${BASELINE_ANCHOR}")"
if [[ ! "$BASELINE_FILED" =~ ^[0-9]+$ ]]; then
  echo "FATAL: could not derive the pre-merge baseline for a ${WEEKS}-week window." >&2
  echo "Refusing to emit a verdict against a baseline that did not resolve -- an" >&2
  echo "empty baseline compares every rate favourably." >&2
  exit 2
fi
BASELINE_FILED_PER_WEEK=$(( BASELINE_FILED / WEEKS ))
BASELINE_OPEN_TOTAL=1455

echo "SOLEUR_ISSUE_FLOW_MEASURE window_weeks=${WEEKS} since=${SINCE}"
echo "1. filed=${FILED} filed_per_week=${FILED_PER_WEEK} baseline_per_week=${BASELINE_FILED_PER_WEEK} (baseline derived over the same ${WEEKS}w window ending ${BASELINE_ANCHOR})"
echo "1b. of which workflow-authored (OUTSIDE the gate's reach)=${FILED_AUTOMATION} — the irreducible floor under metric 1"
echo "1c. of which cron run-reports (RUN_REPORT_CRONS labels)=${FILED_RUN_REPORTS} — a second irreducible floor, INSIDE the gate's reach but not reducible by it"
echo "1d. of which took exit 1 (meta/machinery)=${FILED_MACHINERY}"
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
