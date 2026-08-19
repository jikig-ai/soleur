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
TC_SESSION_STATE="${TC_SESSION_STATE:-$_tc_lib_dir/../../plugins/soleur/scripts/lib/session-state.sh}"
# A test-all.sh run is minutes, not seconds. with_lock's 30s default would fire
# the advisory path on essentially every genuine overlap, so size the wait to a
# full suite.
TC_LOCK_TIMEOUT="${TC_LOCK_TIMEOUT:-900}"

# --- Capacity probes -------------------------------------------------------
# `df -P` pins POSIX single-line output so a long device name cannot wrap and
# shift the awk field indices. TC_DF_CMD is a test seam so a suite can pin a
# KNOWN avail/used% (the real `df` cannot be fixtured); it defaults to the real
# binary and every caller invokes it exactly as `df` would be.
TC_DF_CMD="${TC_DF_CMD:-df}"

tc_tmp_entry_count() {
  local d="${1:-$TC_TMPDIR}"
  [[ -d "$d" ]] || { printf '0\n'; return 0; }
  local n
  n=$(find "$d" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l) || n=0
  printf '%s\n' "${n// /}"
}

tc_avail_mb() {
  local d="${1:-$TC_TMPDIR}" kb
  kb=$("$TC_DF_CMD" -P -k "$d" 2>/dev/null | awk 'NR==2 {print $4}') || kb=""
  [[ "$kb" =~ ^[0-9]+$ ]] || { printf '0\n'; return 0; }
  printf '%s\n' $(( kb / 1024 ))
}

tc_used_pct() {
  local d="${1:-$TC_TMPDIR}" p
  p=$("$TC_DF_CMD" -P -k "$d" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}') || p=""
  [[ "$p" =~ ^[0-9]+$ ]] || { printf '0\n'; return 0; }
  printf '%s\n' "$p"
}

