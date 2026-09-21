#!/usr/bin/env bash
# deploy-arm.sh — which web-platform-release deploy arm delivered a merge, and does
# production serve it? The single place ship and postmerge decide this (#8492).
#
# A `workflow_run` run's `head_sha` is the tip of main when the run FIRED, not the
# commit it deploys. So `actions/runs?head_sha=<merge>&event=workflow_run` misses the
# real arm when main moved before the merge's CI completed (#8297) and returns the
# PREVIOUS merge's arm when that arm fired after main reached this merge (#8391).
# The arm is identified here by what its `resolve-target` job checks out:
# `depth=1 origin <sha>` in that job's log (fallback: the workflow's own
# `resolving deploy target for <sha>` echo). The `head_sha=` query survives only as
# a first guess that goes through the same classifier.
#
# Usage:
#   deploy-arm.sh find [--wait [MIN]] <MERGE_SHA>
#   deploy-arm.sh contains <MERGE_SHA> <BUILD_SHA>
#   deploy-arm.sh served <MERGE_SHA> [URL]
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
EMITTED=0
TMP="$(mktemp -d -t deploy-arm.XXXXXXXX)"

emit() { # emit <line> <rc> — the only writer of stdout besides the ERR trap
  printf '%s\n' "$1"
  EMITTED=1
  exit "$2"
}

err_line() {
  case "$SUB" in
    contains) printf 'ERROR CAUSE=%s' "$1" ;;
    served) printf 'ERROR CAUSE=%s BUILD_SHA=-' "$1" ;;
    *) printf 'ARM=none REASON=error CAUSE=%s' "$1" ;;
  esac
}

on_err() {
  local line="$1" cmd="$2"
  if [[ "$EMITTED" == 0 ]]; then
    printf 'deploy-arm: internal error line=%s cmd=%s\n' "$line" "${cmd%% *}" >&2
    printf '%s\n' "$(err_line internal)"
    EMITTED=1
  fi
  exit 2
}
trap 'on_err "$LINENO" "$BASH_COMMAND"' ERR
trap 'rm -rf "$TMP"' EXIT

NOW="${DEPLOY_ARM_NOW:-$(date +%s)}"
SLEEP_MULT="${DEPLOY_ARM_SLEEP:-1}"
WORKFLOW_PATH=".github/workflows/web-platform-release.yml"
LOG_GRACE_S=180
CI_ABSENT_AFTER_S=600
CAND_CAP=30

nap() { local s=$(( $1 * SLEEP_MULT )); (( s > 0 )) && sleep "$s"; return 0; }
is_sha() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }
to_epoch() { jq -rn --arg t "$1" '$t | fromdateiso8601'; }

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

fetch_default() { # non-fatal: ancestry then runs on what is local, rc 128 -> unresolved
  git fetch -q origin "$(default_branch)" >&2 2>/dev/null || \
    printf 'deploy-arm: git fetch origin %s failed (continuing on local objects)\n' "$(default_branch)" >&2
}

ancestry() { # prints 0|1|128-ish rc of: is MERGE an ancestor of (or equal to) $2
  local rc=0
  git merge-base --is-ancestor "$1" "$2" 2>/dev/null || rc=$?
  printf '%s' "$rc"
}

