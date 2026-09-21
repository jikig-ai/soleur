#!/usr/bin/env bash
# Print the commit whose Sentry state was last APPLIED to live Sentry: the head
# SHA of the newest apply-sentry-infra.yml run on `main` whose `apply` JOB
# concluded success (#8451 CTO ruling).
#
# WHY. The create gate matches every planned create against a resource block
# ADDED in a reviewed diff. Its diff used to be "this PR" (plan_pr) or
# "HEAD~1..HEAD" (apply). Both are correct only while every merge applies.
# Once the apply wedges (#8451: a persistent 410 from 2026-09-18), blocks merged
# in between are planned as creates by the NEXT plan and are in neither diff,
# so the gate refuses the one plan that could unwedge the root. The window the
# gate must cover is "since the last applied state", which is this SHA..HEAD.
#
# WHY THE JOB, NOT THE RUN. A run can conclude success with the apply job
# SKIPPED (the `[skip-sentry-apply]` kill switch). Its head SHA was never
# applied, and using it would shrink the window and refuse a legitimate create.
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

rc=0
runs=$(gh api "repos/${REPO}/actions/workflows/${WF}/runs?branch=main&status=success&per_page=50" \
  --jq '.workflow_runs[] | select(.event == "push" or .event == "workflow_dispatch") | "\(.id) \(.head_sha)"') || rc=$?
if [[ "$rc" -ne 0 ]]; then
  echo "::error::last-applied lookup: could not list ${WF} runs on main (gh exit ${rc}). The create gate cannot bound its window, so it refuses rather than guess." >&2
  exit 1
fi

while read -r id sha; do
  [[ -n "$id" ]] || continue
  concl=""
  rc=0
  concl=$(gh api "repos/${REPO}/actions/runs/${id}/jobs?per_page=100" \
    --jq '[.jobs[] | select(.name == "apply") | .conclusion] | first // ""') || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "::error::last-applied lookup: could not read the jobs of run ${id} (gh exit ${rc}); refusing to skip past it." >&2
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

echo "::error::last-applied lookup: none of the newest successful ${WF} runs on main has an apply job that concluded success. The create gate cannot bound its window, so it refuses rather than guess." >&2
exit 1
