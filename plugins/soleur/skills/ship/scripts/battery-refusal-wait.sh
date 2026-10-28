#!/usr/bin/env bash
# Bounded wait for a REFUSED local battery, then "CI is the gate" (P4d, #10924).
#
# WHEN THIS RUNS. `soleur:ship` Phase 4 launches the detached local battery. When another
# worktree already runs a full-gate battery, `scripts/test-all.sh` refuses with rc=4 ("REFUSED,
# nothing ran") and the log carries
#     ERROR: refusing a full-gate run <dash> N sibling full-gate run(s) already in flight
# That is the ONLY refusal time can clear. This script waits for the sibling to drain, bounded
# by a wall-clock budget, and prints a machine verdict. It does NOT change the runner's rc
# contract (many consumers); the verdict lives here, ship-side.
#
# SCOPE. rc=4 is the refusal form: it arises for a `--full` run or an affected run that
# degraded to full. A plain affected run is exempt from the refusal and QUEUES on the lock; that
# form is already bounded by `affected-tests.sh` rc 6 (budget deferral, CI authoritative). This
# script is Soleur-repo specific: it needs `scripts/test-all.sh --capacity` and the runner's
# refusal text, and answers NOT_WAITABLE or QUEUE_IN_LOCK where either is absent.
#
# USAGE
#   battery-refusal-wait.sh --log FILE --state FILE [--budget-s N] [--interval-s N]
#                           [--probe-timeout-s N] [--full]
#   battery-refusal-wait.sh --classify-only FILE   # class=contention|contention-force-all|not-waitable
#
#   --log FILE           the refused run's log
#   --state FILE         episode state: the epoch of the first call, so the budget is shared
#                        across relaunches. Create it EMPTY with mktemp; an empty file starts an
#                        episode. A malformed, future or stale (> 6 h) epoch exits 2.
#   --budget-s N         wall-clock budget (default 1800: the documented escalation point; a full
#                        gate runs ~35-45 min, so on a typical contended start the budget lapses
#                        to CI, which is intended). The wait can overshoot it by one probe.
#   --interval-s N       poll interval (default 60)
#   --probe-timeout-s N  bound on one `--capacity` call (default 30)
#                        Flags only: no environment variable is read, so a stale export cannot
#                        shorten the wait into a CI_IS_THE_GATE verdict.
#   --full               the operator asked for the full local run by name; never defers
#
# EXIT CONTRACT (the caller branches on this, never on the prose):
#   42  CI_IS_THE_GATE   budget elapsed, sibling still running, diff positively resolved with no
#                        infra trigger, no --full: record it and continue WITHOUT local evidence
#   10  RETRY            capacity reports idle (CAPACITY_OK measured_runs=0): relaunch the battery
#   12  QUEUE_IN_LOCK    the local run is the sole blocking gate (infra diff, unresolved diff) or
#                        was asked for by name (--full, or SOLEUR_TEST_FORCE_ALL in the log):
#                        queue inside the lock instead
#   11  NOT_WAITABLE     time cannot clear this refusal (or capacity was never readable): stop
#    2  usage error, or a bad runtime input (state file, clock): stop
#    0  only for --classify-only
#   anything else       an error: the caller MUST stop
#
# ONLY 42 CONTINUES, and the oddness of that number is the point (as battery-owed.sh SKIPPABLE):
# a `set -u` abort exits 1, a missing file 127, a signal 128+N, and none of those may read as
# "skip the local battery". 42 is shared with battery-owed.sh SKIPPABLE ON PURPOSE: in both the
# caller action is the same (CI is the gate, skip the local run) and the two contracts are
# independent.
#
# THE CHOKEPOINT. Every path to 42 flows through the final `case`, which reads all six
# conjuncts: refusal class, budget spent, a capacity reading seen, --full absent, the diff
# positively resolved, no infra trigger.
#
# INFRA. The apps/web-platform/infra tree has no required CI check (#6480), so CI is NOT its
# gate and a deferral there would delete the only blocking one. The predicate follows
# scripts/test-all.sh (the `_diff_names` assembly and `_infra_in_diff`): the same two triggers,
# rename SOURCES included (`--name-status -M`), untracked files included, unanchored substring
# match. It is STRICTER on failure: any git read that fails, a grep that errors, or an empty
# change set is "unresolved". Git runs from the repo root with the same GIT_* variables cleared
# as the runner. The suite pins both trigger literals against the live runner.
#
# NOT WAITABLE: SOLEUR_SUBAGENT=1 is a declared env var polling cannot clear; selection
# refusals mean a gutted index; [FAIL]/[KILLED] mean the battery ran; a toolchain fault means it
# never started. AFFECTED_FALLBACK is classified by its reason (CTO ruling, 2026-10-28):
# index-missing and enumerate-unavailable are a broken tool (stop); force-all is the operator's
# whole-battery lever, the twin of --full (QUEUE_IN_LOCK); runner-changed and undecidable-diff
# stay waitable; an unknown reason stops.
#
# KNOWN LIMIT. Idle is read from `--capacity`, which still counts a stale orphan past the
# runtime ceiling and low /tmp, while the refusal counts fresh siblings only. After the fresh
# sibling drains an orphan can hold capacity non-idle, so the wait runs to the budget. That loss
# is bounded and ends in CI or the lock queue.
#
# Records, never claims: the PR Test plan line in references/battery-refusal-wait.md says the
# local run was NOT executed. Suite: plugins/soleur/test/ship-battery-refusal-wait.test.sh.
set -uo pipefail