# ---------------------------------------------------------------------------
# contains / served — Guard 2
# ---------------------------------------------------------------------------
contains_verdict() { # sets CV_LINE CV_RC
  local m="$1" b="$2" rc
  if [[ -z "$b" || "$b" == "dev" ]] || ! is_sha "$b"; then CV_LINE="UNRESOLVED"; CV_RC=3; return 0; fi
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
  require git curl jq
  scope_guard
  local url="${2:-https://app.soleur.ai/health}" body="" i bsha="" shown
  for i in 1 2 3; do
    body="$(curl -s --max-time 10 "$url" 2>/dev/null)" || body=""
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
# find — Guard 1. evaluate() sets EV_LINE/EV_RC; errors emit+exit directly.
# ---------------------------------------------------------------------------
GH_JOBS_JQ='.jobs[] | [.name, (.id|tostring), .status, (.conclusion // "-"), (.completed_at // "-")] | @tsv'
GH_RUNS_JQ='.workflow_runs[] | select(.path == ".github/workflows/web-platform-release.yml") | [.created_at, (.id|tostring), .status, (.conclusion // "-")] | @tsv'

gh_or_die() { # gh_or_die <outfile under $TMP> <gh args...>
  local rel="${1#"$TMP"/}"; shift
  if ! gh "$@" > "$TMP/$rel" 2>>"$TMP/gh.err"; then
    printf 'deploy-arm: gh %s failed\n' "${*:1:3}" >&2
    emit "$(err_line gh_failed)" 2
  fi
}

job_field() { # job_field <jobsfile> <name> <col 2=id 3=status 4=conclusion 5=completed_at>
  awk -F'\t' -v n="$2" -v c="$3" '$1 == n { print $c; exit }' "$1"
}

derive_deploy() { # derive_deploy <jobsfile>
  local jf="$1" st con w wc
  st="$(job_field "$jf" deploy 3)"; con="$(job_field "$jf" deploy 4)"
  if [[ -z "$st" || "$st" != "completed" ]]; then printf 'pending'; return 0; fi
  case "$con" in
    success) printf 'success' ;;
    cancelled) printf 'superseded' ;;
    skipped)
      for w in resolve-target migrate verify-migrations verify-doppler-secrets; do
        wc="$(job_field "$jf" "$w" 4)"
        [[ "$wc" == "failure" || "$wc" == "timed_out" ]] && { printf 'blocked'; return 0; }
      done
      for w in resolve-target migrate verify-migrations verify-doppler-secrets; do
        [[ "$(job_field "$jf" "$w" 4)" == "cancelled" ]] && { printf 'superseded'; return 0; }
      done
      if [[ "$(job_field "$jf" resolve-target 4)" == "success" ]]; then printf 'skipped'; else printf 'blocked'; fi ;;
    *) printf 'failure' ;;
  esac
}

# classify <idx> — fills C_CLASS C_SHA C_DEPLOY C_CAUSE for candidate idx
classify() {
  local i="$1" id="${C_ID[$1]}" jf="$TMP/jobs.$1" lf="$TMP/log.$1"
  local rt rt_st rt_done a ok line d rc
  gh_or_die "$jf" api --paginate "repos/{owner}/{repo}/actions/runs/$id/jobs?per_page=100" --jq "$GH_JOBS_JQ"
  rt="$(job_field "$jf" resolve-target 2)"; rt_st="$(job_field "$jf" resolve-target 3)"
  rt_done="$(job_field "$jf" resolve-target 5)"
  C_SHA[i]="-"; C_DEPLOY[i]="-"; C_CAUSE[i]="-"
  if [[ "$rt_st" != "completed" ]]; then
    if [[ "${C_STATUS[i]}" == "completed" ]]; then
      C_CLASS[i]="dropped"; C_CAUSE[i]="no_resolve_target"
    else
      C_CLASS[i]="pending"; C_CAUSE[i]="resolve_target_running"
    fi
    return 0
  fi
  ok=0
  for a in 1 2 3; do
    if gh api --allow-escape-sequences "repos/{owner}/{repo}/actions/jobs/$rt/logs" > "$lf" 2>>"$TMP/gh.err"; then
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
  # Read from the FILE, never `gh … | grep | head` under pipefail (SIGPIPE fakes an empty read).
  line="$(grep -m1 -oE 'depth=1 origin [0-9a-f]{40}' "$lf" || true)"
  [[ -n "$line" ]] || line="$(grep -m1 -oE 'resolving deploy target for [0-9a-f]{40}' "$lf" || true)"
  line="${line%%$'\n'*}"
  d="${line##* }"
  if ! is_sha "$d"; then C_CLASS[i]="unresolved"; C_CAUSE[i]="log_line_absent"; return 0; fi
  C_SHA[i]="$d"
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
  local i="$1" m="exact"
  [[ "${C_CLASS[i]}" == "descendant" ]] && m="descendant"
  EV_LINE="ARM=${C_ID[i]} DEPLOYED_SHA=${C_SHA[i]} MATCH=$m DEPLOY=${C_DEPLOY[i]} CI=$CI_CONC"
  EV_RC=0; [[ "${C_DEPLOY[i]}" == "pending" ]] && EV_RC=4
  return 0
}

delivering() { [[ "$1" =~ ^(success|failure|blocked|pending)$ ]]; }

