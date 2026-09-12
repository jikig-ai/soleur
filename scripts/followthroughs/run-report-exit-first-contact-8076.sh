#!/usr/bin/env bash
# Follow-through verification for #8076 (AC18 + AC19 of the plan
# 2026-09-11-feat-filing-gate-run-report-exit-plan.md).
#
# The run-report exit shipped with two post-merge claims that only the live
# crons can settle: (AC18) the first run-report crons to fire after merge —
# architecture-diagram-sync (Sun 02:00Z) and roadmap-review (Mon 09:00Z) — file
# their issue on the directive alone, i.e. with ONLY their own scheduled-* label
# and no `SOLEUR_CRON_FILING_DENY` marker for that run; (AC19) the sweeper's
# 12:00Z fires closed SUCCESS community digests attributed by its own marker
# comment, refused every FAILED-bodied one (36 of the 43 open digests on
# 2026-09-12 are FAILED self-reports — the plan's "43 drain" premise was an
# open-count, not a guard-derived count), and left the FAILED self-report #8027
# open.
#
# Every guard fails toward NOT passing: a cron that has not fired yet is
# NOT YET (2), a missing credential is CANNOT ESTABLISH (3), an unanswered or
# dark telemetry channel is FAIL (1), and a deny-row page that hit its LIMIT is
# NOT YET (the graded crons' rows may have been truncated off it).
#
# Row shape (measured 2026-09-12, 38/40 live rows): betterstack-query.sh emits
# one JSON object per line with a DOUBLE-ENCODED `raw`; the pino payload sits
# under `.message` of the decoded raw (`.message.component`,
# `.message.SOLEUR_CRON_FILING_DENY`), NOT at its top level. Decode in ONE
# `jq -R` pass so a non-JSON line (merged stderr, a mid-stream ClickHouse
# exception) is skipped rather than aborting jq into a silent "0 rows".
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS               (all assertions hold; sweeper closes #8076)
#   1 = FAIL               (a live cron was denied / relabelled, the sweeper
#                           misfired, or the telemetry channel is dark)
#   2 = NOT YET            (crons not fired yet, page truncated, API garbage)
#   3 = CANNOT ESTABLISH   (a required credential is not injected)
#
# Directive on #8076:
#   <!-- soleur:followthrough script=scripts/followthroughs/run-report-exit-first-contact-8076.sh earliest=2026-09-15T12:30:00Z secrets=GH_TOKEN,BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->
#
# Required env (ALL via the directive's secrets= clause — the sweeper runs this
# under `env -i` and forwards only declared names; GH_TOKEN is not a default):
# GH_TOKEN, BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD.
set -uo pipefail

# xtrace would print every expanded command — the Better Stack password and
# GH_TOKEN included — so refuse to trace while a live credential is set (#7797).
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO="${REPO:-jikig-ai/soleur}"
# Merge-time floor: issues created before this are pre-merge and not evidence.
MERGE_FLOOR="${FT8076_MERGE_FLOOR:-2026-09-12T20:00:00Z}"
QUERY="${FT8076_QUERY:-scripts/betterstack-query.sh}"
WINDOW="${FT8076_WINDOW:-4d}"
DENY_LIMIT="${FT8076_DENY_LIMIT:-200}"
FAILED_PREFIX="Automated FAILED self-report"

for v in GH_TOKEN BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  [[ -n "${!v:-}" ]] || { echo "CANNOT ESTABLISH: $v is not injected (declare it in the directive's secrets= clause)"; exit 3; }
done
[[ -f "$QUERY" ]] || { echo "NOT YET: $QUERY not found"; exit 2; }

fail=0
numeric() { [[ "$1" =~ ^[0-9]+$ ]]; }
numeric "$DENY_LIMIT" || { echo "CANNOT ESTABLISH: FT8076_DENY_LIMIT is not a number: '${DENY_LIMIT:0:40}'"; exit 3; }

# --- AC18a: the first post-merge run-reports carry ONLY their own label ----------
for label in scheduled-architecture-diagram-sync scheduled-roadmap-review; do
  rows="$(gh api "search/issues?q=repo:${REPO}+is:issue+label:${label}+created:>=${MERGE_FLOOR}&per_page=5" \
            --jq '[.items[] | {number, labels: [.labels[].name]}]' 2>&1)" || {
    echo "NOT YET: GitHub search failed for ${label}: ${rows:0:200}"; exit 2; }
  n="$(jq -r 'length' <<<"$rows" 2>/dev/null || true)"
  bad="$(jq -r '[.[] | select((.labels | index("meta/machinery")) != null)] | length' <<<"$rows" 2>/dev/null || true)"
  if ! numeric "$n" || ! numeric "$bad"; then
    echo "NOT YET: could not parse the ${label} search result (n='${n:0:40}', bad='${bad:0:40}')"; exit 2
  fi
  if [[ "$n" == "0" ]]; then
    echo "NOT YET: no ${label} issue created since ${MERGE_FLOOR} yet — the cron has not fired post-merge"
    exit 2
  fi
  if [[ "$bad" != "0" ]]; then
    echo "FAIL: ${bad} ${label} issue(s) filed since ${MERGE_FLOOR} carry meta/machinery — the cron relabelled instead of using the run-report exit"
    jq -c '.[]' <<<"$rows"; fail=1
  else
    echo "ok: ${n} ${label} issue(s) since ${MERGE_FLOOR}, none relabelled"
  fi
done

# --- AC18b: zero SOLEUR_CRON_FILING_DENY rows for those crons, with a control -----
# One decoder for both reads: `-R` + `fromjson?` at BOTH levels, structural
# field-isolation on `.message.component` (a webhook echo of an issue body
# quoting the marker name has no such field). `$1` = component, `$2` = jq
# expression evaluated on the decoded message, printed one per row.
decode_rows() {
  jq -R -r --arg component "$1" \
    'fromjson? | .raw? | fromjson? | .message? | select(type == "object" and .component == $component) | '"$2"
}
# Positive control on the FAR side of the same decoder: SOLEUR_CLAUDE_COST is
# emitted by the same finish() on the same WARN logger, so if it has no rows
# in the window the channel is dark and a zero below means nothing.
ctl="$(bash "$QUERY" --since "$WINDOW" --grep SOLEUR_CLAUDE_COST --limit 5 2>&1)" || {
  echo "FAIL: the Better Stack query did not answer (control): ${ctl:0:200}"; exit 1; }
ctl_n="$(printf '%s\n' "$ctl" | decode_rows claude-cost 'select(.SOLEUR_CLAUDE_COST == true) | "row"' | grep -c . || true)"
if ! numeric "$ctl_n" || [[ "$ctl_n" == "0" ]]; then
  echo "FAIL: the positive control (SOLEUR_CLAUDE_COST decoded under .message in $WINDOW) returned 0 rows — the telemetry channel is dark or its row shape changed; not grading an absence through it"
  exit 1
fi
deny="$(bash "$QUERY" --since "$WINDOW" --grep SOLEUR_CRON_FILING_DENY --limit "$DENY_LIMIT" 2>&1)" || {
  echo "FAIL: the Better Stack query did not answer (deny marker): ${deny:0:200}"; exit 1; }
deny_all="$(printf '%s\n' "$deny" | decode_rows cron-filing-deny 'select(.SOLEUR_CRON_FILING_DENY == true) | .fn' || true)"
deny_n="$(printf '%s\n' "$deny_all" | grep -c . || true)"
if [[ "$deny_n" -ge "$DENY_LIMIT" ]]; then
  echo "NOT YET: the deny-marker page hit its LIMIT (${deny_n} >= ${DENY_LIMIT}) — the first-contact crons' rows may be truncated; raise FT8076_DENY_LIMIT"
  exit 2
fi
hits="$(printf '%s\n' "$deny_all" | grep -cE '^cron-(architecture-diagram-sync|roadmap-review)$' || true)"
if [[ "$hits" != "0" ]]; then
  echo "FAIL: ${hits} SOLEUR_CRON_FILING_DENY row(s) for the first-contact crons in $WINDOW (control live: ${ctl_n} rows; deny rows total: ${deny_n})"
  fail=1
else
  echo "ok: 0 SOLEUR_CRON_FILING_DENY rows for the first-contact crons in $WINDOW (control live: ${ctl_n} rows; deny rows total: ${deny_n})"
fi

# --- AC19: the sweeper attributed by ITS marker, refused FAILED, left #8027 open --
# The property is the GUARD, not a count: every marker-closed digest is
# SUCCESS-bodied. (A ">= 25 closed" threshold was unreachable — 36 of the 43
# were FAILED-bodied and 3 more human-commented — and would have paged a
# false alarm on first fire.)
closed_rows="$(gh api "search/issues?q=repo:${REPO}+is:issue+is:closed+label:scheduled-community-monitor+%22soleur:auto-close-run-report%22+in:comments&per_page=100" \
            --jq '[.items[] | {number, failed: ((.body // "") | startswith("'"$FAILED_PREFIX"'"))}]' 2>&1)" || {
  echo "NOT YET: GitHub search failed (AC19): ${closed_rows:0:200}"; exit 2; }
closed="$(jq -r 'length' <<<"$closed_rows" 2>/dev/null || true)"
closed_failed="$(jq -r '[.[] | select(.failed)] | length' <<<"$closed_rows" 2>/dev/null || true)"
if ! numeric "$closed" || ! numeric "$closed_failed"; then
  echo "NOT YET: could not parse the AC19 search result (closed='${closed:0:40}')"; exit 2
fi
if [[ "$closed" == "0" ]]; then
  echo "FAIL: no community digest carries the run-report close marker — the sweeper arm never attributed a close"
  fail=1
elif [[ "$closed_failed" != "0" ]]; then
  echo "FAIL: ${closed_failed} of ${closed} marker-closed community digest(s) are FAILED-bodied — the FAILED guard did not hold"
  jq -c '.[] | select(.failed)' <<<"$closed_rows"; fail=1
else
  echo "ok: ${closed} community digest(s) closed by the run-report arm, none FAILED-bodied"
fi
state="$(gh issue view 8027 --repo "$REPO" --json state --jq .state 2>&1)" || { echo "NOT YET: could not read #8027: ${state:0:100}"; exit 2; }
if [[ "$state" != "OPEN" ]]; then
  echo "FAIL: #8027 (FAILED self-report) is ${state} — the FAILED guard did not hold"
  fail=1
else
  echo "ok: #8027 (FAILED self-report) still OPEN"
fi

if [[ "$fail" == "0" ]]; then
  echo "PASS: first live contact clean — directive honoured, no denials, sweeper attributed by marker and refused FAILED (AC18 + AC19)"
  exit 0
fi
exit 1
