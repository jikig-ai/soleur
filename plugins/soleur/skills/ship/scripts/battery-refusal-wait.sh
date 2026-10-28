#!/usr/bin/env bash
# Bounded wait for a REFUSED local battery, then "CI is the gate" (P4d, #10924).
#
# WHEN THIS RUNS. `soleur:ship` Phase 4 launches the detached local battery. When another
# worktree already runs a full-gate battery, `scripts/test-all.sh` refuses with rc=4 ("REFUSED,
# nothing ran") and the log carries
#     refusing a full-gate run <dash> N sibling full-gate run(s) already in flight
# That is the ONLY refusal time can clear. This script waits for the sibling to drain, bounded
# by a wall-clock budget, and prints a machine verdict. It does NOT change the runner's rc
# contract (many consumers); the verdict lives here, ship-side.
#
# USAGE
#   battery-refusal-wait.sh --log FILE --state FILE [--budget-s N] [--interval-s N] [--full]
#   battery-refusal-wait.sh --classify-only FILE     # prints class=contention|not-waitable
#
#   --log FILE      the refused run's log
#   --state FILE    episode state: the epoch of the first call, so the budget is shared across
#                   relaunches. Create it EMPTY with mktemp; an empty file starts an episode.
#   --budget-s N    wall-clock budget (default 1800: the documented escalation point; a full
#                   gate runs ~35-45 min, so on a typical contended start the budget lapses to
#                   CI, which is intended)
#   --interval-s N  poll interval (default 60). Flags only: no environment variable is read, so
#                   a stale export cannot shorten the wait into a CI_IS_THE_GATE verdict.
#   --full          the operator asked for the full local run by name; never defers
#
# EXIT CONTRACT (the caller branches on this, never on the prose):
#   42  CI_IS_THE_GATE   budget elapsed, sibling still running, diff positively resolved with no
#                        infra trigger, no --full: record it and continue WITHOUT local evidence
#   10  RETRY            capacity reports idle (CAPACITY_OK measured_runs=0): relaunch the battery
#   12  QUEUE_IN_LOCK    the local run is the sole blocking gate (infra diff, diff unresolved) or
#                        was asked for by name (--full): queue inside the lock instead
#   11  NOT_WAITABLE     time cannot clear this refusal (or capacity was never readable): stop
#    2  usage / bad state
#   anything else       an error: the caller MUST stop
#
# ONLY 42 CONTINUES, and the oddness of that number is the point (as battery-owed.sh SKIPPABLE):
# a `set -u` abort exits 1, a missing file 127, a signal 128+N, and none of those may read as
# "skip the local battery".
#
# INFRA. `apps/web-platform/infra/` has no required CI check (#6480), so CI is NOT its gate and a
# deferral there would delete the only blocking one. The predicate mirrors scripts/test-all.sh
# (the `_diff_names` assembly and `_infra_in_diff`): the same two triggers, rename SOURCES
# included (`--name-status -M`), untracked files included, unanchored substring match, and any
# git failure fails CLOSED. The suite pins both literals against the live runner.
#
# NOT WAITABLE (G1): SOLEUR_SUBAGENT=1 is a declared env var polling cannot clear; selection
# refusals (below-floor, zero-selected, ...) mean a gutted index; any [FAIL]/[KILLED] means the
# battery ran. All stay stop-and-fix. `AFFECTED_FALLBACK` is a companion line (a degraded
# affected run), not an exclusion.
#
# Records, never claims: the PR Test plan line in references/battery-refusal-wait.md says the
# local run was NOT executed. Suite: plugins/soleur/test/ship-battery-refusal-wait.test.sh.
set -uo pipefail

RC_RETRY=10
RC_NOT_WAITABLE=11
RC_QUEUE=12
RC_USAGE=2
RC_CI=42

