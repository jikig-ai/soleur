#!/usr/bin/env bash
#
# Follow-through probe for #6969 — the web-2 rebirth dispatch.
#
# WHY THIS EXISTS. PR #6973 ships the MECHANISM (apply_target=web-host-replace) but not the
# rebirth itself: the dispatch is gated on the `web-platform-infra-apply` reviewer, so it
# cannot fire at merge. #6969 therefore stays open on an operator action that nothing
# re-checks — exactly the shape the sweeper exists to catch. Without this probe the issue
# sits open indefinitely while soleur-web-2 stays dark, which is the originating incident.
#
# NOT A SOAK. The ship-time gate matched the word "soak" inside the plan's own line
# "**Soak follow-through:** not engaged — no acceptance criterion is time-gated" — a
# negation. No criterion here is time-gated; this probe checks a DISCRETE event (did the
# dispatch run and succeed), not a window. Enrolled anyway because the rot risk is real.
#
# EXIT CONTRACT (sweep-followthroughs.sh):
#   0 = PASS      a web_host_replace job completed successfully -> safe to close #6969
#   1 = FAIL      a web_host_replace job ran and did NOT succeed -> needs attention
#   2 = TRANSIENT no such job yet, or the API could not be read -> try again later
#
# The TRANSIENT default is load-bearing: "the operator has not fired it yet" is the normal
# state for weeks, and must not read as failure. Only an OBSERVED unsuccessful run FAILs.
set -uo pipefail

WORKFLOW="apply-web-platform-infra.yml"
JOB_NAME="web_host_replace"

command -v gh >/dev/null 2>&1 || { echo "TRANSIENT: gh not on PATH"; exit 2; }

# Dispatch runs of this workflow, newest first. --json on `gh run list` needs no auth beyond
# GH_TOKEN, which the sweeper supplies via the directive's secrets= clause.
runs=$(gh run list --workflow "$WORKFLOW" --event workflow_dispatch \
         --limit 40 --json databaseId,conclusion,status,createdAt 2>/dev/null) || {
  echo "TRANSIENT: gh run list failed (API/auth)"; exit 2; }

[ -n "$runs" ] && [ "$runs" != "[]" ] || { echo "TRANSIENT: no workflow_dispatch runs yet"; exit 2; }

# Only COMPLETED runs carry a verdict. A queued/in-progress run is transient by definition.
ids=$(printf '%s' "$runs" | jq -r '.[] | select(.status == "completed") | .databaseId' 2>/dev/null)
[ -n "$ids" ] || { echo "TRANSIENT: no completed dispatch runs yet"; exit 2; }

saw_job=0
for id in $ids; do
  # A dispatch run's TARGET is not in its title, so identify by the JOB that actually ran —
  # every apply_target has a mutually-exclusive `if:`, so exactly one job body executes.
  concl=$(gh run view "$id" --json jobs \
            --jq '[.jobs[] | select(.name == "'"$JOB_NAME"'")] | .[0].conclusion // empty' 2>/dev/null) || continue
  [ -n "$concl" ] || continue          # this run was some other apply_target
  saw_job=1
  if [ "$concl" = "success" ]; then
    echo "PASS: ${JOB_NAME} succeeded in run ${id} — web-2 rebirth dispatch completed."
    echo "      Confirm the boot trail reached cloud_init_complete, update the post-mortem,"
    echo "      then close #6969 with the run URL as evidence."
    exit 0
  fi
done

if [ "$saw_job" -eq 1 ]; then
  echo "FAIL: ${JOB_NAME} has run but never concluded 'success'. Inspect:"
  echo "      gh run list --workflow ${WORKFLOW} --event workflow_dispatch"
  exit 1
fi

echo "TRANSIENT: no ${JOB_NAME} job in any completed dispatch run yet (not fired)."
exit 2
