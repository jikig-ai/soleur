#!/usr/bin/env bash
# Follow-through verification for #8076 (AC18 + AC19 of the plan
# 2026-09-11-feat-filing-gate-run-report-exit-plan.md).
#
# The run-report exit shipped with two post-merge claims that only the live
# crons can settle: (AC18) the first run-report crons to fire after merge —
# architecture-diagram-sync (Sun 02:00Z) and roadmap-review (Mon 09:00Z) — file
# their issue on the directive alone, i.e. with ONLY their own scheduled-* label
# and no `SOLEUR_CRON_FILING_DENY` marker for that run; (AC19) the sweeper's
# first 12:00Z fire closed SUCCESS community digests (attributed by its own
# marker comment, never by an open-count a concurrent filing could move) and
# left the FAILED self-report #8027 open.
#
# Every guard fails toward NOT passing: a cron that has not fired yet is
# TRANSIENT, an unanswered telemetry query is FAIL (not a clean sweep), and the
# positive control sits on the far side of the --grep narrowing.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (all four assertions hold; sweeper closes #8076)
#   1 = FAIL       (a live cron was denied / relabelled, or the sweeper misfired)
#   * = TRANSIENT  (crons not fired yet, API unreachable; retry next sweep)
#
# Directive on #8076:
#   <!-- soleur:followthrough script=scripts/followthroughs/run-report-exit-first-contact-8076.sh earliest=2026-09-15T12:30:00Z secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->
#
# Required env: GH_TOKEN (sweeper default), BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD.
set -uo pipefail

REPO="${REPO:-jikig-ai/soleur}"
# Merge-time floor: issues created before this are pre-merge and not evidence.
MERGE_FLOOR="${FT8076_MERGE_FLOOR:-2026-09-12T20:00:00Z}"
QUERY="${FT8076_QUERY:-scripts/betterstack-query.sh}"
WINDOW="${FT8076_WINDOW:-4d}"

for v in GH_TOKEN BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  [[ -n "${!v:-}" ]] || { echo "TRANSIENT: $v is not injected (declare it in the directive's secrets= clause / sweeper env)"; exit 2; }
done
[[ -f "$QUERY" ]] || { echo "TRANSIENT: $QUERY not found"; exit 2; }

fail=0

# --- AC18a: the first post-merge run-reports carry ONLY their own label ----------
for label in scheduled-architecture-diagram-sync scheduled-roadmap-review; do
  rows="$(gh api "search/issues?q=repo:${REPO}+is:issue+label:${label}+created:>=${MERGE_FLOOR}&per_page=5" \
            --jq '[.items[] | {number, labels: [.labels[].name]}]' 2>&1)" || {
    echo "TRANSIENT: GitHub search failed for ${label}: ${rows:0:200}"; exit 2; }
  n="$(jq 'length' <<<"$rows")"
  if [[ "$n" == "0" ]]; then
    echo "TRANSIENT: no ${label} issue created since ${MERGE_FLOOR} yet — the cron has not fired post-merge"
    exit 2
  fi
  bad="$(jq -r '[.[] | select((.labels | index("meta/machinery")) != null)] | length' <<<"$rows")"
  if [[ "$bad" != "0" ]]; then
    echo "FAIL: ${bad} ${label} issue(s) filed since ${MERGE_FLOOR} carry meta/machinery — the cron relabelled instead of using the run-report exit"
    jq -c '.[]' <<<"$rows"; fail=1
  else
    echo "ok: ${n} ${label} issue(s) since ${MERGE_FLOOR}, none relabelled"
  fi
done

# --- AC18b: zero SOLEUR_CRON_FILING_DENY rows for those crons, with a control -----
# Positive control on the FAR side of the --grep narrowing: the same query with a
# marker that fires on every cron run (SOLEUR_CLAUDE_COST) must return rows, or
# the instrument is dark and a zero below means nothing.
ctl="$(bash "$QUERY" --since "$WINDOW" --grep SOLEUR_CLAUDE_COST --limit 5 2>&1)" || {
  echo "FAIL: the Better Stack query did not answer (control): ${ctl:0:200}"; exit 1; }
ctl_n="$(printf '%s\n' "$ctl" | grep -c '"raw"' || true)"
if [[ "$ctl_n" == "0" ]]; then
  echo "FAIL: the positive control (SOLEUR_CLAUDE_COST in $WINDOW) returned 0 rows — the telemetry channel is dark; not grading an absence through it"
  exit 1
fi
deny="$(bash "$QUERY" --since "$WINDOW" --grep SOLEUR_CRON_FILING_DENY --limit 50 2>&1)" || {
  echo "FAIL: the Better Stack query did not answer (deny marker): ${deny:0:200}"; exit 1; }
hits="$(printf '%s\n' "$deny" | jq -r '.raw | fromjson? | select(.SOLEUR_CRON_FILING_DENY == true) | .fn' 2>/dev/null \
          | grep -cE '^cron-(architecture-diagram-sync|roadmap-review)$' || true)"
if [[ "$hits" != "0" ]]; then
  echo "FAIL: ${hits} SOLEUR_CRON_FILING_DENY row(s) for the first-contact crons in $WINDOW (control live: ${ctl_n} rows)"
  fail=1
else
  echo "ok: 0 SOLEUR_CRON_FILING_DENY rows for the first-contact crons in $WINDOW (control live: ${ctl_n} rows)"
fi

# --- AC19: the sweeper closed digests by ITS marker, and left #8027 open ---------
closed="$(gh api "search/issues?q=repo:${REPO}+is:issue+is:closed+label:scheduled-community-monitor+%22soleur:auto-close-run-report%22+in:comments" \
            --jq '.total_count' 2>&1)" || { echo "TRANSIENT: GitHub search failed (AC19): ${closed:0:200}"; exit 2; }
if ! [[ "$closed" =~ ^[0-9]+$ ]]; then echo "TRANSIENT: non-numeric total_count for AC19: ${closed:0:100}"; exit 2; fi
if [[ "$closed" -lt 25 ]]; then
  echo "FAIL: only ${closed} community digest(s) closed with the run-report marker (expected >= 25 after the first 12:00Z fire; 43 were eligible)"
  fail=1
else
  echo "ok: ${closed} community digests closed by the run-report arm"
fi
state="$(gh issue view 8027 --repo "$REPO" --json state --jq .state 2>&1)" || { echo "TRANSIENT: could not read #8027: ${state:0:100}"; exit 2; }
if [[ "$state" != "OPEN" ]]; then
  echo "FAIL: #8027 (FAILED self-report) is ${state} — the FAILED guard did not hold"
  fail=1
else
  echo "ok: #8027 (FAILED self-report) still OPEN"
fi

if [[ "$fail" == "0" ]]; then
  echo "PASS: first live contact clean — directive honoured, no denials, sweeper attributed, FAILED report untouched (AC18 + AC19)"
  exit 0
fi
exit 1
