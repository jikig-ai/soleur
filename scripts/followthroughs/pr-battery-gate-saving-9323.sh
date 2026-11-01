#!/usr/bin/env bash
# pr-battery-gate-saving-9323.sh — post-merge soak probe for #9323 (ADR-262).
#
# Does the pull_request path-gate on the five self-test mutation batteries actually save runner time,
# without letting a break through? Two conditions, both required for exit 0:
#   (a) mean billable runner-minutes per qualifying ci.yml pull_request run is at least 20 below the
#       pinned pre-change baseline (BASELINE_RUNNER_MIN, below), and
#   (b) no escape: for the qualifying PRs, the ci.yml `push` run on that PR's merge commit is not red.
#       A push run that is absent or not yet complete is NOT YET (exit 2), never "no escape".
# Mean `test-scripts*` queue wait is printed for context and NEVER affects the exit code (load is not
# controllable, and the issue's queue-wait target is "at similar load"). Only that figure is informational:
# the saving threshold IS the verdict.
#
# BASELINE_RUNNER_MIN=76 was measured on 2026-09-30 over the last 15 completed ci.yml runs (all events) as the
# sum of (completed_at - started_at) over every non-skipped job of a run, in minutes (issue #9323). The probe
# measures the same quantity over pull_request runs only, so the comparison is close to, not exactly, like
# for like; the 20-minute margin is what absorbs that.
#
# Qualifying run: ci.yml, event pull_request, completed with conclusion `success`, created after the merge
# time of PR 9324 (the change itself — its own run is excluded by that window), authored by a human (a bot PR
# carries synthetic checks and never runs the real legs), whose PR touches NONE of the gate-machinery paths
# (those arm every battery by design), and which actually ran a `test-scripts*` job. Red, cancelled and
# aborted runs are excluded because they stop early and would read as "cheap". Needs >= MIN_RUNS qualifying
# runs, else NOT YET — never a fail.
#
# WINDOW STARVATION (measured on the sweeps of 2026-10-09..2026-10-24): one page is the ~100 most recent
# completed pull_request runs — roughly 24 h at this repo's volume — and a qualifying run is only ~5-15%
# of one (most runs are cancelled or red, machinery-touching PRs arm every battery by design, and bot PRs
# never run the legs). MIN_RUNS inside a single page needs a >20% qualifying day; the sweeps saw 0-12 of
# the required 20 for three weeks, so the soak could not conclude. The runs list is therefore PAGINATED
# (up to PAGE_CAP pages of 100) and the detail scan is bounded separately by EXAMINE_CAP, because each
# candidate costs 1-3 API calls (a head-branch lookup when needed, a PR-files read always, a jobs read
# when it clears the machinery filter) inside the sweeper's ~1000-requests-per-hour budget. Neither cap
# loosens the bar: MIN_RUNS qualifying runs are still required for a verdict, and a capped scan reports
# NOT YET, never a fail.
#
# HEAD-BRANCH RESOLUTION (measured 2026-10-25): the runs API only populates `pull_requests` while the PR
# is still OPEN — 2 of 13 successful human runs on the latest page carried one. A merged PR's run (the
# exact set the escape check needs) reports the field EMPTY, and an open-PR candidate reaches the escape
# arm with no merge commit and lands in `pending` — so the pre-resolution probe could never converge at
# any page count: the candidates it could see were the ones that could never satisfy arm (b). A run
# whose `pull_requests` is empty is therefore resolved through `pulls?head=<owner>:<head_branch>` —
# `.[0]`, the newest PR on that branch — before the machinery filter. Residual: a branch reused for a
# second PR resolves to the newer one, so the machinery filter reads the newer PR's file set — a touch
# present only in the newer diff over-includes (conservative: the candidate drops out), a touch present
# only in the older under-includes (a wrong-direction miss, priced as rare; the alternative — no
# resolution — is the deadlock above). Only runs whose head_repository is THIS repo are resolved:
# a fork PR's run carries the fork's branch name, which can collide with a same-repo branch, and
# head=<owner>:<branch> can never name the fork's own PR anyway.
#
# Exit semantics (sweep-followthroughs.sh contract):
#   0 = PASS    soak holds        1 = FAIL   mean saving too small, or an escape was found
#   2 = NOT YET too few qualifying runs, PR not merged yet, or a push run still pending
#   3 = CANNOT ESTABLISH  gh/jq/GH_TOKEN missing, or a GitHub API read failed (the sweeper retries)
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

