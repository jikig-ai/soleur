#!/usr/bin/env bash
# test-contention.sh — contention instrumentation for scripts/test-all.sh (#6789).
#
# WHY THIS EXISTS
# ---------------
# Parallel worktrees are this repo's documented workflow, but two sessions
# running `scripts/test-all.sh` concurrently could produce failures that look
# like real regressions. The mitigation used to be prose telling the operator
# to run `ps -ef | grep test-all` and wait — detection guidance for a human,
# not isolation, and it made every overlap a manual serialization.
#
# The contended resource is NOT a colliding path. It is a capacity: every
# suite's `mktemp` lands in the same machine-global tmpfs, which is RAM-backed,
# so its occupancy is memory withheld from both concurrent runs. The failure
# mode both implicated suites already document in-repo is a TIMEOUT
# (skill-security-scan.test.ts #4096; vitest.config.ts #3817/#4128), never a
# path collision. See the plan's Research Reconciliation table for the two
# refuted hypotheses and their discriminators.
#
# This module only OBSERVES. It creates no files, takes no locks, and deletes
# nothing. Every function is safe to call under `set -euo pipefail`.
#
# TEST SEAMS (all default to the real system; overridden only by the suite):
#   TC_PROC_ROOT     procfs root                  (default /proc)
#   TC_TMPDIR        the tmpfs under observation  (default ${TMPDIR:-/tmp})
#   TC_XDG_DIR       runtime dir                  (default $XDG_RUNTIME_DIR)
#   TC_SELF_PID      pid to exclude from the scan (default $$)
#   TC_MIN_AVAIL_MB  headroom floor in MB         (default 1024)
#   TC_NPROC         core count                   (default `nproc`)

# Guard against double-source within a single shell (session-state.sh idiom).
if [[ "${_SOLEUR_TEST_CONTENTION_LOADED:-}" == "1" ]]; then
  return 0 2>/dev/null || true
fi
_SOLEUR_TEST_CONTENTION_LOADED=1

TC_PROC_ROOT="${TC_PROC_ROOT:-/proc}"
TC_TMPDIR="${TC_TMPDIR:-${TMPDIR:-/tmp}}"
TC_XDG_DIR="${TC_XDG_DIR:-${XDG_RUNTIME_DIR:-}}"
TC_SELF_PID="${TC_SELF_PID:-$$}"
TC_MIN_AVAIL_MB="${TC_MIN_AVAIL_MB:-1024}"
_TC_CLK_TCK="$(getconf CLK_TCK 2>/dev/null || echo 100)"

# session-state.sh supplies the advisory lock (Phase 3). Resolved relative to
# this lib so it works from any CWD; overridable for tests.
_tc_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
TC_SESSION_STATE="${TC_SESSION_STATE:-$_tc_lib_dir/../../.claude/hooks/lib/session-state.sh}"
# A test-all.sh run is minutes, not seconds. with_lock's 30s default would fire
# the advisory path on essentially every genuine overlap, so size the wait to a
# full suite.
TC_LOCK_TIMEOUT="${TC_LOCK_TIMEOUT:-900}"

# --- Capacity probes -------------------------------------------------------
# `df -P` pins POSIX single-line output so a long device name cannot wrap and
# shift the awk field indices.

tc_tmp_entry_count() {
  local d="${1:-$TC_TMPDIR}"
  [[ -d "$d" ]] || { printf '0\n'; return 0; }
  local n
  n=$(find "$d" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l) || n=0
  printf '%s\n' "${n// /}"
}

tc_avail_mb() {
  local d="${1:-$TC_TMPDIR}" kb
  kb=$(df -P -k "$d" 2>/dev/null | awk 'NR==2 {print $4}') || kb=""
  [[ "$kb" =~ ^[0-9]+$ ]] || { printf '0\n'; return 0; }
  printf '%s\n' $(( kb / 1024 ))
}

tc_used_pct() {
  local d="${1:-$TC_TMPDIR}" p
  p=$(df -P -k "$d" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}') || p=""
  [[ "$p" =~ ^[0-9]+$ ]] || { printf '0\n'; return 0; }
  printf '%s\n' "$p"
}

# --- Sibling scan ----------------------------------------------------------
#
# /proc/<pid>/stat field 22 is starttime in clock ticks since boot; combined
# with /proc/uptime it yields elapsed seconds with no `ps` dependency, which
# keeps the whole scan hermetically testable against a synthesized procfs.
#
# comm (field 2) is parenthesized and MAY contain spaces and close-parens, so
# the parser strips through the LAST ') ' rather than splitting on whitespace.
# A naive `awk '{print $22}'` mis-indexes on any such process.

