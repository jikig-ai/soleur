#!/usr/bin/env bash
# pr-battery-gate-saving-9323.sh — post-merge soak probe for #9323 (ADR-262).
#
# Does the pull_request path-gate on the five self-test mutation batteries actually save runner time,
# without letting a break through? Two conditions, both required for exit 0:
#   (a) mean billable runner-minutes per qualifying ci.yml pull_request run is at least 20 below the
#       pinned pre-change baseline (BASELINE_RUNNER_MIN, below), and
#   (b) no escape: for the qualifying PRs whose PR run was green, the ci.yml `push` run on that PR's
#       merge commit is not red.
# Mean `test-scripts*` queue wait is printed for context and NEVER affects the exit code (load is not
# controllable, and the issue's queue-wait target is "at similar load").
#
# BASELINE_RUNNER_MIN=76 was measured on 2026-09-30 over the last 15 completed ci.yml runs as the sum of
# (completed_at - started_at) over every non-skipped job of a run, in minutes (issue #9323). The probe
# measures the same quantity, so the comparison is like for like.
#
# Qualifying run: ci.yml, event pull_request, completed, not cancelled, created after the merge time of
# PR 9324 (the change itself — its own run is excluded by that window), authored by a human (a bot PR
# carries synthetic checks and never runs the real legs), and whose PR touches NONE of the gate-machinery
# paths (those arm every battery by design, so they would measure the un-gated cost). Needs >= MIN_RUNS
# qualifying runs, else NOT YET — never a fail.
#
# Exit semantics (sweep-followthroughs.sh contract):
#   0 = PASS    soak holds        1 = FAIL   mean saving too small, or an escape was found
#   2 = NOT YET too few qualifying runs, PR not merged yet, or gh/jq/GH_TOKEN missing
#   3 = CANNOT ESTABLISH  a GitHub API read failed (the sweeper retries)
#   78 = refused to run under xtrace while GH_TOKEN is set (#7797)
#
# RETIREMENT: when #9323 closes, delete this file, its .test.sh, the run_suite line in scripts/test-all.sh,
# the `scripts/followthroughs/pr-battery-gate-saving-9323` rows in scripts/suite-shard-legs.tsv and
# scripts/suite-durations.tsv, and its mention in ADR-262's Consequences.
set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}${GITHUB_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO="${FT_REPO:-jikig-ai/soleur}"
GATE_PR="${FT_GATE_PR:-9324}"
BASELINE_RUNNER_MIN=76
REQUIRED_SAVING_MIN=20
MIN_RUNS=20
MAX_RUNS=40          # bounds API use: the sweeper's GITHUB_TOKEN allows ~1000 requests/hour/repo
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for need in gh jq; do
  command -v "$need" >/dev/null 2>&1 || { echo "NOT YET: $need is not installed"; exit 2; }
done
[ -n "${GH_TOKEN:-}" ] || { echo "NOT YET: GH_TOKEN is not set"; exit 2; }

# the gate-machinery paths, single-sourced from the lib that declares them
# shellcheck source=scripts/lib/test-relevance-paths.sh
source "$HERE/../lib/test-relevance-paths.sh" 2>/dev/null || { echo "CANNOT ESTABLISH: cannot read test-relevance-paths.sh"; exit 3; }
MACHINERY=("${PR_GATE_MACHINERY_PATHS[@]}" "scripts/lib/test-relevance-paths.sh")

api() { gh api "$@" 2>/dev/null; }
fail_api() { echo "CANNOT ESTABLISH: GitHub API read failed ($1)"; exit 3; }

merged_at="$(api "repos/$REPO/pulls/$GATE_PR" --jq '.merged_at // empty')" || fail_api "pull $GATE_PR"
[ -n "$merged_at" ] || { echo "NOT YET: PR $GATE_PR is not merged"; exit 2; }

runs="$(api "repos/$REPO/actions/workflows/ci.yml/runs?event=pull_request&status=completed&per_page=100&created=%3E$merged_at" \
        --jq '[.workflow_runs[] | select(.conclusion != "cancelled" and (.actor.type // "") != "Bot")
               | {id, conclusion, pr: (.pull_requests[0].number // empty)}]')" || fail_api "ci.yml runs"
[ -n "$runs" ] || fail_api "ci.yml runs (empty body)"

n=0; sum_min=0; green_prs=""; qwait_sum=0; qwait_n=0
while read -r id conclusion pr; do
  [ -n "$id" ] && [ -n "$pr" ] || continue
  (( n < MAX_RUNS )) || break
  files="$(api "repos/$REPO/pulls/$pr/files?per_page=100" --jq '.[].filename')" || fail_api "pull $pr files"
  touches=0
  for m in "${MACHINERY[@]}"; do
    case "$files" in *"$m"*) touches=1 ;; esac
  done
  (( touches == 0 )) || continue
  jobs_json="$(api "repos/$REPO/actions/runs/$id/jobs?per_page=100")" || fail_api "run $id jobs"
  run_min="$(jq -r '[.jobs[] | select(.conclusion != "skipped" and .started_at and .completed_at)
                    | ((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601))] | add // 0 | . / 60' <<<"$jobs_json")"
  [ -n "$run_min" ] || fail_api "run $id duration"
  sum_min="$(awk -v a="$sum_min" -v b="$run_min" 'BEGIN { print a + b }')"
  while read -r qw; do
    [ -n "$qw" ] || continue
    qwait_sum="$(awk -v a="$qwait_sum" -v b="$qw" 'BEGIN { print a + b }')"; qwait_n=$((qwait_n + 1))
  done < <(jq -r '.jobs[] | select(.name | startswith("test-scripts")) | select(.started_at and .created_at)
                  | ((.started_at | fromdateiso8601) - (.created_at | fromdateiso8601)) / 60' <<<"$jobs_json")
  n=$((n + 1))
  [ "$conclusion" = "success" ] && green_prs="$green_prs $pr"
done < <(jq -r '.[] | "\(.id) \(.conclusion) \(.pr)"' <<<"$runs")

if (( n < MIN_RUNS )); then
  echo "NOT YET: $n qualifying run(s) since $merged_at (need >= $MIN_RUNS)"; exit 2
fi

mean="$(awk -v s="$sum_min" -v n="$n" 'BEGIN { printf "%.1f", s / n }')"
qmean="n/a"; (( qwait_n > 0 )) && qmean="$(awk -v s="$qwait_sum" -v n="$qwait_n" 'BEGIN { printf "%.1f", s / n }')"
echo "qualifying_runs=$n mean_runner_min=$mean baseline=$BASELINE_RUNNER_MIN required_saving=$REQUIRED_SAVING_MIN (informational) test_scripts_mean_queue_wait_min=$qmean"

escapes=0
for pr in $green_prs; do
  sha="$(api "repos/$REPO/pulls/$pr" --jq '.merge_commit_sha // empty')" || fail_api "pull $pr merge sha"
  [ -n "$sha" ] || continue
  concl="$(api "repos/$REPO/actions/workflows/ci.yml/runs?event=push&head_sha=$sha" --jq '.workflow_runs[0].conclusion // empty')" || fail_api "push run for $sha"
  case "$concl" in failure|timed_out|startup_failure) echo "ESCAPE: PR $pr was green but its merge-commit push run on $sha is $concl"; escapes=$((escapes + 1)) ;; esac
done

if (( escapes > 0 )); then echo "FAIL: $escapes escape(s); widen the declaring array (ADR-262 R1) or revert the PR arm"; exit 1; fi
if awk -v m="$mean" -v b="$BASELINE_RUNNER_MIN" -v r="$REQUIRED_SAVING_MIN" 'BEGIN { exit !(m <= b - r) }'; then
  echo "PASS: mean $mean runner-min per run is at least $REQUIRED_SAVING_MIN below the $BASELINE_RUNNER_MIN baseline, no escapes in $n runs"; exit 0
fi
echo "FAIL: mean $mean runner-min per run is not $REQUIRED_SAVING_MIN below the $BASELINE_RUNNER_MIN baseline"; exit 1
