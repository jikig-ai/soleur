#!/usr/bin/env bash
# common.sh — shared helpers for plugins/soleur/scripts/affected-tests.sh (#9307 PR2).
#
# Sourced by the gate and by the stack adapters in this directory. Declarations
# only: no `exit`, no top-level side effects — the ONE exit site is finish().
#
# External binaries invoked here: bash, ps, awk, grep, getconf, sysctl, nproc,
# sleep, kill, date, command (builtin), printf (builtin). NO bare `timeout` —
# affected_timeout resolves timeout -> gtimeout -> bounded watchdog.

if [[ "${_SOLEUR_AFFECTED_COMMON_LOADED:-}" == "1" ]]; then
  return 0 2>/dev/null || true
fi
_SOLEUR_AFFECTED_COMMON_LOADED=1

# --- epoch ------------------------------------------------------------------
# `date +%s` is POSIX and present on BSD/macOS. `date -d` is banned (GNU-only).
affected_now() { date +%s; }

# --- cpu count --------------------------------------------------------------
# getconf -> sysctl -> nproc. Prints an integer >= 1, always.
affected_ncpu() {
  local n=""
  n="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
  [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 )) || n=""
  if [[ -z "$n" ]]; then
    n="$(sysctl -n hw.ncpu 2>/dev/null || true)"
    [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 )) || n=""
  fi
  if [[ -z "$n" ]]; then
    n="$(nproc 2>/dev/null || true)"
    [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 )) || n=""
  fi
  printf '%s\n' "${n:-1}"
}

