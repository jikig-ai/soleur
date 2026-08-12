#!/usr/bin/env bash
# Follow-through verification for #7490 (post-merge criteria of the delivery-canary PR).
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (the canary's most recent run was green with a non-zero comparison
#                   count, AND the upstream postings are recorded)
#   1 = FAIL       (the canary ran RED; the sweeper comments and files action-required)
#   * = TRANSIENT  (the run has not happened yet, or GitHub was unreachable; retry)
#
# WHY THIS EXISTS AT ALL. Both trackers close at merge, because `closes:` fires then.
# Two acceptance criteria are POST-merge — the canary's first real run, and the upstream
# postings — so without a carrier there is nothing left to notice a red first run. The
# alternative that was rejected is "remember to check": a criterion carried by memory is
# a criterion that is not carried.
#
# WHY IT DOES NOT SEND THE UPSTREAM POSTS. It observes state and has no send capability.
# Treating it as the carrier for sending would make canary-green-plus-postings-unsent
# evaluate to neither PASS nor FAIL — a permanent TRANSIENT that re-runs forever and
# alarms never. So the send stays operator-gated and this script only REPORTS which
# routes landed; the operator-visible artefact for an unsent route is the issue the
# sweeper files, not a retry loop.
#
# Required env: GH_TOKEN (or an authenticated `gh`).

set -uo pipefail

WORKFLOW="scheduled-marketplace-drift.yml"
REPO="${GH_REPO:-jikig-ai/soleur}"
REPORTS="knowledge-base/project/specs/feat-one-shot-7489-7490-marketplace-retire-delivery-followups/upstream-reports.md"

command -v gh >/dev/null 2>&1 || { echo "TRANSIENT: gh unavailable" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "TRANSIENT: jq unavailable" >&2; exit 2; }

# ---------------------------------------------------------------------------
# 1. The canary's most recent completed run.
# ---------------------------------------------------------------------------
# `--json` over `gh run list` rather than scraping: a formatting change upstream
# must not silently turn a red run into an unparsed one.
runs="$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --limit 10 \
        --json databaseId,conclusion,status,createdAt 2>/dev/null)"
list_rc=$?
if [[ "$list_rc" -ne 0 || -z "$runs" ]]; then
  echo "TRANSIENT: could not list runs of ${WORKFLOW} (gh exited ${list_rc})" >&2
  exit 2
fi

completed="$(jq -r '[.[] | select(.status == "completed")] | .[0] // empty' <<<"$runs")"
if [[ -z "$completed" ]]; then
  echo "TRANSIENT: ${WORKFLOW} has not completed a run yet" >&2
  exit 2
fi

run_id="$(jq -r '.databaseId' <<<"$completed")"
conclusion="$(jq -r '.conclusion' <<<"$completed")"

# ---------------------------------------------------------------------------
# 2. Did the CANARY JOB specifically run, and what did it conclude?
# ---------------------------------------------------------------------------
# The workflow-level conclusion is NOT sufficient. `drift-check` carries
# `if: !cancelled()` so it runs even when the canary fails, and a canary finding
# travels as DATA rather than as a failed step — so a run can conclude `success`
# while the canary reported a mismatch. Asking the job directly is the only read
# that answers the question this criterion actually poses.
jobs="$(gh api "repos/${REPO}/actions/runs/${run_id}/jobs" --jq '.jobs' 2>/dev/null)"
api_rc=$?
if [[ "$api_rc" -ne 0 || -z "$jobs" ]]; then
  echo "TRANSIENT: could not read jobs for run ${run_id} (gh exited ${api_rc})" >&2
  exit 2
fi

canary_conclusion="$(jq -r '[.[] | select(.name == "canary")] | .[0].conclusion // empty' <<<"$jobs")"
if [[ -z "$canary_conclusion" ]]; then
  # The job is absent entirely. That is not "not yet" and it is not a passing
  # canary -- it is the wiring being gone, which is precisely the mutation the
  # static assertion in the test suite exists to catch and which would otherwise
  # read here as a clean run.
  echo "FAIL: run ${run_id} contains no job named 'canary' -- the canary is not wired into ${WORKFLOW}" >&2
  exit 1
fi

if [[ "$canary_conclusion" != "success" ]]; then
  echo "FAIL: the canary job concluded '${canary_conclusion}' on run ${run_id} (workflow conclusion: ${conclusion})" >&2
  echo "  https://github.com/${REPO}/actions/runs/${run_id}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 3. A green canary that compared NOTHING is not a green canary.
# ---------------------------------------------------------------------------
# `compared=0` and "0 differences found" are the same bytes in a log and only one
# of them is a pass. The script and the job both fail closed on this; the check is
# repeated here because this is the one place that reads the run AFTER the fact,
# and a regression that made the count vacuous would otherwise land as PASS.
log="$(gh run view "$run_id" --repo "$REPO" --log --job \
       "$(jq -r '[.[] | select(.name == "canary")] | .[0].databaseId' <<<"$jobs")" 2>/dev/null || true)"
if [[ -n "$log" ]]; then
  counts_line="$(grep -oE 'compared=[0-9]+ expected=[0-9]+' <<<"$log" | tail -1 || true)"
  if [[ -n "$counts_line" ]]; then
    compared="${counts_line#compared=}"; compared="${compared%% *}"
    if [[ "${compared:-0}" -eq 0 ]]; then
      echo "FAIL: the canary job succeeded on run ${run_id} but reported ${counts_line} -- a zero comparison count is not a clean result" >&2
      exit 1
    fi
  fi
  # A log we could not read is NOT a failure: the run may have aged past log
  # retention. The job conclusion above already carries the verdict.
fi

# ---------------------------------------------------------------------------
# 4. Are the upstream postings recorded?
# ---------------------------------------------------------------------------
# Reported, never sent (see the header). An unsent route is surfaced to the
# operator as a FAIL the sweeper turns into an issue, rather than as a TRANSIENT
# that retries forever and never alarms.
if [[ ! -r "$REPORTS" ]]; then
  echo "FAIL: ${REPORTS} is missing -- the upstream evidence record is the durable artefact" >&2
  exit 1
fi

pending="$(grep -c '_pending_' "$REPORTS" || true)"
if [[ "${pending:-0}" -gt 0 ]]; then
  echo "FAIL: the canary is green on run ${run_id}, but ${pending} upstream posting slot(s) in ${REPORTS} are still marked pending." >&2
  echo "  Post the composed bodies, record each URL, and re-run the scrub against the body AS POSTED:" >&2
  echo "  bash scripts/upstream-report-scrub.sh -   # fed from: gh api <comment-url> --jq .body" >&2
  exit 1
fi

echo "PASS: canary green on run ${run_id} (compared>0), and every upstream posting slot is recorded."
exit 0