# Used BYTES on the mount a directory lives on.
#
# WHY THIS EXISTS. The per-suite probe records `tmp_delta=<ENTRY COUNT>`, but
# ADR-133's capacity verdict is about BYTES -- that ADR explicitly rejected
# count-based reasoning because 4,294 small entries held 160 MB (4.5%) while
# three trees held 3.1 GiB (88%). The quantity the advisory lock exists to
# protect had never been measured by the instrument shipped to measure it.
#
# `df`, NOT `du`. ADR-133's question is a MOUNT's capacity ("a machine-global
# RAM-backed 4 GiB /tmp at 86% full"), not a directory's size, and df answers it
# in O(1) with no recursive walk. Measured on this machine: `du -sk /tmp` took
# 2.15 s and `du -sk /var/tmp` did not finish in 115 s, so a du-based probe would
# have added an unbounded observer effect to the very run it instruments.
#
# PER-MOUNT BY CONSTRUCTION. It takes a directory and reports the mount that
# directory lives on; there is deliberately no "total scratch" variant. TMPDIR
# (/var/tmp, disk-backed) and TC_TMPDIR (/tmp, the tmpfs) are different mounts ON
# PURPOSE, and a single number spanning both would report health from whichever
# is roomier -- indistinguishable from a healthy mount, which is the exact
# fail-open the comment at test-all.sh:18-29 was written to prevent.
#
# Field 3 of `df -P -k` is Used in 1024-blocks. Degrades to 0 rather than
# failing: callers run inside the gate, so an exception on an unparseable
# reading would take a whole run down mid-flight.
tc_used_bytes() {
  local d="${1:-$TC_TMPDIR}" kb
  kb=$("$TC_DF_CMD" -P -k "$d" 2>/dev/null | awk 'NR==2 {print $3}') || kb=""
  [[ "$kb" =~ ^[0-9]+$ ]] || { printf '0\n'; return 0; }
  printf '%s\n' $(( kb * 1024 ))
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
# Overall field 5 (pgrp) => field 3 after the comm strip.
_tc_pgrp() { _tc_stat_field "$1" 3; }

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

# Applies the RUN predicate to one /proc/<pid> directory. Exit 0 on a match.
#
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
#
# Extracted from the scan loop UNCHANGED (#7424 Phase 4). It is now called from
# two places — the classifier below and the ancestry walk — and the ancestry
# walk needs the PREDICATE, not the match SET: an ancestor may legitimately be
# excluded from the scan (it is in the self/pgid exclusion, or it is $$ itself)
# and must still cancel its children.
_tc_is_run_proc() {
  local d="$1"
  [[ -r "$d/cmdline" ]] || return 1
  local -a argv=()
  mapfile -t -d '' argv < "$d/cmdline" 2>/dev/null || true
  (( ${#argv[@]} > 0 )) || return 1

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
  (( matched )) || return 1
  return 0
}

# Does this path name an INDIVIDUAL suite? `*.test.sh`, or `test-*.sh` that is
# not the runner.
#
# THE `test-all.sh` EXCLUSION. The runner's own basename matches `test-*.sh`, so
# without it a full run would ALSO read as an individual suite and
# SIBLING_SUITE_DETECTED would fire on every solo run — the exact "a banner that
# always fires carries no information" failure the block above exists to prevent.
#
# MEASURED CORRECTION (2026-08-11, mutation battery): as _tc_scan_procs is
# written today the exclusion is the SECOND line of defence, not the first —
# classification tests the RUN predicate first, and every cmdline that would
# newly match here already classified as `run`, so deleting this clause changes
# no verdict through the scan. It is kept, and pinned by a predicate-level arm,
# because the thing standing between a solo run and a permanently-firing banner
# would otherwise be the ORDER of one if/elif.
#
# Two further scope edges, both measured, neither fatal:
#   - deliberately OVER-broad in one direction: `scripts/lib/test-contention.sh`
#     matches `test-*.sh`. It is sourced, never executed, so no process ever
#     carries it at argv[0] or as a bare token — latent, not live.
#   - deliberately UNDER-broad in another: `tests/hooks/test_incidents.sh` uses
#     an underscore and matches neither rule, and `timeout N bash <suite>` puts
#     a non-shell at argv[0] (a real shape in this repo, as does the webplat
#     `env … bash -c …` registration). Ancestry cancellation below is what keeps
#     the under-broad cases from mattering for the run-CHILD case, which is the
#     one that would otherwise produce a wrong count rather than a missing line.
_tc_is_suite_basename() {
  local b="${1##*/}"
  if [[ "$b" == *.test.sh ]]; then return 0; fi
  if [[ "$b" == test-*.sh && "$b" != "test-all.sh" ]]; then return 0; fi
  return 1
}

# Applies the SUITE predicate to one /proc/<pid> directory, with the SAME
# argv-position discipline as _tc_is_run_proc: argv[0] itself, or a
# whitespace-free later token under a shell argv[0]. The whitespace guard is
# what stops `bash -c 'grep -rn x tests/scripts/test-foo.sh'` — a command
# STRING, not an invocation — from counting as a running suite.
_tc_is_suite_proc() {
  local d="$1"
  [[ -r "$d/cmdline" ]] || return 1
  local -a argv=()
  mapfile -t -d '' argv < "$d/cmdline" 2>/dev/null || true
  (( ${#argv[@]} > 0 )) || return 1

  local a0="${argv[0]}" matched=0
  if _tc_is_suite_basename "$a0"; then
    matched=1
  else
    local b0="${a0##*/}"
    if [[ "$b0" == bash || "$b0" == sh || "$b0" == dash || "$b0" == zsh || "$b0" == ksh ]]; then
      local tok i
      for (( i = 1; i < ${#argv[@]}; i++ )); do
        tok="${argv[i]}"
        [[ "$tok" == *[[:space:]]* ]] && continue
        if _tc_is_suite_basename "$tok"; then matched=1; break; fi
      done
    fi
  fi
  (( matched )) || return 1
  return 0
}

# Walks a pid's ppid chain under the same 64-step guard as
# _tc_self_and_ancestors and reports whether ANY ancestor is a sibling run.
#
# WHY ANCESTRY AND NOT A cwd SET-DIFFERENCE. Three measured ways the cwd
# difference produces a wrong count:
#   - suites routinely `cd` into a `mktemp -d` sandbox, so one worktree appears
#     under two unequal cwd strings and the difference FAILS to cancel —
#     double-reporting the very worktree it existed to protect;
#   - `<unreadable>` is substituted for every cwd that cannot be read, so all
#     such processes share one pseudo-worktree and a SINGLE unreadable run would
#     subtract EVERY unreadable suite;
#   - a run behind `timeout … bash scripts/test-all.sh` has a non-shell argv[0],
#     so no run match exists at all while its suite children do — reporting a
#     full run as "a worktree running an individual suite".
# Ancestry is invariant under `cd`, immune to `<unreadable>`, and reaches
# through wrapper processes that match neither predicate.
_tc_has_run_ancestor() {
  local pid="$1" guard=0 ppid
  while [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 0 && guard < 64 )); do
    ppid=$(_tc_ppid "$TC_PROC_ROOT/$pid/stat") || ppid=""
    [[ "$ppid" =~ ^[0-9]+$ ]] || return 1
    (( ppid > 0 )) || return 1
    [[ "$ppid" == "$pid" ]] && return 1
    if _tc_is_run_proc "$TC_PROC_ROOT/$ppid"; then return 0; fi
    pid="$ppid"
    guard=$(( guard + 1 ))
  done
  return 1
}

# ONE /proc walk. Emits "class<TAB>pid<TAB>cwd<TAB>elapsed_s", class ∈ run|suite.
#
# WHY ONE WALK AND NOT TWO VIEWS: cancellation is a CROSS-BUCKET predicate — a
# suite match survives only if no run match is its ancestor — so the run set must
# be in scope during the same pass. Two walks are two non-atomic snapshots, over
# which a difference is computed on inconsistent sets.
#
# Own-suite children cannot self-match here: tc_preamble runs BEFORE the first
# run_suite, so no child exists yet, and the self_pgrp exclusion below covers
# this run's children in any case. Both statements are the precondition for any
# later "call the preamble mid-run" edit.
_tc_scan_procs() {
  local proc="$TC_PROC_ROOT"
  [[ -d "$proc" ]] || return 0

  local uptime_s=0
  if [[ -r "$proc/uptime" ]]; then
    uptime_s=$(awk '{print int($1)}' "$proc/uptime" 2>/dev/null) || uptime_s=0
  fi
  [[ "$uptime_s" =~ ^[0-9]+$ ]] || uptime_s=0

  local excluded
  excluded=" $(_tc_self_and_ancestors)"

  # Own process GROUP. The `&`-backgrounding shells and command-substitution
  # subshells of THIS very test-all.sh invocation share its pgid but are NOT in
  # the preamble's ancestor chain, so ancestor-exclusion alone lets a run flag a
  # transient fork of ITSELF as a concurrent sibling (observed: a "running 0s"
  # self-phantom at startup). A genuinely separate run — another worktree,
  # another terminal — has a DIFFERENT pgid, so pgid is the exact discriminator.
  # Empty when self has no readable stat (the synthetic-self test path), which
  # correctly disables this extra exclusion there.
  local self_pgrp
  self_pgrp=$(_tc_pgrp "$proc/$TC_SELF_PID/stat" 2>/dev/null) || self_pgrp=""
  [[ "$self_pgrp" =~ ^[0-9]+$ ]] || self_pgrp=""

  # Run pgids are accumulated space-delimited so the fallback below is a
  # substring test on a bounded string rather than a nested loop.
  local run_pgrps=" "
  local -a suite_pids=() suite_rows=() suite_pgrps=()
  local d pid cwd starttime elapsed pgrp kind
  for d in "$proc"/[0-9]*; do
    [[ -d "$d" ]] || continue
    pid="${d##*/}"
    [[ "$excluded" == *" $pid "* ]] && continue
    pgrp=$(_tc_pgrp "$d/stat") || pgrp=""
    if [[ -n "$self_pgrp" ]]; then
      [[ "$pgrp" == "$self_pgrp" ]] && continue
    fi
    [[ -r "$d/cmdline" ]] || continue

    kind=""
    if _tc_is_run_proc "$d"; then
      kind="run"
    elif _tc_is_suite_proc "$d"; then
      kind="suite"
    else
      continue
    fi

    cwd=$(readlink "$d/cwd" 2>/dev/null) || cwd="<unreadable>"
    [[ -n "$cwd" ]] || cwd="<unreadable>"

    starttime=$(_tc_starttime_ticks "$d/stat") || starttime=""
    elapsed=0
    if [[ "$starttime" =~ ^[0-9]+$ ]] && (( uptime_s > 0 )); then
      elapsed=$(( uptime_s - starttime / _TC_CLK_TCK ))
      (( elapsed < 0 )) && elapsed=0
    fi

    if [[ "$kind" == "run" ]]; then
      # pgid 0 is not a real process group; admitting it would make every
      # process whose pgid could not be read cancel every other such process.
      if [[ "$pgrp" =~ ^[0-9]+$ ]] && (( pgrp > 0 )); then
        run_pgrps+="$pgrp "
      fi
      printf 'run\t%s\t%s\t%s\n' "$pid" "$cwd" "$elapsed"
    else
      suite_pids+=("$pid")
      suite_rows+=("$pid"$'\t'"$cwd"$'\t'"$elapsed")
      suite_pgrps+=("$pgrp")
    fi
  done

  # Cancellation pass. A suite match that belongs to a sibling RUN is that run's
  # own child, already reported by the run line; emitting it too would count one
  # worktree twice and label a full run "an individual test suite".
  local i spg
  for (( i = 0; i < ${#suite_pids[@]}; i++ )); do
    if _tc_has_run_ancestor "${suite_pids[i]}"; then continue; fi
    # Fallback for the reparented case: a run_suite child inherits the runner's
    # pgid under a non-interactive shell, so a shared pgid still identifies it
    # after the ppid chain has been cut by the parent's exit.
    spg="${suite_pgrps[i]}"
    if [[ "$spg" =~ ^[0-9]+$ ]] && (( spg > 0 )) && [[ "$run_pgrps" == *" $spg "* ]]; then
      continue
    fi
    printf 'suite\t%s\n' "${suite_rows[i]}"
  done
  return 0
}

# Back-compat views over the single snapshot. Both emit the historical
# "pid<TAB>cwd<TAB>elapsed_s" shape and take no arguments, so every existing
# tc_siblings call site keeps working byte-for-byte.
tc_siblings()       { _tc_scan_procs | awk -F'\t' '$1=="run"   {print $2"\t"$3"\t"$4}'; }
tc_suite_siblings() { _tc_scan_procs | awk -F'\t' '$1=="suite" {print $2"\t"$3"\t"$4}'; }

# --- Preamble --------------------------------------------------------------
#
# Emitted before the first suite. Banners are NAMED (LOW_TMP_HEADROOM /
# SIBLING_RUN_DETECTED) so a reader is never left inferring which condition
# fired — that inference is exactly what turned #6726 into a regression hunt.

tc_preamble() {
  local used_pct avail_mb entries scan sibs suite_sibs sib_count suite_count
  local load cores memavail_kb
  used_pct=$(tc_used_pct)
  avail_mb=$(tc_avail_mb)
  entries=$(tc_tmp_entry_count)
  # ONE /proc walk, split into the two views here. Calling the two view
  # functions instead would take two non-atomic snapshots.
  scan=$(_tc_scan_procs || true)
  sibs=$(awk -F'\t' '$1=="run"   {print $2"\t"$3"\t"$4}' <<<"$scan")
  suite_sibs=$(awk -F'\t' '$1=="suite" {print $2"\t"$3"\t"$4}' <<<"$scan")
  # Count DISTINCT worktrees, not raw pids: one logical run legitimately shows
  # up as several processes (the script plus its wrapper shell), so a pid count
  # overstates how many concurrent runs are actually competing for the tmpfs.
  # The per-pid detail lines below keep the raw view available.
  sib_count=0
  if [[ -n "${sibs//[[:space:]]/}" ]]; then
    sib_count=$(cut -f2 <<<"$sibs" | sort -u | grep -c . || true)
  fi
  suite_count=0
  if [[ -n "${suite_sibs//[[:space:]]/}" ]]; then
    suite_count=$(cut -f2 <<<"$suite_sibs" | sort -u | grep -c . || true)
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

  # Exported so a POLICY at the call site can read it. Deliberately NOT acted on here: this
  # function is a REPORTER, and burying a refusal in a measurement function is how the next
  # reader ends up trusting a comment that is no longer true. scripts/test-all.sh decides.
  TC_SIBLING_RUN_COUNT="$sib_count"
  export TC_SIBLING_RUN_COUNT

  if (( sib_count > 0 )); then
    while IFS=$'\t' read -r p c e; do
      [[ -n "$p" ]] || continue
      printf '[contention]   -> pid %s in %s (running %ss)\n' "$p" "$c" "$e"
    done <<< "$sibs"
  fi

  printf '[contention] suite siblings: %s other worktree(s) running an individual test suite\n' \
    "$suite_count"
  if (( suite_count > 0 )); then
    while IFS=$'\t' read -r p c e; do
      [[ -n "$p" ]] || continue
      printf '[contention]   -> pid %s in %s (running %ss)\n' "$p" "$c" "$e"
    done <<< "$suite_sibs"
  fi

  # Named banners. Everything THIS FUNCTION does is advisory: nothing below changes the run's
  # outcome, and tc_preamble still always returns 0.
  #
  # But `SIBLING_RUN_DETECTED` is no longer purely advisory END-TO-END (#7553). The count it
  # reports is exported as TC_SIBLING_RUN_COUNT, and scripts/test-all.sh refuses a full-gate run
  # on it unless SOLEUR_ALLOW_FULL_GATE=1. The refusal lives there, not here, so the policy sits
  # next to the SOLEUR_SUBAGENT refusal it joins rather than inside the reporter.
  if [[ "$avail_mb" =~ ^[0-9]+$ ]] && (( avail_mb < TC_MIN_AVAIL_MB )); then
    printf '[contention] BANNER LOW_TMP_HEADROOM: %sMB avail is below the %sMB floor. A failure in this run may be resource contention, not a regression — re-run the failing suite in isolation before diagnosing.\n' \
      "$avail_mb" "$TC_MIN_AVAIL_MB" >&2
  fi
  if (( sib_count > 0 )); then
    printf '[contention] BANNER SIBLING_RUN_DETECTED: test-all.sh is running in %s other worktree(s) (listed above). Confirm a failure three ways — isolated re-run, the matching CI gate, and a clean full re-run once the sibling exits — before accepting it as real.\n' \
      "$sib_count" >&2
  fi
  # A separate banner, NOT a widening of the one above: the two answer different
  # questions, and folding suites into SIBLING_RUN_DETECTED would silently change
  # what every already-logged instance of that name meant.
  if (( suite_count > 0 )); then
    printf '[contention] BANNER SIBLING_SUITE_DETECTED: an individual test suite is running in %s other worktree(s) (listed above). This runner competes with it for the same tmpfs capacity. Confirm a failure three ways — isolated re-run, the matching CI gate, and a clean full re-run once the sibling exits — before accepting it as real.\n' \
      "$suite_count" >&2
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

# Elapsed between two EPOCHREALTIME readings, formatted for a banner:
# "<N>ms", or the literal "unknown".
#
# DELIBERATE DUPLICATION of run_suite's arithmetic in scripts/test-all.sh (find
# it there by the `local elapsed_ms=0` block). Not shared, and the reason is NOT
# a dependency cycle — the de-duplicating direction is script->lib, which is the
# direction that already exists. It is that test-all.sh degrades this lib to a
# silent noop stub when it cannot be sourced (`tc_acquire() { :; }`), so routing
# run_suite's REQUIRED timing through an OPTIONALLY-present function would trade
# 5 duplicated lines for a new silent-zero failure mode in the most load-bearing
# script in the repo.
#
# WHY "unknown" AND NOT 0: a fabricated zero is indistinguishable from a lock
# that was free on the first try — the exact false claim this change removes.
# Enforced behaviourally by the degraded-timing arm in scripts/test-contention.test.sh
# (search it for `unset EPOCHREALTIME`), which also pins the `${EPOCHREALTIME:-}`
# discipline below.
#
# EVERY read of EPOCHREALTIME here and in tc_acquire is `${EPOCHREALTIME:-}`,
# never bare: test-all.sh sources this lib under `set -euo pipefail`, where a
# bare read is an unbound-variable ABORT inside the one function whose contract
# is that it cannot abort (ADR-133 Decision 3).
_tc_ms_since() {
  local start="${1:-}" end="${2:-}"
  # The separator is LOCALE-dependent: bash renders EPOCHREALTIME using
  # LC_NUMERIC's radix, so a comma-locale operator (fr_FR, de_DE, ru_RU, pt_BR …)
  # gets `1786573806,515545`. Accept both, and require PURE DIGITS on each side.
  # The previous `*.*` glob was a SHAPE test, not a numeric one, so `100.` and
  # `x.1` passed it and reached the arithmetic — where they abort the caller
  # under `set -e`. Measured: comma locale blanked every banner to `unknown`
  # AND reddened three gate arms on a healthy bash 5 with a working clock.
  local re='^([0-9]+)[.,]([0-9]+)$'
  [[ "$start" =~ $re ]] || { printf 'unknown'; return 0; }
  local s_i="${BASH_REMATCH[1]}" s_f="${BASH_REMATCH[2]}"
  [[ "$end" =~ $re ]] || { printf 'unknown'; return 0; }
  local e_i="${BASH_REMATCH[1]}" e_f="${BASH_REMATCH[2]}"
  # `10#` forces base-10 so a leading zero in the microseconds field is not read
  # as octal.
  printf '%sms' $(( (e_i * 1000000 + 10#$e_f - s_i * 1000000 - 10#$s_f) / 1000 ))
}

tc_acquire() {
  # `${1:-}`, never bare `$1`. Under the `set -euo pipefail` that test-all.sh
  # sources this lib into, a zero-arg call is an unbound-variable ABORT one line
  # into the function whose whole contract is that it cannot abort — the same
  # class as the EPOCHREALTIME reads, one construct further out, and `|| true`
  # at the call site does not rescue it (a `set -u` expansion error is not
  # suppressible that way).
  local name="${1:-}"
  local timeout_s="${2:-$TC_LOCK_TIMEOUT}"
  if [[ -z "$name" ]]; then
    echo "[contention] LOCK_UNAVAILABLE: tc_acquire called with no lock name; proceeding without serialization." >&2
    return 0
  fi

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

  # The serialization primitive itself. acquire_lock returns the SAME 99 for
  # "waited the whole budget" and "flock(1) is not installed", so without this
  # precheck a run that never waited at all takes the contended path and then
  # reports a duration for a wait that never happened.
  #
  # It removes the DOMINANT such source, not all of them: `exec {fd}>>` failing
  # on an unwritable lock dir also returns 99 and still reports as contention
  # (measured: `gave up after 5ms of 900s`). The measured elapsed is what keeps
  # that case self-diagnosing rather than a flat lie — classifying it by an
  # elapsed threshold was considered and rejected as approximate where
  # `command -v` is exact.
  #
  # Placed AFTER the session-state check so a flock-less host still reports a
  # MISSING LIB when that is also true — that line is the tell for the
  # #7426 / ADR-178 plugin-path regression class, and checking flock first
  # masked it. Carries session-state's own remediation, which this early return
  # means we never reach.
  if ! command -v flock >/dev/null 2>&1; then
    echo "[contention] LOCK_UNAVAILABLE: flock(1) not found on PATH; proceeding without serialization." >&2
    echo "[contention]   macOS: brew install util-linux && add \$(brew --prefix util-linux)/sbin to PATH" >&2
    return 0
  fi
  # shellcheck source=/dev/null
  source "$TC_SESSION_STATE" 2>/dev/null || true
  if ! declare -F acquire_lock >/dev/null 2>&1; then
    echo "[contention] LOCK_UNAVAILABLE: acquire_lock not defined after sourcing; proceeding." >&2
    return 0
  fi

  # Emitted after every skip path, so its PRESENCE is a fact about control flow:
  # this run reached the wait. It is a live-stderr affordance — a 15-minute
  # block reads as a queue rather than a hang — and deliberately a plain line
  # rather than a BANNER, because it fires on every run that gets here and
  # work/SKILL.md's contention grep is anchored specifically to avoid
  # always-firing hits.
  echo "[contention] LOCK_WAITING: '$name' — waiting up to ${timeout_s}s for the advisory lock." >&2

  # The two readings bracket the blocking call and nothing else. `_tc_ms_since`
  # is called AFTER the end reading is captured, so its command substitution
  # cannot inflate the number it formats.
  local t0="${EPOCHREALTIME:-}" t1 waited
  if acquire_lock "$name" "$timeout_s"; then
    t1="${EPOCHREALTIME:-}"
    waited="$(_tc_ms_since "$t0" "$t1")"
    echo "[contention] LOCK_ACQUIRED: '$name' after $waited (worktrees of this repo serialize on it)." >&2
    return 0
  fi
  t1="${EPOCHREALTIME:-}"
  waited="$(_tc_ms_since "$t0" "$t1")"

  # Advisory: proceed, never abort. Reports the duration that was MEASURED
  # against the budget it was given. The previous text asserted `still held
  # after <timeout>s` unconditionally, which was false whenever acquire_lock
  # returned without waiting — the case the flock precheck above now removes.
  echo "[contention] LOCK_CONTENDED_PROCEEDING: '$name' — gave up after $waited of ${timeout_s}s; proceeding anyway (advisory). A failure now may be interleaving — re-run the failing suite in isolation before diagnosing." >&2
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
