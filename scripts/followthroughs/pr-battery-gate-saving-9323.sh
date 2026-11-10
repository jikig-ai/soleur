#!/usr/bin/env bash
# pr-battery-gate-saving-9323.sh — post-merge soak probe for #9323 (ADR-262).
#
# Does the pull_request path-gate on the five self-test mutation batteries actually save runner time,
# without letting a break through? Two conditions, both required for exit 0:
#   (a) the mean REALIZED saving per qualifying ci.yml pull_request run — the committed
#       suite-durations{,-heavy}.tsv prices of the `label\t0\tskip=relevance` rows that run's
#       suite-timings-(scripts|scripts-heavy)-N artifacts record, deduped per label across the run's
#       artifacts — is at least REQUIRED_SAVING_MIN (20) suite-minutes, and
#   (b) no escape: for the qualifying PRs, the ci.yml `push` run on that PR's merge commit is not red
#       on a gated test-scripts* job — a red run whose failed jobs are all outside the gated family
#       is reported in the note line (`unrelated`), never counted (2026-11-08 classifier ruling).
#       A push run that is absent, incomplete, or inconclusive falls back to the merge commit's `merge_group`
#       run — ADR-276's full-battery authority; a queue-merged PR's merge commit carries merge_group
#       runs, never a push run (#12478) — classified identically. No conclusive run of either event
#       is NOT YET (exit 2), never "no escape".
# The realized-skip measure is drift-immune (the 2026-10-28 investigation on the tracker: whole-run
# billable means measure suite growth, not the gate — same-shape pre-gate control ~113 vs post-gate
# ~266). BASELINE_RUNNER_MIN below is HISTORICAL — the retired whole-run criterion's pin (measured
# 2026-09-30 over the last 15 completed ci.yml runs of all events), printed as baseline_runner_min
# for context only; the verdict prices only the gate's own skips. Mean `test-scripts*` queue wait is
# printed for context and NEVER affects the exit code (load is not controllable, and the issue's
# queue-wait target is "at similar load").
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
# arm with no merge-commit evidence to check (the `open` bucket today — see the escape arm) — so the
# pre-resolution probe could never converge at any page count: the candidates it could see were the ones
# that could never satisfy arm (b). A run whose `pull_requests` is empty is therefore resolved through
# `pulls?head=<owner>:<head_branch>` — `.[0]`, the newest PR on that branch — before the machinery filter.
# Residual: a branch reused for a second PR resolves to the newer one, so the machinery filter reads the
# newer PR's file set — a touch present only in the newer diff over-includes (conservative: the candidate
# drops out), a touch present only in the older under-includes (a wrong-direction miss, priced as rare;
# the alternative — no resolution — is the deadlock above). Only runs whose head_repository is THIS repo
# are resolved: a fork PR's run carries the fork's branch name, which can collide with a same-repo branch,
# and head=<owner>:<branch> can never name the fork's own PR anyway.
#
# BOUNDED-PARALLEL READS (#12360): the four serial read phases (runs pages, candidate examine, artifact
# listings+downloads, escape arm) starved inside every wall the probe can occupy (~11 min measured
# 2026-11-07 under PBG_UNBOUNDED=1 for qualifying_runs=40 evidenced_runs=21). Each phase now runs its
# independent units through a bounded `&`-worker pool (wait -n -p reap, width PBG_JOBS) whose workers
# write per-unit result FILES under $WORK; the parent aggregates the rows in candidate order, so the
# verdict path is bit-identical to the serial one. Workers never exit, never print probe output and
# never call cut_ny/fail_api — the parent owns every verdict emission; a worker that dies without its
# row file is CANNOT ESTABLISH, never a skipped unit. The api()/api_bin() per-call deadline contract is
# unchanged: `( )`/`&` subshells share the parent's SECONDS epoch, so the min(60, END-SECONDS-5) cap
# works inside workers exactly as before (a `bash -c`/xargs child would restart SECONDS and silently
# break it — one reason the pool is `&`-based, mirroring scripts/test-all.sh's _pj_fill/_pj_reap idiom
# ~:2342-2419, including its bash<5.1 serial-degrade gate at :2229-2231).
#
# Exit semantics (sweep-followthroughs.sh contract):
#   0 = PASS    soak holds        1 = FAIL   mean saving too small, or an escape was found
#   2 = NOT YET too few qualifying runs, PR not merged yet, or no conclusive push/merge_group run
#   3 = CANNOT ESTABLISH  gh/jq/GH_TOKEN missing, or a GitHub API read failed (the sweeper retries)
#   78 = refused to run under xtrace while GH_TOKEN is set (#7797)
#
# Env: GH_TOKEN required (declared secrets=GH_TOKEN on the tracker directive);
#   PBG_UNBOUNDED=1 is an operator-local verdict seam — replaces the wall
#   deadline with END=T0+86400 so one local run can converge; refused under
#   the sweeper channel (SOLEUR_FT_EARLIEST set). PBG_BUDGET_S is the
#   budgeted-path deadline test seam (integer 1..300, sweeper contract).
#   PBG_JOBS is the read-pool width — integer, clamped to 1-16, default 8;
#   1 forces the serial path and bash<5.1 serial-degrades (announced), so the
#   sweeper's env -i contract needs no forwarding to stay byte-identical.
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
BASELINE_RUNNER_MIN=76   # HISTORICAL: the retired whole-run-billable criterion's pin (see header); informational only
REQUIRED_SAVING_MIN=20
MIN_RUNS=20
MAX_RUNS=40          # bounds API use: the sweeper's GITHUB_TOKEN allows ~1000 requests/hour/repo
PAGE_CAP=6           # list calls: 6 pages x 100 completed pull_request runs ~= 6 days at current volume
EXAMINE_CAP=220      # detail calls: <=3 reads per candidate (head lookup, files, jobs), ~660 worst case
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for need in gh jq unzip mktemp awk sed grep sort date timeout comm paste cut cat seq head xargs mv; do
  command -v "$need" >/dev/null 2>&1 || { echo "CANNOT ESTABLISH: $need is not installed"; exit 3; }
