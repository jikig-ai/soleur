#!/usr/bin/env bash
# deploy-arm.sh — which web-platform-release deploy arm delivered a merge, and does
# production serve it? The single place ship and postmerge decide this (#8492).
#
# A `workflow_run` run's `head_sha` is the tip of main when the run FIRED, not the
# commit it deploys. So `actions/runs?head_sha=<merge>&event=workflow_run` misses the
# real arm when main moved before the merge's CI completed (#8297) and returns the
# PREVIOUS merge's arm when that arm fired after main reached this merge (#8391).
# The arm is identified here by what its `resolve-target` job checks out: the
# actions/checkout `[command]… --depth=1 origin <sha>` line in that job's log
# (fallback: the workflow's own `resolving deploy target for <sha>` echo). Both are
# anchored at the start of a log line, so a commit subject echoed later in the log
# (`HEAD is now at <sha7> <subject>`) cannot supply them. Reading the log needs
# `gh api --allow-escape-sequences`: without it gh exits 1 writing zero bytes.
# The `head_sha=` query survives only as a first guess through the same classifier.
#
# Usage:
#   deploy-arm.sh find [--wait [POLLS]] <MERGE_SHA>   (one poll per ~minute; default 120)
#   deploy-arm.sh contains <MERGE_SHA> <BUILD_SHA>
#   deploy-arm.sh served <MERGE_SHA> [https-URL]
# MERGE_SHA must be the full 40-hex sha: a short one matches nothing (#8135).
#
# Output contract: exactly ONE verdict line on stdout on every path, errors included;
# diagnostics on stderr. rc: 0 verdict, 1 NOT_CONTAINED, 2 error, 3 stop (no verdict
# possible / could-not-measure), 4 poll again.
#   find  -> ARM=<id> DEPLOYED_SHA=<sha> MATCH=exact|descendant DEPLOY=<state> CI=<c>
#            ARM=none REASON=<ci_pending|arm_pending|ci_absent|no_candidate|unresolved|timeout|not_applicable|error> [CAUSE=..|LAST=..]
#   contains -> CONTAINS | NOT_CONTAINED | UNRESOLVED | ERROR CAUSE=..
#   served   -> the contains verdict + " BUILD_SHA=<sha|->"
#
# Test seams: DEPLOY_ARM_NOW (epoch "now"), DEPLOY_ARM_SLEEP (sleep multiplier; 0 in tests).
set -Eeuo pipefail

SUB="${1:-}"
# Verdicts go to fd 3 so a trap firing inside a command substitution cannot write a
# verdict into a captured variable.
exec 3>&1

err_line() {
  case "$SUB" in
    contains) printf 'ERROR CAUSE=%s' "$1" ;;
    served) printf 'ERROR CAUSE=%s BUILD_SHA=-' "$1" ;;
    *) printf 'ARM=none REASON=error CAUSE=%s' "$1" ;;
  esac
}

emit() { # emit <line> <rc> — the only writer of fd 3
  printf '%s\n' "$1" >&3
  exit "$2"
}

on_err() {
  # Inside a subshell the parent's own failure reports; print nothing here.
  (( BASH_SUBSHELL > 0 )) && exit 2
  printf 'deploy-arm: internal error line=%s cmd=%s\n' "$1" "${2%% *}" >&2
  emit "$(err_line internal)" 2
}
trap 'on_err "$LINENO" "$BASH_COMMAND"' ERR
trap 'emit "$(err_line interrupted)" 2' INT TERM
TMP="$(mktemp -d -t deploy-arm.XXXXXXXX)"
trap 'rm -rf "$TMP"' EXIT

NOW="${DEPLOY_ARM_NOW:-$(date +%s)}"
SLEEP_MULT="${DEPLOY_ARM_SLEEP:-1}"
WORKFLOW_PATH=".github/workflows/web-platform-release.yml"
LOG_GRACE_S=180        # a job's log can 404 briefly after it completes; an arm is created seconds after CI completes
CI_ABSENT_AFTER_S=600  # a merge with no push CI run after 10 minutes is ci_absent, not ci_pending
CAND_CAP=30            # candidates classified per evaluation (~2 API calls each)
WAIT=0
FETCH_OK=0

nap() { local s=$(( $1 * SLEEP_MULT )); (( s > 0 )) && sleep "$s"; return 0; }
is_sha() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }
to_epoch() { jq -rn --arg t "$1" '$t | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601'; }

