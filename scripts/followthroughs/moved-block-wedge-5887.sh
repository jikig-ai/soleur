#!/usr/bin/env bash
# Follow-through verification for #5887 (the #5877 moved-block migration wedge).
#
# The four `moved {}` blocks #5877 added to placement-group.tf red-lined BOTH
# target-scoped apply pipelines (apply-web-platform-infra.yml + apply-deploy-
# pipeline-fix.yml). The wedge clears ONLY via the operator's ADR-068 Phase-3
# maintenance-window `terraform apply`, which consumes the pending moves; the
# workflow `.yml` is intentionally unchanged (adding hcloud_server.web to the
# per-PR -target set would reboot the running prod host — see #5887 / ADR-068
# §Amendment 2026-07-02). This probe closes #5887 once BOTH pipelines are green
# on main again (i.e. the cutover has landed and the plans self-healed).
#
# Stateless read of the two workflows' most-recent COMPLETED run on main via the
# GitHub Actions API — hr-no-dashboard-eyeball-pull-data-yourself compliant.
#
# Exit semantics (per scripts/sweep-followthroughs.sh contract):
#   0 = PASS       (both pipelines' latest completed main run == success — cutover
#                   landed; sweeper closes #5887)
#   1 = FAIL       (one/both still red — the operator cutover has not been applied;
#                   sweeper comments, leaves open)
#   * = TRANSIENT  (no completed run yet / API error; sweeper retries next sweep)
#
# Required env (declared in the #5887 followthrough directive; GH_TOKEN is already
# wired in scheduled-followthrough-sweeper.yml env:):
#   GH_TOKEN

set -uo pipefail

if [[ -z "${GH_TOKEN:-}" ]]; then echo "TRANSIENT: GH_TOKEN not set" >&2; exit 2; fi

latest_completed_conclusion() {
  # Most-recent COMPLETED run's conclusion for a workflow on main (empty if none
  # completed yet). Returns non-zero on API failure so the caller can TRANSIENT.
  gh run list --workflow "$1" --branch main --limit 5 \
    --json conclusion,status \
    --jq 'map(select(.status == "completed"))[0].conclusion // empty' 2>/dev/null
}

infra_concl=$(latest_completed_conclusion apply-web-platform-infra.yml) || {
  echo "TRANSIENT: gh API error reading apply-web-platform-infra.yml" >&2; exit 2; }
deploy_concl=$(latest_completed_conclusion apply-deploy-pipeline-fix.yml) || {
  echo "TRANSIENT: gh API error reading apply-deploy-pipeline-fix.yml" >&2; exit 2; }

if [[ -z "$infra_concl" || -z "$deploy_concl" ]]; then
  echo "TRANSIENT: no completed run yet (infra='${infra_concl:-none}', deploy='${deploy_concl:-none}')" >&2
  exit 2
fi

if [[ "$infra_concl" == "success" && "$deploy_concl" == "success" ]]; then
  echo "PASS: both apply pipelines green on main — #5877 moved-block wedge cleared (operator cutover landed)."
  exit 0
fi

echo "FAIL: apply-web-platform-infra=${infra_concl}, apply-deploy-pipeline-fix=${deploy_concl} — operator Phase-3 cutover not yet applied; both must be 'success'." >&2
exit 1