done
[ -n "${GH_TOKEN:-}" ] || { echo "CANNOT ESTABLISH: GH_TOKEN is not set (the tracker directive must declare secrets=GH_TOKEN)"; exit 3; }
BUDGET="${PBG_BUDGET_S:-270}"   # the ONE wall deadline END=T0+BUDGET covering listing, examine, artifacts and the escape check (default 30 s under the sweeper's 300 s per-probe kill; test seam, cap 300)
T0=$SECONDS
# PBG_UNBOUNDED=1 is the operator-local verdict seam (#9323): the probe starves
# inside the sweeper's 300 s kill (~20 qualifying runs x ~13 artifact reads
# cannot fit 270 s), so a local run overrides the wall deadline with a
# far-future bound — the bound is REPLACED, never removed (api()'s
# rem=$((END-SECONDS-5)) would crash under `set -u` on an unset END). The
# sweeper never sets the variable, so sweep behaviour is byte-identical: the
# PBG_BUDGET_S<=300 contract still guards the budgeted path and stays
# irrelevant on the unbounded one (an irrelevant PBG_BUDGET_S cannot refuse a
# run it no longer bounds). Per-call 60 s caps still bound every read: a
# stalled gh api call dies in place as a read failure, never hangs the
# operator's shell.
if [[ "${PBG_UNBOUNDED:-}" = 1 ]]; then
  [[ -z "${SOLEUR_FT_EARLIEST+x}" ]] || { echo "CANNOT ESTABLISH: PBG_UNBOUNDED is operator-local only — the sweeper channel must never see it"; exit 3; }
  END=$((T0 + 86400))
  echo "[operator-local] wall deadline overridden by PBG_UNBOUNDED=1 (END=+86400s, per-call 60s caps still bind)"
else
  [[ "$BUDGET" =~ ^[1-9][0-9]*$ && "$BUDGET" -le 300 ]] || { echo "CANNOT ESTABLISH: PBG_BUDGET_S is not an integer from 1 to 300"; exit 3; }
  END=$((T0 + BUDGET))
fi

# PBG_JOBS: the read-pool width (#12360) — integer, clamped to 1-16, default 8. Validated
# unconditionally (it binds the unbounded operator seam too — a tunable there was the ruling's
# point); the refuse shape mirrors PBG_BUDGET_S's. `wait -n -p` needs bash>=5.1 — older bash
# serial-degrades, announced, mirroring the test-all.sh:2229-2231 gate: the probe must keep
# producing NOT YET, never crash, on an old bash (the PBG_UNBOUNDED local-verdict path may run
# on macOS bash 3.2; the sweeper runs ubuntu-24.04 bash 5.2).
JOBS="${PBG_JOBS:-8}"
[[ "$JOBS" =~ ^[0-9]+$ ]] || { echo "CANNOT ESTABLISH: PBG_JOBS is not an integer"; exit 3; }
JOBS=$((10#$JOBS))   # strip leading zeros: 08/09 would hit the octal trap in every later (( )) (PBG_BUDGET_S's regex refuses them outright; this knob accepts then normalizes)
if (( JOBS > 16 )); then echo "[pbg] PBG_JOBS=$JOBS exceeds the 16-worker ceiling — clamped to 16"; JOBS=16; fi
(( JOBS < 1 )) && JOBS=1
_pbg_pool_on=0
if (( JOBS > 1 )); then
  if (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1) )); then
    _pbg_pool_on=1
  else
    echo "[pbg] serial fallback — bash<5.1 (wait -n -p unavailable); reads run serially"
  fi
fi

# the gate-machinery paths, single-sourced from the lib that declares them
# shellcheck source=scripts/lib/test-relevance-paths.sh
source "$HERE/../lib/test-relevance-paths.sh" 2>/dev/null || { echo "CANNOT ESTABLISH: cannot read test-relevance-paths.sh"; exit 3; }
MACHINERY=("${PR_GATE_MACHINERY_PATHS[@]}" "scripts/lib/test-relevance-paths.sh")

# one deadline-capped read: each call is capped at min(60 s, END - SECONDS - 5), recomputed per call, so no
# in-flight read can carry the probe past the sweeper's kill. rc 46 = the wall deadline is spent (or the
# probe's own cap killed the read): a budget CUT, reported as NOT YET, never a failed read.
api() {
  local out rc=0 rem cap
  rem=$((END - SECONDS - 5)); cap=60; (( rem < cap )) && cap=$rem
  if (( cap < 1 )); then return 46; fi
  out="$(timeout "$cap" gh api "$@" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 124 ] && (( cap < 60 )); then return 46; fi   # killed by OUR cap, not a stall: a budget event
  [ "$rc" -eq 0 ] || return "$rc"
  printf '%s\n' "$out"
}
# the same deadline contract for a binary payload (a zip cannot ride a $() capture)
api_bin() {
  local rem cap rc=0
  rem=$((END - SECONDS - 5)); cap=60; (( rem < cap )) && cap=$rem
  if (( cap < 1 )); then return 46; fi
  timeout "$cap" gh api "$@" 2>/dev/null || rc=$?
  if [ "$rc" -eq 124 ] && (( cap < 60 )); then return 46; fi
  return "$rc"
}
fail_api() { echo "CANNOT ESTABLISH: GitHub API read failed ($1)"; exit 3; }
cut_ny() { echo "NOT YET: the wall deadline ($((END - T0))s) ended during $1 — the sweep retries next run"; exit 2; }