# --- running-gate count ------------------------------------------------------
# Counts OTHER running affected-tests.sh processes, anchored on an argv SLOT —
# never pgrep -f and never a `ps | grep` substring over the joined command line
# (the #8231 class: the pattern self-matches the poller's own `bash -c` argv and
# the count can never reach zero). ps + word-splitting is used with ONE further
# restriction: the script name is matched only at (a) argv[0] — a direct/shebang
# exec — or (b) the first operand of a resolved shell word — `bash
# <path>/affected-tests.sh`. A `bash -c '…affected-tests.sh…'` payload starts
# with `-c` at that slot and never counts, so a watcher can never self-match;
# the accepted gap is that a bare `-c` payload whose whole body is the script
# path also does not count (it undercounts siblings, which biases the divisor
# UP for nobody and merely widens width — documented, not corrected).
#
# Leading wrapper commands (timeout/gtimeout/env/nohup/nice/setsid/flock/…) are
# stepped over together with their option-ish operands, per the proc.sh wrapper
# walk — without it `timeout 600 bash affected-tests.sh` is invisible.
affected_running_gates() {
  local line pid b n=0
  local -a w=()
  while IFS= read -r line; do
    # ps pads the pid column; capture pid and argv separately by regex rather
    # than field-splitting a column whose width varies.
    [[ "$line" =~ ^[[:space:]]*([0-9]+)[[:space:]]+(.*)$ ]] || continue
    pid="${BASH_REMATCH[1]}"
    # Self and (when bash >= 4 exposes it) the command-substitution subshell
    # this loop runs in — the subshell INHERITS this script's argv and would
    # otherwise self-count. bash 3.2 has no BASHPID: the substitution then
    # counts as one extra gate, biasing width DOWN — the safe direction.
    [[ "$pid" == "$$" || "$pid" == "${BASHPID:-$pid}" ]] && continue
    w=()
    read -ra w <<<"${BASH_REMATCH[2]}"
    ((${#w[@]} > 0)) || continue
    # Wrapper walk: consume a wrapper word plus its own operands
    # (options, VAR=value assignments, bare durations).
    while ((${#w[@]} > 0)); do
      case "${w[0]##*/}" in
        timeout|gtimeout|env|nohup|nice|ionice|setsid|flock|stdbuf|time|taskset|command)
          w=("${w[@]:1}")
          while ((${#w[@]} > 0)) && [[ "${w[0]}" == -* || "${w[0]}" == *=* || "${w[0]}" =~ ^[0-9]+$ ]]; do
            w=("${w[@]:1}")
          done
          continue
          ;;
      esac
      break
    done
    ((${#w[@]} > 0)) || continue
    b="${w[0]##*/}"
    if [[ "$b" == "affected-tests.sh" ]]; then
      n=$((n + 1))
      continue
    fi
    case " bash sh dash zsh ksh mksh ash " in
      *" $b "*)
        if ((${#w[@]} > 1)) && [[ "${w[1]}" != -* && "${w[1]##*/}" == "affected-tests.sh" ]]; then
          n=$((n + 1))
        fi
        ;;
    esac
  done < <(ps -eo pid=,args= 2>/dev/null)
  printf '%s\n' "$n"
}

# --- worker width ------------------------------------------------------------
# max(1, ncpu/2) / (1 + running gate processes); $1 (config max_workers) wins.
# Unmeasured heuristic — labelled as such in the gate header.
affected_workers() {
  local override="${1:-}" ncpu gates w
  if [[ "$override" =~ ^[0-9]+$ ]] && (( override >= 1 )); then
    printf '%s\n' "$override"
    return 0
  fi
  ncpu="$(affected_ncpu)"
  gates="$(affected_running_gates)"
  [[ "$gates" =~ ^[0-9]+$ ]] || gates=0
  w=$(( (ncpu / 2) / (1 + gates) ))
  (( w >= 1 )) || w=1
  printf '%s\n' "$w"
}

# --- portable bound ------------------------------------------------------------
# affected_timeout <seconds> <cmd...> — timeout -> gtimeout -> bounded watchdog.
# Returns the command's rc, or 124 on expiry (timeout's own spelling, so callers
# can treat the three backends uniformly; the watchdog prints 124 the same way).
# 137 is also an expiry signal when the bound had to escalate to SIGKILL.
affected_timeout() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
    return $?
  fi
  # Bounded watchdog: no coreutils on this host (stock macOS). 1 s granularity.
  local pid rc=0 waited=0
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if (( waited >= secs )); then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid" || rc=$?
  return "$rc"
}

# affected_bound <cmd...> — run the command under the REMAINING wall-clock
# budget when enforcement is armed (AFFECTED_BUDGET_ACTIVE=1 and
# AFFECTED_DEADLINE is an epoch). Unarmed: a plain run. Expired or expired
# mid-run: 124. A failure observed before expiry returns the command's own rc —
# that ordering (failure wins over deferral) is the contract's rc-1-over-rc-6
# rule and is why the bound is applied per runner invocation rather than once
# around the whole gate.
AFFECTED_BUDGET_ACTIVE="${AFFECTED_BUDGET_ACTIVE:-0}"
AFFECTED_DEADLINE="${AFFECTED_DEADLINE:-0}"
affected_bound() {
  if [[ "$AFFECTED_BUDGET_ACTIVE" == "1" ]]; then
    local rem
    rem=$(( AFFECTED_DEADLINE - $(affected_now) ))
    (( rem > 0 )) || return 124
    affected_timeout "$rem" "$@"
    return $?
  fi
  "$@"
}

# --- emit helpers --------------------------------------------------------------
# Marker + human lines are emitted ONLY from finish(); the guard property is
# that there is one place a verdict can be written and one place a run can end.
#
# finish <rc> <mode> <reason> <stack> <ci> [ran of skipped]
#   rc:     0 pass-or-inert | 1 failure/signal | 4 refused | 6 budget-deferred | 7 no suite
#   mode:   selected | full | custom | explain | none
#   reason: ok | inert | empty-selection | empty-diff | global-paths | full-requested |
#           custom-command | delegated | runner-refused | runner-signal | foreign-runner |
#           no-stack | bad-config key=<k> | vacuous-test-command | no-base-ref |
#           toolchain-missing | no-tests | budget-deferred | bad-usage | help
#   Counts are decimal, or `-` when the path does not produce a count
#   (delegated runner, opaque test_command, refused runs).
finish() {
  local rc="$1" mode="${2:--}" reason="${3:--}" stack="${4:--}" ci="${5:-none}"
  local ran="${6:--}" of="${7:--}" skipped="${8:--}"
  case "$rc" in
    0)
      if [[ "$reason" == inert ]]; then
        echo "NO_TESTS_AFFECTED inert_rule=${INERT_RULE:--}"
        echo "No tests ran: docs-only change."
      elif [[ "$reason" == help || "$ran" == "-" ]]; then
        : # non-run paths (help, explain, self-check) emit no verdict sentence —
          # a `Ran - of -` line would read as a test result that never happened.
      else
        printf 'Ran %s of %s test files affected by this change: passed.\n' "$ran" "$of"
        echo "affected-suite gate passed."
      fi
      ;;
    4)
      # A refusal is a marker line with the reason, plus a human-readable name
      # for the cause — never a bare rc.
      echo "AFFECTED_GATE_REFUSED reason=$reason"
      ;;
    6)
      echo "AFFECTED_GATE_BUDGET_DEFERRED ran=$ran of=$of"
      echo "Budget expired before the run completed; the detected CI test workflow is the authoritative gate."
      ;;
    7)
      echo "No test suite detected in this repository; the affected-suite gate had nothing to run."
      ;;
  esac
  echo "AFFECTED_GATE ran=$ran of=$of skipped=$skipped mode=$mode reason=$reason stack=$stack ci=$ci"
  exit "$rc"
}
