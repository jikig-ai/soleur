#!/usr/bin/env bash
# Follow-through verification (#9905): the first real runs of the S4 credential conversions.
#
# PR #9893 (slice S4 of the argv-credential sweep, tracker #9597) moved the credentials of the
# push-triggered production-class workflows, composites and scripts off curl's (and openssl's, and
# git's) argument list. The suites drive their real bodies against a recording curl; only a real
# run proves them against the real vendors. Several converted files run rarely or only by a manual
# dispatch, so this probe tracks each workflow's FIRST real run of its converted step(s).
#
# TWO INDEPENDENT READINGS per workflow, over the runs since the merge:
#
#   EXERCISED   positive proof the converted step ran. A run concluding `success` proves nothing by
#               itself: a workflow can succeed while the converted step was skipped (the mint
#               workflow deciding "noop", an apply job gated off, a revoke with nothing to revoke).
#               REQUIRED below lists, per workflow, (job-name regex, step-name regex) pairs taken
#               from the committed workflows; a run counts only when EVERY pair has a job matching
#               the job regex with a step matching the step regex whose conclusion is `success`
#               (read from `gh run view --json jobs`, no log download). A workflow is exercised
#               once ANY run since the merge satisfies all of its pairs. Where the conversion lives
#               in a composite action or a script the workflow calls (the mint composite, track.sh,
#               the pin-bump script, the tunnel verifier), the pair names the CALLING step, which is
#               the only name the jobs API reports; that step succeeding is the honest proxy.
#               Scope note: the dispatch-only jobs of apply-web-platform-infra (the host replace and
#               create jobs) are not tracked; its push-triggered `apply` job is.
#
#   MARKER      no credential-refusal line anywhere in the scanned logs. Not every conversion can emit
#               one: the library (`bc_curl`) and the inline `_sig_curl` / `_bearer_curl` wrappers print
#               the `SOLEUR_CREDENTIAL_REFUSED` line (the library names the variable on a
#               `bc_curl: <VAR> unusable` line beside it, the inline wrappers on `_sig_curl: <VAR>
#               unusable` or `_bearer_curl: <VAR> unusable`), but `verify-tunnel-ingress-origin.sh`
#               (tracked through apply-web-platform-infra's tunnel-verify step) prints NO marker: a
#               refusal there shows only as that step not concluding `success`, so the workflow stays
#               `wait` and ends at ACTION REQUIRED after the wait budget, never at FAIL. A GitHub log line is
#               `<job>TAB<step>TAB<ISO-8601Z timestamp> <text>`, and the library emits the marker as
#               the WHOLE text of its own line. The pattern is anchored on that emitted shape
#               (timestamp, then the marker, then end of line) because the inline wrappers also
#               carry the marker as literal text inside their `run:` source, which GitHub echoes
#               into the log indented and colourised (`ESC[36;1m  echo "SOLEUR_..."`). An unanchored
#               pattern false-FAILs on that echo on every healthy run. Measured on real run logs
#               2026-10-10: emitted lines start the text right after the timestamp; the echoed
#               source lines of the same logs begin with `ESC[36;1m` and indentation (0 hits).
#
# VERDICTS (exit codes; 2/3/5 are the registered notify-only sub-vocabulary of the sweeper):
#   0 PASS             every workflow exercised AND no marker in any scanned log. Closes the tracker.
#   1 FAIL             a marker line was found: a conversion refused a credential before any request
#                      (a value outside the token alphabet or with a stray control byte; the inline
#                      copies print the same marker for a missing python3 or an empty HMAC key
#                      too, so read the `... unusable` line beside it), a rotation or storage problem
#                      the suites cannot see.
#                      The marker, not a run conclusion, is the failure: a dispatch-only workflow
#                      may fail for reasons that have nothing to do with this change. After fixing a
#                      refused credential the operator closes the tracker AND removes its
#                      `follow-through` label (the sweeper's closed-set pass keeps running a
#                      labelled probe).
#   2 NOT YET          some workflow is unexercised and the wait budget (merge + 30 days) is open,
#                      or the PR is not merged yet.
#   3 CANNOT ESTABLISH a gh call failed, timed out or returned an unexpected shape, or the probe's
#                      own time budget ran out (the sweeper retries next sweep).
#   5 ACTION REQUIRED  the wait budget is spent and some workflow was never exercised. An operator
#                      then exercises it with a sanctioned dispatch (a dispatch that writes needs its
#                      own approval; not every tracked workflow has a read-only one) or accepts it
#                      explicitly on the tracker; this probe never closes the tracker in that state.
#
# COST (bounded, worst case stated). List: 1 PR read + 12 run lists (limit 100, newest first).
# MARKER: logs are downloaded for the newest SCAN_RUNS=6 runs per workflow, only for a workflow that
# has a run since the merge: at most 12 x 6 = 72 downloads. The bound is deliberate: a persistent
# refusal shows in recent runs, and a refusal that stopped recurring is fixed. EXERCISED: the jobs
# JSON (small, no log) of at most EXERCISE_RUNS=20 runs per workflow, stopping at the first run that
# satisfies the workflow: at most 12 x 20 = 240 reads. Worst case about 325 gh calls; each runs under
# `timeout 60`, and the whole probe stops with CANNOT ESTABLISH once a 420 s budget is spent
# (checked before each call, so one in-flight call can overrun it by up to 60 s). THIS PROBE ALONE
# is therefore bounded by 480 s worst case. The sweeper job has no per-probe cap and about 50
# trackers share its 900 s `timeout-minutes`, so a degraded GitHub day can still starve the probes
# after this one; the budget keeps this probe from being the one that does it, it does not
# guarantee the others finish. A healthy sweep makes calls of 1 to 4 s (measured 2026-10-10), so a
# cold worst-case sweep (325 calls) can reach the budget; it then exits 3 and the stateless probe
# retries next sweep.
#
# TEST SEAMS (read only when set; the sweeper runs probes under `env -i`, so production never sets
# them): BC_S4_NOW_EPOCH overrides "now" for the wait-deadline arm; BC_S4_GH_TIMEOUT overrides the
# per-call timeout seconds; BC_S4_BUDGET_S overrides the total budget seconds. The suite is
# scripts/followthroughs/bearer-curl-s4-first-runs-9905.test.sh.
#
# Credential posture: needs GH_TOKEN (declared in the directive's secrets= clause) to read run
# lists, jobs and logs; it holds no vendor credential.
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md
#
# RETIREMENT: when #9905 closes (and its follow-through label is removed), delete this file and
# scripts/followthroughs/bearer-curl-s4-first-runs-9905.test.sh, drop their run_suite line in
# scripts/test-all.sh and rows in scripts/suite-shard-legs.tsv / scripts/suite-durations.tsv, and
# retire the tracker's `script=` directive. Re-census with `git grep bearer-curl-s4-first-runs`.

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797): GH_TOKEN is in the environment and -x would print it.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe holds GH_TOKEN and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

