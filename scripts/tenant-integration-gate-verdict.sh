#!/usr/bin/env bash
# tenant-integration-gate-verdict.sh — fail-closed verdict for the
# `tenant-integration-required` aggregator gate job (#5585).
#
# Usage: tenant-integration-gate-verdict.sh <detect_changes_result> <tenant_integration_result>
#   where each arg is a GitHub Actions `needs.<job>.result`
#   (success | failure | cancelled | skipped | "").
#
# Exit 0 (gate SUCCESS) iff BOTH:
#   - detect-changes succeeded (the path-detection that decides whether to
#     run the heavy suite actually ran), AND
#   - the heavy tenant-integration job is `success` (relevant PR, suite green)
#     OR `skipped` (unrelated PR — detect-changes emitted tenant=false).
# Exit 1 (gate FAILURE) for everything else. This is an ALLOW-LIST: any
# unenumerated state — detect-changes failure/cancelled/skipped/empty
# (the DROP-1 fail-open class), suite failure/cancelled/empty, or a future
# GitHub-added result string — fails closed.
#
# Lives in a script (not inline in the workflow) so the six-branch verdict
# is unit-tested by tests/scripts/test-tenant-integration-gate-verdict.sh.
set -uo pipefail

detect="${1:-}"
suite="${2:-}"

if [[ "$detect" == "success" && ( "$suite" == "success" || "$suite" == "skipped" ) ]]; then
  echo "tenant-integration gate: PASS (detect-changes=$detect, tenant-integration=$suite)"
  # The two PASS arms are NOT the same evidence, and the check reports the same
  # green for both. On the `skipped` arm nothing was verified against this tree
  # — detect-changes emitted tenant=false, so the heavy dev-Supabase suite never
  # ran and its first execution against these changes is the post-merge push to
  # `main`. Say so, in the annotation and in the job summary, rather than
  # letting a green check imply a suite that executed. (Widening the workflow's
  # path filter is deliberately NOT the fix: a required check's anchors must
  # cover the verified surface, not everything, or a heavy live-DB suite runs on
  # every PR.)
  if [[ "$suite" == "skipped" ]]; then
    skipped_msg="tenant-integration PASSED on the SKIPPED arm: the heavy dev-Supabase isolation suite did NOT execute against this tree (detect-changes emitted tenant=false). Its first execution against these changes will therefore be post-merge, on main."
    echo "::notice::$skipped_msg"
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
      printf '%s\n' "- :warning: $skipped_msg" >>"$GITHUB_STEP_SUMMARY"
    fi
  fi
  exit 0
fi

# Eviction arm (#7055) -- DIAGNOSTIC ONLY, the verdict is unchanged. The heavy
# `tenant-integration` job holds a PER-BRANCH job-level `dev-supabase-<ref>`
# mutex (repo-wide was tried in #7986 and reverted in #8028 -- it starved). GitHub keeps at most ONE pending entry per concurrency group: a third
# arrival cancels the pending one, and `cancel-in-progress: false` does not
# prevent that. So `cancelled` here is most often an EVICTION, not a red suite.
# It still FAILS CLOSED, because detect-changes said this tree touches the
# isolation surface and the suite never executed against it -- greening that would
# be a fail-open on a tenant-isolation gate. What changes is the diagnosis: the
# author is told the run was displaced and that a re-run clears it, instead of
# hunting a test failure that does not exist. A whole-run cancellation cannot
# reach this arm: it would cancel this aggregator job too, so this line would
# never execute.
if [[ "$detect" == "success" && "$suite" == "cancelled" ]]; then
  echo "::error::tenant-integration gate FAILED closed: the heavy dev-Supabase suite was CANCELLED before it could report (detect-changes=success, tenant-integration=cancelled). OBSERVED, not diagnosed -- this gate receives two job results and cannot tell WHY the suite was cancelled. One cause that produces exactly this state is concurrency EVICTION: the job holds a per-branch 'dev-supabase-<ref>' mutex, GitHub keeps at most one PENDING job per group, and a third isolation-surface run ON THIS BRANCH displaces the one waiting. A manual cancel and a runner failure look identical here -- check the run timeline to tell them apart. Either way nothing was verified against this tree, so the gate cannot pass. 'Re-run failed jobs' clears the eviction case; if it recurs on every attempt, something other than eviction is cancelling the suite and the run timeline is where to look." >&2
  exit 1
fi

echo "::error::tenant-integration gate FAILED closed (detect-changes=${detect:-<empty>}, tenant-integration=${suite:-<empty>}). The required check passes only when detect-changes succeeds AND the suite is success or skipped." >&2
exit 1