scope_guard() { # not_applicable outside the repo whose pipeline this reads
  local top=""
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || top=""
  if [[ -z "$top" || ! -f "$top/$WORKFLOW_PATH" ]]; then
    case "$SUB" in
      contains) emit "UNRESOLVED REASON=not_applicable" 3 ;;
      served) emit "UNRESOLVED REASON=not_applicable BUILD_SHA=-" 3 ;;
      *) emit "ARM=none REASON=not_applicable" 3 ;;
    esac
  fi
}

require() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || emit "$(err_line "missing_dep:$c")" 2
  done
}

default_branch() {
  local b=""
  b="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)" || b=""
  b="${b#origin/}"
  printf '%s' "${b:-main}"
}

fetch_default() { # non-fatal and bounded; ancestry then runs on local objects
  local b
  b="$(default_branch)"
  if GIT_TERMINAL_PROMPT=0 timeout 120 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 \
      fetch -q origin "$b" >&2 2>/dev/null; then
    FETCH_OK=1
  else
    FETCH_OK=0
    printf 'deploy-arm: git fetch origin %s failed (continuing on local objects)\n' "$b" >&2
  fi
}

ancestry() { # rc of: is $1 an ancestor of (or equal to) $2 — 0 yes, 1 no, 128 unknown
  local rc=0
  git merge-base --is-ancestor "$1" "$2" 2>/dev/null || rc=$?
  # A shallow clone answers "no" when history is merely cut: that is could-not-measure.
  if [[ "$rc" == 1 && "$(git rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then rc=128; fi
  printf '%s' "$rc"
}

# ---------------------------------------------------------------------------
# contains / served — Guard 2
# ---------------------------------------------------------------------------
contains_verdict() { # sets CV_LINE CV_RC
  local m="$1" b="$2" rc
  if ! is_sha "$b"; then CV_LINE="UNRESOLVED"; CV_RC=3; return 0; fi  # empty, dev, garbage
  if [[ "$b" == "$m" ]]; then CV_LINE="CONTAINS"; CV_RC=0; return 0; fi
  fetch_default
  rc="$(ancestry "$m" "$b")"
  case "$rc" in
    0) CV_LINE="CONTAINS"; CV_RC=0 ;;
    1) CV_LINE="NOT_CONTAINED"; CV_RC=1 ;;
    *) CV_LINE="UNRESOLVED"; CV_RC=3 ;;
  esac
}