REPO="jikig-ai/soleur"
GATE_PR=9324
BASELINE_RUNNER_MIN=76
REQUIRED_SAVING_MIN=20
MIN_RUNS=20
MAX_RUNS=40          # bounds API use: the sweeper's GITHUB_TOKEN allows ~1000 requests/hour/repo
PAGE_CAP=6           # list calls: 6 pages x 100 completed pull_request runs ~= 6 days at current volume
EXAMINE_CAP=220      # detail calls: <=3 reads per candidate (head lookup, files, jobs), ~660 worst case
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for need in gh jq; do
  command -v "$need" >/dev/null 2>&1 || { echo "CANNOT ESTABLISH: $need is not installed"; exit 3; }
done
[ -n "${GH_TOKEN:-}" ] || { echo "CANNOT ESTABLISH: GH_TOKEN is not set (the tracker directive must declare secrets=GH_TOKEN)"; exit 3; }

# the gate-machinery paths, single-sourced from the lib that declares them
# shellcheck source=scripts/lib/test-relevance-paths.sh
source "$HERE/../lib/test-relevance-paths.sh" 2>/dev/null || { echo "CANNOT ESTABLISH: cannot read test-relevance-paths.sh"; exit 3; }
MACHINERY=("${PR_GATE_MACHINERY_PATHS[@]}" "scripts/lib/test-relevance-paths.sh")

api() { gh api "$@" 2>/dev/null; }
fail_api() { echo "CANNOT ESTABLISH: GitHub API read failed ($1)"; exit 3; }

