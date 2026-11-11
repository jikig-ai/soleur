#!/usr/bin/env bash
# Follow-through verification for #12514 (PR 12553): the claude-code 2.1.321 / claude-agent-sdk 0.3.321 bump.
#
# Two pieces of evidence exist only after the merge, so the PR could not carry them:
#   (i)  the first scheduled-marketplace-drift.yml run on main after the merge, which is the first run that installs
#        CLI 2.1.321 (CLI_VERSION in that workflow, read at the run's head commit), is green, with the canary job's
#        "Install the pinned Claude Code CLI" and "Assert the published channel delivers this repo's plugin" steps
#        both `success` (ADR-182 2026-11-10 addendum);
#   (ii) the first scheduled-real-sdk-ask-probe.yml run on main after the merge that actually measured is green: its
#        "Run the real-SDK ask probe" step concluded `success` (ADR-284 2026-11-10 addendum). A run whose probe step
#        was skipped (billing preflight, or a package-only push the workflow declines) or that was cancelled did not
#        measure, so the next run is read instead.
# "Ran" is proven from `gh run view --json jobs` step conclusions, never from the run conclusion alone (a run can
# conclude `success` with the measuring step skipped; followthrough-convention.md).
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       both first runs exist and are green (sweeper closes)
#   1 = FAIL       a first measuring run is red: read plan 4.4 (rollback triggers) for #12514
#   2 = NOT YET    PR 12553 is not merged yet, or either first run does not exist / has not completed
#   3 = CANNOT ESTABLISH  gh unreachable, no token, an unreadable response, or the window holds too many runs
#   5 = ACTION REQUIRED   PR 12553 was closed without merging: nothing to verify, close this tracker by hand
#  78 = REFUSED    running under `set -x` with a live GH_TOKEN (#7797)
#
# CREDENTIAL POSTURE: GH_TOKEN with actions:read, pull-requests:read and contents:read (declared via the directive's
# secrets= clause). No other credential; the probe reads GitHub only.
# RETIREMENT: delete this file when its tracker closes, and re-census `git grep claude-cli-fable-bump` (seeded by the
# ADR-182 and ADR-284 2026-11-10 addenda, which name this probe).
set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO="jikig-ai/soleur"
PR=12553
CLI_FLOOR="2.1.321"
DRIFT_WF="scheduled-marketplace-drift.yml"
ASK_WF="scheduled-real-sdk-ask-probe.yml"
RUN_LIMIT=100
MAX_JOB_READS=10

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "CANNOT ESTABLISH: GH_TOKEN not set" >&2
  exit 3
fi

pr_rc=0
pr_line=$(gh pr view "$PR" --repo "$REPO" --json state,mergedAt --jq '[.state, (.mergedAt // "")] | @tsv' 2>/dev/null) || pr_rc=$?
if [[ "$pr_rc" -ne 0 || -z "$pr_line" ]]; then
  echo "CANNOT ESTABLISH: reading PR ${PR} failed (rc ${pr_rc})" >&2
  exit 3
fi
pr_state=${pr_line%%$'\t'*}
merged_at=${pr_line#*$'\t'}
case "$pr_state" in
  OPEN)
    echo "NOT YET: PR ${PR} is still open; the post-merge runs do not exist yet"
    exit 2
    ;;
  CLOSED)
    echo "ACTION REQUIRED: PR ${PR} was closed without merging; there is no bump to verify. Close this tracker by hand." >&2
    exit 5
    ;;
  MERGED) ;;
  *)
    echo "CANNOT ESTABLISH: PR ${PR} state '${pr_state}' is not OPEN, CLOSED or MERGED" >&2
    exit 3
    ;;
