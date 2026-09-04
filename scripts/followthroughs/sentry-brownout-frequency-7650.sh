#!/usr/bin/env bash
# Follow-through meter for #7650 — how often Sentry's deprecated alert-rule API
# brownouts, and whether it has stopped being a brownout and become a retirement.
#
# WHY THIS EXISTS. Before the retry, every brownout produced a red required check, so
# `gh run list --json conclusion` WAS the frequency meter: 89 success / 3 failure / 8
# cancelled over the last 100 runs. The retry greens the runs that clear on attempt 2
# or 3, which decays that counter toward zero and leaves the residual failures meaning
# something narrower ("wider than the retry budget") than they used to.
#
# That trade is only acceptable if the count moves somewhere. It cannot move to the
# markers alone: SOLEUR_* is a host-journald convention — every source in
# apps/web-platform/infra/vector.toml is scoped to the Hetzner host's SYSLOG_IDENTIFIER
# — and these run on a GitHub-hosted runner whose stdout no Vector source ships. A
# marker in an Actions log is a detail line inside a signal, not a signal. That exact
# correction was already made on this same workflow (see the 2026-07-17 sentry-iac
# delete-path plan), and the retry would have reintroduced it.
#
# So the meter lives HERE, outside the workflow it observes, on the sweeper's cadence.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS       brownouts observed at or below the retry budget, or none at all
#   1 = FAIL       an `outcome=exhausted` was observed — the window now exceeds the
#                  budget, or the family is fully retired. Either way the retry has
#                  reached its shelf life and the sentry_alert migration is the fix.
#   * = TRANSIENT  API unreachable / no runs in window, or the window contains failed
#                  runs this meter cannot explain — retry next sweep
#
# TWO FIELDS WERE FETCHED AND NEVER READ (#7650 Phase 2). `conclusion` and
# `createdAt` were both in the `--json` list and neither was consumed:
#
#   * `conclusion`. A FAILED apply that carries no `exhausted` marker scored
#     `exhausted=0` and exited 0, so this meter posted PASS — "the deprecated
#     family answered on first attempt every time" — over a window in which the
#     workflow was failing. Whatever the cause, that is not a sentence this
#     script was in a position to write. Failures it cannot explain now yield
#     TRANSIENT, which is the honest verdict: the meter did not measure a clean
#     window, it measured a window it does not understand.
#
#   * `createdAt`. The window was "the last N runs" with no time bound, so on a
#     workflow that fires rarely those N runs can span a year and the meter
#     reports a brownout rate from a period the vendor's deprecation schedule has
#     moved on from. The window is now bounded in DAYS as well, and the observed
#     span is printed so a reader can see what the number describes.
#
# FAIL is deliberately NOT wired to "the rate went up". A rising rate is information the
# operator should see, not a page: the retry is still absorbing it, and a threshold
# picked without data would be a number invented to look rigorous.
#
# Required secrets: GH_TOKEN (declare in the directive's `secrets=` clause).
set -uo pipefail

WORKFLOW="apply-sentry-infra.yml"
WINDOW="${BROWNOUT_WINDOW_RUNS:-40}"
# Days, not just runs. Both bounds apply; whichever is tighter wins.
WINDOW_DAYS="${BROWNOUT_WINDOW_DAYS:-30}"

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "TRANSIENT: GH_TOKEN not set — the sweeper's env -i sandbox did not pass it through." >&2
  exit 3
fi

all_runs=$(gh run list --workflow "$WORKFLOW" --limit "$WINDOW" \
         --json databaseId,conclusion,createdAt 2>/dev/null) || {
  echo "TRANSIENT: could not list runs for $WORKFLOW." >&2; exit 3; }

# Bound on `createdAt` as well as on count. `date -d` is GNU-only, which is what
# the sweeper runs on; a portability fallback that silently skipped the bound
# would reinstate the unbounded window it exists to remove.
cutoff=$(date -u -d "${WINDOW_DAYS} days ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || {
  echo "TRANSIENT: could not compute a ${WINDOW_DAYS}-day cutoff (no GNU date -d)." >&2; exit 3; }
runs=$(jq -c --arg c "$cutoff" '[ .[] | select(.createdAt >= $c) ]' <<<"$all_runs" 2>/dev/null) || {
  echo "TRANSIENT: could not apply the ${WINDOW_DAYS}-day window." >&2; exit 3; }

total=$(jq -r 'length' <<<"$runs" 2>/dev/null || echo 0)
if [[ "${total:-0}" -eq 0 ]]; then
  echo "TRANSIENT: no $WORKFLOW runs in the last $WINDOW runs / $WINDOW_DAYS days — nothing to measure yet." >&2
  exit 3