evaluate() {
  TMP_EVAL="$TMP/eval.$RANDOM"; mkdir -p "$TMP_EVAL"
  local cif="$TMP_EVAL/ci" row ci_created="" ci_started="" ci_updated="" ci_attempt=1 ci_status=""
  CI_ABSENT=0; CI_CONC="-"
  gh_or_die "$cif" api "repos/{owner}/{repo}/actions/workflows/ci.yml/runs?head_sha=$MERGE&event=push&per_page=10" \
    --jq '.workflow_runs | sort_by(.created_at) | last | if . == null then "" else [.status, (.conclusion // "-"), .created_at, (.run_started_at // .created_at), (.updated_at // .created_at), (.run_attempt // 1 | tostring)] | @tsv end'
  row="$(grep -m1 . "$cif" || true)"
  local T
  if [[ -n "$row" ]]; then
    IFS=$'\t' read -r ci_status CI_CONC ci_created ci_started ci_updated ci_attempt <<< "$row"
    if [[ "$ci_status" != "completed" ]]; then EV_LINE="ARM=none REASON=ci_pending"; EV_RC=4; return 0; fi
    T="$ci_created"
  else
    CI_CONC="absent"
    git cat-file -e "$MERGE^{commit}" 2>/dev/null || fetch_default
    local ct=""
    ct="$(git log -1 --format=%ct "$MERGE" 2>/dev/null)" || ct=""
    [[ -n "$ct" ]] || emit "$(err_line not_on_main)" 2
    if (( NOW - ct < CI_ABSENT_AFTER_S )); then EV_LINE="ARM=none REASON=ci_pending"; EV_RC=4; return 0; fi
    CI_ABSENT=1
    T="$(jq -rn --argjson t "$ct" '$t | todate')"
  fi

  # Candidates: first guess (head_sha=) + window (created>=T), one classifier for both.
  local fg="$TMP_EVAL/fg" win="$TMP_EVAL/win" all="$TMP_EVAL/all"
  gh_or_die "$fg" api "repos/{owner}/{repo}/actions/runs?head_sha=$MERGE&event=workflow_run&per_page=100" --jq "$GH_RUNS_JQ"
  C_ID=(); C_CREATED=(); C_STATUS=(); C_CLASS=(); C_SHA=(); C_DEPLOY=(); C_CAUSE=()
  local n=0 created id st con i ci_started_e
  ci_started_e=0; [[ -n "$ci_started" ]] && ci_started_e="$(to_epoch "$ci_started")"

  # Fast path: CI attempt 1 and completed — the first guess alone, newest first.
  if [[ -z "$row" || "$ci_attempt" != "1" ]]; then :; else
    while IFS=$'\t' read -r created id st con; do
      [[ -n "$id" ]] || continue
      C_ID[n]="$id"; C_CREATED[n]="$created"; C_STATUS[n]="$st"
      classify "$n"; diag "$n"
      if [[ "${C_CLASS[n]}" == "exact" ]] && delivering "${C_DEPLOY[n]}"; then arm_line "$n"; return 0; fi
      n=$((n + 1))
    done < <(sort -r "$fg")
    C_ID=(); C_CREATED=(); C_STATUS=(); C_CLASS=(); C_SHA=(); C_DEPLOY=(); C_CAUSE=(); n=0
  fi

  gh_or_die "$win" api --paginate "repos/{owner}/{repo}/actions/workflows/web-platform-release.yml/runs?event=workflow_run&created=%3E%3D$T&per_page=100" --jq "$GH_RUNS_JQ"
  # Sort AFTER --paginate: --jq runs per page, so per-page order is not global order.
  sort -u "$fg" "$win" | awk -F'\t' '!seen[$2]++' > "$all"
  local total cap_hit=0
  total="$(grep -c . "$all" || true)"
  (( total > CAND_CAP )) && cap_hit=1
  # Fetch AFTER listing, so every SHA a listed arm checked out is local.
  fetch_default
  while IFS=$'\t' read -r created id st con; do
    [[ -n "$id" ]] || continue
    (( n >= CAND_CAP )) && break
    C_ID[n]="$id"; C_CREATED[n]="$(to_epoch "$created")"; C_STATUS[n]="$st"
    classify "$n"; diag "$n"
    n=$((n + 1))
  done < "$all"

  # Rule 1 — newest exact arm created at/after the CI run's start, delivering or pending.
  local best=-1 later_pending=0
  for (( i = 0; i < n; i++ )); do
    [[ "${C_CLASS[i]}" == "exact" ]] || continue
    (( C_CREATED[i] >= ci_started_e )) || continue
    delivering "${C_DEPLOY[i]}" && best="$i"
  done
  if (( best >= 0 )); then
    if [[ "$ci_attempt" != "1" ]]; then
      for (( i = best + 1; i < n; i++ )); do [[ "${C_CLASS[i]}" == "pending" ]] && later_pending=1; done
      (( later_pending )) && { EV_LINE="ARM=none REASON=arm_pending"; EV_RC=4; return 0; }
    fi
    arm_line "$best"; return 0
  fi
  # The merge's own arm is created seconds after its CI completes.
  local any_exact_after=0
  for (( i = 0; i < n; i++ )); do
    [[ "${C_CLASS[i]}" == "exact" ]] && (( C_CREATED[i] >= ci_started_e )) && any_exact_after=1
  done
  if [[ -n "$row" && "$any_exact_after" == 0 && -n "$ci_updated" ]] && (( NOW - $(to_epoch "$ci_updated") < LOG_GRACE_S )); then
    EV_LINE="ARM=none REASON=arm_pending"; EV_RC=4; return 0
  fi

  # Rule 2 — earliest delivering descendant, unless an earlier candidate is undecided.
  local blk_pending=0 blk_unres=""
  for (( i = 0; i < n; i++ )); do
    case "${C_CLASS[i]}" in
      pending) blk_pending=1 ;;
      unresolved) [[ -n "$blk_unres" ]] || blk_unres="${C_CAUSE[i]}" ;;
      descendant)
        if delivering "${C_DEPLOY[i]}"; then
          (( blk_pending )) && { EV_LINE="ARM=none REASON=arm_pending"; EV_RC=4; return 0; }
          [[ -n "$blk_unres" ]] && { EV_LINE="ARM=none REASON=unresolved CAUSE=$blk_unres"; EV_RC=3; return 0; }
          arm_line "$i"; return 0
        fi ;;
    esac
  done

  # Rule 3 — newest exact arm that did not deliver (skipped / superseded).
  best=-1
  for (( i = 0; i < n; i++ )); do
    [[ "${C_CLASS[i]}" == "exact" ]] && best="$i"
  done
  if (( best >= 0 )); then
    for (( i = best + 1; i < n; i++ )); do
      [[ "${C_CLASS[i]}" == "pending" ]] && { EV_LINE="ARM=none REASON=arm_pending"; EV_RC=4; return 0; }
    done
    arm_line "$best"; return 0
  fi

  # Rule 4 — no run.
  (( blk_pending )) && { EV_LINE="ARM=none REASON=arm_pending"; EV_RC=4; return 0; }
  [[ -n "$blk_unres" ]] && { EV_LINE="ARM=none REASON=unresolved CAUSE=$blk_unres"; EV_RC=3; return 0; }
  (( cap_hit )) && { EV_LINE="ARM=none REASON=unresolved CAUSE=cap_hit"; EV_RC=3; return 0; }
  (( CI_ABSENT )) && { EV_LINE="ARM=none REASON=ci_absent"; EV_RC=3; return 0; }
  EV_LINE="ARM=none REASON=no_candidate"; EV_RC=3
}

