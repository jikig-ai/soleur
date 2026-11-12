#!/usr/bin/env bash
# main-health-monitor-mutations-12626.sh — scheduled-run confirmation probe for #12626
# (the dedicated `test-webplat-mutations` leg fix, merged 2026-11-12T19:46:34Z as
# squash 34634d7431 via PR #12654).
#
# CREDENTIAL POSTURE: needs GH_TOKEN (the tracker directive carries
# `secrets=GH_TOKEN`). With GH_TOKEN absent every gh call fails -> exit 3
# forever, so refuse loudly instead (sibling convention: ci-push-dedupe-soak-9512.sh).
#
# Property. Exit 0 only when >= MIN_GREEN (2) completed post-merge SCHEDULED
# main-health-monitor.yml runs are all green AND each carries all three
# `test-webplat-mutations (*)` jobs green. A scheduled run is a
# workflow_dispatch run whose actor.login == "soleur-ai[bot]" — the Inngest cron
# `cron-main-health-monitor` (`0 */6 * * *` -> 00/06/12/18Z) dispatches through a
# GitHub-App installation token that mints that actor. Manual dispatches (any
# other actor login) are never cadence evidence in either direction: a green
# manual dispatch does not count toward MIN_GREEN and a red one is not a FAIL
# (it does not exercise the cron dispatch path). `cancelled`/in-progress runs are
# excluded from the sample — a cancel is operational, not regression evidence;
# the "run never happened" arm is owned by the missed-check-in watchdog
# `sentry_cron_monitor.main_health_monitor`. `created_at >= MERGE_TS` pins the
# window to post-merge code: runs before it exercised the pre-split layout and
# are not evidence about this fix.
#
# Any scheduled run concluding `failure`, or a green scheduled run whose jobs
# list is missing a `test-webplat-mutations` leg or shows one non-success, is
# exit 1 — the leg-silently-dropped shape (matrix+EXPECTED_LEGS edited
# consistently -> a green run that never executed the battery) is exactly what
# the per-run jobs read exists to see, and it is not visible in the run-level
# conclusion. Jobs reads are bounded to the newest MAX_EVAL qualifying runs.
#
# Followthrough-convention exit vocabulary:
#   0 = PASS    1 = FAIL (a non-success scheduled run, or a missing/red mut leg)
#   2 = NOT YET (< MIN_GREEN qualifying completed scheduled runs, no failure evidence)
#   3 = CANNOT ESTABLISH (GH_TOKEN unset, a tool missing, or a gh/parse failure)
#   78 = refused to run under xtrace while GH_TOKEN is set (#7797)
#
# Prints exactly one `CONFIRM key=value...` line per verdict; the sweeper folds
# the probe's last-4KB output into a <details> block on the tracker comment
# (sweep-followthroughs.sh), so the line must stay self-reading.
#
# Test seams (the sweeper runs this under env -i, so they are inert in
# production): PATH controls which `gh` resolves (fixture suites prepend a fake
# bin dir); nothing else is read from the environment.
#
# RETIREMENT: when the tracker carrying this probe's `soleur:followthrough`
# directive closes, delete this file, its .test.sh, the
# `scripts/followthroughs/main-health-monitor-mutations-12626` run_suite line in
# scripts/test-all.sh, and its rows in scripts/suite-shard-legs.tsv and
# scripts/suite-durations.tsv.
set -uo pipefail