fi

# The observed span, so the reported rate is legible as "over what".
span_from=$(jq -r 'map(.createdAt) | min' <<<"$runs")
span_to=$(jq -r 'map(.createdAt) | max' <<<"$runs")

# `conclusion` is now READ. A failed run in the window that carries no
# `exhausted` marker is something this meter cannot account for, and reporting
# PASS over it is the defect being fixed.
failed=$(jq -r '[ .[] | select(.conclusion == "failure") ] | length' <<<"$runs")

retried=0; cleared=0; exhausted=0; scanned=0
# Only non-success runs can carry an `exhausted`, but a CLEARED brownout lives inside a
# SUCCESSFUL run — which is the whole point of the meter — so every run must be read.
while read -r id; do
  [[ -n "$id" ]] || continue
  log=$(gh run view "$id" --log 2>/dev/null) || continue
  scanned=$((scanned+1))
  r=$(grep -c 'SOLEUR_SENTRY_BROWNOUT outcome=retry'     <<<"$log")
  c=$(grep -c 'SOLEUR_SENTRY_BROWNOUT outcome=cleared'   <<<"$log")
  e=$(grep -c 'SOLEUR_SENTRY_BROWNOUT outcome=exhausted' <<<"$log")
  retried=$((retried+r)); cleared=$((cleared+c)); exhausted=$((exhausted+e))
done < <(jq -r '.[].databaseId' <<<"$runs")

if [[ "$scanned" -eq 0 ]]; then
  echo "TRANSIENT: listed $total runs but could not read any logs (retention or permissions)." >&2
  exit 3
fi

echo "SOLEUR_SENTRY_BROWNOUT_METER window_runs=${scanned} window_days=${WINDOW_DAYS} span=${span_from}..${span_to} failed_runs=${failed} retry_events=${retried} cleared=${cleared} exhausted=${exhausted} #7650"

if [[ "$exhausted" -gt 0 ]]; then
  cat >&2 <<MSG
FAIL: ${exhausted} run(s) in the last ${scanned} exhausted the brownout retry budget.

The retry is a mitigation with a stated shelf life and this is that shelf life
expiring. Either Sentry's brownout window is now wider than the budget, or the
alert-rule family is fully retired and every attempt now 410s.

Raising the attempt count is NOT the fix and will not work in the second case.
The fix is the sentry_alert migration — see the plan referenced from #7650.
Since Phase 2 (2026-09-04) the split is 27 + 2, not 25 + 4: 27 rules are managed
as sentry_alert and are unaffected by this family's retirement. Exactly TWO
remain on the deprecated path — auth-per-user-loop and sandbox-startup-failure —
because the pinned provider cannot express event_unique_user_frequency_count as
a trigger (upstream jianyuan/terraform-provider-sentry issue 950, tracked here by
#7634). Only auth-per-user-loop still has configure-sentry-alerts.sh as its
writer; the other three auth-* rules are Terraform-owned and reconcile via
terraform apply. If this family is fully retired, ONE rule is stranded without a
writer, not four.
MSG
  exit 1
fi

# Ordered AFTER the exhausted check on purpose: an `exhausted` marker is a
# specific, actionable verdict, and demoting it to "I cannot explain these
# failures" because the same window also holds an unrelated red would lose the
# louder finding to the quieter one.
if [[ "$failed" -gt 0 ]]; then
  cat >&2 <<MSG
TRANSIENT: ${failed} of the ${scanned} runs in this window FAILED, and none of them
carries an \`outcome=exhausted\` marker.

This meter measures brownout frequency. It cannot explain a failure that is not a
brownout, and it must not report PASS over one: before #7650 Phase 2 it did
exactly that — \`exhausted=0\` was read as "the deprecated family answered on first
attempt every time", over a window in which the workflow was failing for some
other reason entirely.

Read the failed runs directly:
  gh run list --workflow ${WORKFLOW} --limit ${WINDOW} --json databaseId,conclusion,createdAt \\
    | jq -r '.[] | select(.conclusion == "failure") | .databaseId'
MSG
  exit 3
fi

if [[ "$retried" -eq 0 ]]; then
  echo "PASS: no brownout retries across the ${scanned} runs in the last ${WINDOW_DAYS} days (${span_from}..${span_to}), and no failed runs — the deprecated family answered on first attempt every time."
else
  echo "PASS: ${retried} retry event(s) across ${scanned} runs in the last ${WINDOW_DAYS} days (${span_from}..${span_to}), ${cleared} cleared within budget, 0 exhausted, 0 failed."
fi
exit 0