# Arm (a) verdict input is the lever's own realized saving, drift-immune (the 2026-10-28 investigation on the tracker:
# whole-run billable means measure suite growth, not the gate — same-shape pre-gate control ~113 vs post-gate ~266,
# against an all-events pinned baseline of 76). For every qualifying run the probe enumerates its suite-timings-*
# artifacts, sums the committed suite-durations{,-heavy}.tsv prices of the `label\t0\tskip=relevance` rows, and the
# mean over qualifying runs is compared to REQUIRED_SAVING_MIN: under it the probe FAILs, honestly. A qualifying run
# whose timing evidence is missing or unreadable is NOT YET (evidence absence is not a zero, never a FAIL input).
# The gated suite set is derived from the runner's own `skip_suite "<label>" "relevance"` call sites (each guarded by a
# `_diff_touches --pr-gated` arm), as ci-battery-gate-replay.sh derives its battery list — a new gated battery is
# priced without any edit here. ART_READ_CAP bounds artifact reads inside the sweeper's hourly token budget, preflighted
# by a rate_limit read. The whole-run mean and the queue-wait mean are printed, informational only.
ART_READ_CAP=60
GATED_SUITES="$({ sed 's/[[:space:]]*#.*$//' "$HERE/../test-all.sh" | grep -oE 'skip_suite "[^"]+" "relevance"' | sed 's/skip_suite "//;s/" "relevance"//'; } | LC_ALL=C sort -u)" \
  || { echo "CANNOT ESTABLISH: no skip_suite relevance call sites in test-all.sh"; exit 3; }
[ -n "$GATED_SUITES" ] || { echo "CANNOT ESTABLISH: no skip_suite relevance call sites in test-all.sh"; exit 3; }
PRICE="$(awk -F'\t' '$2 ~ /^[0-9]+$/ { p[$1] = $2 / 60000 } END { for (s in p) printf "%s\t%.4f\n", s, p[s] }' \
  "$HERE/../suite-durations.tsv" "$HERE/../suite-durations-heavy.tsv" 2>/dev/null)" \
  || { echo "CANNOT ESTABLISH: cannot read suite-durations TSVs"; exit 3; }
[ -n "$PRICE" ] || { echo "CANNOT ESTABLISH: suite-durations TSVs hold no priced rows"; exit 3; }

rl="$(api "rate_limit")" || fail_api "rate_limit preflight"
rl_rem="$(jq -r '.resources.core.remaining // 0' <<<"$rl" 2>/dev/null)"
[[ "$rl_rem" =~ ^[0-9]+$ ]] || fail_api "rate_limit preflight (malformed body)"
# a quota cut is NOT YET — the sweep is retried when the hourly window rolls; never a failed read, never a verdict
need_min=$(( 3 * MAX_RUNS + PAGE_CAP + ART_READ_CAP + 20 ))
if (( rl_rem < need_min )); then
  echo "NOT YET: API quota remaining=$rl_rem under the $need_min-request floor for a full sweep; the sweeper retries"; exit 2
fi
WORK="$(mktemp -d "${TMPDIR:-/var/tmp}/pbg9323.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT

merged_at="$(api "repos/$REPO/pulls/$GATE_PR" --jq '.merged_at // empty')" || fail_api "pull $GATE_PR"
[ -n "$merged_at" ] || { echo "NOT YET: PR $GATE_PR is not merged"; exit 2; }

# Paginate the runs list: a page is 100 completed pull_request runs, so PAGE_CAP bounds the scan to
# ~PAGE_CAP days of history at current volume. A short page (< 100 raw runs) is the last one — filtering
# happens client-side, so the raw length, not the filtered count, decides whether another page exists.
runs="[]"
pages=0
while (( pages < PAGE_CAP )); do
  pages=$((pages + 1))
  resp="$(api "repos/$REPO/actions/workflows/ci.yml/runs?event=pull_request&status=completed&per_page=100&created=%3E$merged_at&page=$pages")" \
    || fail_api "ci.yml runs (page $pages)"
  [ -n "$resp" ] || fail_api "ci.yml runs (page $pages, empty body)"
  raw_n="$(jq -r '.workflow_runs | length' <<<"$resp" 2>/dev/null)"
  [[ "$raw_n" =~ ^[0-9]+$ ]] || fail_api "ci.yml runs (page $pages, malformed body)"
  chunk="$(jq '[.workflow_runs[] | select(.conclusion == "success" and (.actor.type // "") != "Bot")
               | {id, conclusion, pr: (.pull_requests[0].number // "-"), branch: (.head_branch // "-"),
                  hrepo: (.head_repository.full_name // "-")}]' <<<"$resp")" \
    || fail_api "ci.yml runs (page $pages, filter failed)"
  runs="$(jq --argjson c "$chunk" '. + $c' <<<"$runs")" || fail_api "ci.yml runs (page $pages, merge failed)"
  (( raw_n < 100 )) && break
done

n=0; sum_min=0; green_prs=""; green_ids=""; qwait_sum=0; qwait_n=0; examined=0
while read -r id _ pr branch hrepo; do
  [ -n "$id" ] || continue
  (( n < MAX_RUNS && examined < EXAMINE_CAP )) || break
  examined=$((examined + 1))
  # `pull_requests` is empty once the PR merges (see HEAD-BRANCH RESOLUTION above): resolve the run's
  # head_branch back to its PR — `state=all`, because the merged set is exactly what the escape arm needs.
  # Only same-repo heads: a fork run's head_branch can collide with a same-repo branch name and would
  # misresolve to the wrong PR (head=<owner>:<branch> cannot see the fork's PR).
  if [[ "$pr" == "-" || -z "$pr" ]]; then
    [[ "$branch" != "-" && -n "$branch" && "$hrepo" == "$REPO" ]] || continue
    pr="$(api "repos/$REPO/pulls?head=${REPO%%/*}:$branch&state=all&per_page=1" --jq '.[0].number // empty')" \
      || fail_api "head-branch PR lookup ($branch)"
    [ -n "$pr" ] || continue
  fi
  files="$(api "repos/$REPO/pulls/$pr/files?per_page=100" --jq '.[].filename')" || fail_api "pull $pr files"
  touches=0
  for m in "${MACHINERY[@]}"; do
    case "$files" in *"$m"*) touches=1 ;; esac
  done
  (( touches == 0 )) || continue
  jobs_json="$(api "repos/$REPO/actions/runs/$id/jobs?per_page=100")" || fail_api "run $id jobs"
  # a run that never executed a test-scripts* job measures nothing about the batteries
  ran_scripts="$(jq '[.jobs[] | select((.name | startswith("test-scripts")) and .conclusion != "skipped")] | length' <<<"$jobs_json")"
  [ "${ran_scripts:-0}" -gt 0 ] 2>/dev/null || continue
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
  green_prs="$green_prs $pr"; green_ids="$green_ids $id"
done < <(jq -r '.[] | "\(.id) \(.conclusion) \(.pr) \(.branch) \(.hrepo)"' <<<"$runs")

if (( n < MIN_RUNS )); then
  echo "NOT YET: $n qualifying run(s) in $examined candidate(s) across $pages page(s) since $merged_at (need >= $MIN_RUNS)"; exit 2
fi

# --- realized saving per qualifying run: price the `label\t0\tskip=relevance` rows of the gated battery set in the
# run's suite-timings-* artifacts. Artifact evidence that cannot be read is NOT YET (evidence_absent), never a zero.
real_sum=0; evidence_absent=0; art_reads=0
for rid in $green_ids; do
  (( art_reads < ART_READ_CAP )) || { evidence_absent=$((evidence_absent + 1)); continue; }
  arts="$(api "repos/$REPO/actions/runs/$rid/artifacts?per_page=100")" || { evidence_absent=$((evidence_absent + 1)); continue; }
  art_reads=$((art_reads + 1))
  aids="$(jq -r '.artifacts[]? | select(.name | startswith("suite-timings")) | .id' <<<"$arts" 2>/dev/null)"
  [ -n "$aids" ] || { evidence_absent=$((evidence_absent + 1)); continue; }
  run_saved=0; have_any=0
  while IFS= read -r aid; do
    (( art_reads < ART_READ_CAP )) || break
    art_reads=$((art_reads + 1))
    gh api "repos/$REPO/actions/artifacts/$aid/zip" > "$WORK/art-$aid.zip" 2>/dev/null || continue
    tsv="$(unzip -p "$WORK/art-$aid.zip" suite-timings.tsv 2>/dev/null || unzip -p "$WORK/art-$aid.zip" 2>/dev/null)" || continue
    saved="$(printf '%s\n' "$tsv" | awk -F'\t' -v gs="$GATED_SUITES" -v P="$PRICE" '
      BEGIN { ng = split(gs, g, "\n"); for (i = 1; i <= ng; i++) gate[g[i]] = 1
              np = split(P, pl, "\n"); for (i = 1; i <= np; i++) { split(pl[i], kv, "\t"); price[kv[1]] = kv[2] } }
      $2 == 0 && $3 == "skip=relevance" && ($1 in gate) { s += price[$1]; seen[$1] = 1 }
      END { printf "%.4f", s + 0 }')"
    [[ "$saved" =~ ^[0-9.]+$ ]] && { run_saved="$(awk -v a="$run_saved" -v b="$saved" 'BEGIN{print a+b}')"; have_any=1; }
  done <<<"$aids"
  (( have_any == 1 )) || { evidence_absent=$((evidence_absent + 1)); continue; }
  real_sum="$(awk -v a="$real_sum" -v b="$run_saved" 'BEGIN{print a+b}')"
done
evidenced=$((n - evidence_absent))
if (( evidenced < MIN_RUNS )); then
  echo "NOT YET: $evidence_absent of $n qualifying runs lack readable suite-timings-* artifact evidence ($evidenced evidenced, need >= $MIN_RUNS)"; exit 2
fi
real_mean="$(awk -v s="$real_sum" -v n="$evidenced" 'BEGIN { printf "%.1f", s / n }')"

mean="$(awk -v s="$sum_min" -v n="$n" 'BEGIN { printf "%.1f", s / n }')"
qmean="n/a"; (( qwait_n > 0 )) && qmean="$(awk -v s="$qwait_sum" -v n="$qwait_n" 'BEGIN { printf "%.1f", s / n }')"
echo "qualifying_runs=$n evidenced_runs=$evidenced mean_runner_min=$mean required_saving=$REQUIRED_SAVING_MIN test_scripts_mean_queue_wait_min=$qmean (queue wait is informational only) candidates_examined=$examined pages=$pages"

# A qualifying PR in one of three states: merged (state closed + merged_at set — the escape arm checks
# its push run), open (a merge commit may exist as a test merge, but no main-side push run can —
# pending, NOT YET), or CLOSED UNMERGED (head-branch resolution admits these; no merge commit will ever
# exist — dropped, never pending: the PR's verdict was never committed to main, so there is nothing to
# catch). merge_commit_sha CANNOT be the discriminator: the API reports the TEST-merge sha there for
# open and closed-unmerged PRs alike (verified on #11038: state=closed, merged_at=null, sha set) — it is
# null only before the test merge is computed. state=closed + merged_at=null is the drop condition.
escapes=0; pending=0; dropped=0
for pr in $green_prs; do
  meta="$(api "repos/$REPO/pulls/$pr" --jq '"\(.merge_commit_sha // "") \(.state // "") \(.merged_at // "")"')" || fail_api "pull $pr merge sha"
  sha="${meta%% *}"; rest="${meta#* }"; pstate="${rest%% *}"; pr_merged_at="${rest##* }"
  if [[ "$pstate" == "closed" && -z "$pr_merged_at" ]]; then dropped=$((dropped + 1)); continue; fi
  [ -n "$sha" ] || { pending=$((pending + 1)); continue; }
  concl="$(api "repos/$REPO/actions/workflows/ci.yml/runs?event=push&head_sha=$sha" --jq '.workflow_runs[0].conclusion // empty')" || fail_api "push run for $sha"
  case "$concl" in
    failure|timed_out|startup_failure|action_required) echo "ESCAPE: PR $pr was green but its merge-commit push run on $sha is $concl"; escapes=$((escapes + 1)) ;;
    success) : ;;
    *) pending=$((pending + 1)) ;;   # absent or not yet complete: not evidence of "no escape"
  esac
done

if (( dropped > 0 )); then echo "note: $dropped qualifying PR(s) closed unmerged — no merge commit exists; excluded from the escape check"; fi
if (( escapes > 0 )); then echo "FAIL: $escapes escape(s); widen the declaring array (ADR-262 R1) or revert the PR arm"; exit 1; fi
if (( pending > 0 )); then echo "NOT YET: $pending qualifying PR(s) have no completed push run on their merge commit"; exit 2; fi
echo "realized_saving_min=$real_mean over $evidenced evidenced runs (mean_runner_min=$mean is informational: whole-run billing drifts with suite growth, the verdict prices only the gate's own skips)"
if awk -v m="$real_mean" -v r="$REQUIRED_SAVING_MIN" 'BEGIN { exit !(m >= r) }'; then
  echo "PASS: mean realized saving $real_mean suite-min/run meets the $REQUIRED_SAVING_MIN bar over $evidenced runs, no escapes in $n runs"; exit 0
fi
echo "FAIL: mean realized saving $real_mean suite-min/run is under the $REQUIRED_SAVING_MIN bar; widen nothing, but check the gate is declining (grep -F '[skip]' in a docs-only PR's test-scripts log) and the replay rates (scripts/ci-battery-gate-replay.sh)"; exit 1
