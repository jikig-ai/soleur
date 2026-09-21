#!/usr/bin/env bash
# actions-queue-tail-8450.sh — post-Team-upgrade soak probe for #8450.
#
# Measures the thing the issue actually reports: how long DEPLOY-ARM jobs wait
# for a hosted runner. Metric is per-JOB `started_at - created_at` on the
# `migrate`/`deploy` jobs of web-platform-release.yml runs whose event is
# `workflow_run` (every merge produces TWO runs — a `push`-arm run carrying
# only `release`, which would contaminate the sample). Run-level
# `created_at → run_started_at` is vacuous (equal on every sampled run) and
# `job.created_at` is stamped at job instantiation — post-`needs:` — so the
# delta is pure runner-acquisition wait. Pinned empirically in
# knowledge-base/project/specs/feat-8450-ci-concurrency/measurements.md.
#
# Exit semantics (sweep-followthroughs.sh contract):
#   0 = PASS       (plan==team AND >=5 in-window runs AND p95 wait < 15 min;
#                   sweeper closes #8450)
#   1 = FAIL       (p95 >= 15 min, or in-window samples exist but are
#                   unmeasurable; sweeper comments, leaves open)
#   2 = NOT YET    (plan.name != team — SKIP-DECLARED; clock unset/unparseable;
#                   or fewer than 5 usable in-window runs. NOT exit 0: the
#                   plan's original SKIP-DECLARED-exit-0 would auto-close
#                   #8450 on an unmet precondition — a false resolution)
#   * = TRANSIENT  (gh API failures; retry next sweep)
#
# Required env: GH_TOKEN (needs actions:read — the sweeper job gained that
# scope under #8450; an explicit permissions block defaults unlisted scopes
# to none). Clock: UPGRADE_NOT_BEFORE (ISO-8601) overrides the forwarded
# SOLEUR_FT_EARLIEST; one of them must be set — `plan.name` reports the
# CURRENT tier, not when it changed, so a pre-upgrade sample is stale data.
set -uo pipefail

REPO="jikig-ai/soleur"
WORKFLOW="web-platform-release.yml"
DEPLOY_ARM_JOBS="migrate deploy live-verify"
MIN_RUNS=5
P95_BUDGET_S=900

[ -n "${GH_TOKEN:-}" ] || { echo "TRANSIENT: GH_TOKEN not set (secrets= clause)" >&2; exit 2; }
command -v gh  >/dev/null || { echo "TRANSIENT: gh not on PATH" >&2; exit 2; }
command -v jq  >/dev/null || { echo "TRANSIENT: jq not on PATH" >&2; exit 2; }

CUTOFF="${UPGRADE_NOT_BEFORE:-${SOLEUR_FT_EARLIEST:-}}"
if [ -z "$CUTOFF" ]; then
  echo "NOT YET: no cutoff clock — UPGRADE_NOT_BEFORE/SOLEUR_FT_EARLIEST unset." >&2
  exit 2
fi
CUTOFF_EPOCH="$(date -u -d "$CUTOFF" +%s 2>/dev/null || true)"
if [ -z "${CUTOFF_EPOCH:-}" ]; then
  echo "NOT YET: cutoff '$CUTOFF' is not a parseable ISO timestamp." >&2
  exit 2
fi

# Precondition: the probe only means something on the 60-job pool. `plan.name`
# reads the CURRENT tier — the cutoff is what makes samples post-upgrade.
PLAN="$(gh api orgs/jikig-ai --jq '.plan.name' 2>/dev/null)" || {
  echo "TRANSIENT: gh api orgs/jikig-ai failed" >&2; exit 3; }
if [ "$PLAN" != "team" ]; then
  echo "SKIP-DECLARED: org plan is '$PLAN', not 'team' — AC-TEAM unmet; soaking is meaningless on the 20-job pool." >&2
  exit 2
fi

RUNS_JSON="$(gh api "repos/$REPO/actions/workflows/$WORKFLOW/runs?event=workflow_run&per_page=50" 2>/dev/null)" || {
  echo "TRANSIENT: gh api workflow runs failed" >&2; exit 3; }

# Usable in-window runs: event=workflow_run (already server-filtered, but the
# filter is re-asserted client-side so a fixture/stubbed page can't smuggle a
# push-arm row), created_at strictly after the cutoff, and finished or running
# (queued runs pre-populate started_at == created_at — unmeasurable).
IDS="$(printf '%s' "$RUNS_JSON" | jq -r --arg cut "$CUTOFF" '
  .workflow_runs // []
  | map(select(.event == "workflow_run"
        and .created_at > $cut
        and (.status == "completed" or .status == "in_progress")))
  | .[].id' 2>/dev/null)" || { echo "TRANSIENT: could not parse runs payload" >&2; exit 3; }

N_RUNS=0
WAITS=""
for id in $IDS; do
  JOBS="$(gh api "repos/$REPO/actions/runs/$id/jobs" 2>/dev/null)" || {
    echo "TRANSIENT: gh api jobs for run $id failed" >&2; exit 3; }
  W="$(printf '%s' "$JOBS" | jq -r '
    [.jobs[] | select(.name == "migrate" or .name == "deploy" or .name == "live-verify")
     | select(.status == "completed" or .status == "in_progress")
     | select(.started_at != null and .created_at != null)
     | ((.started_at | fromdateiso8601) - (.created_at | fromdateiso8601))] | .[]' 2>/dev/null)"
  [ -n "$W" ] && { WAITS="$WAITS$W"$'\n'; N_RUNS=$((N_RUNS + 1)); }
done

if [ "$N_RUNS" -lt "$MIN_RUNS" ]; then
  echo "INSUFFICIENT: $N_RUNS usable deploy-arm runs postdate $CUTOFF (need >=$MIN_RUNS). Soak continues next sweep." >&2
  exit 2
fi

P95="$(printf '%s' "$WAITS" | sort -n | awk -v p=0.95 '{a[NR]=$1} END {i=int((NR-1)*p)+1; print a[i]}')"
if [ -z "${P95:-}" ]; then
  echo "FAIL: $N_RUNS in-window runs but no measurable deploy-arm job waits." >&2
  exit 1
fi

if [ "$P95" -lt "$P95_BUDGET_S" ]; then
  echo "PASS: deploy-arm queue wait p95=${P95}s < ${P95_BUDGET_S}s across $N_RUNS post-upgrade workflow_run runs (cutoff $CUTOFF)."
  exit 0
fi
echo "FAIL: deploy-arm queue wait p95=${P95}s >= ${P95_BUDGET_S}s across $N_RUNS post-upgrade runs — the 60-job ceiling did not dissolve the tail." >&2
exit 1
