#!/usr/bin/env bash
# Print the commit whose Sentry state was last APPLIED to live Sentry: the head
# SHA of the newest apply-sentry-infra.yml run on `main` whose `apply` job ran
# its `Terraform apply` STEP to success (#8451 CTO ruling + review).
#
# WHY. The create gate matches every planned create against a resource block
# ADDED in a reviewed diff. Its diff used to be "this PR" (plan_pr) or
# "HEAD~1..HEAD" (apply). Both are correct only while every merge applies.
# Once the apply wedges (#8451: a persistent 410 from 2026-09-18), blocks merged
# in between are planned as creates by the NEXT plan and are in neither diff,
# so the gate refuses the one plan that could unwedge the root. The window the
# gate must cover is "since the last applied state", which is this SHA..HEAD.
#
# WHY THE STEP, NOT THE JOB OR THE RUN. Both proxies are wrong, in opposite
# directions:
#   - A run (and its job) can conclude SUCCESS with the apply SKIPPED (the
#     `[skip-sentry-apply]` kill switch): that SHA was never applied.
#   - A job can conclude FAILURE after `terraform apply` succeeded, because
#     read-only checks run after it in the same job (BYOK liveness, AC17, the
#     live-fidelity probe). That SHA WAS applied. Keying on the job would stall
#     the window at an older commit and widen it with every merge — the create
#     gate would slowly admit creates "explained" by old diffs (measured on
#     main: runs 34532702665, 34491157462, 34149741385).
# The step conclusion answers the question actually asked.
#
# SCOPE. Only runs on `main` with event push or workflow_dispatch are read; the
# apply job itself refuses any other ref. A re-run of an OLDER run after a newer
# one applied leaves live state at the older SHA while this reports the newer
# one (the window is then narrower than truth, so the gate fails closed).
# Re-running a non-latest apply run is out of contract for that reason.
#
# Fail-closed: exit 1 with an ::error:: when nothing qualifying is found or the
# API cannot be read. The caller must also check the SHA is an ancestor of HEAD.
#
# Usage: sentry-last-applied-sha.sh          (needs GH_TOKEN with actions:read,
#                                             GITHUB_REPOSITORY=owner/repo)
set -uo pipefail
case "$-" in
  *x*) echo "REFUSING: shell xtrace is enabled; re-run without -x" >&2; exit 2 ;;
esac

REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set (owner/repo)}"
WF="apply-sentry-infra.yml"
APPLY_JOB="apply"
APPLY_STEP="Terraform apply (cron + uptime monitors)"
PAGE=50

rc=0
runs=$(gh api "repos/${REPO}/actions/workflows/${WF}/runs?branch=main&status=completed&per_page=${PAGE}" \
  --jq '.workflow_runs[] | select(.event == "push" or .event == "workflow_dispatch") | "\(.id) \(.head_sha)"' </dev/null) || rc=$?
if [[ "$rc" -ne 0 ]]; then
  echo "::error::last-applied lookup: could not list ${WF} runs on main (gh exit ${rc}). This is a transport/API failure: re-running the job may clear it. The create gate cannot bound its window, so it refuses rather than guess." >&2
  exit 1
fi

while read -r id sha; do
  [[ -n "$id" ]] || continue
  concl=""
  rc=0
  # filter=all: every ATTEMPT's jobs. The default (latest) hides an attempt that
  # applied when a later re-run attempt failed at the apply step, which would
  # push the window back to an older commit (permissive direction).
  concl=$(gh api "repos/${REPO}/actions/runs/${id}/jobs?filter=all&per_page=100" \
    --jq "[.jobs[] | select(.name == \"${APPLY_JOB}\") | .steps[]? | select(.name == \"${APPLY_STEP}\") | .conclusion] | if index(\"success\") != null then \"success\" else (first // \"\") end" </dev/null) || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "::error::last-applied lookup: could not read the jobs of run ${id} (gh exit ${rc}); refusing to skip past it. This is a transport/API failure: re-running the job may clear it." >&2
    exit 1
  fi
  if [[ "$concl" == "success" ]]; then
    if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
      echo "::error::last-applied lookup: run ${id} reported a head SHA that is not 40 hex characters; refusing." >&2
      exit 1
    fi
    printf '%s\n' "$sha"
    exit 0
  fi
done <<<"$runs"

echo "::error::last-applied lookup: none of the newest ${PAGE} completed push/dispatch ${WF} runs on main ran the '${APPLY_STEP}' step to success (a renamed step or job also produces this). The create gate cannot bound its window, so it refuses rather than guess." >&2
exit 1
