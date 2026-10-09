#!/usr/bin/env bash
# ci-push-dedupe-soak-9512.sh — post-merge soak probe for #9512 (ADR-276 S2, the push-dedupe stage).
#
# Is the push-run elision honest and does it pay? Over the push `CI` runs on main since activation, exit 0 needs ALL of:
#   (a) every run OBSERVED to be elided has, recomputed here from a separate merge_group runs listing, a
#       completed `success` merge_group run with the same head SHA. "Elided" is read from the run's job
#       conclusions (`push-dedupe` success and every `test-scripts` job skipped), never from the
#       `ci-push-dedupe` annotation, which could fail to emit and would blind the probe.
#       This is evaluated on EVERY sweep, before any NOT YET: a wrong elision is reported within a day.
#   (b) the mean runner-bound job-minutes over ALL push runs since activation, elided or not, is at most
#       29.08 per run (20% of the 145.41 baseline, ADR-276 S2 amendment). Computed here from the jobs API
#       (the census refuses live mode in CI) with the census's counted-job definition: conclusion not skipped,
#       runner_id a positive number, both timestamps set, completed not before started.
#   (c) at least MIN_ELIDED (10) elided runs and MIN_DAYS (7) days since the variable's own `updated_at`.
#   (d) an `S2-EXIT-CENSUS: <url>` comment on the tracker: the sweeper closes the tracker itself on exit 0, so
#       a pass without the exit census attached would close the stage without its evidence.
# The variable CI_PUSH_DEDUPE is read from the repository (activation = its `updated_at`, value exactly `on`).
# Unset is NOT YET ("not activated") unless a run is observed elided anyway (an org-level or environment
# variable, or a deleted one): that is a FAIL, there is no activation record to justify it. More than
# DEADLINE_DAYS (30) days after the S2 PR merged with the variable still unset is exit 1: activate, or revert.
#
# Sampling: the most recent MAX_RUNS (100) completed push runs created after the later of the PR merge and the
# activation. A sweep is daily (about 25 push runs a day), so every run is seen by several sweeps.
#
# Exit semantics (sweep-followthroughs.sh contract):
#   0 = PASS    1 = FAIL (a wrong elision, the mean over target, or the 30-day deadline)
#   2 = NOT YET (not activated, too few elided runs or days, or the exit census marker is missing)
#   3 = CANNOT ESTABLISH (gh/jq/GH_TOKEN missing, or a GitHub API read failed: the sweeper retries)
#   78 = refused to run under xtrace while GH_TOKEN is set (#7797)
#
# RETIREMENT: when #9512's tracker closes, delete this file, its .test.sh, the run_suite line in scripts/test-all.sh,
# the rows in scripts/suite-shard-legs.tsv and scripts/suite-durations.tsv, and the CODEOWNERS line.
set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}${GITHUB_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO="jikig-ai/soleur"
VAR_NAME="CI_PUSH_DEDUPE"
S2_PR=9808
DIRECTIVE_SCRIPT="scripts/followthroughs/ci-push-dedupe-soak-9512.sh"
MIN_ELIDED=10
MIN_DAYS=7
DEADLINE_DAYS=30
MAX_RUNS=100         # bounds API use: the sweeper token allows ~1000 requests/hour/repo
# 29.08 job-minutes per run, compared as integers: total_seconds * 100 <= 2908 * 60 * runs
MEAN_LIMIT_HUNDREDTHS_MIN=2908

for need in gh jq; do
  command -v "$need" >/dev/null 2>&1 || { echo "CANNOT ESTABLISH: $need is not installed"; exit 3; }
done
[ -n "${GH_TOKEN:-}" ] || { echo "CANNOT ESTABLISH: GH_TOKEN is not set (the tracker directive must declare secrets=GH_TOKEN)"; exit 3; }

NOW="${SOAK_NOW_EPOCH:-$(date -u +%s)}"
[[ "$NOW" =~ ^[0-9]+$ ]] || { echo "CANNOT ESTABLISH: SOAK_NOW_EPOCH is not an epoch"; exit 3; }

fail_api() { echo "CANNOT ESTABLISH: GitHub API read failed ($1)"; exit 3; }

# --- the S2 PR merge time ----------------------------------------------------------------------------------
merged_at="$(gh api "repos/$REPO/pulls/$S2_PR" --jq '.merged_at // empty' 2>/dev/null)" || fail_api "pull $S2_PR"
[ -n "$merged_at" ] || { echo "NOT YET: PR $S2_PR is not merged"; exit 2; }
merged_epoch="$(date -u -d "$merged_at" +%s 2>/dev/null)" || fail_api "merge time $merged_at"

# --- the variable: 404 is unset, any other failure is CANNOT ESTABLISH -----------------------------------------
var_err="$(mktemp "${TMPDIR:-/var/tmp}/soak9512.XXXXXXXX")" || { echo "CANNOT ESTABLISH: mktemp failed"; exit 3; }
trap 'rm -f "$var_err"' EXIT
var_state="unset"; var_value=""; var_updated=""
if var_json="$(gh api "repos/$REPO/actions/variables/$VAR_NAME" 2>"$var_err")"; then
  var_value="$(jq -r '.value // ""' <<<"$var_json" 2>/dev/null)" || fail_api "variable body"
  var_updated="$(jq -r '.updated_at // ""' <<<"$var_json" 2>/dev/null)" || fail_api "variable body"
  var_state="set"
else
  if grep -cE 'HTTP 404|Not Found' "$var_err" >/dev/null; then var_state="unset"; else fail_api "variable $VAR_NAME"; fi
fi
act_epoch=""
if [ "$var_state" = "set" ]; then
  [ -n "$var_updated" ] || fail_api "variable updated_at"
  act_epoch="$(date -u -d "$var_updated" +%s 2>/dev/null)" || fail_api "variable updated_at $var_updated"
fi

# --- the sample window: after the PR merge (a run elided BEFORE the activation is as wrong as one elided with the
# variable unset), while the counts and the mean below only use runs created at or after the activation ------------
since_epoch="$merged_epoch"
since_iso="$(date -u -d "@$since_epoch" +%Y-%m-%dT%H:%M:%SZ)"

runs_json="$(gh api "repos/$REPO/actions/workflows/ci.yml/runs?event=push&branch=main&status=completed&per_page=100&created=%3E$since_iso" \
              --jq '[.workflow_runs[] | {id, head_sha, created_at}]' 2>/dev/null)" || fail_api "ci.yml push runs"
[ -n "$runs_json" ] || fail_api "ci.yml push runs (empty body)"

# the merge_group listing: a different read and a different (weaker, separate) client check than the proof's
mg_since_iso="$(date -u -d "@$((since_epoch - 86400))" +%Y-%m-%dT%H:%M:%SZ)"
mg_raw="$(gh api --paginate "repos/$REPO/actions/workflows/ci.yml/runs?event=merge_group&per_page=100&created=%3E$mg_since_iso" 2>/dev/null)" \
  || fail_api "ci.yml merge_group runs"
mg_json="$(jq -s '[.[] | .workflow_runs[]? | select(.event == "merge_group" and .status == "completed" and .conclusion == "success") | .head_sha]' <<<"$mg_raw" 2>/dev/null)" \
  || fail_api "ci.yml merge_group runs (parse)"
[ -n "$mg_json" ] || fail_api "ci.yml merge_group runs (empty)"

# --- per run: elided? counted seconds ---------------------------------------------------------------------------------
n=0; elided=0; total_s=0; wrong=0; wrong_list=""; early=0; early_list=""; seen=0
while IFS=$'\t' read -r id sha created; do
  [ -n "$id" ] || continue
  (( seen < MAX_RUNS )) || break
  seen=$((seen + 1))
  created_epoch="$(date -u -d "$created" +%s 2>/dev/null)" || fail_api "run $id created_at $created"
  jobs_json="$(gh api "repos/$REPO/actions/runs/$id/jobs?per_page=100&filter=latest" 2>/dev/null)" || fail_api "run $id jobs"
  is_elided="$(jq -r '
      ([.jobs[]? | select(.name == "push-dedupe" and .conclusion == "success")] | length) as $pd
      | ([.jobs[]? | select(.name | test("^test-scripts( |$)"))] ) as $ts
      | if $pd > 0 and ($ts | length) > 0 and ($ts | all(.conclusion == "skipped")) then "yes" else "no" end' <<<"$jobs_json" 2>/dev/null)" \
    || fail_api "run $id jobs (parse)"
  secs="$(jq -r '[.jobs[]? | select(.conclusion != "skipped" and ((.runner_id | type) == "number") and .runner_id > 0 and .started_at and .completed_at)
                  | ((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601)) | select(. >= 0)] | add // 0' <<<"$jobs_json" 2>/dev/null)" \
    || fail_api "run $id duration"
  [[ "$secs" =~ ^[0-9]+$ ]] || fail_api "run $id duration (not an integer: $secs)"
  # before the activation (or with the variable not 'on'): the run only counts as evidence of a wrong elision
  if [ "$var_state" != "set" ] || [ "$var_value" != "on" ] || [ "$created_epoch" -lt "${act_epoch:-0}" ]; then
    if [ "$is_elided" = "yes" ]; then early=$((early + 1)); early_list="$early_list run=$id sha=${sha:0:10}"; fi
    continue
  fi
  n=$((n + 1)); total_s=$((total_s + secs))
  if [ "$is_elided" = "yes" ]; then
    elided=$((elided + 1))
    covered="$(jq -r --arg sha "$sha" 'map(select(. == $sha)) | length' <<<"$mg_json" 2>/dev/null)" || fail_api "voucher lookup"
    if ! [ "${covered:-0}" -gt 0 ] 2>/dev/null; then wrong=$((wrong + 1)); wrong_list="$wrong_list run=$id sha=${sha:0:10}"; fi
  fi