cmd_contains() {
  [[ $# -eq 2 ]] || emit "$(err_line bad_input)" 2
  is_sha "$1" || emit "$(err_line bad_input)" 2
  require git
  scope_guard
  contains_verdict "$1" "$2"
  emit "$CV_LINE" "$CV_RC"
}

cmd_served() {
  [[ $# -eq 1 || $# -eq 2 ]] || emit "$(err_line bad_input)" 2
  is_sha "$1" || emit "$(err_line bad_input)" 2
  local url="${2:-https://app.soleur.ai/health}" body="" i bsha="" shown
  [[ "$url" == https://* ]] || emit "$(err_line bad_input)" 2
  require git curl jq
  scope_guard
  for i in 1 2 3; do
    body="$(curl -s --proto '=https' --max-time 10 --max-filesize 65536 --url "$url" 2>/dev/null)" || body=""
    [[ -n "$body" ]] && break
    [[ "$i" -lt 3 ]] && nap $(( i * 2 ))
  done
  if [[ -n "$body" ]]; then
    bsha="$(printf '%s' "$body" | jq -r '.build_sha // empty' 2>/dev/null)" || bsha=""
  fi
  contains_verdict "$1" "$bsha"
  shown="-"
  [[ "$bsha" =~ ^[A-Za-z0-9._-]{1,64}$ ]] && shown="$bsha"
  emit "$CV_LINE BUILD_SHA=$shown" "$CV_RC"
}

# ---------------------------------------------------------------------------
# find — Guard 1. evaluate() sets EV_LINE/EV_RC and returns; bad input exits.
# ---------------------------------------------------------------------------
# Jobs: name, id, status, conclusion, completed_at, and the conclusion of the
# deploy job's "Deploy via webhook" step (skipped when the ordering guard found
# production already newer — the job then concludes success having deployed nothing).
GH_JOBS_JQ='.jobs[] | [.name, (.id|tostring), .status, (.conclusion // "-"), (.completed_at // "-"), ((.steps // []) | map(select(.name == "Deploy via webhook")) | .[0].conclusion // "-")] | @tsv'
GH_RUNS_JQ='.workflow_runs[] | select(.path == ".github/workflows/web-platform-release.yml") | [.created_at, (.id|tostring), .status, (.conclusion // "-")] | @tsv'

gh_try() { # gh_try <outfile under $TMP> <gh args...> — rc 1 on failure, cause on stderr
  local rel="${1#"$TMP"/}"; shift
  if ! gh "$@" > "$TMP/$rel" 2>"$TMP/gh.err"; then
    printf 'deploy-arm: gh %s failed: %s\n' "${*:1:3}" "$(tail -n 1 "$TMP/gh.err" 2>/dev/null || true)" >&2
    return 1
  fi
}

gh_failed() { # a failed list/jobs call: an error, or (under --wait) one more poll
  EV_LINE="ARM=none REASON=error CAUSE=gh_failed"; EV_RC=2
  [[ "$WAIT" == 1 ]] && EV_RC=4
  return 0
}

job_field() { # job_field <jobsfile> <name> <col 2=id 3=status 4=conclusion 5=completed_at 6=deploy-step>
  awk -F'\t' -v n="$2" -v c="$3" '$1 == n { print $c; exit }' "$1"
}

derive_deploy() { # derive_deploy <jobsfile>
  local jf="$1" st con w wc cancelled=0
  st="$(job_field "$jf" deploy 3)"; con="$(job_field "$jf" deploy 4)"
  if [[ "$st" != "completed" ]]; then printf 'pending'; return 0; fi
  case "$con" in
    success)
      if [[ "$(job_field "$jf" deploy 6)" == "skipped" ]]; then printf 'superseded'; else printf 'success'; fi ;;
    cancelled) printf 'superseded' ;;
    skipped)
      for w in resolve-target migrate verify-migrations verify-doppler-secrets; do
        wc="$(job_field "$jf" "$w" 4)"
        [[ "$wc" == "failure" || "$wc" == "timed_out" ]] && { printf 'blocked'; return 0; }
        [[ "$wc" == "cancelled" ]] && cancelled=1
      done
      if (( cancelled )); then printf 'superseded'
      elif [[ "$(job_field "$jf" resolve-target 4)" == "success" ]]; then printf 'skipped'
      else printf 'blocked'; fi ;;
    *) printf 'failure' ;;
  esac
}

# classify <idx> — fills C_CLASS C_SHA C_DEPLOY C_CAUSE; rc 1 on a gh failure
classify() {
  local i="$1" id="${C_ID[$1]}" jf="$TMP/jobs.$1" lf="$TMP/log.$1"
  local rt rt_st rt_con rt_done a ok line d rc onmain
  gh_try "$jf" api --paginate "repos/{owner}/{repo}/actions/runs/$id/jobs?per_page=100" --jq "$GH_JOBS_JQ" || return 1
  rt="$(job_field "$jf" resolve-target 2)"; rt_st="$(job_field "$jf" resolve-target 3)"
  rt_con="$(job_field "$jf" resolve-target 4)"; rt_done="$(job_field "$jf" resolve-target 5)"
  C_SHA[i]="-"; C_DEPLOY[i]="-"; C_CAUSE[i]="-"
  if [[ "$rt_st" != "completed" ]]; then
    if [[ "${C_STATUS[i]}" == "completed" ]]; then
      C_CLASS[i]="dropped"; C_CAUSE[i]="no_resolve_target"
    else
      C_CLASS[i]="pending"; C_CAUSE[i]="resolve_target_running"
    fi
    return 0
  fi
  if [[ "$rt_con" == "cancelled" || "$rt_con" == "skipped" ]]; then
    C_CLASS[i]="dropped"; C_CAUSE[i]="resolve_target_$rt_con"; return 0
  fi
  if [[ -s "$TMP/sha.$rt" ]]; then
    d="$(cat "$TMP/sha.$rt")"
  else
    ok=0
    for a in 1 2 3; do
      if gh api --allow-escape-sequences "repos/{owner}/{repo}/actions/jobs/$rt/logs" > "$lf" 2>"$TMP/gh.err"; then
        ok=1; break
      fi
      [[ "$a" -lt 3 ]] && nap $(( a * 2 ))
    done
    if [[ "$ok" == 0 ]]; then
      if [[ "$rt_done" != "-" ]] && (( NOW - $(to_epoch "$rt_done") < LOG_GRACE_S )); then
        C_CLASS[i]="pending"; C_CAUSE[i]="log_grace"
      else
        C_CLASS[i]="unresolved"; C_CAUSE[i]="log_read_failed"
      fi
      return 0
    fi
    # Read from the FILE, never `gh … | grep | head` under pipefail (SIGPIPE fakes an
    # empty read). Both keys are anchored at a log line's start (timestamp, then the
    # runner's own text), and the sha must end the line.
    line="$(grep -m1 -oE '^[0-9T:.Z-]+ \[command\][^ ]*git .* --depth=1 origin [0-9a-f]{40}'$'\r''?$' "$lf" || true)"
    [[ -n "$line" ]] || line="$(grep -m1 -oE '^[0-9T:.Z-]+ resolving deploy target for [0-9a-f]{40}'$'\r''?$' "$lf" || true)"
    line="${line%$'\r'}"
    d="${line##* }"
    if ! is_sha "$d"; then C_CLASS[i]="unresolved"; C_CAUSE[i]="log_line_absent"; return 0; fi
    printf '%s' "$d" > "$TMP/sha.$rt"
  fi
  C_SHA[i]="$d"
  # Every arm checks out a commit on the default branch; one that is not (a fork PR's
  # run on a branch named main) is not a deploy of anything.
  # After a successful fetch of the default branch (made after listing), a sha that is
  # still unknown locally is not on it either.
  onmain="$(ancestry "$d" "origin/$(default_branch)")"
  case "$onmain" in
    0) ;;
    1) C_CLASS[i]="reject"; C_CAUSE[i]="not_on_main"; return 0 ;;
    *) if [[ "$FETCH_OK" == 1 ]] && ! git cat-file -e "$d^{commit}" 2>/dev/null; then
         C_CLASS[i]="reject"; C_CAUSE[i]="not_on_main"
       else
         C_CLASS[i]="unresolved"; C_CAUSE[i]="ancestry_128"
       fi
       return 0 ;;
  esac
  if [[ "$d" == "$MERGE" ]]; then
    C_CLASS[i]="exact"
  else
    rc="$(ancestry "$MERGE" "$d")"
    case "$rc" in
      0) C_CLASS[i]="descendant" ;;
      1) C_CLASS[i]="reject"; return 0 ;;
      *) C_CLASS[i]="unresolved"; C_CAUSE[i]="ancestry_128"; return 0 ;;
    esac
  fi
  C_DEPLOY[i]="$(derive_deploy "$jf")"
}