_tc_stat_field() {
  # $1 = path to a /proc/<pid>/stat file, $2 = field index AFTER the comm strip
  # (i.e. overall field N maps to N-2 here).
  local f="$1" idx="$2" line rest
  [[ -r "$f" ]] || return 0
  line=$(cat "$f" 2>/dev/null) || return 0
  rest="${line##*') '}"
  awk -v i="$idx" '{print $i}' <<<"$rest"
}

# Overall field 22 (starttime) => field 20 after the comm strip.
_tc_starttime_ticks() { _tc_stat_field "$1" 20; }
# Overall field 4 (ppid) => field 2 after the comm strip.
_tc_ppid() { _tc_stat_field "$1" 2; }

# Self plus every ancestor pid.
#
# WHY THE WHOLE CHAIN, not just $$: this runner is normally launched through a
# wrapper (`bash -c '... bash scripts/test-all.sh ...'`, a CI step shell, an
# agent harness), and that wrapper's OWN cmdline contains the string
# "test-all.sh". Excluding only $$ therefore reports the caller's own
# invocation as a concurrent sibling on EVERY run — a banner that always fires
# is indistinguishable from one that never fires, which is precisely the
# "a guard that warns is not a guard that guards" failure this module exists
# to correct. Observed live during development: a clean solo run reported 2
# phantom siblings, both links in its own ancestor chain.
_tc_self_and_ancestors() {
  local pid="$TC_SELF_PID" out="" guard=0
  while [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 0 && guard < 64 )); do
    out+="$pid "
    local ppid
    ppid=$(_tc_ppid "$TC_PROC_ROOT/$pid/stat") || ppid=""
    [[ "$ppid" =~ ^[0-9]+$ ]] || break
    [[ "$ppid" == "$pid" ]] && break
    pid="$ppid"
    guard=$(( guard + 1 ))
  done
  printf '%s' "$out"
}

