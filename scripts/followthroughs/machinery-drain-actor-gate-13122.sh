#!/usr/bin/env bash
# Follow-through verification for #13122 / PR #13096: the first post-fix weekly
# scheduled-machinery-drain measurement must no longer hit claude-code-action's
# non-human actor refusal.
#
# Evidence bar:
#   * select the first completed post-cutoff workflow_dispatch run of
#     scheduled-machinery-drain.yml on main whose triggering actor is
#     soleur-ai[bot], skipping cancelled/skipped rows as non-measurements;
#   * read the exact per-step log of `Drain the machinery ledger`, not the run
#     or step conclusion, and find no timestamped emitted
#     `##[error]Action failed ... Workflow initiated by non-human actor` line;
#   * read the exact per-step log of `Update the standing measurement issue`
#     and find the emitted `updated standing issue #9508` line;
#   * find a correlated github-actions[bot] comment on #9508 within fifteen
#     minutes of the run start whose body has `Machinery drain outcome:` and a
#     parseable `closed=N` in that outcome block.
#
# Echoed workflow source is not evidence either way: GitHub echoes the workflow
# source into step logs with colour escapes and indentation. The actor refusal
# is matched only as a timestamped emitted `##[error]` runtime line. Run and job
# conclusions are never sufficient because the Drain step uses continue-on-error.
#
# PASS additionally requires either closed>0, an explicit WAIVED-* token in the
# outcome block, or a substantive non-actor `##[error]` diagnosis. A bare
# process-exit error with unexplained closed=0 is CANNOT ESTABLISH.
#
# Exit semantics (sweep-followthroughs.sh contract):
#   0 PASS              full evidence bar passes
#   1 FAIL              the actor-gate refusal persists
#   2 NOT YET           no qualifying completed non-cancelled measurement exists
#   3 CANNOT ESTABLISH  evidence cannot be established or is incomplete
#  78 REFUSED           xtrace is enabled while GH_TOKEN is live (#7797)
#
# CREDENTIAL POSTURE: GH_TOKEN with actions:read and issues:read, declared via
# the directive's secrets= clause. The probe reads GitHub only.
# RETIREMENT: when its tracker closes and the follow-through label is removed,
# delete this file, machinery-drain-actor-gate-13122.test.sh, their test-all
# registration and generated shard/duration rows; re-census with
# `git grep machinery-drain-actor-gate-13122`.

set -uo pipefail

case "$-" in
  *x*)
    if [[ -n "${GH_TOKEN:+x}" ]]; then
      printf '[FATAL] refusing to run under xtrace: this probe holds GH_TOKEN and -x would print it (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO='jikig-ai/soleur'
WF='scheduled-machinery-drain.yml'
CUTOFF='2026-11-28T12:57:15Z'
PER_PAGE=100
RUNS_ENDPOINT="repos/${REPO}/actions/workflows/${WF}/runs?actor=soleur-ai%5Bbot%5D&status=completed&created=%3E%3D2026-11-28T12%3A57%3A15Z&per_page=100"
ISSUE=9508

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo 'CANNOT ESTABLISH: GH_TOKEN is not set' >&2
  exit 3
fi

cannot() {
  echo "CANNOT ESTABLISH: $1" >&2
  exit 3
}

ghx() {
  timeout 60 gh api "$@" 2>/dev/null
}

iso_epoch() {
  date -u -d "$1" +%s 2>/dev/null
}

runs_json="$(ghx "$RUNS_ENDPOINT")" || cannot 'reading the workflow-runs page failed'
printf '%s' "$runs_json" | jq -e 'type == "object" and (.total_count | type == "number") and (.workflow_runs | type == "array")' >/dev/null 2>&1 \
  || cannot 'the workflow-runs response has an unexpected shape'
total_count="$(printf '%s' "$runs_json" | jq -r '.total_count')" || cannot 'could not read total_count'
if (( total_count > PER_PAGE )); then
  cannot "workflow-runs total_count=${total_count} exceeds per_page=${PER_PAGE}; refusing to select from an incomplete newest page"
fi

