#!/usr/bin/env bash
# Follow-through verification for #7159 — the token-drift scan's coverage fan-out.
#
# WHAT THIS PROVES. #7159's Done-when is not "the code merged", it is a LIVE observation:
# a scheduled `scheduled-terraform-drift` run reports `coverage: at-floor`, and the
# `Close the coverage issue once the declared floor is met` step auto-closes the recurring
# `token-drift-coverage` issue with no operator step. Neither is true at merge — the
# `terraform apply` that mints DOPPLER_TOKEN_DRIFT sits behind the `web-platform-infra-apply`
# required-reviewer gate, so the credential does not exist until a human releases it.
#
# The PR therefore uses `Ref #7159`, not `Closes`. This script is what actually closes it:
# it re-checks the live world on the sweeper's cadence instead of resting on the author's
# memory, which is the failure this whole PR is about.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS       (a real run reported at-floor AND no coverage issue is open)
#   1 = FAIL       (a run reported degraded/unknown — the credential regressed or never landed)
#   * = TRANSIENT  (apply not released yet, API unreachable, unparseable — retry next sweep)
#
# TRANSIENT (not FAIL) is the correct verdict for "the apply has not run yet": the operator
# gate has no SLA, and a FAIL would comment on the issue every sweep for a state that is
# expected and blameless. Only a run that actually measured and came back short is a FAIL.
#
# Required secrets: GH_TOKEN (declared in the directive's `secrets=` clause; already present
# in .github/workflows/scheduled-followthrough-sweeper.yml).

set -uo pipefail

WORKFLOW="scheduled-terraform-drift.yml"
COVERAGE_LABEL="token-drift-coverage"

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "TRANSIENT: GH_TOKEN not set — the sweeper's env -i sandbox did not pass it through." >&2
  exit 2
fi

# 1. Newest run of the drift workflow. Deliberately NOT filtered by --status success:
#    that filter returns the last HEALTHY run and would report a green verdict while a
#    newer run is failing — a clean bill of health for a question never asked, which is
#    the exact defect #7159 exists to close.
RUN_ID=$(gh run list --workflow="$WORKFLOW" -L 1 --json databaseId --jq '.[0].databaseId // empty' 2>/dev/null)
if [[ -z "$RUN_ID" ]]; then
  echo "TRANSIENT: could not enumerate runs of ${WORKFLOW} (API error or no runs yet)." >&2
  exit 2
fi

LOG=$(gh run view "$RUN_ID" --log 2>/dev/null)
if [[ -z "$LOG" ]]; then
  echo "TRANSIENT: could not fetch the log for run ${RUN_ID}." >&2
  exit 2
fi

# 2. Anchor on the RESOLVED verdict line, never the bare prefix. Actions echoes the
#    `run:` script source into the log, and that source contains the literal
#    "token-drift verdict:" — so a prefix grep matches on a run that never printed a
#    verdict at all. The `[a-z]+ \(detector exit` tail is what only real output produces.
VERDICT_LINE=$(printf '%s' "$LOG" | grep -aoE 'token-drift verdict: [a-z]+ \(detector exit[^)]*\)' | tail -1)
if [[ -z "$VERDICT_LINE" ]]; then
  echo "TRANSIENT: run ${RUN_ID} printed no resolved verdict line (job may have aborted before the detector step)." >&2
  exit 2
fi

COVERAGE=$(printf '%s' "$VERDICT_LINE" | grep -oE 'coverage: [a-z-]+' | cut -d' ' -f2)
RATIO=$(printf '%s' "$VERDICT_LINE" | grep -oE 'ratio: [0-9]+/[0-9-]+' | cut -d' ' -f2)

case "$COVERAGE" in
  at-floor)
    # 3. The second half of the Done-when: the recurring issue must be auto-closed.
    #    `gh issue list` returning empty is only meaningful if the call SUCCEEDED —
    #    an API failure also prints nothing, and reading that as "closed" would be
    #    the same fail-open this PR removes from the detector.
    OPEN_JSON=$(gh issue list --label "$COVERAGE_LABEL" --state open -L 5 --json number 2>/dev/null)
    if [[ -z "$OPEN_JSON" ]]; then
      echo "TRANSIENT: could not query open ${COVERAGE_LABEL} issues; declining to read an API failure as 'closed'." >&2
      exit 2
    fi
    OPEN_COUNT=$(printf '%s' "$OPEN_JSON" | jq 'length' 2>/dev/null)
    if [[ ! "$OPEN_COUNT" =~ ^[0-9]+$ ]]; then
      echo "TRANSIENT: unparseable issue-list response." >&2
      exit 2
    fi
    if (( OPEN_COUNT == 0 )); then
      echo "PASS: run ${RUN_ID} reported coverage: at-floor at ${RATIO:-<no ratio>}, and no open ${COVERAGE_LABEL} issue remains. #7159's Done-when is met live."
      exit 0
    fi
    echo "TRANSIENT: coverage is at-floor at ${RATIO:-?} but ${OPEN_COUNT} ${COVERAGE_LABEL} issue(s) still open — the close arm may not have run yet on this run." >&2
    exit 2
    ;;
  degraded|unknown)
    # The credential either never landed (apply not released) or landed narrowed.
    # Distinguish: a 0/N ratio on a run this soon after merge is the un-applied case.
    if [[ "$RATIO" == 0/* ]]; then
      echo "TRANSIENT: coverage ${COVERAGE} at ${RATIO} — reads as the credential not yet minted (the terraform apply is behind the web-platform-infra-apply reviewer gate). Retrying next sweep." >&2
      exit 2
    fi
    # THE DOCUMENTED INTERIM STATE IS NOT A FAILURE. #7234: the project-scoped service
    # account was measured unable to enumerate or read, so the scan runs on the
    # config-scoped credential and reports 1/13 every run. Without this arm the FAIL
    # below fires on EVERY sweep, forever, reopening the issue and telling the operator
    # to "check the service-account membership role" -- which was measured correct. A
    # follow-through that comments a wrong remedy twice a day is the noise channel this
    # substrate exists to avoid.
    if [[ "$RATIO" == 1/* ]]; then
      echo "TRANSIENT: coverage ${COVERAGE} at ${RATIO} — the documented #7234 interim (scan on the config-scoped credential; the service account sees 0 configs by measurement). Not a regression; retrying next sweep until #7234 restores the fan-out." >&2
      exit 2
    fi
    echo "FAIL: run ${RUN_ID} reported coverage: ${COVERAGE} at ${RATIO:-?}. The credential landed but reaches fewer configs than the declared floor — check the service-account membership role and its environments scope." >&2
    exit 1
    ;;
  *)
    echo "TRANSIENT: unrecognized coverage value '${COVERAGE}' in: ${VERDICT_LINE}" >&2
    exit 2
    ;;
esac