cmd_find() {
  local wait=0 cap=120
  if [[ "${1:-}" == "--wait" ]]; then
    wait=1; shift
    if [[ "${1:-}" =~ ^[0-9]+$ && $# -ge 2 ]]; then cap="$1"; shift; fi
  fi
  [[ $# -eq 1 ]] || emit "$(err_line bad_input)" 2
  MERGE="$1"
  is_sha "$MERGE" || emit "$(err_line bad_input)" 2
  require gh git jq
  scope_guard
  local iter=0 reason
  while :; do
    evaluate
    [[ "$wait" == 1 && "$EV_RC" == 4 ]] || emit "$EV_LINE" "$EV_RC"
    iter=$((iter + 1))
    if (( iter >= cap )); then
      reason="${EV_LINE#*REASON=}"; reason="${reason%% *}"
      [[ "$EV_LINE" == *REASON=* ]] || reason="deploy_pending"
      emit "ARM=none REASON=timeout LAST=$reason" 3
    fi
    printf 'deploy-arm: waiting (%s/%s min): %s\n' "$iter" "$cap" "$EV_LINE" >&2
    nap 60
  done
}

case "$SUB" in
  find) shift; cmd_find "$@" ;;
  contains) shift; cmd_contains "$@" ;;
  served) shift; cmd_served "$@" ;;
  *) SUB="find"; emit "$(err_line bad_input)" 2 ;;
esac