rows="$(printf '%s' "$runs_json" | jq -r --arg cutoff "$CUTOFF" '
  [.workflow_runs[]
    | select((.id | type == "number")
      and (.created_at | type == "string")
      and (.conclusion | type == "string")
      and .created_at >= $cutoff
      and .event == "workflow_dispatch"
      and .head_branch == "main"
      and .triggering_actor.login == "soleur-ai[bot]")]
  | sort_by(.created_at)
  | .[] | [(.id | tostring), .created_at, .conclusion] | @tsv
')" || cannot 'could not project the workflow-runs response'

run_id=''
run_created=''
run_conclusion=''
while IFS=$'\t' read -r id created conclusion; do
  [[ -n "$id" ]] || continue
  if [[ "$conclusion" == "cancelled" || "$conclusion" == "skipped" ]]; then
    echo "skip: run ${id} concluded ${conclusion}; it is not a measurement"
    continue
  fi
  run_id="$id"
  run_created="$created"
  run_conclusion="$conclusion"
  break
done <<<"$rows"

if [[ -z "$run_id" ]]; then
  echo "NOT YET: no qualifying completed non-cancelled ${WF} measurement on main since ${CUTOFF}" >&2
  exit 2
fi

jobs_json="$(ghx "repos/${REPO}/actions/runs/${run_id}/jobs?per_page=100")" \
  || cannot "reading jobs for run ${run_id} failed"
printf '%s' "$jobs_json" | jq -e 'type == "object" and (.jobs | type == "array")' >/dev/null 2>&1 \
  || cannot "the jobs response for run ${run_id} has an unexpected shape"

job_count="$(printf '%s' "$jobs_json" | jq '[.jobs[] | select(.name == "measure-and-drain")] | length')" \
  || cannot "could not count measure-and-drain jobs for run ${run_id}"
(( job_count == 1 )) || cannot "run ${run_id} has ${job_count} measure-and-drain jobs, expected exactly one"
job_id="$(printf '%s' "$jobs_json" | jq -r '.jobs[] | select(.name == "measure-and-drain") | .id')" \
  || cannot "could not read the measure-and-drain job id for run ${run_id}"
[[ "$job_id" =~ ^[0-9]+$ ]] || cannot "unexpected measure-and-drain job id '${job_id}'"

