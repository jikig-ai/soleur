#!/usr/bin/env bash
# vendor-pin-gate-verdict.sh — fail-closed verdict for the
# `vendor-pin-required` aggregator gate job (#8203).
#
# Usage: vendor-pin-gate-verdict.sh <detect_changes_result> <verify_upstream_blobs_result>
#   where each arg is a GitHub Actions `needs.<job>.result`
#   (success | failure | cancelled | skipped | "").
#
# Exit 0 (gate SUCCESS) iff BOTH:
#   - detect-changes succeeded (the path detection that decides whether to run
#     the upstream-blob verification actually ran), AND
#   - verify-upstream-blobs is `success` (vendored-tree PR, every NOTICE
#     upstream-blob-sha resolved) OR `skipped` (unrelated PR — detect-changes
#     emitted vendor=false, or a merge_group candidate whose authoritative
#     run already passed pre-queue).
# Exit 1 (gate FAILURE) for everything else. This is an ALLOW-LIST: any
# unenumerated state — detect-changes failure/cancelled/skipped/empty
# (the DROP-1 fail-open class), verify failure/cancelled/empty, or a future
# GitHub-added result string — fails closed.
#
# WHY AN ALLOW-LIST AND NOT `!= 'failure'`. A deny-list greens on `cancelled`
# and on the empty string. The empty string is what a `needs` job reports when
# it never ran because an EARLIER job in its chain failed — so a deny-list would
# hand a green to exactly the case where the gate learned nothing. This gate's
# entire purpose is to refuse a vendored-tree diff whose NOTICE pin was never
# verified against upstream; a gate that greens when it did not run is worse
# than no gate, because it launders "unknown" into "approved".
#
# Lives in a script (not inline in the workflow) so the verdict's branches are
# unit-tested by tests/scripts/test-vendor-pin-gate-verdict.sh. Mirrors
# scripts/tenant-integration-gate-verdict.sh (#5585) and
# scripts/sentry-destroy-gate-verdict.sh (#6589).
set -uo pipefail

detect="${1:-}"
verify="${2:-}"

if [[ "$detect" == "success" && ( "$verify" == "success" || "$verify" == "skipped" ) ]]; then
  echo "vendor-pin gate: PASS (detect-changes=$detect, verify-upstream-blobs=$verify)"
  # The two PASS arms are NOT the same evidence, and the check reports the same
  # green for both. On the `skipped` arm nothing was verified against this tree
  # — detect-changes emitted vendor=false, so the upstream-blob verification
  # never ran. Say so, in the annotation and in the job summary, rather than
  # letting a green check imply a verification that executed. (Widening the
  # detect anchors to everything is deliberately NOT the fix: a required check's
  # anchors must cover the verified surface, not the whole repo, or every PR
  # pays for an upstream-network verification it cannot fail.)
  if [[ "$verify" == "skipped" ]]; then
    skipped_msg="vendor-pin-required PASSED on the SKIPPED arm: the NOTICE upstream-blob verification did NOT execute against this tree (detect-changes emitted vendor=false — no vendored-surface path in the diff). The green asserts nothing about upstream blob SHAs on this PR."
    echo "::notice::$skipped_msg"
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
      printf '%s\n' "- :warning: $skipped_msg" >>"$GITHUB_STEP_SUMMARY"
    fi
  fi
  exit 0
fi

# Cancellation arm (#7055) -- DIAGNOSTIC ONLY, the verdict is unchanged. The
# `verify-upstream-blobs` job holds a PER-REF job-level
# `vendor-pin-verify-<ref>` concurrency group with cancel-in-progress: false.
# Per-ref means per-PR on pull_request (refs/pull/<n>/merge), and all of
# main's pushes sharing one entry on push (refs/heads/main).
#
# GitHub keeps at most ONE pending entry per concurrency group: a third
# arrival cancels the pending one, and `cancel-in-progress: false` does not
# prevent that. So `cancelled` here is most often an EVICTION, not a red
# verification. It still FAILS CLOSED, because detect-changes said this tree
# touches the vendored surface and the verification never executed against it
# -- greening that would be a fail-open on the #8181 path+commit+blob binding.
# What changes is the diagnosis: the author is told the run was displaced and
# that a re-run clears it, instead of hunting a verification failure that does
# not exist. A whole-run cancellation cannot reach this arm: it would cancel
# this aggregator job too, so this line would never execute.
if [[ "$detect" == "success" && "$verify" == "cancelled" ]]; then
  echo "::error::vendor-pin gate FAILED closed: the upstream-blob verification was CANCELLED before it could report (detect-changes=success, verify-upstream-blobs=cancelled). OBSERVED, not diagnosed -- this gate receives two job results and cannot tell WHY the verification was cancelled. One cause that produces exactly this state is concurrency EVICTION: the job holds a per-ref 'vendor-pin-verify-<ref>' group, GitHub keeps at most one PENDING job per group, and a third vendored-surface run on this ref displaces the one waiting. A manual cancel and a runner failure look identical here -- check the run timeline to tell them apart. Either way nothing was verified against this tree, so the gate cannot pass. 'Re-run failed jobs' clears the eviction case; if it recurs on every attempt, something other than eviction is cancelling the verification and the run timeline is where to look." >&2
  exit 1
fi

echo "::error::vendor-pin gate FAILED closed (detect-changes=${detect:-<empty>}, verify-upstream-blobs=${verify:-<empty>}). The required check passes only when detect-changes succeeds AND the upstream-blob verification is success or skipped." >&2
exit 1