diag() { printf 'deploy-arm: candidate %s class=%s sha=%s cause=%s deploy=%s\n' \
  "${C_ID[$1]}" "${C_CLASS[$1]}" "${C_SHA[$1]}" "${C_CAUSE[$1]}" "${C_DEPLOY[$1]}" >&2; }

arm_line() { # arm_line <idx>
  local i="$1"
  EV_LINE="ARM=${C_ID[i]} DEPLOYED_SHA=${C_SHA[i]} MATCH=${C_CLASS[i]} DEPLOY=${C_DEPLOY[i]} CI=$CI_CONC"
  EV_RC=0; [[ "${C_DEPLOY[i]}" == "pending" ]] && EV_RC=4
  return 0
}

delivering() { [[ "$1" =~ ^(success|failure|blocked|pending)$ ]]; }

reset_candidates() { C_ID=(); C_CREATED=(); C_STATUS=(); C_CLASS=(); C_SHA=(); C_DEPLOY=(); C_CAUSE=(); }

evaluate() {
  local cif="$TMP/ci" row="" ci_created="" ci_started="" ci_updated="" ci_attempt=1 ci_status="" a
  CI_CONC="-"
  for a in 1 2; do  # a transiently empty listing must not read as "no CI run"
    gh_try "$cif" api "repos/{owner}/{repo}/actions/workflows/ci.yml/runs?head_sha=$MERGE&event=push&per_page=10" \
      --jq '.workflow_runs | sort_by(.created_at) | last | if . == null then "" else [.status, (.conclusion // "-"), .created_at, (.run_started_at // .created_at), (.updated_at // .created_at), (.run_attempt // 1 | tostring)] | @tsv end' \
      || { gh_failed; return 0; }
    row="$(grep -m1 . "$cif" || true)"
    [[ -n "$row" ]] && break
    [[ "$a" -lt 2 ]] && nap 3
  done
  local T
  if [[ -n "$row" ]]; then
    IFS=$'\t' read -r ci_status CI_CONC ci_created ci_started ci_updated ci_attempt <<< "$row"
    [[ "$CI_CONC" =~ ^[a-z_-]+$ ]] || CI_CONC="-"
    if [[ "$ci_status" != "completed" ]]; then EV_LINE="ARM=none REASON=ci_pending"; EV_RC=4; return 0; fi
    T="$ci_created"
  else
    CI_CONC="absent"
    git cat-file -e "$MERGE^{commit}" 2>/dev/null || fetch_default
    local ct=""
    ct="$(git log -1 --format=%ct "$MERGE" 2>/dev/null)" || ct=""
    [[ -n "$ct" ]] || emit "$(err_line unknown_commit)" 2
    if (( NOW - ct < CI_ABSENT_AFTER_S )); then EV_LINE="ARM=none REASON=ci_pending"; EV_RC=4; return 0; fi
    T="$(jq -rn --argjson t "$ct" '$t | todate')"
  fi

  # Candidates: first guess (head_sha=) + window (created>=T), one classifier for both.
  local fg="$TMP/fg" win="$TMP/win" all="$TMP/all"
  gh_try "$fg" api "repos/{owner}/{repo}/actions/runs?head_sha=$MERGE&event=workflow_run&per_page=100" --jq "$GH_RUNS_JQ" \
    || { gh_failed; return 0; }
  reset_candidates
  local n=0 created id st con i ci_started_e=0
  [[ -n "$ci_started" ]] && ci_started_e="$(to_epoch "$ci_started")"

  # Fast path: CI attempt 1 and completed — the first guess alone, newest first.
  if [[ -n "$row" && "$ci_attempt" == "1" ]]; then
    while IFS=$'\t' read -r created id st con; do
      [[ -n "$id" ]] || continue
      C_ID[n]="$id"; C_CREATED[n]="$(to_epoch "$created")"; C_STATUS[n]="$st"
      classify "$n" || { gh_failed; return 0; }
      diag "$n"
      if [[ "${C_CLASS[n]}" == "exact" ]] && delivering "${C_DEPLOY[n]}"; then arm_line "$n"; return 0; fi
      n=$((n + 1))
    done < <(LC_ALL=C sort -r "$fg")
    reset_candidates; n=0
  fi

  gh_try "$win" api --paginate "repos/{owner}/{repo}/actions/workflows/web-platform-release.yml/runs?event=workflow_run&created=%3E%3D$T&per_page=100" --jq "$GH_RUNS_JQ" \
    || { gh_failed; return 0; }
  # Sort AFTER --paginate: --jq runs per page, so per-page order is not global order.
  # Duplicates (a run in both lists) keep the window's row, the fresher one.
  LC_ALL=C sort -s -t$'\t' -k1,1 -k2,2 "$win" "$fg" | awk -F'\t' '!seen[$2]++' > "$all"
  local total cap_hit=0 skip=0
  total="$(grep -c . "$all" || true)"
  # Past the cap keep the NEWEST candidates: the merge's own arm is created last.
  if (( total > CAND_CAP )); then cap_hit=1; skip=$(( total - CAND_CAP )); fi
  # Fetch AFTER listing, so every SHA a listed arm checked out is local.
  fetch_default
  while IFS=$'\t' read -r created id st con; do
    [[ -n "$id" ]] || continue
    if (( skip > 0 )); then skip=$((skip - 1)); continue; fi
    C_ID[n]="$id"; C_CREATED[n]="$(to_epoch "$created")"; C_STATUS[n]="$st"
    classify "$n" || { gh_failed; return 0; }
    diag "$n"
    n=$((n + 1))
  done < "$all"

  local best=-1 any_pending=0 first_unres="" any_exact_after=0
  for (( i = 0; i < n; i++ )); do
    case "${C_CLASS[i]}" in
      pending) any_pending=1 ;;
      unresolved) [[ -n "$first_unres" ]] || first_unres="${C_CAUSE[i]}" ;;
      exact) (( C_CREATED[i] >= ci_started_e )) && any_exact_after=1 ;;
    esac
  done

  # Rule 1 — newest exact arm created at/after the CI run's start, delivering or pending.
  # Only this merge's CI can produce an exact arm; after a re-run, a later undecided
  # candidate may be the re-run's own arm.
  for (( i = 0; i < n; i++ )); do
    [[ "${C_CLASS[i]}" == "exact" ]] || continue
    (( C_CREATED[i] >= ci_started_e )) || continue
    delivering "${C_DEPLOY[i]}" && best="$i"
  done
  if (( best >= 0 )); then
    if [[ "$ci_attempt" != "1" ]]; then
      for (( i = best + 1; i < n; i++ )); do
        [[ "${C_CLASS[i]}" == "pending" ]] && { EV_LINE="ARM=none REASON=arm_pending"; EV_RC=4; return 0; }
        [[ "${C_CLASS[i]}" == "unresolved" ]] && { EV_LINE="ARM=none REASON=unresolved CAUSE=${C_CAUSE[i]}"; EV_RC=3; return 0; }
      done
    fi
    arm_line "$best"; return 0
  fi
  # The merge's own arm is created seconds after its CI completes.
  if [[ -n "$row" && "$any_exact_after" == 0 ]] && (( NOW - $(to_epoch "$ci_updated") < LOG_GRACE_S )); then
    EV_LINE="ARM=none REASON=arm_pending"; EV_RC=4; return 0
  fi

  # Any undecided candidate may be the merge's own arm (or an earlier descendant):
  # settle nothing below until it is decided.
  (( any_pending )) && { EV_LINE="ARM=none REASON=arm_pending"; EV_RC=4; return 0; }
  [[ -n "$first_unres" ]] && { EV_LINE="ARM=none REASON=unresolved CAUSE=$first_unres"; EV_RC=3; return 0; }

  # Rule 2 — a descendant delivered it: the earliest successful one, else the earliest
  # that attempted (failure / blocked / pending).
  best=-1
  for (( i = 0; i < n; i++ )); do
    [[ "${C_CLASS[i]}" == "descendant" && "${C_DEPLOY[i]}" == "success" ]] && { best="$i"; break; }
  done
  if (( best < 0 )); then
    for (( i = 0; i < n; i++ )); do
      [[ "${C_CLASS[i]}" == "descendant" ]] && delivering "${C_DEPLOY[i]}" && { best="$i"; break; }
    done
  fi
  (( best >= 0 )) && { arm_line "$best"; return 0; }

  # Rule 3 — newest exact arm of this CI run that did not deliver (skipped / superseded).
  for (( i = 0; i < n; i++ )); do
    [[ "${C_CLASS[i]}" == "exact" ]] && (( C_CREATED[i] >= ci_started_e )) && best="$i"
  done
  (( best >= 0 )) && { arm_line "$best"; return 0; }

  # Rule 4 — no run.
  [[ -n "$row" && "$ci_attempt" != "1" ]] && { EV_LINE="ARM=none REASON=arm_pending"; EV_RC=4; return 0; }
  (( cap_hit )) && { EV_LINE="ARM=none REASON=unresolved CAUSE=cap_hit"; EV_RC=3; return 0; }
  [[ "$CI_CONC" == "absent" ]] && { EV_LINE="ARM=none REASON=ci_absent"; EV_RC=3; return 0; }
  EV_LINE="ARM=none REASON=no_candidate"; EV_RC=3
}