step_number() {
  local wanted="$1" count num
  count="$(printf '%s' "$jobs_json" | jq --arg wanted "$wanted" '[.jobs[] | select(.name == "measure-and-drain") | .steps[]? | select(.name == $wanted)] | length')" || return 1
  [[ "$count" == "1" ]] || return 1
  num="$(printf '%s' "$jobs_json" | jq -r --arg wanted "$wanted" '.jobs[] | select(.name == "measure-and-drain") | .steps[]? | select(.name == $wanted) | .number')" || return 1
  [[ "$num" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$num"
}

drain_step="$(step_number 'Drain the machinery ledger')" \
  || cannot "run ${run_id} does not expose exactly one Drain the machinery ledger step"
update_step="$(step_number 'Update the standing measurement issue')" \
  || cannot "run ${run_id} does not expose exactly one Update the standing measurement issue step"

TMPD="$(mktemp -d -t machinery-drain-13122.XXXXXXXX)" || cannot 'mktemp -d failed'
trap 'rm -rf -- "$TMPD"' EXIT
DRAIN_LOG="$TMPD/drain.log"
UPDATE_LOG="$TMPD/update.log"

ghx --allow-escape-sequences "repos/${REPO}/actions/jobs/${job_id}/steps/${drain_step}/logs" > "$DRAIN_LOG" \
  || cannot "reading Drain step ${drain_step} of job ${job_id} failed"
ghx --allow-escape-sequences "repos/${REPO}/actions/jobs/${job_id}/steps/${update_step}/logs" > "$UPDATE_LOG" \
  || cannot "reading Update step ${update_step} of job ${job_id} failed"

# Canonicalise CRLF emitted by hosted runners. This does not strip colour escapes;
# echoed source therefore still cannot satisfy either emitted-line regex.
tr -d '\r' < "$DRAIN_LOG" > "$DRAIN_LOG.clean"
tr -d '\r' < "$UPDATE_LOG" > "$UPDATE_LOG.clean"

TS_RE='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z'
REFUSAL_RE="^${TS_RE} ##\\[error\\]Action failed with error: Workflow initiated by non-human actor: soleur-ai \\(type: Bot\\)\\."
if grep -aEq "$REFUSAL_RE" "$DRAIN_LOG.clean"; then
  echo "FAIL: run ${run_id} job ${job_id} step ${drain_step} emitted the non-human actor refusal; the PR #13096 actor gate did not take effect" >&2
  exit 1
fi

UPDATE_RE="^${TS_RE} updated standing issue #${ISSUE}[[:space:]]*$"
if ! grep -aEq "$UPDATE_RE" "$UPDATE_LOG.clean"; then
  cannot "run ${run_id} did not emit 'updated standing issue #${ISSUE}' in the exact Update step log"
fi

start_epoch="$(iso_epoch "$run_created")" || cannot "could not parse run created_at '${run_created}'"
[[ "$start_epoch" =~ ^[0-9]+$ ]] || cannot "could not parse run created_at '${run_created}'"
deadline="$(date -u -d "@$((start_epoch + 900))" +%Y-%m-%dT%H:%M:%SZ)" || cannot 'could not compute the comment correlation deadline'
since_enc="${run_created//:/%3A}"
comments_json="$(ghx "repos/${REPO}/issues/${ISSUE}/comments?since=${since_enc}&per_page=100")" \
  || cannot "reading comments on #${ISSUE} failed"
printf '%s' "$comments_json" | jq -e 'type == "array"' >/dev/null 2>&1 \
  || cannot "the comments response for #${ISSUE} has an unexpected shape"
comment_count="$(printf '%s' "$comments_json" | jq 'length')" || cannot "could not count comments on #${ISSUE}"
if (( comment_count >= 100 )); then
  cannot "#${ISSUE} returned ${comment_count} comments in the correlation window; the page may be incomplete"
fi

comment_json="$(printf '%s' "$comments_json" | jq -c --arg start "$run_created" --arg end "$deadline" '
  [.[] | select(.created_at >= $start and .created_at <= $end
    and .user.login == "github-actions[bot]"
    and (.body | type == "string")
    and (.body | contains("Machinery drain outcome:")))]
  | sort_by(.created_at) | .[0] // empty
')" || cannot "could not project comments on #${ISSUE}"
if [[ -z "$comment_json" ]]; then
  cannot "no correlated github-actions[bot] 'Machinery drain outcome:' comment on #${ISSUE} within fifteen minutes of run ${run_id}"
fi

body="$(printf '%s' "$comment_json" | jq -r '.body')" || cannot 'could not read the correlated comment body'
outcome_block="$(printf '%s\n' "$body" | sed -n '/Machinery drain outcome:/,$p')"
closed="$(printf '%s\n' "$outcome_block" | sed -n 's/.*closed=\([0-9][0-9]*\).*/\1/p' | sed -n '1p')"
[[ "$closed" =~ ^[0-9]+$ ]] || cannot "the correlated #${ISSUE} outcome comment has no parseable closed=N value"

if (( closed > 0 )); then
  echo "PASS: run ${run_id} measured without the actor refusal; #${ISSUE} reports closed=${closed}"
  exit 0
fi

if printf '%s\n' "$outcome_block" | grep -aEq 'WAIVED-[A-Z0-9][A-Z0-9-]*'; then
  waiver="$(printf '%s\n' "$outcome_block" | sed -n 's/.*\(WAIVED-[A-Z0-9][A-Z0-9-]*\).*/\1/p' | sed -n '1p')"
  echo "PASS: run ${run_id} measured without the actor refusal; #${ISSUE} reports closed=0 with explicit ${waiver}"
  exit 0
fi

ERROR_RE="^${TS_RE} ##\\[error\\]"
if grep -aEq "$ERROR_RE" "$DRAIN_LOG.clean"; then
  substantive="$(grep -aE "$ERROR_RE" "$DRAIN_LOG.clean" \
    | grep -av 'Process completed with exit code' \
    | grep -av 'Workflow initiated by non-human actor' \
    | sed -n '1p')"
  if [[ -n "$substantive" ]]; then
    echo "PASS: run ${run_id} measured without the actor refusal; #${ISSUE} reports closed=0 with substantive non-actor diagnosis: ${substantive}"
    exit 0
  fi
fi

cannot "run ${run_id} measured without the actor refusal, but #${ISSUE} reports unexplained closed=0 (run conclusion ${run_conclusion}); inspect the Drain output before closing this tracker"