esac
if [[ ! "$merged_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  echo "CANNOT ESTABLISH: PR ${PR} is MERGED but mergedAt '${merged_at}' is not an ISO-8601 UTC timestamp" >&2
  exit 3
fi

# CLI_VERSION in scheduled-marketplace-drift.yml at a commit; prints x.y.z or nothing.
cli_version_at() {
  local sha="$1" raw body rc=0
  raw=$(gh api "repos/${REPO}/contents/.github/workflows/${DRIFT_WF}?ref=${sha}" --jq '.content' 2>/dev/null) || rc=$?
  [[ "$rc" -eq 0 && -n "$raw" ]] || return 1
  body=$(printf '%s' "$raw" | base64 -d 2>/dev/null) || return 1
  mapfile -t versions < <(printf '%s\n' "$body" | sed -n 's/^[[:space:]]*CLI_VERSION:[[:space:]]*"\([0-9][0-9.]*\)".*$/\1/p')
  [[ "${#versions[@]}" -eq 1 && "${versions[0]}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  printf '%s\n' "${versions[0]}"
}

# leg_verdict <label> <workflow> <events-json-array> <job> <step>...
# Sets LEG_RC (0 pass, 1 fail, 2 not yet, 3 cannot establish) and prints one line.
leg_verdict() {
  local label="$1" wf="$2" events="$3" job="$4"
  shift 4
  local steps_json
  steps_json=$(printf '%s\n' "$@" | jq -R . | jq -s -c .)
  local list_rc=0 runs
  runs=$(gh run list --repo "$REPO" --workflow "$wf" --branch main --created ">=${merged_at%%T*}" \
    --limit "$RUN_LIMIT" --json databaseId,event,status,conclusion,createdAt,headSha 2>/dev/null) || list_rc=$?
  if [[ "$list_rc" -ne 0 ]] || ! printf '%s' "$runs" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "CANNOT ESTABLISH: ${label}: gh run list for ${wf} failed (rc ${list_rc})"
    LEG_RC=3
    return
  fi
  if [[ "$(printf '%s' "$runs" | jq 'length')" -ge "$RUN_LIMIT" ]]; then
    echo "CANNOT ESTABLISH: ${label}: ${RUN_LIMIT}+ runs of ${wf} since ${merged_at}; the first one is outside the read"
    LEG_RC=3
    return
  fi
  local ordered
  ordered=$(printf '%s' "$runs" | jq -c --arg m "$merged_at" --argjson ev "$events" \
    '[.[] | select(.createdAt >= $m and (.event as $e | $ev | index($e) != null))] | sort_by(.createdAt) | .[]')
  if [[ -z "$ordered" ]]; then
    echo "NOT YET: ${label}: no ${wf} run on main since the merge (${merged_at})"
    LEG_RC=2
    return
  fi
  local reads=0 line id status concl sha
  while IFS= read -r line; do
    # One jq call per run; `|` never occurs in an id, status, conclusion or sha (empty fields survive: `|` is not IFS
    # whitespace, so `1|in_progress||abc` keeps its empty conclusion).
    IFS='|' read -r id status concl sha < <(printf '%s' "$line" |
      jq -r '[(.databaseId | tostring), .status, (.conclusion // ""), (.headSha // "")] | join("|")')
    if [[ "$status" != "completed" ]]; then
      echo "NOT YET: ${label}: run ${id} of ${wf} is ${status}"
      LEG_RC=2
      return
    fi
    if [[ "$concl" == "cancelled" || "$concl" == "skipped" ]]; then
      continue
    fi
    reads=$((reads + 1))
    if [[ "$reads" -gt "$MAX_JOB_READS" ]]; then
      echo "CANNOT ESTABLISH: ${label}: ${MAX_JOB_READS} completed ${wf} runs since the merge and none measured"
      LEG_RC=3
      return
    fi
    # Two captures, each with its own rc: a piped `gh | jq` reports jq's rc, so a failed read would parse as "no
    # steps" and be skipped as "did not measure" instead of reported.
    local jobs_rc=0 jobs_json step_concls
    jobs_json=$(gh run view "$id" --repo "$REPO" --json jobs 2>/dev/null) || jobs_rc=$?
    if [[ "$jobs_rc" -ne 0 ]] || ! printf '%s' "$jobs_json" | jq -e '.jobs | type == "array"' >/dev/null 2>&1; then
      echo "CANNOT ESTABLISH: ${label}: reading the jobs of run ${id} failed (rc ${jobs_rc})"
      LEG_RC=3
      return
    fi
    # A step with no conclusion yet is dropped (`// empty`), so it counts as not measured, never as a match.
    local want_n=$# got_n
    IFS='|' read -r got_n step_concls < <(printf '%s' "$jobs_json" | jq -r --arg j "$job" --argjson want "$steps_json" \
      '[.jobs[] | select(.name == $j) | .steps[] | select(.name as $n | $want | index($n) != null) | .conclusion // empty]
       | "\(length)|\(join(","))"')
    if [[ ",${step_concls}," == *",failure,"* ]]; then
      echo "FAIL: ${label}: run ${id} of ${wf} (${concl}): a measuring step failed (${step_concls})"
      LEG_RC=1
      return
    fi
    if [[ "$got_n" -ne "$want_n" || ",${step_concls}," == *",skipped,"* || ",${step_concls}," == *",cancelled,"* ]]; then
      # Did not measure (step absent or skipped): the next run is the first one that counts.
      continue
    fi
    if [[ "$concl" != "success" ]]; then
      echo "FAIL: ${label}: run ${id} of ${wf} measured but concluded ${concl}"
      LEG_RC=1
      return
    fi
    if [[ "$wf" == "$DRIFT_WF" ]]; then
      local v lowest
      if ! v=$(cli_version_at "$sha"); then
        echo "CANNOT ESTABLISH: ${label}: could not read CLI_VERSION from ${DRIFT_WF} at ${sha:0:12}"
        LEG_RC=3
        return
      fi
      lowest=$(printf '%s\n%s\n' "$v" "$CLI_FLOOR" | sort -V | head -1)
      if [[ "$lowest" != "$CLI_FLOOR" ]]; then
        echo "CANNOT ESTABLISH: ${label}: run ${id} installed CLI ${v} (< ${CLI_FLOOR}); the bump looks reverted on main"
        LEG_RC=3
        return
      fi
      echo "PASS: ${label}: run ${id} (${status}/${concl}) installed CLI ${v}; canary steps ${step_concls}"
    else
      echo "PASS: ${label}: run ${id} (${status}/${concl}); probe step ${step_concls}"
    fi
    LEG_RC=0
    return
  done <<<"$ordered"
  echo "NOT YET: ${label}: no ${wf} run since the merge has measured yet (all skipped or cancelled)"
  LEG_RC=2
}

LEG_RC=3
leg_verdict "(i) marketplace-drift canary on CLI ${CLI_FLOOR}" "$DRIFT_WF" '["schedule","workflow_dispatch"]' canary \
  "Install the pinned Claude Code CLI" "Assert the published channel delivers this repo's plugin"
rc_i=$LEG_RC
LEG_RC=3
leg_verdict "(ii) real-SDK ask probe" "$ASK_WF" '["push","schedule","workflow_dispatch"]' probe \
  "Run the real-SDK ask probe"
rc_ii=$LEG_RC

if [[ "$rc_i" -eq 1 || "$rc_ii" -eq 1 ]]; then
  echo "FAIL: a first post-merge run is red; read plan 4.4 (rollback triggers) and comment the verdict on #12514" >&2
  exit 1
fi
if [[ "$rc_i" -eq 3 || "$rc_ii" -eq 3 ]]; then
  exit 3
fi
if [[ "$rc_i" -eq 2 || "$rc_ii" -eq 2 ]]; then
  exit 2
fi
echo "PASS: both first post-merge runs are green"
exit 0