cmd_find() {
  local cap=120
  if [[ "${1:-}" == "--wait" ]]; then
    WAIT=1; shift
    if [[ "${1:-}" =~ ^[0-9]{1,4}$ && $# -ge 2 ]]; then cap="$1"; shift; fi
  fi
  [[ $# -eq 1 ]] || emit "$(err_line bad_input)" 2
  MERGE="$1"
  is_sha "$MERGE" || emit "$(err_line bad_input)" 2
  require gh git jq timeout
  scope_guard
  local iter=0 last
  while :; do
    evaluate
    [[ "$WAIT" == 1 && "$EV_RC" == 4 ]] || emit "$EV_LINE" "$EV_RC"
    iter=$((iter + 1))
    if (( iter >= cap )); then
      if [[ "$EV_LINE" == *REASON=* ]]; then
        last="${EV_LINE#*REASON=}"; last="LAST=${last%% *}"
        [[ "$EV_LINE" == *CAUSE=* ]] && last="$last CAUSE=${EV_LINE##*CAUSE=}"
      else
        last="LAST=deploy_pending ${EV_LINE%% *}"
      fi
      emit "ARM=none REASON=timeout $last" 3
    fi
    printf 'deploy-arm: waiting (%s/%s): %s\n' "$iter" "$cap" "$EV_LINE" >&2
    nap 60
  done
}

case "$SUB" in
  find) shift; cmd_find "$@" ;;
  contains) shift; cmd_contains "$@" ;;
  served) shift; cmd_served "$@" ;;
  *) SUB="find"; printf 'usage: deploy-arm.sh find [--wait [POLLS]] <sha> | contains <sha> <build_sha> | served <sha> [https-url]\n' >&2
     emit "$(err_line bad_input)" 2 ;;
esac