PR=9893
WAIT_DAYS=30
LIST_LIMIT=100
SCAN_RUNS=6
EXERCISE_RUNS=20

GH_TIMEOUT="${BC_S4_GH_TIMEOUT:-60}"
BUDGET_S="${BC_S4_BUDGET_S:-420}"
[[ "$GH_TIMEOUT" =~ ^[0-9]+$ && "$GH_TIMEOUT" -gt 0 ]] || GH_TIMEOUT=60
[[ "$BUDGET_S" =~ ^[0-9]+$ ]] || BUDGET_S=420

# workflow-file @@ job-name regex @@ step-name regex. Step names are the committed workflows' own
# (`git grep -n 'name:' .github/workflows/<wf>`). scheduled-inngest-health's converted step used to
# be UNNAMED (the jobs API then reports "Run <first line of the script>", which the suite could not
# tie to the file); it is named `Probe inngest health` now, so every pair is a real step name.
REQUIRED=(
  'scheduled-inngest-health.yml@@^probe$@@^Probe inngest health$'
  'apply-inngest-rls.yml@@^apply$@@^Apply lockdown \+ authoritative verification$'
  'apply-deploy-pipeline-fix.yml@@^apply$@@^Capture pre-apply infra-config frame'
  'apply-deploy-pipeline-fix.yml@@^apply$@@^Verify webhook is alive post-apply$'
  'apply-deploy-pipeline-fix.yml@@^apply$@@^Verify infra-config apply succeeded$'
  'apply-web-platform-infra.yml@@^apply$@@^Verify tunnel ingress origins are live and origin-relative$'
  'web-platform-release.yml@@^deploy$@@^Deploy via webhook$'
  'web-platform-release.yml@@^deploy$@@^Verify deploy script completion$'
  'build-inngest-bootstrap-image.yml@@^bump-cloud-init-pin$@@^Bump the cloud-init pin$'
  'mint-inngest-bootstrap-tag.yml@@^mint$@@^Mint soleur-infra App token'
  'apply-github-infra.yml@@^apply$@@^Mint soleur-infra App token'
  'apply-github-infra.yml@@^apply$@@^Revoke the soleur-infra token$'
  'restart-inngest-server.yml@@^restart$@@^Trigger restart via webhook$'
  'restart-inngest-server.yml@@^restart$@@^Verify restart completion$'
  'deploy-inngest-image.yml@@^deploy$@@^Trigger deploy via webhook$'
  'deploy-inngest-image.yml@@^deploy$@@^Verify deploy completion$'
  'workspaces-luks-cutover.yml@@^cutover$@@^Run workspaces-luks cutover$'
  'git-data-cutover.yml@@^cutover$@@^Same-version redeploy of the web fleet'
)