# Emits one TAB-separated "pid<TAB>cwd<TAB>elapsed_s" line per sibling run.
tc_siblings() {
  local proc="$TC_PROC_ROOT"
  [[ -d "$proc" ]] || return 0

  local uptime_s=0
  if [[ -r "$proc/uptime" ]]; then
    uptime_s=$(awk '{print int($1)}' "$proc/uptime" 2>/dev/null) || uptime_s=0
  fi
  [[ "$uptime_s" =~ ^[0-9]+$ ]] || uptime_s=0

  local excluded
  excluded=" $(_tc_self_and_ancestors)"

  local d pid cwd starttime elapsed
  for d in "$proc"/[0-9]*; do
    [[ -d "$d" ]] || continue
    pid="${d##*/}"
    [[ "$excluded" == *" $pid "* ]] && continue
    [[ -r "$d/cmdline" ]] || continue

    # Match on ARGV POSITION, never on the substring anywhere in the joined
    # cmdline (cq-assert-anchor-not-bare-token applied to process matching).
    # A process counts as a RUN only when either:
    #   (a) argv[0] is the runner itself (direct shebang exec), or
    #   (b) argv[0] is a shell AND some later argument is a whitespace-free
    #       path whose basename is test-all.sh.
    #
    # Every weaker rule was tried and rejected against real cmdlines:
    #   - substring over the joined cmdline matches any process that merely
    #     MENTIONS the runner (a `bash -c` with it in a trailing COMMENT
    #     matched itself during development);
    #   - "any token whose basename is test-all.sh" still matches that comment,
    #     because `${tok##*/}` on `... # scripts/test-all.sh` yields exactly
    #     `test-all.sh`, and it also matches `grep -rn test-all.sh scripts/`.
    # A false sibling makes the banner fire on every solo run, and a banner
    # that always fires carries no information.
    local -a argv=()
    mapfile -t -d '' argv < "$d/cmdline" 2>/dev/null || true
    (( ${#argv[@]} > 0 )) || continue

    local a0="${argv[0]##*/}" matched=0
    if [[ "$a0" == "test-all.sh" ]]; then
      matched=1
    elif [[ "$a0" == bash || "$a0" == sh || "$a0" == dash || "$a0" == zsh || "$a0" == ksh ]]; then
      local tok i
      for (( i = 1; i < ${#argv[@]}; i++ )); do
        tok="${argv[i]}"
        [[ "$tok" == *[[:space:]]* ]] && continue
        if [[ "${tok##*/}" == "test-all.sh" ]]; then matched=1; break; fi
      done
    fi
    (( matched )) || continue

    cwd=$(readlink "$d/cwd" 2>/dev/null) || cwd="<unreadable>"
    [[ -n "$cwd" ]] || cwd="<unreadable>"

    starttime=$(_tc_starttime_ticks "$d/stat") || starttime=""
    elapsed=0
    if [[ "$starttime" =~ ^[0-9]+$ ]] && (( uptime_s > 0 )); then
      elapsed=$(( uptime_s - starttime / _TC_CLK_TCK ))
      (( elapsed < 0 )) && elapsed=0
    fi

    printf '%s\t%s\t%s\n' "$pid" "$cwd" "$elapsed"
  done
  return 0
}

_tc_line_count() {
  local s="$1"
  [[ -n "${s//[[:space:]]/}" ]] || { printf '0\n'; return 0; }
  printf '%s\n' "$(grep -c . <<<"$s" || true)"
}

# --- Preamble --------------------------------------------------------------
#
# Emitted before the first suite. Banners are NAMED (LOW_TMP_HEADROOM /
# SIBLING_RUN_DETECTED) so a reader is never left inferring which condition
# fired — that inference is exactly what turned #6726 into a regression hunt.

tc_preamble() {
  local used_pct avail_mb entries sibs sib_count load cores memavail_kb
  used_pct=$(tc_used_pct)
  avail_mb=$(tc_avail_mb)
  entries=$(tc_tmp_entry_count)
  sibs=$(tc_siblings || true)
  # Count DISTINCT worktrees, not raw pids: one logical run legitimately shows
  # up as several processes (the script plus its wrapper shell), so a pid count
  # overstates how many concurrent runs are actually competing for the tmpfs.
  # The per-pid detail lines below keep the raw view available.
  sib_count=0
  if [[ -n "${sibs//[[:space:]]/}" ]]; then
    sib_count=$(cut -f2 <<<"$sibs" | sort -u | grep -c . || true)
  fi

  load="?"
  if [[ -r "$TC_PROC_ROOT/loadavg" ]]; then
    load=$(awk '{print $1}' "$TC_PROC_ROOT/loadavg" 2>/dev/null) || load="?"
  fi
  cores="${TC_NPROC:-$(nproc 2>/dev/null || echo '?')}"
  memavail_kb="?"
  if [[ -r "$TC_PROC_ROOT/meminfo" ]]; then
    memavail_kb=$(awk '/^MemAvailable:/ {print $2}' "$TC_PROC_ROOT/meminfo" 2>/dev/null) || memavail_kb="?"
  fi
  local memavail_mb="?"
  [[ "$memavail_kb" =~ ^[0-9]+$ ]] && memavail_mb=$(( memavail_kb / 1024 ))

  echo "=== test-all.sh contention preamble (#6789) ==="
  printf '[contention] tmp %s: %s%% used, %sMB avail, %s entries\n' \
    "$TC_TMPDIR" "$used_pct" "$avail_mb" "$entries"
  if [[ -n "$TC_XDG_DIR" && -d "$TC_XDG_DIR" ]]; then
    printf '[contention] runtime %s: %s%% used, %sMB avail, %s entries\n' \
      "$TC_XDG_DIR" "$(tc_used_pct "$TC_XDG_DIR")" "$(tc_avail_mb "$TC_XDG_DIR")" \
      "$(tc_tmp_entry_count "$TC_XDG_DIR")"
  fi
  printf '[contention] machine: %s cores, load %s, MemAvailable %sMB\n' \
    "$cores" "$load" "$memavail_mb"
  printf '[contention] siblings: %s other worktree(s) running test-all.sh\n' "$sib_count"

  if (( sib_count > 0 )); then
    while IFS=$'\t' read -r p c e; do
      [[ -n "$p" ]] || continue
      printf '[contention]   -> pid %s in %s (running %ss)\n' "$p" "$c" "$e"
    done <<< "$sibs"
  fi

  # Named banners. Both are advisory: nothing here changes the run's outcome.
  if [[ "$avail_mb" =~ ^[0-9]+$ ]] && (( avail_mb < TC_MIN_AVAIL_MB )); then
    printf '[contention] BANNER LOW_TMP_HEADROOM: %sMB avail is below the %sMB floor. A failure in this run may be resource contention, not a regression — re-run the failing suite in isolation before diagnosing.\n' \
      "$avail_mb" "$TC_MIN_AVAIL_MB" >&2
  fi
  if (( sib_count > 0 )); then
    printf '[contention] BANNER SIBLING_RUN_DETECTED: test-all.sh is running in %s other worktree(s) (listed above). Confirm a failure three ways — isolated re-run, the matching CI gate, and a clean full re-run once the sibling exits — before accepting it as real.\n' \
      "$sib_count" >&2
  fi
  return 0
}

# --- Epilogue --------------------------------------------------------------
#
# The whole-run delta. A non-zero delta means the run leaked tempfiles; the
# per-suite delta (appended to TEST_TIMING_LOG by run_suite) attributes it to
# a named suite. That per-suite attribution is the probe for hypothesis H4 —
# a shared derived tempfile path in some suite reached by the runner.

# --- Advisory queue (Phase 3) ----------------------------------------------
#
# Replaces the manual `ps -ef | grep test-all` ritual with a git-common-dir
# advisory lock (session-state.sh's acquire_lock, so all worktrees of one repo
# share one lock). It is ADVISORY — the load-bearing safety property: on
# timeout it PROCEEDS with a named banner, NEVER aborts. Aborting would turn
# today's silent 10-minute wait into a hard failure, strictly worse than the
# status quo; proceeding-with-announcement preserves today's worst case (an
# interleaved run) while making it attributable, which is the actual defect.
# Because it never blocks, no failure mode of the lock can wedge a session.
#
# Emits exactly one named status line so the reason is never inferred:
#   LOCK_SKIPPED_DISABLED / LOCK_SKIPPED_CI / LOCK_UNAVAILABLE /
#   LOCK_ACQUIRED / LOCK_CONTENDED_PROCEEDING
#
# Deliberately NO stale-holder detection (Phase 3.6): flock is kernel-managed
# and inode-bound, released automatically once the last fd holder dies (proven
# by AC5b). A "dead pid still holds the lock" state is unreachable with real
# flock, so code defending it would be dead code.
tc_acquire() {
  local name="$1"
  local timeout_s="${2:-$TC_LOCK_TIMEOUT}"

  # Kill switch — honoured before anything else so an operator can always
  # disable the layer in an emergency.
  if [[ "${SOLEUR_DISABLE_SESSION_STATE:-}" == "1" ]]; then
    echo "[contention] LOCK_SKIPPED_DISABLED: SOLEUR_DISABLE_SESSION_STATE=1; not serializing." >&2
    return 0
  fi

  # CI exemption. Matrix shards run one job per runner, so a lock buys nothing
  # and risks wedging a matrix.
  if [[ -n "${CI:-}" ]]; then
    echo "[contention] LOCK_SKIPPED_CI: CI is set; matrix shards are already isolated." >&2
    return 0
  fi

  if [[ ! -f "$TC_SESSION_STATE" ]]; then
    echo "[contention] LOCK_UNAVAILABLE: session-state.sh not found at $TC_SESSION_STATE; proceeding without serialization." >&2
    return 0
  fi
  # shellcheck source=/dev/null
  source "$TC_SESSION_STATE" 2>/dev/null || true
  if ! declare -F acquire_lock >/dev/null 2>&1; then
    echo "[contention] LOCK_UNAVAILABLE: acquire_lock not defined after sourcing; proceeding." >&2
    return 0
  fi

  if acquire_lock "$name" "$timeout_s"; then
    echo "[contention] LOCK_ACQUIRED: '$name' (worktrees of this repo serialize on it)." >&2
    return 0
  fi

  # Advisory: proceed, never abort.
  echo "[contention] LOCK_CONTENDED_PROCEEDING: '$name' still held after ${timeout_s}s; proceeding anyway (advisory). A failure now may be interleaving — re-run the failing suite in isolation before diagnosing." >&2
  return 0
}

tc_epilogue() {
  local start_count="${1:-0}"
  local now delta
  now=$(tc_tmp_entry_count)
  delta=$(( now - start_count ))
  echo "=== test-all.sh contention epilogue (#6789) ==="
  printf '[contention] tmp entries %s -> %s (delta %s), %s%% used, %sMB avail\n' \
    "$start_count" "$now" "$delta" "$(tc_used_pct)" "$(tc_avail_mb)"
  if (( delta > 0 )); then
    printf '[contention] NOTE: this run left %s new entries in %s. Per-suite deltas are in TEST_TIMING_LOG when set.\n' \
      "$delta" "$TC_TMPDIR"
  fi
  return 0
}