# Strip C0 controls, DEL and the Unicode line separators before printing: the log and the
# capacity output are not trusted to be single-line (same helper as battery-owed.sh).
_ctx_lib="$(cd "${BASH_SOURCE[0]%/*}/../../../scripts/lib" 2>/dev/null && pwd -P)/context-sanitize.sh"
_ctx_lib="${_ctx_lib:-/nonexistent/context-sanitize.sh}"
# shellcheck source=/dev/null
[[ -r "$_ctx_lib" ]] && . "$_ctx_lib" || true
declare -F soleur_ctx_sanitize >/dev/null 2>&1 \
  || soleur_ctx_sanitize() { LC_ALL=C tr -d '\000-\037\177' | LC_ALL=C sed $'s/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g'; }
_sanitize() { printf '%s' "$*" | soleur_ctx_sanitize; }
say() { printf 'BATTERY_REFUSAL_WAIT %s\n' "$(_sanitize "$*")"; }

WAITED=0
verdict() { # <NAME> <exit> <reason>
  say "verdict=$1 waited_s=$WAITED reason=$3"
  exit "$2"
}
usage() {
  printf 'BATTERY_REFUSAL_WAIT usage: %s\n' "$(_sanitize "$1")" >&2
  exit "$RC_USAGE"
}

LOG=""; STATE=""; BUDGET_S=1800; INTERVAL_S=60; FULL=0; CLASSIFY_ONLY=""
is_posint() { [[ "$1" =~ ^[1-9][0-9]{0,5}$ ]]; }
while (( $# )); do
  case "$1" in
    --log)           (( $# >= 2 )) || usage "--log needs a value"; LOG="$2"; shift 2 ;;
    --state)         (( $# >= 2 )) || usage "--state needs a value"; STATE="$2"; shift 2 ;;
    --budget-s)      (( $# >= 2 )) && is_posint "$2" || usage "--budget-s needs a positive integer"; BUDGET_S="$2"; shift 2 ;;
    --interval-s)    (( $# >= 2 )) && is_posint "$2" || usage "--interval-s needs a positive integer"; INTERVAL_S="$2"; shift 2 ;;
    --full)          FULL=1; shift ;;
    --classify-only) (( $# >= 2 )) || usage "--classify-only needs a file"; CLASSIFY_ONLY="$2"; shift 2 ;;
    *)               usage "unknown argument: $1" ;;
  esac
done

# --- classifier: whole-log scan, CR stripped, full refusal shape required -----------------------
# echoes `contention` or `not-waitable:<reason>`.
classify() { # <file>
  local f="$1" body bad
  [[ -f "$f" && -r "$f" ]] || { echo "not-waitable:log-missing"; return 0; }
  body="$(LC_ALL=C tr -d '\r' < "$f")"
  [[ -n "$body" ]] || { echo "not-waitable:log-empty"; return 0; }
  if grep -qE '\[FAIL\]|\[KILLED\]' <<<"$body"; then echo "not-waitable:battery-ran"; return 0; fi
  if grep -qF 'AFFECTED_UNRESOLVED' <<<"$body"; then echo "not-waitable:selection-refusal"; return 0; fi
  bad="$(grep -E 'AFFECTED_GATE_REFUSED reason=' <<<"$body" | grep -vE 'reason=runner-refused')"
  if [[ -n "$bad" ]]; then echo "not-waitable:gate-refusal"; return 0; fi
  if grep -qF 'SOLEUR_SUBAGENT=1 is set' <<<"$body"; then echo "not-waitable:subagent-env"; return 0; fi
  if grep -qE 'refusing a full-gate run .* [0-9]+ sibling full-gate run\(s\) already in flight' <<<"$body"; then
    echo "contention"; return 0
  fi
  echo "not-waitable:not-a-sibling-refusal"
}

if [[ -n "$CLASSIFY_ONLY" ]]; then
  c="$(classify "$CLASSIFY_ONLY")"
  [[ "$c" == contention ]] && echo "class=contention" || echo "class=not-waitable"
  exit 0
fi

[[ -n "$LOG" ]] || usage "--log is required"
[[ -n "$STATE" ]] || usage "--state is required"

# DISPATCH-ANCHOR
class="$(classify "$LOG")"
if [[ "$class" != contention ]]; then
  verdict NOT_WAITABLE "$RC_NOT_WAITABLE" "${class#not-waitable:}"
fi

# --- clock: `date +%s` via PATH (a test seam, not an authority grant) ----------------------------
clock() {
  local n
  n="$(date +%s)" || return 1
  [[ "$n" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$n"
}
CALL_START="$(clock)" || usage "cannot read the clock"

# --- episode state: the epoch of the first call, written atomically BEFORE the first poll -------
init_episode() {
  local cur tmp
  [[ -e "$STATE" ]] || usage "--state file does not exist (create it with mktemp)"
  cur="$(tr -d '[:space:]' < "$STATE")"
  if [[ -z "$cur" ]]; then
    tmp="$(mktemp "${STATE}.XXXXXX")" || usage "cannot write the state file"
    printf '%s\n' "$CALL_START" > "$tmp" && mv -f "$tmp" "$STATE" || { rm -f "$tmp"; usage "cannot write the state file"; }
    cur="$CALL_START"
  fi
  [[ "$cur" =~ ^[0-9]+$ ]] || usage "state file holds a non-integer epoch"
  (( cur <= CALL_START )) || usage "state file holds a future epoch"
  EPOCH="$cur"
}
init_episode  # EPISODE-INIT

# --- capacity ------------------------------------------------------------------------------------
# CAP is one of: idle | ok | contended | unknown | unreadable. Only `CAPACITY_OK` with
# `measured_runs=0` on the SAME line is idle: CAPACITY_CONTENDED reason=low_tmp also prints
# measured_runs=0, and `measured_runs=?` is a degraded reading, neither is an idle host.
CALL_TIMEOUT=$(( INTERVAL_S < 30 ? INTERVAL_S : 30 ))
poll_capacity() {
  local top out ok_line
  CAP=unreadable
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  [[ -f "$top/scripts/test-all.sh" ]] || return 0
  out="$(timeout -k 1 "$CALL_TIMEOUT" bash "$top/scripts/test-all.sh" --capacity 2>&1)" || return 0
  ok_line="$(grep -F 'CAPACITY_OK' <<<"$out" | head -1)"
  if [[ "$out" == *CAPACITY_OK* && "$ok_line" =~ measured_runs=0([^0-9]|$) ]]; then
    CAP=idle
  elif [[ "$out" == *CAPACITY_OK* ]]; then
    CAP=ok
  elif [[ "$out" == *CAPACITY_CONTENDED* ]]; then
    CAP=contended
  elif [[ "$out" == *CAPACITY_UNKNOWN* ]]; then
    CAP=unknown
  fi
  return 0
}

SEEN=0
while :; do
  poll_capacity
  case "$CAP" in
    idle) verdict RETRY "$RC_RETRY" capacity-idle ;;
    ok|contended) SEEN=1 ;;
  esac
  now="$(clock)" || usage "cannot read the clock"
  elapsed=$(( now - EPOCH ))
  WAITED="$elapsed"
  if (( elapsed >= BUDGET_S )); then break; fi
  say "WAITING elapsed_s=$elapsed budget_s=$BUDGET_S capacity=$CAP"
  remaining=$(( BUDGET_S - elapsed ))
  sleep "$(( INTERVAL_S < remaining ? INTERVAL_S : remaining ))"
done

# --- infra predicate (mirrors scripts/test-all.sh; see the header) --------------------------------
infra_state() { # echoes clean | infra | unresolved
  local names="" out
  out="$(git -c core.quotePath=false diff --name-only origin/main...HEAD 2>/dev/null)" || { echo unresolved; return 0; }
  names="${names}
${out}"
  out="$(git -c core.quotePath=false diff --name-only HEAD 2>/dev/null)" || { echo unresolved; return 0; }
  names="${names}
${out}"
  out="$(git -c core.quotePath=false diff --name-status -M HEAD 2>/dev/null)" || { echo unresolved; return 0; }
  names="${names}
${out}"
  out="$(git -c core.quotePath=false diff --name-status -M origin/main...HEAD 2>/dev/null)" || { echo unresolved; return 0; }
  names="${names}
${out}"
  out="$(git ls-files --others --exclude-standard 2>/dev/null)" || { echo unresolved; return 0; }
  names="${names}
${out}"
  if grep -qF 'apps/web-platform/infra/' <<<"$names" \
    || grep -qF '.github/workflows/apply-web-platform-infra.yml' <<<"$names"; then
    echo infra
  else
    echo clean
  fi
}

# --- the chokepoint: every path to exit 42 flows through this one case ----------------------------
infra="$(infra_state)"
case "$SEEN:$FULL:$infra" in
  0:*)
    verdict NOT_WAITABLE "$RC_NOT_WAITABLE" capacity-unreadable ;;
  1:1:*)
    verdict QUEUE_IN_LOCK "$RC_QUEUE" full-requested ;;
  1:0:infra)
    verdict QUEUE_IN_LOCK "$RC_QUEUE" infra-diff ;;
  1:0:unresolved)
    verdict QUEUE_IN_LOCK "$RC_QUEUE" diff-unresolved ;;
  1:0:clean)
    verdict CI_IS_THE_GATE "$RC_CI" sibling-contention-budget-elapsed ;;
  *)
    verdict NOT_WAITABLE "$RC_NOT_WAITABLE" internal ;;
esac