# The EMITTED marker line: timestamp, then the marker as the whole text. See the header.
MARKER_RE='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z SOLEUR_CREDENTIAL_REFUSED script=[A-Za-z0-9._-]+ reason=[a-z_]+[[:space:]]*$'

WORKFLOWS=()
for req in "${REQUIRED[@]}"; do
  w="${req%%@@*}"
  [[ " ${WORKFLOWS[*]:-} " == *" $w "* ]] || WORKFLOWS+=("$w")
done

refused=0

# One gh call: bounded by the per-call timeout and by the probe's total budget.
ghx() {
  if (( SECONDS >= BUDGET_S )); then
    echo "CANNOT ESTABLISH: the ${BUDGET_S}s probe budget is spent before 'gh $1 $2'" >&2
    return 124
  fi
  timeout "$GH_TIMEOUT" gh "$@" 2>/dev/null
}

# A reading could not be made. A marker already found outranks it: FAIL is the more useful verdict.
cannot() {
  if (( refused > 0 )); then
    echo "FAIL: $refused run(s) printed a credential-refusal marker (the scan then stopped: $1)"
    exit 1
  fi
  echo "CANNOT ESTABLISH: $1" >&2
  exit 3
}

merged_at="$(ghx pr view "$PR" --json mergedAt --jq '.mergedAt // empty')" \
  || cannot "could not read PR #$PR"