# --- the bounded-parallel worker pool ----------------------------------------------------------------
# _w_row: the worker's ONLY result channel — one atomic write (.part + mv, the replay tool's
# fail_suites pattern) so the parent never reads a torn row. Worker stdout/stderr never carries
# verdict data; _pbg_pool redirects it to a per-unit wlog for postmortems only.
_w_row() {
  local f="$1"; shift
  printf '%s\n' "$*" > "$f.part" && mv "$f.part" "$f"
}
# a dispatched unit MUST produce its row: missing/empty = a worker died silently = CANNOT ESTABLISH,
# never a skipped unit (partial evidence is worse than no verdict).
_pbg_need_row() {
  [ -s "$1" ] || { echo "CANNOT ESTABLISH: a probe worker produced no result for ${1##*/} — a worker dying silently is a defect, never a skipped unit"; exit 3; }
}
_pbg_reap() {  # reap one finished pool worker; drops it from _pbg_pids/_pbg_live (test-all.sh _pj_reap shape)
  local rp="" j
  wait -n -p rp -- "${_pbg_pids[@]}" 2>/dev/null
  rp="${rp:-}"  # wait -p leaves rp unset (not empty) when the finished child is already out of the job table — `set -u` then dies on the test below
  local -a np=()
  for j in "${_pbg_pids[@]}"; do
    if [ -n "$rp" ]; then
      [ "$j" != "$rp" ] && np+=("$j")
    else
      # torn reap: a completed child can leave the job table before wait -n reaches it (rp empty);
      # kill -0 on a reaped-away pid fails, which is the drop condition.
      kill -0 "$j" 2>/dev/null && np+=("$j")
    fi
  done
  _pbg_pids=(); ((${#np[@]})) && _pbg_pids=("${np[@]}")
  _pbg_live=${#_pbg_pids[@]}
}
# _pbg_pool <listfile> <worker-fn>: one `key<TAB>payload` line per unit; at most JOBS `&` workers
# live at once, reaped with `wait -n -p`. Serial path (JOBS=1 or bash<5.1) runs the same worker
# function inline — one code path for unit logic either way. Result FILES are the contract: the
# pool returns after the drain and the parent aggregates rows in ITS chosen order.
_pbg_pool() {
  local list="$1" fn="$2" key payload
  if (( _pbg_pool_on == 0 )); then
    while IFS=$'\t' read -r key payload; do
      [ -n "$key" ] || continue
      "$fn" "$key" "$payload" >> "$WORK/wlog-$fn-$key" 2>&1
    done < "$list"
    return 0
  fi
  _pbg_pids=(); _pbg_live=0
  while IFS=$'\t' read -r key payload; do
    [ -n "$key" ] || continue
    ( "$fn" "$key" "$payload" ) >> "$WORK/wlog-$fn-$key" 2>&1 &
    _pbg_pids+=("$!"); _pbg_live=$((_pbg_live + 1))
    (( _pbg_live < JOBS )) || _pbg_reap
  done < "$list"
  while (( _pbg_live > 0 )); do _pbg_reap; done
}

# --- the workers: each writes one row file and returns; cut_ny/fail_api exist only in the parent ----
# _pbg_w_page <page>: $WORK/page-<p> = `ok <raw_n>` + page-<p>.chunk (filtered candidates);
# `cut <detail>` on the deadline, `fail <detail>` on a failed/empty/malformed read.
_pbg_w_page() {
  local p="$1" rf="$WORK/page-$1" resp rc=0 raw_n chunk
  resp="$(api "repos/$REPO/actions/workflows/ci.yml/runs?event=pull_request&status=completed&per_page=100&created=%3E$merged_at&page=$p")" || rc=$?
  if (( rc == 46 )); then _w_row "$rf" "cut the runs list (page $p)"; return 0; fi
  if (( rc != 0 )) || [ -z "$resp" ]; then _w_row "$rf" "fail ci.yml runs (page $p)"; return 0; fi
  raw_n="$(jq -r '.workflow_runs | length' <<<"$resp" 2>/dev/null)"
  [[ "$raw_n" =~ ^[0-9]+$ ]] || { _w_row "$rf" "fail ci.yml runs (page $p, malformed body)"; return 0; }
  chunk="$(jq '[.workflow_runs[] | select(.conclusion == "success" and (.actor.type // "") != "Bot")
               | {id, conclusion, pr: (.pull_requests[0].number // "-"), branch: (.head_branch // "-"),
                  hrepo: (.head_repository.full_name // "-")}]' <<<"$resp")" \
    || { _w_row "$rf" "fail ci.yml runs (page $p, filter failed)"; return 0; }
  printf '%s\n' "$chunk" > "$WORK/page-$p.chunk" || { _w_row "$rf" "fail ci.yml runs (page $p, chunk write)"; return 0; }
  _w_row "$rf" "ok $raw_n"
}
# _pbg_w_exam <idx> <id<TAB>pr<TAB>branch<TAB>hrepo>: $WORK/exam-<idx> =
# `qual <pr> <id> <run_min> <qwait_sum> <qwait_n>` for a qualifying run, `skip` for every serial
# `continue`, and the same cut/fail details the serial loop emitted (the parent replays them).
_pbg_w_exam() {
  local pl="$2" rf="$WORK/exam-$1" id pr branch hrepo rest rc=0 files m touches=0 jobs_json ran run_min qw
  id="${pl%%$'\t'*}"; rest="${pl#*$'\t'}"
  pr="${rest%%$'\t'*}"; rest="${rest#*$'\t'}"
  branch="${rest%%$'\t'*}"; hrepo="${rest#*$'\t'}"
  # `pull_requests` is empty once the PR merges (see HEAD-BRANCH RESOLUTION above): resolve the run's
  # head_branch back to its PR — `state=all`, because the merged set is exactly what the escape arm
  # needs. Only same-repo heads: a fork run's head_branch can collide with a same-repo branch name and
  # would misresolve to the wrong PR (head=<owner>:<branch> cannot see the fork's PR).
  if [[ "$pr" == "-" || -z "$pr" ]]; then
    if [[ "$branch" == "-" || -z "$branch" || "$hrepo" != "$REPO" || ! "$branch" =~ ^[A-Za-z0-9._/-]+$ ]]; then
      _w_row "$rf" "skip"; return 0
    fi
    pr="$(api "repos/$REPO/pulls?head=${REPO%%/*}:$branch&state=all&per_page=1" --jq '.[0].number // empty')" || rc=$?
    if (( rc == 46 )); then _w_row "$rf" "cut the head-branch lookup ($branch)"; return 0; fi
    if (( rc != 0 )); then _w_row "$rf" "fail head-branch PR lookup ($branch)"; return 0; fi
    [ -n "$pr" ] || { _w_row "$rf" "skip"; return 0; }
  fi
  files="$(api "repos/$REPO/pulls/$pr/files?per_page=100" --jq '.[].filename')" || rc=$?
  if (( rc == 46 )); then _w_row "$rf" "cut the files read of PR $pr"; return 0; fi
  if (( rc != 0 )); then _w_row "$rf" "fail pull $pr files"; return 0; fi
  for m in "${MACHINERY[@]}"; do
    case "$files" in *"$m"*) touches=1 ;; esac
  done
  (( touches == 0 )) || { _w_row "$rf" "skip"; return 0; }
  jobs_json="$(api "repos/$REPO/actions/runs/$id/jobs?per_page=100")" || rc=$?
  if (( rc == 46 )); then _w_row "$rf" "cut the jobs read of run $id"; return 0; fi
  if (( rc != 0 )); then _w_row "$rf" "fail run $id jobs"; return 0; fi
  # a run that never executed a test-scripts* job measures nothing about the batteries
  ran="$(jq '[.jobs[] | select((.name | startswith("test-scripts")) and .conclusion != "skipped")] | length' <<<"$jobs_json")"
  [ "${ran:-0}" -gt 0 ] 2>/dev/null || { _w_row "$rf" "skip"; return 0; }
  run_min="$(jq -r '[.jobs[] | select(.conclusion != "skipped" and .started_at and .completed_at)
                    | ((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601))] | add // 0 | . / 60' <<<"$jobs_json")"
  [ -n "$run_min" ] || { _w_row "$rf" "fail run $id duration"; return 0; }
  qw="$(jq -r '[.jobs[] | select(.name | startswith("test-scripts")) | select(.started_at and .created_at)
                | ((.started_at | fromdateiso8601) - (.created_at | fromdateiso8601)) / 60]
               | "\(add // 0) \(length)"' <<<"$jobs_json")"
  _w_row "$rf" "qual $pr $id $run_min ${qw:-0 0}"
}
# _pbg_w_artlist <rid>: $WORK/arts-<rid> = the run's suite-timings-* aid list (one per line),
# `none` when it carries none, `cut <detail>`/`fail <detail>` on the deadline/transport paths
# (a failed LIST stays a transport failure — the parent fail_apis, never folds it into absent).
_pbg_w_artlist() {
  local rid="$1" rf="$WORK/arts-$1" arts rc=0 aids
  arts="$(api "repos/$REPO/actions/runs/$rid/artifacts?per_page=100")" || rc=$?
  if (( rc == 46 )); then _w_row "$rf" "cut the artifact listing of run $rid"; return 0; fi
  if (( rc != 0 )); then _w_row "$rf" "fail run $rid artifacts"; return 0; fi
  aids="$(jq -r '.artifacts[]? | select(.name | test("^suite-timings-(scripts|scripts-heavy)-[0-9]+$")) | .id' <<<"$arts" 2>/dev/null)"
  if [ -n "$aids" ]; then _w_row "$rf" "$aids"; else _w_row "$rf" "none"; fi
}
# _pbg_w_artdl <rid>-<aid> <rid<TAB>aid>: $WORK/dl-<rid>-<aid> = `ok` (+ the extracted
# $WORK/tsv-<rid>-<aid>), `cut` on the deadline, `partial` on any download/extract failure — the
# serial run_partial arm, folded to evidence_absent by the parent (never a transport fatal).
_pbg_w_artdl() {
  local key="$1" pl="$2" rf="$WORK/dl-$1" rid aid dlrc=0
  rid="${pl%%$'\t'*}"; aid="${pl#*$'\t'}"
  api_bin "repos/$REPO/actions/artifacts/$aid/zip" > "$WORK/art-$rid-$aid.zip" || dlrc=$?
  if (( dlrc == 46 )); then _w_row "$rf" "cut the artifact downloads of run $rid"; return 0; fi
  if (( dlrc != 0 )); then _w_row "$rf" "partial"; return 0; fi
  unzip -p "$WORK/art-$rid-$aid.zip" suite-timings.tsv 2>/dev/null > "$WORK/tsv-$rid-$aid" \
    || unzip -p "$WORK/art-$rid-$aid.zip" 2>/dev/null > "$WORK/tsv-$rid-$aid" \
    || { _w_row "$rf" "partial"; return 0; }
  [ -s "$WORK/tsv-$rid-$aid" ] || { _w_row "$rf" "partial"; return 0; }
  _w_row "$rf" "ok"
}
# _pbg_esc_classify <rf> <event> <concl> <rid> <sha> <pr>: the ONE conclusion→bucket path both the
# push arm and the merge_group arm feed — a red run is an escape only when >=1 FAILED job is a gated
# battery leg (the same test-scripts* prefix the qual arm's `ran=` filter derives, not a second enumeration
# that can drift). A jobs read that cannot be established (missing run id, transport failure,
# empty/non-failed job list, or a gated job left cancelled/inconclusive) is `pending`, never `ok`.
# <event> names the evidence source in the row detail (`push`/`merge_group`); a `success` sourced
# from merge_group writes `ok via_mg` so the parent can report the evidence class.
_pbg_esc_classify() {
  local rf="$1" ev="$2" concl="$3" rid="$4" sha="$5" pr="$6" jnames gated gated_inc unrel jn jc rc=0
  case "$concl" in
    failure|timed_out|startup_failure|action_required)
      [ -n "$rid" ] || { _w_row "$rf" "pending red $ev run on $sha carries no run id — cannot read its jobs"; return 0; }
      jnames="$(api "repos/$REPO/actions/runs/$rid/jobs?per_page=100" --paginate --jq '.jobs[] | select(.conclusion != "success" and .conclusion != "skipped" and .conclusion != "neutral") | "\(.name)\t\(.conclusion)"')" || rc=$?
      if (( rc == 46 )); then _w_row "$rf" "cut the jobs read of $ev run $rid for $sha"; return 0; fi
      if (( rc != 0 )) || [ -z "$jnames" ]; then _w_row "$rf" "pending jobs read of red $ev run $rid on $sha failed or empty"; return 0; fi
      gated=""; gated_inc=""; unrel=""
      while IFS=$'\t' read -r jn jc; do
        [ -n "$jn" ] || continue
        case "$jn" in
          test-scripts*)
            case "$jc" in
              failure|timed_out|action_required|startup_failure) gated="${gated:+$gated, }$jn" ;;
              *) gated_inc=1 ;;
            esac ;;
          *) unrel="${unrel:+$unrel, }$jn" ;;
        esac
      done <<< "$jnames"
      if [ -n "$gated" ]; then
        _w_row "$rf" "escape PR $pr was green but its merge-commit $ev run on $sha is $concl (failed gated job(s): $gated)"
      elif [ -n "$gated_inc" ]; then
        _w_row "$rf" "pending a gated test-scripts* job on $ev run $rid ($sha) is cancelled/inconclusive — cannot establish escape"
      else
        _w_row "$rf" "unrelated PR $pr $ev run on $sha is $concl on non-gated job(s): ${unrel:-names-unreadable}"
      fi ;;
    success)
      if [ "$ev" = merge_group ]; then _w_row "$rf" "ok via_mg"; else _w_row "$rf" "ok"; fi ;;
    *) _w_row "$rf" "pending" ;;   # absent or not yet complete: not evidence of "no escape"
  esac
}
# _pbg_w_esc <pr>: $WORK/esc-<pr> = `dropped` (closed unmerged), `open` (state=="open" — #12360:
# an unmerged PR's absent merge-commit push run is EXPECTED, not missing evidence; `state` rides
# the same pulls/N meta read, so the bucket costs zero extra reads), `ok` / `ok via_mg` (an
# ok sourced from the merge_group run — #12478), `escape <detail>`, `unrelated <detail>` (red run whose failed jobs are
# ALL outside the gated test-scripts* family — ADR-262 R1's escape is a battery breaking on an
# undeclared path; a curl(56) infra flake in a job the path-gate cannot skip is not that, so it is
# reported in the note line, never counted — 2026-11-08 #9323 verdict), `pending` (merged PR with
# no conclusive run of either event, or a red run whose jobs read cannot be established), `cut`/`fail`.
# The merge_group fallback (#12478, Arm A ruling 2026-11-09): a queue-merged PR's merge commit
# carries merge_group runs and NEVER a push run, so the push arm's catch-all issues exactly one
# merge_group read before pending — inconclusive-push only, and the newest mg run goes through the
# SAME _pbg_esc_classify path (head_sha needs the full 40-char sha; merge_commit_sha already is).
_pbg_w_esc() {
  local pr="$1" rf="$WORK/esc-$1" meta rc=0 sha rest pstate pm run_meta rid concl
  meta="$(api "repos/$REPO/pulls/$pr" --jq '"\(.merge_commit_sha // "") \(.state // "") \(.merged_at // "")"')" || rc=$?
  if (( rc == 46 )); then _w_row "$rf" "cut the pull read of PR $pr"; return 0; fi
  if (( rc != 0 )); then _w_row "$rf" "fail pull $pr merge sha"; return 0; fi
  sha="${meta%% *}"; rest="${meta#* }"; pstate="${rest%% *}"; pm="${rest##* }"
  if [[ "$pstate" == "closed" && -z "$pm" ]]; then _w_row "$rf" "dropped"; return 0; fi
  if [[ "$pstate" == "open" ]]; then _w_row "$rf" "open"; return 0; fi
  [ -n "$sha" ] || { _w_row "$rf" "pending"; return 0; }
  run_meta="$(api "repos/$REPO/actions/workflows/ci.yml/runs?event=push&head_sha=$sha" --jq '"\(.workflow_runs[0].id // "") \(.workflow_runs[0].conclusion // "")"')" || rc=$?
  if (( rc == 46 )); then _w_row "$rf" "cut the push-run read for $sha"; return 0; fi
  if (( rc != 0 )); then _w_row "$rf" "fail push run for $sha"; return 0; fi
  rid="${run_meta%% *}"; concl="${run_meta#* }"
  case "$concl" in
    success|failure|timed_out|startup_failure|action_required)
      _pbg_esc_classify "$rf" push "$concl" "$rid" "$sha" "$pr" ;;
    *)
      run_meta="$(api "repos/$REPO/actions/workflows/ci.yml/runs?event=merge_group&head_sha=$sha" --jq '"\(.workflow_runs[0].id // "") \(.workflow_runs[0].conclusion // "")"')" || rc=$?
      if (( rc == 46 )); then _w_row "$rf" "cut the merge_group-run read for $sha"; return 0; fi
      if (( rc != 0 )); then _w_row "$rf" "fail merge_group run for $sha"; return 0; fi
      rid="${run_meta%% *}"; concl="${run_meta#* }"
      _pbg_esc_classify "$rf" merge_group "$concl" "$rid" "$sha" "$pr" ;;
  esac
}

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
ART_READ_CAP=260   # ~= 20 qualifying runs x 13 artifact reads (1 listing + ~12 suite-timings-* zips); the old 60-read cap let only ~5 runs evidence, a structural NOT YET
GATED_SUITES="$({ sed 's/[[:space:]]*#.*$//' "$HERE/../test-all.sh" | grep -oE 'skip_suite "[^"]+" "relevance"' | sed 's/skip_suite "//;s/" "relevance"//'; } | LC_ALL=C sort -u)" \
  || { echo "CANNOT ESTABLISH: no skip_suite relevance call sites in test-all.sh"; exit 3; }
[ -n "$GATED_SUITES" ] || { echo "CANNOT ESTABLISH: no skip_suite relevance call sites in test-all.sh"; exit 3; }
PRICE="$(awk -F'\t' '$2 ~ /^[0-9]+$/ { p[$1] = $2 / 60000 } END { for (s in p) printf "%s\t%.4f\n", s, p[s] }' \
  "$HERE/../suite-durations.tsv" "$HERE/../suite-durations-heavy.tsv" 2>/dev/null)" \
  || { echo "CANNOT ESTABLISH: cannot read suite-durations TSVs"; exit 3; }
[ -n "$PRICE" ] || { echo "CANNOT ESTABLISH: suite-durations TSVs hold no priced rows"; exit 3; }
# a gated label with no committed price contributes 0 silently — the under-count direction is honest, but the
# hole is printed on the status line (unpriced=). e.g. `apps/web-platform [unit]` is gated yet emits no timing
# artifact and has no durations row.
UNPRICED="$(LC_ALL=C comm -23 <(printf '%s\n' "$GATED_SUITES") <(printf '%s\n' "$PRICE" | cut -f1 | LC_ALL=C sort -u) | paste -sd, -)"

rl="$(api "rate_limit")" || { rc=$?; [ "$rc" -eq 46 ] && cut_ny "the quota preflight"; fail_api "rate_limit preflight"; }
rl_rem="$(jq -r '.resources.core.remaining // 0' <<<"$rl" 2>/dev/null)"
[[ "$rl_rem" =~ ^[0-9]+$ ]] || fail_api "rate_limit preflight (malformed body)"
# a quota cut is NOT YET — the sweep is retried when the hourly window rolls; never a failed read, never a verdict.
# need_min is the real worst case: 3 reads per examined candidate, the listing pages, the artifact cap, and 3 reads
# (pull + push-run + merge_group-run) per qualifying run in the escape check — the mg read fires only on the
# inconclusive-push arm, but at queue-merge volume every merged PR lands there (#12478), so the bound is 3, not 2;
# the classifier's jobs read lands only on red runs of either event (rare; a green run needs no third read) and
# rides the same rare carve-out as before (a green run never pays a jobs read). The parallel Stage-A wave lists ALL qualifying runs
# unconditionally — runs past the ART_READ_CAP replay bound had their listing fetched where serial never did —
# so the model carries one extra MAX_RUNS of listing prefetch on top of the cap.
need_min=$(( 3 * EXAMINE_CAP + PAGE_CAP + ART_READ_CAP + 4 * MAX_RUNS + 20 ))
if (( rl_rem < need_min )); then
  echo "NOT YET: API quota remaining=$rl_rem under the $need_min-request floor for a full sweep; the sweeper retries"; exit 2
fi
WORK="$(mktemp -d "${TMPDIR:-/var/tmp}/pbg9323.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT

merged_at="$(api "repos/$REPO/pulls/$GATE_PR" --jq '.merged_at // empty')" || { rc=$?; [ "$rc" -eq 46 ] && cut_ny "the gate-PR read"; fail_api "pull $GATE_PR"; }
[ -n "$merged_at" ] || { echo "NOT YET: PR $GATE_PR is not merged"; exit 2; }

# Paginate the runs list: a page is 100 completed pull_request runs, so PAGE_CAP bounds the scan to
# ~PAGE_CAP days of history at current volume. Page 1 goes alone because the short-page rule (< 100
# raw runs — filtering is client-side, so the RAW length decides whether another page exists)
# decides whether later pages exist at all: a tail wave (pages 2..PAGE_CAP in one pool wave) is
# dispatched only for a FULL page 1 — serial-identical reads, a short page never triggers page>=2.
# Aggregation walks rows in page order and stops at the first short page, so a cut/fail on a page
# the serial loop would never have fetched cannot fire.
_pbg_take_page() {  # _pbg_take_page <n> — consume one page row in page order (mutates runs/pages/_pbg_raw_n)
  local p="$1" row kind chunk
  _pbg_need_row "$WORK/page-$p"
  row="$(cat "$WORK/page-$p")"
  kind="${row%% *}"
  case "$kind" in
    ok) ;;
    cut) cut_ny "${row#* }" ;;
    fail) fail_api "${row#* }" ;;
    *) echo "CANNOT ESTABLISH: malformed worker row page-$p"; exit 3 ;;
  esac
  pages=$((pages + 1))
  [ -s "$WORK/page-$p.chunk" ] || { echo "CANNOT ESTABLISH: worker row ok for page $p but its chunk file is missing"; exit 3; }
  chunk="$(cat "$WORK/page-$p.chunk")"
  runs="$(jq --argjson c "$chunk" '. + $c' <<<"$runs")" || fail_api "ci.yml runs (page $p, merge failed)"
  _pbg_raw_n="${row#* }"
}
runs="[]"; pages=0
printf '1\n' > "$WORK/pages.list"
_pbg_pool "$WORK/pages.list" _pbg_w_page
_pbg_take_page 1
if (( _pbg_raw_n >= 100 )); then
  seq 2 "$PAGE_CAP" > "$WORK/pages.list"
  _pbg_pool "$WORK/pages.list" _pbg_w_page
  _pbg_p=1
  while (( ++_pbg_p <= PAGE_CAP )); do
    _pbg_take_page "$_pbg_p"
    (( _pbg_raw_n < 100 )) && break
  done
fi

# the candidate list in page order — the parent's serial-exact replay order. Workers may finish in
# any order; verdict-relevant order is restored by reading exam rows in candidate sequence, so
# green_prs/green_ids/sum_min/qwait_* aggregate exactly as the serial loop did (first MAX_RUNS
# qualifying candidates win; a cut/fail fires at the same candidate position serial would hit it).
cand_n=0
: > "$WORK/cand.list"
while read -r id _ pr branch hrepo; do
  [ -n "$id" ] || continue
  (( cand_n < EXAMINE_CAP )) || break
  printf '%s\t%s\t%s\t%s\t%s\n' "$cand_n" "$id" "$pr" "$branch" "$hrepo" >> "$WORK/cand.list"
  cand_n=$((cand_n + 1))
done < <(jq -r '.[] | "\(.id) \(.conclusion) \(.pr) \(.branch) \(.hrepo)"' <<<"$runs")

_pbg_pool "$WORK/cand.list" _pbg_w_exam

n=0; sum_min=0; green_prs=""; green_ids=""; qwait_sum=0; qwait_n=0; examined=0
while IFS=$'\t' read -r ckey _; do
  [ -n "$ckey" ] || continue
  (( n < MAX_RUNS )) || break
  examined=$((examined + 1))
  _pbg_need_row "$WORK/exam-$ckey"
  erow="$(cat "$WORK/exam-$ckey")"
  case "${erow%% *}" in
    skip) continue ;;
    qual) ;;
    cut) cut_ny "${erow#* }" ;;
    fail) fail_api "${erow#* }" ;;
    *) echo "CANNOT ESTABLISH: malformed worker row exam-$ckey"; exit 3 ;;
  esac
  set -- $erow   # qual <pr> <id> <run_min> <qwait_sum> <qwait_n>
  sum_min="$(awk -v a="$sum_min" -v b="$4" 'BEGIN { print a + b }')"
  qwait_sum="$(awk -v a="$qwait_sum" -v b="$5" 'BEGIN { print a + b }')"; qwait_n=$((qwait_n + ${6:-0}))
  n=$((n + 1)); green_prs="$green_prs $2"; green_ids="$green_ids $3"
done < "$WORK/cand.list"

if (( n < MIN_RUNS )); then
  echo "NOT YET: $n qualifying run(s) in $examined candidate(s) across $pages page(s) since $merged_at (need >= $MIN_RUNS)"; exit 2
fi

# --- realized saving per qualifying run: price the `label\t0\tskip=relevance` rows of the gated battery set in the
# run's suite-timings-(scripts|scripts-heavy)-N artifacts (the exact name pattern, lockstep with
# scripts/watch-shard-balance-11564.sh — a suite-timings-<other> artifact is never evidence). A failed artifact LIST
# is a transport failure (CANNOT ESTABLISH), distinct from absent evidence (NOT YET). Within a run, ALL of its
# artifacts' TSVs are priced in ONE awk pass so a `skip=relevance` row listed in two artifacts counts once —
# and a cap-cut, failed or unparseable artifact marks the run run_partial: it counts as evidence_absent, never a
# deflated run_saved that could manufacture a FAIL. Stage A lists every run in parallel; the parent then replays
# the SERIAL read sequence on a virtual counter `vc` — a run's listing counts in its serial position, its aids
# queue while vc < ART_READ_CAP, a mid-run cap hit marks the run absent exactly like serial's run_partial break,
# and runs past the cap are absent without their rows being consulted (serial never fetched them). Downloads the
# replay queued run in a second parallel wave; the pricing pass itself stays serial per run.
real_sum=0; evidence_absent=0
: > "$WORK/runs.list"
for rid in $green_ids; do printf '%s\n' "$rid" >> "$WORK/runs.list"; done
_pbg_pool "$WORK/runs.list" _pbg_w_artlist

vc=0; : > "$WORK/dlq"; : > "$WORK/priced.list"
for rid in $green_ids; do
  if (( vc >= ART_READ_CAP )); then evidence_absent=$((evidence_absent + 1)); continue; fi
  vc=$((vc + 1))   # the listing read, in its serial position
  _pbg_need_row "$WORK/arts-$rid"
  afirst="$(head -1 "$WORK/arts-$rid")"
  case "${afirst%% *}" in
    cut) cut_ny "${afirst#* }" ;;
    fail) fail_api "${afirst#* }" ;;
    none) evidence_absent=$((evidence_absent + 1)); continue ;;
    *) ;;   # an aid-list row: the file itself is the run's aid list
  esac
  run_ok=1; : > "$WORK/q-$rid"
  while IFS= read -r aid; do
    [ -n "$aid" ] || continue
    if (( vc >= ART_READ_CAP )); then run_ok=0; break; fi
    vc=$((vc + 1))
    printf '%s\t%s\n' "$rid" "$aid" >> "$WORK/q-$rid"
    printf '%s-%s\t%s\t%s\n' "$rid" "$aid" "$rid" "$aid" >> "$WORK/dlq"
  done < "$WORK/arts-$rid"
  if (( run_ok == 0 )); then evidence_absent=$((evidence_absent + 1)); continue; fi
  printf '%s\n' "$rid" >> "$WORK/priced.list"
done

_pbg_pool "$WORK/dlq" _pbg_w_artdl

while IFS= read -r rid; do
  [ -n "$rid" ] || continue
  run_partial=0
  while IFS=$'\t' read -r qr qaid; do
    [ -n "$qr" ] || continue
    _pbg_need_row "$WORK/dl-$qr-$qaid"
    drow="$(cat "$WORK/dl-$qr-$qaid")"
    case "${drow%% *}" in
      ok) ;;
      cut) cut_ny "${drow#* }" ;;
      partial) run_partial=1; break ;;
      *) echo "CANNOT ESTABLISH: malformed worker row dl-$qr-$qaid"; exit 3 ;;
    esac
  done < "$WORK/q-$rid"
  (( run_partial == 0 )) || { evidence_absent=$((evidence_absent + 1)); continue; }
  run_saved="$(sed 's/\t/-/g;s|^|'"$WORK"'/tsv-|' "$WORK/q-$rid" | xargs cat | awk -F'\t' -v gs="$GATED_SUITES" -v P="$PRICE" '
    BEGIN { ng = split(gs, g, "\n"); for (i = 1; i <= ng; i++) gate[g[i]] = 1
            np = split(P, pl, "\n"); for (i = 1; i <= np; i++) { split(pl[i], kv, "\t"); price[kv[1]] = kv[2] } }
    $2 == 0 && $3 == "skip=relevance" && ($1 in gate) && !seen[$1]++ { s += price[$1] }
    END { printf "%.4f", s + 0 }')"
  [[ "$run_saved" =~ ^[0-9.]+$ ]] || { evidence_absent=$((evidence_absent + 1)); continue; }
  real_sum="$(awk -v a="$real_sum" -v b="$run_saved" 'BEGIN{print a+b}')"
done < "$WORK/priced.list"
evidenced=$((n - evidence_absent))
if (( evidenced < MIN_RUNS )); then
  echo "NOT YET: $evidence_absent of $n qualifying runs lack readable suite-timings-* artifact evidence ($evidenced evidenced, need >= $MIN_RUNS)"; exit 2
fi
real_mean="$(awk -v s="$real_sum" -v n="$evidenced" 'BEGIN { printf "%.1f", s / n }')"

mean="$(awk -v s="$sum_min" -v n="$n" 'BEGIN { printf "%.1f", s / n }')"
qmean="n/a"; (( qwait_n > 0 )) && qmean="$(awk -v s="$qwait_sum" -v n="$qwait_n" 'BEGIN { printf "%.1f", s / n }')"
echo "qualifying_runs=$n evidenced_runs=$evidenced mean_runner_min=$mean required_saving=$REQUIRED_SAVING_MIN baseline_runner_min=$BASELINE_RUNNER_MIN unpriced=${UNPRICED:-none} test_scripts_mean_queue_wait_min=$qmean (queue wait is informational only) candidates_examined=$examined pages=$pages"

# A qualifying PR in one of four states: MERGED (state closed + merged_at set — the escape arm checks
# its push run, falling back to the merge commit's merge_group run when the push run is inconclusive
# — a queue-merged PR's merge commit carries merge_group runs, never a push run, #12478), OPEN
# (#12360 — a merge_commit_sha exists as a TEST merge but no main-side push run
# can; the absence is EXPECTED for an unmerged PR, not missing evidence → the `open` bucket, a note
# mirroring `dropped`, never pending: at ~30 open PRs of repo volume pending>0 was near-permanent and
# NOT YET never cleared), or CLOSED UNMERGED (no merge commit will ever exist → dropped). Residual
# accepted for `open` (same shape as `dropped`): a qualifying PR open at verdict time that later
# merges with a red run is an escape this probe never sees — main-side red is separately paged
# by notify-main-failure. merge_commit_sha CANNOT be the discriminator: the API reports the
# TEST-merge sha there for open and closed-unmerged PRs alike (verified on #11038: state=closed,
# merged_at=null, sha set) — it is null only before the test merge is computed. The discriminator is
# `state` itself, read off the pulls/N meta read the arm already made — zero extra reads.
escapes=0; pending=0; dropped=0; open_prs=0; unrelated=0; via_mg=0
: > "$WORK/prs.list"
for pr in $green_prs; do printf '%s\n' "$pr" >> "$WORK/prs.list"; done
_pbg_pool "$WORK/prs.list" _pbg_w_esc
for pr in $green_prs; do
  _pbg_need_row "$WORK/esc-$pr"
  srow="$(cat "$WORK/esc-$pr")"
  case "${srow%% *}" in
    dropped) dropped=$((dropped + 1)) ;;
    open) open_prs=$((open_prs + 1)) ;;
    pending) pending=$((pending + 1)); [ "${srow#* }" != "$srow" ] && echo "note: pending — ${srow#* }" ;;
    ok) [ "${srow#* }" = "via_mg" ] && via_mg=$((via_mg + 1)) ;;
    unrelated) echo "note: ${srow#* }"; unrelated=$((unrelated + 1)) ;;
    escape) echo "ESCAPE: ${srow#* }"; escapes=$((escapes + 1)) ;;
    cut) cut_ny "${srow#* }" ;;
    fail) fail_api "${srow#* }" ;;
    *) echo "CANNOT ESTABLISH: malformed worker row esc-$pr"; exit 3 ;;
  esac
done

if (( dropped > 0 )); then echo "note: $dropped qualifying PR(s) closed unmerged — no merge commit exists; excluded from the escape check"; fi
if (( open_prs > 0 )); then echo "note: $open_prs qualifying PR(s) still open — no merge commit exists; excluded from the escape check"; fi
if (( unrelated > 0 )); then echo "note: $unrelated qualifying PR(s) have red merge-commit runs only on jobs outside the gated test-scripts* family — reported, never an escape"; fi
if (( via_mg > 0 )); then echo "note: $via_mg qualifying PR(s) verified via merge_group run(s) on their merge commit (queue merges carry no push run)"; fi
if (( escapes > 0 )); then echo "FAIL: $escapes escape(s); widen the declaring array (ADR-262 R1) or revert the PR arm"; exit 1; fi
if (( pending > 0 )); then echo "NOT YET: $pending qualifying PR(s) have no completed push or merge_group run on their merge commit"; exit 2; fi
echo "realized_saving_min=$real_mean over $evidenced evidenced runs (mean_runner_min=$mean is informational: whole-run billing drifts with suite growth, the verdict prices only the gate's own skips)"
if awk -v m="$real_mean" -v r="$REQUIRED_SAVING_MIN" 'BEGIN { exit !(m >= r) }'; then
  echo "PASS: mean realized saving $real_mean suite-min/run meets the $REQUIRED_SAVING_MIN bar over $evidenced runs, no escapes in $n runs"; exit 0
fi
echo "FAIL: mean realized saving $real_mean suite-min/run is under the $REQUIRED_SAVING_MIN bar; widen nothing, but check the gate is declining (grep -F '[skip]' in a docs-only PR's test-scripts log) and the replay rates (scripts/ci-battery-gate-replay.sh)"; exit 1
