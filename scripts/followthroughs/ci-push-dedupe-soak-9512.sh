#!/usr/bin/env bash
# ci-push-dedupe-soak-9512.sh — post-merge soak probe for #9512 (ADR-276 S2, the push-dedupe stage).
#
# Is the push-run elision honest and does it pay? Over the push `CI` runs on main, exit 0 needs ALL of:
#   (a) every run OBSERVED to be elided has, recomputed here from a separate merge_group runs listing, a
#       completed `success` merge_group run with the same head SHA. "Elided" is read from the run's job
#       conclusions (`push-dedupe` success and every `test-scripts` job skipped), never from the
#       `ci-push-dedupe` annotation, which could fail to emit and would blind the probe.
#       Evaluated on EVERY sweep, before any NOT YET: a wrong elision is reported within a day.
#   (b) the mean runner-bound job-minutes over the trailing sample of push runs since activation (the newest
#       MAX_RUNS, at most 100: about 4 days at 25 runs a day), elided or not, is at most 29.08 per run (20% of the
#       145.41 baseline, ADR-276 S2 amendment). Computed here from the jobs API (the census refuses live mode in
#       CI) with the census's counted-job definition: conclusion not skipped, runner_id a positive number, both
#       timestamps set, completed not before started. Metered job-seconds, not billed minutes (ADR note).
#   (c) at least MIN_ELIDED (10) elided runs and MIN_DAYS (7) days since activation.
#   (d) an `S2-EXIT-CENSUS: https://...` comment on the tracker from a repository owner, member or collaborator:
#       the sweeper closes the tracker itself on exit 0, so a pass without the exit census attached would close
#       the stage without its evidence.
# ACTIVATION is read from the tracker, not from the repository variable: the sweeper's GITHUB_TOKEN cannot read
# Actions variables (the sibling watchdog-arm-soak-9237.sh documents the same 403), and a probe that depends on
# that read would sit at CANNOT ESTABLISH forever. The activating agent comments `S2-ACTIVATED: <UTC ISO time>`
# (the variable's updated_at) on the tracker; `S2-DEACTIVATED: <UTC ISO time>` ends it. Only comments by an
# OWNER, MEMBER or COLLABORATOR count, so a drive-by commenter on a public repo can neither activate nor close.
# With no activation on record, an elided run is a FAIL (an org-level variable, or a flip nobody recorded).
# More than DEADLINE_DAYS (30) days after the S2 PR merged with no activation is exit 1: activate, or revert.
# More than DEADLINE_DAYS days after activation with too few elided runs is exit 1: the proof is not eliding
# (read the `would-elide` step conclusions and the `::warning reason=proof_error` annotations).
# Two repo checks run on every sweep: an elided run while ADR-276 still reads `proposed` is a FAIL (activation
# needs the `adopting` flip), and the proof suite must still be registered in scripts/test-all.sh (CODEOWNERS
# cannot be assumed to bind; this probe is the detective control).
#
# Exit semantics (sweep-followthroughs.sh contract):
#   0 = PASS    1 = FAIL (a wrong elision, the mean over target, a deadline, or a deregistered proof suite)
#   2 = NOT YET (not activated, too few elided runs or days, or the exit census marker is missing)
#   3 = CANNOT ESTABLISH (gh/jq/GH_TOKEN missing, or a GitHub API read failed: the sweeper retries)
#   78 = refused to run under xtrace while GH_TOKEN is set (#7797)
#
# RETIREMENT: when #9512's tracker closes, delete this file, its .test.sh, the run_suite line in scripts/test-all.sh,
# the rows in scripts/suite-shard-legs.tsv and scripts/suite-durations.tsv, and the CODEOWNERS lines.
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
S2_PR=9808
DIRECTIVE_SCRIPT="scripts/followthroughs/ci-push-dedupe-soak-9512.sh"
MIN_ELIDED=10
MIN_DAYS=7
DEADLINE_DAYS=30
MAX_RUNS=100         # bounds API use: the sweeper token allows ~1000 requests/hour/repo
IDLE_RUNS=10         # while nothing is activated only a wrong elision matters: a short sample is enough
# 29.08 job-minutes per run, compared as integers: total_seconds * 100 <= 2908 * 60 * runs
MEAN_LIMIT_HUNDREDTHS_MIN=2908
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# test seams (the sweeper runs this under env -i, so they are inert in production)
ADR_GLOB="${SOAK_ADR_FILE:-$HERE/../../knowledge-base/engineering/architecture/decisions/ADR-276-*.md}"
TEST_ALL="${SOAK_TEST_ALL:-$HERE/../test-all.sh}"