done < <(jq -r '.[] | [.id, .head_sha, .created_at] | @tsv' <<<"$runs_json")

# --- (a) first, before any NOT YET -------------------------------------------------------------------------------------
if (( wrong > 0 )); then
  echo "FAIL: $wrong elided push run(s) with no completed success merge_group run for the same head SHA:$wrong_list; unset $VAR_NAME ('gh variable delete $VAR_NAME') and apply the ADR-276 S2 stop rule"
  exit 1
fi
if (( early > 0 )); then
  echo "FAIL: $early push run(s) were elided with no activation record behind them (before $VAR_NAME was set to 'on', or while it is not 'on' for this repository: state=$var_state; an org-level or environment variable?):$early_list"
  exit 1
fi
if [ "$var_state" != "set" ] || [ "$var_value" != "on" ]; then
  if (( NOW - merged_epoch > DEADLINE_DAYS * 86400 )); then
    echo "FAIL: more than $DEADLINE_DAYS days since PR $S2_PR merged and $VAR_NAME is not 'on' (state=$var_state): activate it, or revert the push-dedupe job (ADR-276 S2 stop rule)"
    exit 1
  fi
  echo "NOT YET: not activated ($VAR_NAME state=$var_state, value='${var_value}'); $seen push run(s) sampled, 0 elided"
  exit 2
