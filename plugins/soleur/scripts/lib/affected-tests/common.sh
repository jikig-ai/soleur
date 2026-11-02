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
    # counts as one extra gate, biasing width DOWN — the safe direction (an
    # undercount would bias width UP, toward oversubscription).
    [[ "$pid" == "$$" ]] && continue
    [[ -n "${BASHPID:-}" && "$pid" == "$BASHPID" ]] && continue
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

# --- file census ---------------------------------------------------------------
# affected_find_files <count|any> <basename-glob>… — the ONE census walker every
# adapter shares (consolidates four near-identical find blocks). Prints matching
# paths; `any` adds -quit so callers can pipe to `grep -q .` without a SIGPIPE
# short-read. The prune list is the UNION of what any adapter skips — build and
# vendor output is never a test source.
affected_find_files() {
  local mode="$1"; shift
  local -a expr=()
  local g first=1
  for g in "$@"; do
    (( first )) || expr+=(-o)
    expr+=(-name "$g")
    first=0
  done
  local -a tail=(-print)
  [[ "$mode" == any ]] && tail=(-print -quit)
  find . \( -name .git -o -name node_modules -o -name vendor -o -name .venv \
       -o -name venv -o -name .tox -o -name __pycache__ -o -name dist \
       -o -name build -o -name coverage -o -name .next \) -prune \
    -o -type f \( "${expr[@]}" \) "${tail[@]}" 2>/dev/null
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
# Both coreutils backends carry `-k <grace>` so a TERM-ignoring child is KILLed
# 10 s after expiry rather than running unbounded (BSD gtimeout supports -k too);
# the watchdog arm already escalates on its own schedule.
affected_timeout() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout -k 10 "$secs" "$@"
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout -k 10 "$secs" "$@"
    return $?
  fi
  # Bounded watchdog: no coreutils on this host (stock macOS). 1 s granularity.
  local pid rc=0 waited=0
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if (( waited >= secs )); then
      # Process-group kill first — a bounded command's own children outlive a
      # direct-kill of the leader. GUARDED: under non-job-control `&` the child
      # shares OUR process group, and group-killing that would suicide the
      # gate; the direct kill below is the fallback that always applies.
      local pgid="" ownpg=""
      pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
      ownpg="$(ps -o pgid= -p "$$" 2>/dev/null | tr -d ' ')"
      if [[ -n "$pgid" && "$pgid" != "$ownpg" ]]; then
        kill -TERM -- "-$pgid" 2>/dev/null || true
      fi
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      if [[ -n "$pgid" && "$pgid" != "$ownpg" ]]; then
        kill -KILL -- "-$pgid" 2>/dev/null || true
      fi
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
# INITIALISED UNCONDITIONALLY — these are NEVER inherited from the caller's
# environment. A forged AFFECTED_BUDGET_ACTIVE=1 + a past AFFECTED_DEADLINE
# would let every bound expire on its first check and launder a deferral
# (rc 6 pass-with-note) without a detected CI. The gate arms them itself,
# only when a CI test workflow was detected.
AFFECTED_BUDGET_ACTIVE=0
AFFECTED_DEADLINE=0
# The content trigger (lib content-trigger.sh) is armed by the gate only after the
# whole three-key config group validates, and made eligible only at the exits that
# ran or reported a non-`--full` verdict. Same rule as above: initialised here,
# never inherited from the caller's environment.
AFFECTED_CT_ARMED=0
AFFECTED_CT_ELIGIBLE=0
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

# --- scratch files ---------------------------------------------------------------
# Every mktemp in the gate and its adapters funnels here so an EXIT/INT/TERM
# trap in affected-tests.sh can remove them all — including on the early-exit
# refusal paths that never reach the caller's own rm.
AFFECTED_SCRATCH=()
affected_mktemp() { # <tag> — sets AFFECTED_TMP to a fresh registered scratch path
  AFFECTED_TMP="$(mktemp "${TMPDIR:-/tmp}/affected-$1.XXXXXX")" || return 1 # lint-trap-ownership: ok — owning `trap affected_scratch_clean EXIT INT TERM` is installed by the sourcing gate (affected-tests.sh); a sourced lib cannot own an EXIT trap without clobbering the importer's
  AFFECTED_SCRATCH+=("$AFFECTED_TMP")
}
affected_scratch_clean() {
  ((${#AFFECTED_SCRATCH[@]} > 0)) && rm -f "${AFFECTED_SCRATCH[@]}"
  return 0
}

# --- marker field hygiene -----------------------------------------------------------
# Config-derived strings (key names, workflow filenames, inert/global patterns)
# reach marker fields verbatim; a newline or space in one breaks the field
# shape. Collapse anything outside a printable, whitespace-free set to `_`.
affected_marker_field() {
  printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9_.:/=+-' '_'
}

# --- vacuous test_command denylist -----------------------------------------------------
# A DENYLIST, not a proof: it refuses the shapes that certify nothing — bare
# `true`/`:`/`exit`/`echo`, every segment vacuous (`echo ok; true`), a
# true-swallower at the tail (`cmd || true`, `cmd ; exit 0`, `cmd && true`),
# and exit-inside-subcommand (`bash -c 'exit 0'`, `sh -c '...; exit 0'`).
# Anything not on the list still runs verbatim and unverified.
_affected_vacuous_seg() { # <trimmed segment> → rc 0 when it certifies nothing
  local s="$1"
  s="$(printf '%s' "$s" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [[ -n "$s" ]] || return 0
  case "$s" in
    true|:|exit|"exit "*|echo|"echo "*) return 0 ;;
  esac
  # `sh -c '…'` / `bash -c "…"` (optionally env-wrapped): the inner command is
  # what's vacuous or not — recurse on it.
  local inner=""
  case "$s" in
    env\ *-c\ *|bash\ -c\ *|sh\ -c\ *|dash\ -c\ *|zsh\ -c\ *|ksh\ -c\ *|eval\ *)
      inner="${s#* -c }"
      # `eval\ ` (escaped space) is deliberate: hook-input-contract's A1 idiom ban
      # greps this lib for an `eval` followed by a bare space — a prefix-strip
      # pattern is not an invocation, but the guard keys on the token, so the
      # pattern is spelled to stay outside its match.
      [[ "$inner" == "$s" ]] && inner="${s#eval\ }"
      inner="${inner#[\"\']}"; inner="${inner%[\"\']}"
      _affected_cmd_vacuous "$inner" && return 0 ;;
  esac
  return 1
}
_affected_cmd_vacuous() { # <command string> → rc 0 when it certifies nothing
  local norm split seg last=""
  # Strip comments (`true # ok` is still just `true`), normalise whitespace,
  # then split on the shell's list operators. The LAST segment decides the
  # whole command's rc: a vacuous tail is either an all-vacuous command
  # (`true`, `echo ok; :`) or a true-swallower (`cmd || true`, `cmd ; exit 0`,
  # `cmd && true`, `cmd | true`) — both refuse.
  norm="$(printf '%s' "$1" | sed 's/#.*$//' | tr '\n\t' '  ' | tr -s ' ' \
          | sed 's/^ //; s/ *;*$//; s/ $//')"
  [[ -n "$norm" ]] || return 0
  split="${norm//&&/$'\n'}"
  split="${split//\|\|/$'\n'}"
  split="${split//|/$'\n'}"
  split="${split//;/$'\n'}"
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    [[ -n "$seg" ]] && last="$seg"
  done <<<"$split"
  _affected_vacuous_seg "$last"
}

# Marker + human lines are emitted ONLY from finish(); the guard property is
# that there is one place a verdict can be written and one place a run can end.
#
# finish <rc> <mode> <reason> <stack> <ci> [ran of skipped]
#   rc:     0 pass-or-inert | 1 failure/signal | 4 refused | 6 budget-deferred | 7 no suite
#   mode:   selected | full | custom | explain | none
#   reason: ok | inert | empty-selection | empty-diff | census-degraded |
#           global-paths | full-requested |
#           custom-command | delegated | runner-refused | runner-signal | foreign-runner |
#           no-stack | bad-config key=<k> | vacuous-test-command | no-base-ref |
#           toolchain-missing | no-tests | budget-deferred | bad-usage | help |
#           content-trigger-failed | inert-content-trigger
#   Counts are decimal, or `-` when the path does not produce a count
#   (delegated runner, opaque test_command, refused runs).
finish() {
  local rc="$1" mode="${2:--}" reason="${3:--}" stack="${4:--}" ci="${5:-none}"
  local ran="${6:--}" of="${7:--}" skipped="${8:--}" ct_field=""
  # Content trigger (content-trigger.sh): runs the configured command after a
  # passing verdict whose diff adds the configured string, folds its result into
  # rc/reason, and names the outcome in one trailing marker field. The hook never
  # exits and never calls finish(); an unarmed gate skips this block byte-for-byte.
  if [[ "${AFFECTED_CT_ARMED:-0}" == 1 ]]; then
    affected_ct_hook "$rc" "$reason"
    rc="$AFFECTED_CT_OUT_RC"; reason="$AFFECTED_CT_OUT_REASON"
    if [[ "${AFFECTED_CT_OUT_RESET:-0}" == 1 ]]; then mode="selected"; ran="-"; of="-"; skipped="-"; fi
    ct_field="$AFFECTED_CT_OUT_FIELD"
  fi
  case "$rc" in
    0)
      if [[ "$reason" == inert ]]; then
        echo "NO_TESTS_AFFECTED inert_rule=$(affected_marker_field "${INERT_RULE:--}")"
        echo "No tests ran: docs-only change."
      elif [[ "$ran" == "-" || "$of" == "-" ]]; then
        # `-` counts mark both real runs whose tallies are opaque (delegated
        # runner, custom-command — these still owe the verdict line) and paths
        # where nothing ran (help, explain, self-check — a `Ran - of -` line or
        # a pass claim would read as a test result that never happened). A run
        # where EITHER count is unknown also suppresses the sentence — a
        # half-known tally (`Ran 3 of -`) reads as a real count with a broken
        # denominator.
        # Verdict line still prints for a real run whose tallies are opaque:
        # delegated runner, custom command, or a count-units case like
        # testmon — anything in selected/full/custom mode DID run tests.
        # Suppressed only on paths where nothing ran (explain/none/help).
        case "$mode" in
          selected|full|custom) echo "affected-suite gate passed." ;;
        esac
      else
        # `of` is the repo-wide test-file census, not the affected subset —
        # `ran` counts files actually executed.
        printf 'Ran %s of the repo'"'"'s %s test files affected by this change: passed.\n' "$ran" "$of"
        echo "affected-suite gate passed."
      fi
      ;;
    4)
      # A refusal is a marker line with the reason and a remedy pointer, plus a
      # human-readable name for the cause — never a bare rc.
      local remedy="see plugins/soleur/skills/ship/references/affected-gate-contract.md"
      case "$reason" in
        vacuous-test-command|bad-config*)
          remedy="fix .soleur-test-gate.json (the named key)" ;;
        no-base-ref)
          remedy="git fetch to unshallow, or pass --base <ref>" ;;
        toolchain-missing)
          remedy="install the detected stack's test tool, or set test_command in .soleur-test-gate.json" ;;
        no-stack|foreign-runner)
          remedy="set test_command in .soleur-test-gate.json" ;;
      esac
      echo "AFFECTED_GATE_REFUSED reason=$reason"
      echo "  remedy: $remedy"
      ;;
    6)
      echo "AFFECTED_GATE_BUDGET_DEFERRED ran=$ran of=$of"
      if [[ "$ci" == config:* ]]; then
        # budget_ci forced eligibility — no workflow was detected to name.
        echo "Budget expired before the run completed; CI deferral was forced by ${ci} — the CI gate is authoritative."
      else
        echo "Budget expired before the run completed; the detected CI test workflow ($ci) is the authoritative gate."
      fi
      ;;
    7)
      echo "No test suite detected in this repository; the affected-suite gate had nothing to run."
      ;;
  esac
  echo "AFFECTED_GATE ran=$ran of=$of skipped=$skipped mode=$mode reason=$reason stack=$stack ci=$ci${ct_field:+ content_trigger=$ct_field}"
  exit "$rc"
}
