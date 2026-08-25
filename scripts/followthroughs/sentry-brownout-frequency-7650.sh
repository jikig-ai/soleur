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
#   * = TRANSIENT  API unreachable / no runs in window — retry next sweep
#
# FAIL is deliberately NOT wired to "the rate went up". A rising rate is information the
# operator should see, not a page: the retry is still absorbing it, and a threshold
# picked without data would be a number invented to look rigorous.
#
# Required secrets: GH_TOKEN (declare in the directive's `secrets=` clause).
set -uo pipefail

WORKFLOW="apply-sentry-infra.yml"
WINDOW="${BROWNOUT_WINDOW_RUNS:-40}"

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "TRANSIENT: GH_TOKEN not set — the sweeper's env -i sandbox did not pass it through." >&2
  exit 3
fi

runs=$(gh run list --workflow "$WORKFLOW" --limit "$WINDOW" \
         --json databaseId,conclusion,createdAt 2>/dev/null) || {
  echo "TRANSIENT: could not list runs for $WORKFLOW." >&2; exit 3; }

total=$(jq -r 'length' <<<"$runs" 2>/dev/null || echo 0)
if [[ "${total:-0}" -eq 0 ]]; then
  echo "TRANSIENT: no $WORKFLOW runs in the last $WINDOW — nothing to measure yet." >&2
  exit 3
fi

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

echo "SOLEUR_SENTRY_BROWNOUT_METER window_runs=${scanned} retry_events=${retried} cleared=${cleared} exhausted=${exhausted} #7650"

if [[ "$exhausted" -gt 0 ]]; then
  cat >&2 <<MSG
FAIL: ${exhausted} run(s) in the last ${scanned} exhausted the brownout retry budget.

The retry is a mitigation with a stated shelf life and this is that shelf life
expiring. Either Sentry's brownout window is now wider than the budget, or the
alert-rule family is fully retired and every attempt now 410s.

Raising the attempt count is NOT the fix and will not work in the second case.
The fix is the sentry_alert migration — see the plan referenced from #7650. Note
the migration is 25 + 4: the four auth-* rules cannot be carried by Terraform
because configure-sentry-alerts.sh owns their definitions and its write shape
against workflows/ is blocked on #7634.
MSG
  exit 1
fi

if [[ "$retried" -eq 0 ]]; then
  echo "PASS: no brownout retries in the last ${scanned} runs — the deprecated family answered on first attempt every time."
else
  echo "PASS: ${retried} retry event(s) across ${scanned} runs, ${cleared} cleared within budget, 0 exhausted."
fi
exit 0