# The runner clears these before its diffs; a stale export must not retarget ours.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_TEMPLATE_DIR GIT_EXEC_PATH

RC_RETRY=10
RC_NOT_WAITABLE=11
RC_QUEUE=12
RC_USAGE=2
RC_CI=42
STALE_S=21600

# Strip C0 controls, DEL and the Unicode line separators before printing: the log and the
# capacity output are not trusted to be single-line (same helper as battery-owed.sh).
_ctx_lib="$(cd "${BASH_SOURCE[0]%/*}/../../../scripts/lib" 2>/dev/null && pwd -P)/context-sanitize.sh"
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
usage() { # a flag or argument error, before any wait started: stderr
  printf 'BATTERY_REFUSAL_WAIT usage: %s\n' "$(_sanitize "$1")" >&2
  exit "$RC_USAGE"
}
fault() { # a bad runtime input (state file, clock): a verdict line on stdout, where Monitor reads
  say "verdict=ERROR waited_s=$WAITED reason=$1"
  exit "$RC_USAGE"
}

LOG=""; STATE=""; BUDGET_S=1800; INTERVAL_S=60; PROBE_TIMEOUT_S=30; FULL=0; CLASSIFY_ONLY=""
is_posint() { [[ "$1" =~ ^[1-9][0-9]{0,5}$ ]]; }
while (( $# )); do
  case "$1" in
    --log)             (( $# >= 2 )) || usage "--log needs a value"; LOG="$2"; shift 2 ;;
    --state)           (( $# >= 2 )) || usage "--state needs a value"; STATE="$2"; shift 2 ;;
    --budget-s)        (( $# >= 2 )) && is_posint "$2" || usage "--budget-s needs a positive integer"; BUDGET_S="$2"; shift 2 ;;
    --interval-s)      (( $# >= 2 )) && is_posint "$2" || usage "--interval-s needs a positive integer"; INTERVAL_S="$2"; shift 2 ;;
    --probe-timeout-s) (( $# >= 2 )) && is_posint "$2" || usage "--probe-timeout-s needs a positive integer"; PROBE_TIMEOUT_S="$2"; shift 2 ;;
    --full)            FULL=1; shift ;;
    --classify-only)   (( $# >= 2 )) || usage "--classify-only needs a file"; CLASSIFY_ONLY="$2"; shift 2 ;;
    *)                 usage "unknown argument: $1" ;;
  esac
done

# --- classifier: whole-log scan, CR stripped, full refusal shape required -----------------------
# echoes `contention`, `contention:force-all` or `not-waitable:<reason>`.
classify() { # <file>
  local f="$1" body bad reasons r force=0
  [[ -f "$f" && -r "$f" ]] || { echo "not-waitable:log-missing"; return 0; }
  body="$(LC_ALL=C tr -d '\r' < "$f")"
  [[ -n "$body" ]] || { echo "not-waitable:log-empty"; return 0; }
  if grep -qE '\[FAIL\]|\[KILLED\]' <<<"$body"; then echo "not-waitable:battery-ran"; return 0; fi
  if grep -qE 'mise ERROR|command not found' <<<"$body"; then echo "not-waitable:toolchain"; return 0; fi
  if grep -qF 'AFFECTED_UNRESOLVED' <<<"$body"; then echo "not-waitable:selection-refusal"; return 0; fi
  bad="$(grep -E 'AFFECTED_GATE_REFUSED reason=' <<<"$body" | grep -vE 'reason=runner-refused')"
  if [[ -n "$bad" ]]; then echo "not-waitable:gate-refusal"; return 0; fi
  if grep -qF 'SOLEUR_SUBAGENT=1 is set' <<<"$body"; then echo "not-waitable:subagent-env"; return 0; fi
  reasons="$(grep -oE 'AFFECTED_FALLBACK[[:space:]]+reason=[A-Za-z-]+' <<<"$body" | sed 's/.*reason=//')"
  for r in $reasons; do
    case "$r" in
      index-missing|enumerate-unavailable) echo "not-waitable:affected-index-broken"; return 0 ;;
      force-all) force=1 ;;
      runner-changed|undecidable-diff) ;;
      *) echo "not-waitable:unknown-fallback-reason"; return 0 ;;
    esac
  done
  if grep -qE '^ERROR: refusing a full-gate run .* [1-9][0-9]* sibling full-gate run\(s\) already in flight' <<<"$body"; then
    if (( force == 1 )); then echo "contention:force-all"; else echo "contention"; fi
    return 0
  fi
  echo "not-waitable:not-a-sibling-refusal"
}

if [[ -n "$CLASSIFY_ONLY" ]]; then
  c="$(classify "$CLASSIFY_ONLY")"
  case "$c" in
    contention) echo "class=contention" ;;
    contention:force-all) echo "class=contention-force-all" ;;
    *) echo "class=not-waitable" ;;
  esac
  exit 0
fi

[[ -n "$LOG" ]] || usage "--log is required"
[[ -n "$STATE" ]] || usage "--state is required"
# The state path is absolute by contract (the recipe passes a mktemp path): refuse a relative one
# rather than let it resolve against whatever cwd the caller has, and root it at / by construction.
[[ "$STATE" == /* ]] || usage "--state must be an absolute path"
STATE="/${STATE#/}"

# DISPATCH-ANCHOR
CLASS_OK=0
class="$(classify "$LOG")"
case "$class" in
  contention) CLASS_OK=1 ;;
  contention:force-all) CLASS_OK=1; FULL=1 ;;
  *) verdict NOT_WAITABLE "$RC_NOT_WAITABLE" "${class#not-waitable:}" ;;
esac

# --- clock: `date +%s` via PATH (a test seam, not an authority grant) ----------------------------
clock() {
  local n
  n="$(date +%s)" || return 1
  [[ "$n" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$n"
}
CALL_START="$(clock)" || fault "cannot-read-the-clock"

# --- episode state: the epoch of the first call, written atomically BEFORE the first poll -------
# A real epoch is exactly 10 digits with no leading zero: that rules out octal reads (`010`),
# 64-bit wrap (`1844...`), and `0`/tiny values that would make the whole budget look spent.
# One owning trap for the state temp file: every exit goes through `verdict`/`usage`/`fault`
# (all `exit`), so a crash between mktemp and mv cannot leave a stray file behind.
STATE_TMP=""
trap 'rm -f "${STATE_TMP:-}"' EXIT
init_episode() {
  local cur
  [[ -f "$STATE" && -r "$STATE" ]] || fault "state-file-missing-or-not-a-file"
  cur="$(tr -d '[:space:]' < "$STATE")"
  if [[ -z "$cur" ]]; then
    STATE_TMP="$(mktemp "/${STATE#/}.XXXXXX")" || fault "cannot-write-the-state-file"
    printf '%s\n' "$CALL_START" > "$STATE_TMP" && mv -f "$STATE_TMP" "$STATE" || fault "cannot-write-the-state-file"
    cur="$CALL_START"
  fi
  [[ "$cur" =~ ^[1-9][0-9]{9}$ ]] || fault "state-file-holds-a-malformed-epoch"
  (( cur <= CALL_START )) || fault "state-file-holds-a-future-epoch"
  (( CALL_START - cur <= STALE_S )) || fault "state-file-is-stale-create-a-fresh-one"
  EPOCH="$cur"
}
init_episode  # EPISODE-INIT

# --- capacity ------------------------------------------------------------------------------------
# CAP is one of: idle | ok | contended | unknown | unreadable. Only a banner line (anchored, so a
# sibling detail row naming the token cannot count) with `CAPACITY_OK` and `measured_runs=0` on
# the SAME line is idle: CAPACITY_CONTENDED reason=low_tmp also prints measured_runs=0.
poll_capacity() {
  local top out line
  CAP=unreadable
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  [[ -f "$top/scripts/test-all.sh" ]] || return 0
  out="$(timeout -k 1 "$PROBE_TIMEOUT_S" bash "$top/scripts/test-all.sh" --capacity 2>&1)" || return 0
  line="$(grep -E '^(\[contention\][[:space:]]+)?(BANNER[[:space:]]+)?CAPACITY_(OK|CONTENDED|UNKNOWN)([[:space:]]|$)' <<<"$out" | head -1)"
  case "$line" in
    *CAPACITY_OK*)
      if [[ "$line" =~ measured_runs=0([^0-9]|$) ]]; then CAP=idle; else CAP=ok; fi ;;
    *CAPACITY_CONTENDED*) CAP=contended ;;
    *CAPACITY_UNKNOWN*) CAP=unknown ;;
  esac
  return 0
}

SEEN=0
BUDGET_DONE=0
while :; do
  poll_capacity
  now="$(clock)" || fault "cannot-read-the-clock"
  elapsed=$(( now - EPOCH ))
  (( elapsed >= 0 )) || fault "clock-went-backwards"
  WAITED="$elapsed"
  case "$CAP" in
    idle) verdict RETRY "$RC_RETRY" capacity-idle ;;
    ok|contended) SEEN=1 ;;
  esac
  if (( elapsed >= BUDGET_S )); then BUDGET_DONE=1; break; fi
  say "WAITING elapsed_s=$elapsed budget_s=$BUDGET_S capacity=$CAP"
  remaining=$(( BUDGET_S - elapsed ))
  (( remaining >= 1 )) || fault "internal-non-positive-sleep"
  sleep "$(( INTERVAL_S < remaining ? INTERVAL_S : remaining ))" || fault "sleep-failed"
done

# --- infra predicate (follows scripts/test-all.sh; see the header) --------------------------------
infra_state() { # echoes clean | infra | unresolved
  local top names="" out lit rc hit=0
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo unresolved; return 0; }
  out="$(git -C "$top" -c core.quotePath=false diff --name-only origin/main...HEAD 2>/dev/null)" || { echo unresolved; return 0; }
  names="${names}
${out}"
  out="$(git -C "$top" -c core.quotePath=false diff --name-only HEAD 2>/dev/null)" || { echo unresolved; return 0; }
  names="${names}
${out}"
  out="$(git -C "$top" -c core.quotePath=false diff --name-status -M HEAD 2>/dev/null)" || { echo unresolved; return 0; }
  names="${names}
${out}"
  out="$(git -C "$top" -c core.quotePath=false diff --name-status -M origin/main...HEAD 2>/dev/null)" || { echo unresolved; return 0; }
  names="${names}
${out}"
  out="$(git -C "$top" ls-files --others --exclude-standard 2>/dev/null)" || { echo unresolved; return 0; }
  names="${names}
${out}"
  # A branch with nothing to test is not "clean": an empty change set means a read went wrong.
  [[ -n "${names//[[:space:]]/}" ]] || { echo unresolved; return 0; }
  for lit in 'apps/web-platform/infra/' '.github/workflows/apply-web-platform-infra.yml'; do
    grep -qF -- "$lit" <<<"$names"; rc=$?
    case "$rc" in
      0) hit=1 ;;
      1) ;;
      *) echo unresolved; return 0 ;;
    esac
  done
  if (( hit == 1 )); then echo infra; else echo clean; fi
}

# --- the chokepoint: every path to exit 42 flows through this one case ----------------------------
infra="$(infra_state)"
case "$CLASS_OK:$BUDGET_DONE:$SEEN:$FULL:$infra" in
  1:1:0:*:*)
    verdict NOT_WAITABLE "$RC_NOT_WAITABLE" capacity-unreadable ;;
  1:1:1:1:*)
    verdict QUEUE_IN_LOCK "$RC_QUEUE" full-requested ;;
  1:1:1:0:infra)
    verdict QUEUE_IN_LOCK "$RC_QUEUE" infra-diff ;;
  1:1:1:0:unresolved)
    verdict QUEUE_IN_LOCK "$RC_QUEUE" diff-unresolved ;;
  1:1:1:0:clean)
    verdict CI_IS_THE_GATE "$RC_CI" sibling-contention-budget-elapsed ;;
  *)
    verdict NOT_WAITABLE "$RC_NOT_WAITABLE" internal ;;
esac