for need in gh jq; do
  command -v "$need" >/dev/null 2>&1 || { echo "CANNOT ESTABLISH: $need is not installed"; exit 3; }
done
[ -n "${GH_TOKEN:-}" ] || { echo "CANNOT ESTABLISH: GH_TOKEN is not set (the tracker directive must declare secrets=GH_TOKEN)"; exit 3; }

NOW="${SOAK_NOW_EPOCH:-$(date -u +%s)}"
[[ "$NOW" =~ ^[1-9][0-9]*$ ]] || { echo "CANNOT ESTABLISH: SOAK_NOW_EPOCH is not an epoch"; exit 3; }

fail_api() { echo "CANNOT ESTABLISH: GitHub API read failed ($1)"; exit 3; }
api() { gh api "$@" 2>/dev/null; }

# --- the S2 PR merge time ----------------------------------------------------------------------------------
merged_at="$(api "repos/$REPO/pulls/$S2_PR" --jq '.merged_at // empty')" || fail_api "pull $S2_PR"
[ -n "$merged_at" ] || { echo "NOT YET: PR $S2_PR is not merged"; exit 2; }
merged_epoch="$(date -u -d "$merged_at" +%s 2>/dev/null)" || fail_api "merge time $merged_at"

# --- the tracker: activation and exit-census markers, trusted authors only ---------------------------------------------
issues="$(api "repos/$REPO/issues?labels=follow-through&state=open&per_page=100" \
          --jq "[.[] | select((.body // \"\") | contains(\"script=$DIRECTIVE_SCRIPT\")) | .number]")" || fail_api "follow-through issues"
tracker="$(jq -r '.[0] // empty' <<<"$issues" 2>/dev/null)" || fail_api "tracker lookup"
[ -n "$tracker" ] || { echo "NOT YET: the tracker issue carrying the $DIRECTIVE_SCRIPT directive was not found among open follow-through issues"; exit 2; }
trusted="$(api "repos/$REPO/issues/$tracker/comments?per_page=100" \
           --jq '[.[] | select((.author_association // "") | IN("OWNER", "MEMBER", "COLLABORATOR")) | (.body // "")] | join("\n")')" \
  || fail_api "tracker $tracker comments"
trusted="$(printf '%s' "$trusted" | tr -d '\r')"
TS_RE='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'
last_on="$(printf '%s\n' "$trusted" | grep -oE "^S2-ACTIVATED: $TS_RE\$" | sed 's/^S2-ACTIVATED: //' | sort | tail -n 1)"
last_off="$(printf '%s\n' "$trusted" | grep -oE "^S2-DEACTIVATED: $TS_RE\$" | sed 's/^S2-DEACTIVATED: //' | sort | tail -n 1)"
census_marked="$(printf '%s\n' "$trusted" | grep -cE '^S2-EXIT-CENSUS: https://github\.com/[^ ]+$')"
act_epoch=""; active=0
if [ -n "$last_on" ]; then
  on_epoch="$(date -u -d "$last_on" +%s 2>/dev/null)" || fail_api "activation time $last_on"
  off_epoch=0
  if [ -n "$last_off" ]; then off_epoch="$(date -u -d "$last_off" +%s 2>/dev/null)" || fail_api "deactivation time $last_off"; fi
  if [ "$on_epoch" -gt "$off_epoch" ]; then act_epoch="$on_epoch"; active=1; fi
fi

# --- the repo checks that need no API: ADR status and the proof suite's registration ------------------------------------
adr_file=""
for f in $ADR_GLOB; do [ -f "$f" ] && { adr_file="$f"; break; }; done
[ -n "$adr_file" ] || fail_api "ADR-276 file ($ADR_GLOB)"
adr_status="$(sed -n 's/^status:[[:space:]]*//p' "$adr_file" | head -n 1 | tr -d '"')"
[ -n "$adr_status" ] || fail_api "ADR-276 status line"
[ -r "$TEST_ALL" ] || fail_api "scripts/test-all.sh"
suite_registered="$(grep -cF 'scripts/ci-push-dedupe.test.sh' "$TEST_ALL")"

# --- the sample: push runs since the PR merge (newest first) -----------------------------------------------------------------
since_iso="$(date -u -d "@$merged_epoch" +%Y-%m-%dT%H:%M:%SZ)"
cap="$MAX_RUNS"; (( active )) || cap="$IDLE_RUNS"
runs_json="$(api "repos/$REPO/actions/workflows/ci.yml/runs?event=push&branch=main&status=completed&per_page=100&created=%3E$since_iso" \
              --jq "[.workflow_runs[] | {id, head_sha, created_at}] | .[0:$cap]")" || fail_api "ci.yml push runs"
[ -n "$runs_json" ] || fail_api "ci.yml push runs (empty body)"

# the merge_group listing: a different read and a different (weaker, separate) client check than the proof's,
# anchored one day before the OLDEST sampled run so a long soak does not page through every queue run since the merge
oldest="$(jq -r 'map(.created_at) | min // empty' <<<"$runs_json" 2>/dev/null)" || fail_api "sample bounds"
mg_json='[]'
if [ -n "$oldest" ]; then
  oldest_epoch="$(date -u -d "$oldest" +%s 2>/dev/null)" || fail_api "sample bound $oldest"
  mg_since_iso="$(date -u -d "@$((oldest_epoch - 86400))" +%Y-%m-%dT%H:%M:%SZ)"
  mg_raw="$(api --paginate "repos/$REPO/actions/workflows/ci.yml/runs?event=merge_group&per_page=100&created=%3E$mg_since_iso")" \
    || fail_api "ci.yml merge_group runs"
  mg_json="$(jq -s '[.[] | .workflow_runs[]? | select(.event == "merge_group" and .status == "completed" and .conclusion == "success") | .head_sha]' <<<"$mg_raw" 2>/dev/null)" \
    || fail_api "ci.yml merge_group runs (parse)"
  [ -n "$mg_json" ] || fail_api "ci.yml merge_group runs (empty)"
fi

# --- per run: elided? counted seconds ---------------------------------------------------------------------------------
n=0; elided=0; total_s=0; wrong=0; wrong_list=""; early=0; early_list=""; seen=0; would=0; elided_any=0
while IFS=$'\t' read -r id sha created; do
  [ -n "$id" ] || continue
  seen=$((seen + 1))
  created_epoch="$(date -u -d "$created" +%s 2>/dev/null)" || fail_api "run $id created_at $created"
  jobs_json="$(api "repos/$REPO/actions/runs/$id/jobs?per_page=100&filter=latest")" || fail_api "run $id jobs"
  is_elided="$(jq -r '
      ([.jobs[]? | select(.name == "push-dedupe" and .conclusion == "success")] | length) as $pd
      | ([.jobs[]? | select(.name | test("^test-scripts( |$)"))] ) as $ts
      | if $pd > 0 and ($ts | length) > 0 and ($ts | all(.conclusion == "skipped")) then "yes" else "no" end' <<<"$jobs_json" 2>/dev/null)" \
    || fail_api "run $id jobs (parse)"
  proof_holds="$(jq -r '[.jobs[]? | select(.name == "push-dedupe") | .steps[]? | select(.name == "Proof holds for this SHA" and .conclusion == "success")] | length' <<<"$jobs_json" 2>/dev/null)" \
    || fail_api "run $id steps (parse)"
  secs="$(jq -r '[.jobs[]? | select(.conclusion != "skipped" and ((.runner_id | type) == "number") and .runner_id > 0 and .started_at and .completed_at)
                  | ((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601)) | select(. >= 0)] | add // 0' <<<"$jobs_json" 2>/dev/null)" \
    || fail_api "run $id duration"
  [[ "$secs" =~ ^[0-9]+$ ]] || fail_api "run $id duration (not an integer: $secs)"
  [ "$is_elided" = "yes" ] && elided_any=$((elided_any + 1))
  # before the activation (or with nothing activated): the run only counts as evidence of a wrong elision
  if (( ! active )) || [ "$created_epoch" -lt "${act_epoch:-0}" ]; then
    if [ "$is_elided" = "yes" ]; then early=$((early + 1)); early_list="$early_list run=$id sha=${sha:0:10}"; fi
    continue
  fi
  n=$((n + 1)); total_s=$((total_s + secs))
  [[ "$proof_holds" =~ ^[0-9]+$ ]] && [ "$proof_holds" -gt 0 ] && would=$((would + 1))
  if [ "$is_elided" = "yes" ]; then
    elided=$((elided + 1))
    covered="$(jq -r --arg sha "$sha" 'map(select(. == $sha)) | length' <<<"$mg_json" 2>/dev/null)" || fail_api "voucher lookup"
    if ! [ "${covered:-0}" -gt 0 ] 2>/dev/null; then wrong=$((wrong + 1)); wrong_list="$wrong_list run=$id sha=${sha:0:10}"; fi
  fi
done < <(jq -r '.[] | [.id, .head_sha, .created_at] | @tsv' <<<"$runs_json")

# --- (a) and the repo checks first, before any NOT YET --------------------------------------------------------------------
if (( suite_registered == 0 )); then
  echo "FAIL: scripts/ci-push-dedupe.test.sh is no longer registered in scripts/test-all.sh: the proof's gated-set guard does not run in CI; restore the run_suite line or unset CI_PUSH_DEDUPE"
  exit 1
fi
if (( wrong > 0 )); then
  echo "FAIL: $wrong elided push run(s) with no completed success merge_group run for the same head SHA:$wrong_list; unset CI_PUSH_DEDUPE ('gh variable delete CI_PUSH_DEDUPE') and apply the ADR-276 S2 stop rule"
  exit 1
fi
if (( early > 0 )); then
  echo "FAIL: $early push run(s) were elided with no activation on record (no trusted S2-ACTIVATED comment on #$tracker, or the run predates it; an org-level variable, or an activation nobody recorded?):$early_list"
  exit 1
fi
if (( elided_any > 0 )) && [ "$adr_status" = "proposed" ]; then
  echo "FAIL: $elided_any push run(s) were elided while ADR-276 still reads 'proposed': activation requires the CTO flip to 'adopting' (unset CI_PUSH_DEDUPE until then)"
  exit 1
fi
if (( ! active )); then
  if (( NOW - merged_epoch > DEADLINE_DAYS * 86400 )); then
    echo "FAIL: more than $DEADLINE_DAYS days since PR $S2_PR merged and no activation is on record on #$tracker: activate, or revert the push-dedupe job (ADR-276 S2 stop rule)"
    exit 1
  fi
  echo "NOT YET: not activated (no trusted S2-ACTIVATED comment on #$tracker); $seen recent push run(s) sampled, 0 elided"
  exit 2
fi

# --- active: counts and age ------------------------------------------------------------------------------------------
age_days=$(( (NOW - act_epoch) / 86400 ))
mean="n/a"; (( n > 0 )) && mean="$(awk -v s="$total_s" -v n="$n" 'BEGIN { printf "%.2f", s / n / 60 }')"
echo "activated=$last_on trailing_push_runs=$n elided=$elided would_elide_runs=$would age_days=$age_days mean_job_min_per_run=$mean limit=29.08 adr_status=$adr_status"
if (( elided < MIN_ELIDED || age_days < MIN_DAYS )); then
  if (( age_days >= DEADLINE_DAYS )); then
    echo "FAIL: $age_days days since activation and only $elided elided run(s) (need >= $MIN_ELIDED): the proof is not eliding; read the push-dedupe job's 'Proof holds for this SHA' step conclusions and the ci-push-dedupe warning annotations (reason=proof_error / no_mg_success) in recent push runs"
    exit 1
  fi
  echo "NOT YET: $elided elided run(s) over $age_days day(s) (need >= $MIN_ELIDED over >= $MIN_DAYS days)"
  exit 2
fi

# --- (b) the cost criterion over ALL sampled push runs, in exact integers -----------------------------------------------
if (( n == 0 )) || (( total_s * 100 > MEAN_LIMIT_HUNDREDTHS_MIN * 60 * n )); then
  echo "FAIL: mean $mean job-minutes per push run is over 29.08 (20% of the 145.41 baseline) across the trailing $n run(s), elided or not; the stage did not pay: apply the ADR-276 S2 stop rule"
  exit 1
fi

# --- (d) the exit census marker, from a trusted author --------------------------------------------------------------------
if (( census_marked == 0 )); then
  echo "NOT YET: criteria (a)-(c) hold ($elided elided, $age_days days, mean $mean) but tracker #$tracker has no 'S2-EXIT-CENSUS: https://github.com/...' comment from an owner, member or collaborator; attach the exit census (plan PM-4)"
  exit 2
fi
echo "PASS: $elided elided push run(s) over $age_days days, every one vouched by a green merge_group run, mean $mean job-min per push run (limit 29.08), exit census attached on #$tracker"
exit 0