fi

# --- active: counts and age ------------------------------------------------------------------------------------------
age_days=$(( (NOW - act_epoch) / 86400 ))
mean="n/a"; (( n > 0 )) && mean="$(awk -v s="$total_s" -v n="$n" 'BEGIN { printf "%.2f", s / n / 60 }')"
echo "since_activation=$var_updated push_runs=$n elided=$elided age_days=$age_days mean_job_min_per_run=$mean limit=29.08"
if (( elided < MIN_ELIDED || age_days < MIN_DAYS )); then
  echo "NOT YET: $elided elided run(s) over $age_days day(s) (need >= $MIN_ELIDED over >= $MIN_DAYS days)"
  exit 2
fi

# --- (b) the cost criterion over ALL sampled push runs, in exact integers -----------------------------------------------
if (( n == 0 )) || (( total_s * 100 > MEAN_LIMIT_HUNDREDTHS_MIN * 60 * n )); then
  echo "FAIL: mean $mean job-minutes per push run is over 29.08 (20% of the 145.41 baseline) across $n run(s), elided or not; the stage did not pay: apply the ADR-276 S2 stop rule"
  exit 1
fi

# --- (d) the exit census marker, on the tracker --------------------------------------------------------------------------
issues="$(gh api "repos/$REPO/issues?labels=follow-through&state=open&per_page=100" --jq "[.[] | select((.body // \"\") | contains(\"script=$DIRECTIVE_SCRIPT\")) | .number]" 2>/dev/null)" \
  || fail_api "follow-through issues"
tracker="$(jq -r '.[0] // empty' <<<"$issues" 2>/dev/null)" || fail_api "tracker lookup"
[ -n "$tracker" ] || { echo "NOT YET: the tracker issue carrying the $DIRECTIVE_SCRIPT directive was not found among open follow-through issues"; exit 2; }
marked="$(gh api "repos/$REPO/issues/$tracker/comments?per_page=100" --jq '[.[] | select((.body // "") | test("(^|\n)S2-EXIT-CENSUS: [^ \n]+"))] | length' 2>/dev/null)" \
  || fail_api "tracker $tracker comments"
if ! [ "${marked:-0}" -gt 0 ] 2>/dev/null; then
  echo "NOT YET: criteria (a)-(c) hold ($elided elided, $age_days days, mean $mean) but tracker #$tracker has no 'S2-EXIT-CENSUS: <url>' comment; attach the exit census (plan PM-4)"
  exit 2
fi
echo "PASS: $elided elided push run(s) over $age_days days, every one vouched by a green merge_group run, mean $mean job-min per push run (limit 29.08), exit census attached on #$tracker"
exit 0