[[ -n "$merged_at" ]] || { echo "NOT YET: PR #$PR is not merged yet" >&2; exit 2; }
# gh --jq takes no --arg, so the timestamp is interpolated: refuse anything but an ISO-8601 instant.
[[ "$merged_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$ ]] || cannot "unexpected mergedAt shape"

deadline_epoch="$(date -u -d "$merged_at + $WAIT_DAYS days" +%s 2>/dev/null)" \
  || cannot "could not compute the wait deadline"
now_epoch="${BC_S4_NOW_EPOCH:-}"
if [[ -z "$now_epoch" ]]; then now_epoch="$(date -u +%s)"; fi
[[ "$now_epoch" =~ ^[0-9]+$ ]] || cannot "BC_S4_NOW_EPOCH is not a number"

LOG="$(mktemp -t bearer-curl-s4-first-runs.XXXXXXXX.log)" || cannot "mktemp failed"
trap 'rm -f "$LOG"' EXIT

# step_ok <jobs-json> <job-regex> <step-regex>: 0 when a job matching the first has a step matching
# the second that concluded success; 1 when not; anything else is a jq failure.
step_ok() {
  jq -e --arg j "$2" --arg s "$3" \
    '[.jobs[] | select((.name | test($j)) and ((.steps // []) | any(.[]; (.name | test($s)) and .conclusion == "success")))] | length > 0' \
    <<<"$1" >/dev/null 2>&1
}

unexercised=()
for wf in "${WORKFLOWS[@]}"; do
  rows="$(ghx run list --workflow "$wf" --status completed -L "$LIST_LIMIT" \
    --json databaseId,createdAt \
    --jq "[.[] | select(.createdAt > \"$merged_at\")] | sort_by(.createdAt) | reverse | .[] | .databaseId")" \
    || cannot "could not list the runs of $wf"
  ids=()
  while read -r id; do
    [[ -n "$id" ]] || continue
    [[ "$id" =~ ^[0-9]+$ ]] || cannot "unexpected run id for $wf"
    ids+=("$id")
  done <<<"$rows"
  if (( ${#ids[@]} == 0 )); then
    echo "wait: $wf has no completed run since the merge ($merged_at)"
    unexercised+=("$wf")
    continue
  fi

  # MARKER: the newest SCAN_RUNS runs, whatever their conclusion.
  scanned=0
  for id in "${ids[@]:0:SCAN_RUNS}"; do
    ghx run view "$id" --log > "$LOG" || cannot "could not read the log of $wf run $id"
    markers="$(grep -cE "$MARKER_RE" "$LOG")"
    grc=$?
    (( grc <= 1 )) || cannot "could not scan the log of $wf run $id"
    scanned=$((scanned + 1))
    if (( markers > 0 )); then
      echo "FAIL: $wf run $id printed $markers credential-refusal marker line(s)"
      refused=$((refused + 1))
    fi
  done

  # EXERCISED: any run with every required (job, step) pair successful.
  exercised_by=""
  checked=0
  for id in "${ids[@]:0:EXERCISE_RUNS}"; do
    jobs_json="$(ghx run view "$id" --json jobs)" || cannot "could not read the jobs of $wf run $id"
    jq -e '.jobs | type == "array"' <<<"$jobs_json" >/dev/null 2>&1 || cannot "unexpected jobs shape for $wf run $id"
    checked=$((checked + 1))
    all=1
    for req in "${REQUIRED[@]}"; do
      [[ "${req%%@@*}" == "$wf" ]] || continue
      rest="${req#*@@}"
      step_ok "$jobs_json" "${rest%%@@*}" "${rest#*@@}"
      src=$?
      if (( src == 1 )); then all=0; break; fi
      (( src == 0 )) || cannot "could not evaluate the step table against $wf run $id"
    done
    if (( all == 1 )); then exercised_by="$id"; break; fi
  done
  if [[ -n "$exercised_by" ]]; then
    echo "ok:   $wf exercised its converted step(s) in run $exercised_by ($scanned log(s) scanned)"
  else
    echo "wait: $wf has $checked completed run(s) since the merge but none ran its converted step(s) successfully"
    unexercised+=("$wf")
  fi
done

if (( refused > 0 )); then exit 1; fi
if (( ${#unexercised[@]} == 0 )); then
  echo "PASS: every tracked workflow exercised its converted step(s) since the merge, and no scanned log carries a refusal marker"
  exit 0
fi
if (( now_epoch >= deadline_epoch )); then
  echo "ACTION REQUIRED: the ${WAIT_DAYS}-day wait budget since the merge is spent and these never exercised their converted step(s): ${unexercised[*]}. Exercise each with a sanctioned dispatch (a dispatch that writes needs its own approval) or accept it explicitly on the tracker, then close it and remove the follow-through label."
  exit 5
fi
echo "NOT YET: ${#unexercised[@]} workflow(s) have not exercised their converted step(s) yet: ${unexercised[*]}"
exit 2