# xtrace refusal: never let a live credential reach a trace (see #7797)
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}${GITHUB_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO="jikig-ai/soleur"
WORKFLOW="main-health-monitor.yml"
MERGE_TS="2026-11-12T19:46:34Z"   # #12654 squash-merged at this instant; post-merge window is >=
BOT_ACTOR="soleur-ai[bot]"      # the Inngest cron's GitHub-App installation identity
MIN_GREEN=2                     # tracker may close only after this many all-green scheduled runs
MAX_EVAL=8                      # bounds jobs reads: newest 8 qualifying runs (~2 days of cadence)
MUT_LEG_PREFIX="test-webplat-mutations ("
MUT_LEG_MIN=3                   # approval-guard1-mutation, destroy-ask-mutation, home-census-mutations

# every external command this probe runs by name, builtins aside (a missing one
# is exit 3, never a silent verdict; the needcomplete row drives it)
for need in gh jq; do
  command -v "$need" >/dev/null 2>&1 || { echo "CANNOT ESTABLISH: $need is not installed"; exit 3; }
done

[ -n "${GH_TOKEN:-}" ] || { echo "CANNOT ESTABLISH: GH_TOKEN is not set (the tracker directive must declare secrets=GH_TOKEN)"; exit 3; }

fail_api() { echo "CANNOT ESTABLISH: GitHub API read failed ($1)"; exit 3; }
api() { gh api "$@" 2>/dev/null; }

runs_json="$(api "repos/$REPO/actions/workflows/$WORKFLOW/runs?event=workflow_dispatch&per_page=30")" \
  || fail_api "workflow runs listing"
printf '%s' "$runs_json" | jq -e '.workflow_runs | type == "array"' >/dev/null 2>&1 \
  || fail_api "workflow runs listing unparseable"

# Qualifying scheduled runs: the cron's bot actor, on main, post-merge window,
# completed (success or failure — cancelled/in-progress excluded), newest first,
# bounded. A `total_count` we never read: completeness comes from enumerating
# the listed runs, not from trusting a count (the sample shrinks over time).
qual_tsv="$(printf '%s' "$runs_json" | jq -r --arg actor "$BOT_ACTOR" --arg since "$MERGE_TS" --argjson cap "$MAX_EVAL" '
  [.workflow_runs[]
   | select(.actor.login == $actor)
   | select(.head_branch == "main")
   | select(.created_at >= $since)
   | select(.conclusion == "success" or .conclusion == "failure")]
  | sort_by(.created_at) | reverse | .[0:$cap][]
  | "\(.id)\t\(.conclusion)\t\(.created_at)"')" \
  || fail_api "workflow runs projection"

green=0
evidence=""
while IFS=$'\t' read -r id conc ts; do
  [ -n "$id" ] || continue
  if [ "$conc" != "success" ]; then
    evidence="${evidence} run=${id}@${ts}(conclusion=${conc});"
    continue
  fi
  jobs_json="$(api "repos/$REPO/actions/runs/$id/jobs?per_page=100")" \
    || fail_api "jobs listing for run $id"
  mut_counts="$(printf '%s' "$jobs_json" | jq -r --arg p "$MUT_LEG_PREFIX" '
      [.jobs[] | select(.name | startswith($p))] as $m
      | "\($m | length)\t\([$m[] | select(.conclusion == "success")] | length)"' 2>/dev/null)" \
    || fail_api "jobs unparseable for run $id"
  mut_total="${mut_counts%%$'\t'*}"
  mut_green="${mut_counts##*$'\t'}"
  if [ "$mut_total" -lt "$MUT_LEG_MIN" ] || [ "$mut_green" != "$mut_total" ]; then
    evidence="${evidence} run=${id}@${ts}(mut-legs=${mut_green}/${mut_total}<${MUT_LEG_MIN});"
    continue
  fi
  green=$((green + 1))
done <<< "$qual_tsv"

if [ -n "$evidence" ]; then
  printf 'CONFIRM verdict=fail green_scheduled=%s evidence=%s\n' "$green" "$evidence"
  exit 1
fi
if [ "$green" -ge "$MIN_GREEN" ]; then
  printf 'CONFIRM verdict=pass green_scheduled=%s threshold=%s\n' "$green" "$MIN_GREEN"
  exit 0
fi
printf 'CONFIRM verdict=not-yet green_scheduled=%s threshold=%s\n' "$green" "$MIN_GREEN"
exit 2
