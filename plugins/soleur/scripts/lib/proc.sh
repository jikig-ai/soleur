#!/usr/bin/env bash
# Soleur process helpers: enumerate and signal test runs WITHOUT killing the
# invoking shell or another worktree's session.
#
# WHY THIS FILE EXISTS. A prose rule forbidding self-matching `pkill -f` already
# lived in the work skill and did not prevent the failure it describes: on
# 2026-08-13 an agent read that rule, ran the forbidden form anyway, killed its
# own shell, then wrote a "more careful" pgrep loop that self-matched and killed
# its shell a second time. The second attempt was also unscoped across sibling
# worktrees — parallel worktrees are this repo's documented workflow, so an
# unscoped pattern is a cross-session destructive action. Prose does not
# execute; this does. See #7525.
#
# WHY BRACKET-SAFETY IS A CATEGORY ERROR HERE. `[t]est-all` is a pgrep/`ps|grep`
# idiom: it stops the MATCHER from matching itself. A /proc walk has no pattern
# for a bracket to fool, and the invoker's own command line still contains the
# literal pattern either way. The property ("never reports the process
# performing the enumeration") is bought by the three exclusions below instead.
#
# HIDDEN ASSUMPTION, stated because the design depends on it: proc.sh's own
# command line MATCHES proc.sh's own predicate. That is the entire reason the
# process-group exclusion is required — proc.sh's command-substitution forks
# match the predicate and are NOT ancestors. Do not remove it on the grounds
# that ancestry already covers the invoking shell.
#
# THE SCAN->SIGNAL CHANNEL CARRIES NO PATHS. This is the file's single most
# important structural property and it was learned the hard way: the first
# revision emitted `class<TAB>pid<TAB>cwd` and read it back with
# `IFS=$'\t' read`. A directory name may legally contain a newline, and
# /proc/<pid>/cwd reports it verbatim — so a process whose cwd was a directory
# named $'evil\nsignal\t31337\t/pwned' injected a FORGED `signal` row into the
# protocol. Measured: pid 31337 reached the kill site having never matched the
# pattern, never been classified, and never had its cwd tested, while the
# carrier process itself was correctly refused. The refusal path WAS the
# injection vector, so a correct boundary check did not help.
#
# Therefore the channel now carries only (a) a class token from a closed set of
# literals and (b) a pid, which is numeric by construction and re-validated
# before use. Paths are re-read by the consumer for DISPLAY only, and sanitized.
# Do not put a filesystem path back into this channel.
#
# The /proc primitives below are MIRRORED from scripts/lib/test-contention.sh
# (search that file for `_tc_stat_field`), deliberately not sourced: this file
# ships inside the plugin (ADR-178) and a shipped file sourcing a repo-root
# library is the exact defect ADR-178 exists to prevent. plugins/soleur/test/
# proc.test.sh pins the mirrored forms against drift.
#
# Location: ships INSIDE the plugin (ADR-178, ADR-179) so a marketplace install
# resolves it, and so a customer's own `scripts/` directory cannot shadow a file
# whose advertised contract is to send signals.
#
# PORTABILITY: bash 3.2 (the /bin/bash macOS ships). `mapfile -d` is bash 4.4+
# and is deliberately NOT used — when it is absent the error is swallowed, argv
# stays empty, nothing ever matches, and `kill_mine` prints `killed=0`, which
# reads as "nothing to kill" and sends the operator back to pkill. That is this
# file's own failure mode reappearing one level down, so the NUL read below is
# written the portable way on purpose.

# Guard against double-source within a single shell.
if [[ "${_SOLEUR_PROC_LOADED:-}" == "1" ]]; then
  return 0 2>/dev/null || true
fi
_SOLEUR_PROC_LOADED=1

# Test seams. Namespace-prefixed because scripts/tmpfs-guard.sh already binds a
# bare PROC_ROOT and this file is sourceable.
PROC_SH_ROOT="${PROC_SH_ROOT:-/proc}"
PROC_SH_SELF_PID="${PROC_SH_SELF_PID:-$$}"

# Wrapper commands that legitimately precede a shell on the command line.
# Without this, `timeout 600 bash scripts/test-all.sh` has argv[0]=timeout and
# is INVISIBLE to both verbs — and `timeout … bash <suite>` is a real shape in
# this repo (scripts/lib/test-contention.sh says so in its own comments). An
# invisible run is a silent `killed=0`, i.e. the D6 failure mode.
_PROC_WRAPPERS='timeout env nohup nice ionice setsid stdbuf time taskset flock script unbuffer'
# NOT `busybox`: it is an applet multiplexer, not a shell, so admitting it makes
# `busybox grep -rn test-all.sh` scan every later token and match — the same
# over-match the wrapper walk below was corrected for.
_PROC_SHELLS='bash sh dash zsh ksh mksh ash'

# --- /proc primitives (mirrored from scripts/lib/test-contention.sh) --------
#
# comm (field 2) is parenthesized and MAY contain spaces and close-parens, so
# the parser strips through the LAST ') ' rather than splitting on whitespace.
# A naive `awk '{print $4}'` mis-indexes on any such process — which is exactly
# what the /proc recipe currently quoted in git-worktree/SKILL.md does.
_proc_stat_field() {
  # $1 = path to a /proc/<pid>/stat file, $2 = field index AFTER the comm strip
  # (i.e. overall field N maps to N-2 here).
  local f="$1" idx="$2" line rest
  [[ -r "$f" ]] || return 0
  line=$(cat "$f" 2>/dev/null) || return 0
  rest="${line##*') '}"
  awk -v i="$idx" '{print $i}' <<<"$rest"
}

# Overall field 4 (ppid) => field 2 after the comm strip.
_proc_ppid() { _proc_stat_field "$1" 2; }
# Overall field 5 (pgrp) => field 3 after the comm strip.
_proc_pgrp() { _proc_stat_field "$1" 3; }

# Self plus every ancestor pid.
#
# WHY THE WHOLE CHAIN, not just $$ and $PPID: this helper is normally launched
# through a wrapper (`bash -c '… bash …/proc.sh kill_mine test-all.sh'`, a CI
# step shell, an agent harness), and that wrapper's OWN command line contains
# the pattern. Excluding only $$ reports the caller's own invocation as a
# target on EVERY run. Measured in test-contention.sh's development: a clean
# solo run reported 2 phantom siblings, both links in its own ancestor chain.
_proc_self_and_ancestors() {
  local pid="$PROC_SH_SELF_PID" out="" guard=0
  while [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 0 && guard < 64 )); do
    out+="$pid "
    local ppid
    ppid=$(_proc_ppid "$PROC_SH_ROOT/$pid/stat") || ppid=""
    [[ "$ppid" =~ ^[0-9]+$ ]] || break
    [[ "$ppid" == "$pid" ]] && break
    pid="$ppid"
    guard=$(( guard + 1 ))
  done
  printf '%s' "$out"
}

# --- Ownership boundary ----------------------------------------------------

# Canonicalize a directory so a symlinked worktree path compares equal to the
# resolved cwd /proc reports. Without this, kill_mine refuses EVERYTHING and
# looks correct — a failure the suite must have a fixture for, because a
# positive control whose paths are already canonical cannot see it.
_proc_canon() {
  local p="$1"
  if [[ -d "$p" ]]; then
    (cd "$p" 2>/dev/null && pwd -P) && return 0
  fi
  printf '%s' "$p"
}

# The current worktree, or a loud failure. Fail-closed on purpose: a scan with
# no ownership boundary would classify every match as foreign or, worse, as
# mine — and this file's whole contract is that boundary.
_proc_worktree() {
  local root
  if [[ -n "${PROC_SH_WORKTREE:-}" ]]; then
    root=$(_proc_canon "$PROC_SH_WORKTREE")
  else
    root=$(git rev-parse --show-toplevel 2>/dev/null) || root=""
    if [[ -z "$root" ]]; then
      echo "proc.sh: cannot resolve the current worktree (not inside a git repository and PROC_SH_WORKTREE is unset)." >&2
      echo "proc.sh: refusing to scan — without an ownership boundary this cannot tell your processes from another session's." >&2
      return 1
    fi
    root=$(_proc_canon "$root")
  fi

  # The boundary must be an absolute path below the filesystem root. An empty
  # root would make the prefix test `/*`, which matches EVERY absolute path;
  # a bare `/` is a boundary that owns the whole machine. Both are refused
  # structurally rather than relying on the prefix test's incidental behaviour.
  if [[ "$root" != /* || "$root" == "/" ]]; then
    echo "proc.sh: refusing to scan — ownership boundary '$root' is not an absolute path below /." >&2
    return 1
  fi
  printf '%s' "$root"
}

# Sibling worktrees nested UNDER the current root, loaded into the global array
# `_PROC_NESTED`.
#
# WHY: in the ordinary non-bare layout the main checkout's toplevel is a strict
# PREFIX of every worktree beneath it, so `kill_mine` run from the main checkout
# would classify every sibling worktree's processes as `mine` — the exact
# cross-session kill this file exists to prevent, arriving through the boundary
# rather than around it.
#
# AN ARRAY, NOT A DELIMITED STRING, and `--porcelain`, NOT the default format.
# The first revision of this function did `${line%% *}` over `git worktree list`
# and joined the results space-delimited, then re-split them with an unquoted
# `for`. That is the F1 defect class — a path in a text channel — re-created
# inside the guard written to close a different instance of it. Measured: a
# worktree at `.worktrees/my branch` truncated to `.worktrees/my`, matched
# nothing, and was NOT excluded, so the cross-worktree kill came back through
# the new guard. The unquoted `for` also glob-expanded any path containing `*`.
# `--porcelain` emits one unambiguous `worktree <path>` line per entry.
#
# `git -C "$root"`, not the ambient cwd: with PROC_SH_WORKTREE scoping the
# boundary to a repo other than the caller's cwd — the documented seam — running
# git in the cwd returns nothing, and an empty exclusion set is NOT harmless. It
# is precisely the state this function exists to prevent, so it warns.
_PROC_NESTED=()
_proc_load_nested() {
  local root="$1" line p
  _PROC_NESTED=()
  if ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    echo "proc.sh: warning — cannot enumerate worktrees under '$root' (not a git repo, or git unavailable)." >&2
    echo "proc.sh: nested worktrees will NOT be excluded; a process in one may be classified as yours." >&2
    return 0
  fi
  while IFS= read -r line; do
    [[ "$line" == worktree\ * ]] || continue
    p="${line#worktree }"
    [[ -n "$p" ]] || continue
    p=$(_proc_canon "$p")
    [[ "$p" == "$root" ]] && continue
    [[ "$p" == "$root"/* ]] && _PROC_NESTED+=("$p")
  done < <(git -C "$root" worktree list --porcelain 2>/dev/null || true)
}

# Does this pid's own cwd lie inside the ownership boundary?
#
# The SINGLE source of truth for the boundary — called once during the walk and
# again immediately before the signal. The second call narrows the pid-reuse
# window and re-validates numeric form; it is NOT a forgery defence (a forged
# pid naming any process whose cwd is inside the boundary would pass it
# unchanged). The forgery defence is that the channel carries no paths at all.
#
# On success it sets `_PROC_OWNS_CWD` to the canonicalized path that PASSED the
# check, so the caller can report the value the decision was made on rather than
# taking a third, independent reading.
_PROC_OWNS_CWD=""
_proc_owns() {
  local pid="$1" root="$2" cwd n
  _PROC_OWNS_CWD=""
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  cwd=$(readlink "$PROC_SH_ROOT/$pid/cwd" 2>/dev/null) || return 1
  [[ -n "$cwd" ]] || return 1
  # A deleted cwd is reported by the kernel as `<path> (deleted)`, with rc 0.
  # That is a "could not establish where this process is" state, not a path, so
  # it is refused rather than string-matched — no positive proof, no signal.
  #
  # This suffix test is FALSIFIABLE, and deliberately kept anyway (#7537).
  # Measured: a live directory literally named `work (deleted)` reads st_nlink 2
  # while a genuinely deleted cwd reads 0, so the suffix alone cannot tell the
  # two apart. Here that does not matter, because the failure direction is a
  # REFUSAL — a process in such a directory is simply never claimed as ours, and
  # nothing is signalled on the strength of it.
  #
  # The repo-root `scripts/orphan-process-reaper.sh` (a developer-box tool, not
  # shipped to customers, so this path may not exist in your checkout) asks a
  # DIFFERENT question about the same
  # link — "is this inode unlinked?" — and answers it with `stat -Lc '%h'`
  # rather than with the suffix, because for that question the failure direction
  # is a KILL. The two predicates are meant to diverge; unifying them would move
  # this file's refusal onto a test built for the opposite consequence.
  [[ "$cwd" == *' (deleted)' ]] && return 1
  cwd=$(_proc_canon "$cwd")
  for n in ${_PROC_NESTED[@]+"${_PROC_NESTED[@]}"}; do
    [[ "$cwd" == "$n" || "$cwd" == "$n"/* ]] && return 1
  done
  # The trailing `/` is the whole prefix boundary: without it a sibling
  # worktree named `<ROOT>-two` is selected as ours.
  if [[ "$cwd" == "$root" || "$cwd" == "$root"/* ]]; then
    _PROC_OWNS_CWD="$cwd"
    return 0
  fi
  return 1
}

# A string rendered safe to print.
#
# `tr -c '[:print:]'`, not a hand-picked list. The first revision mapped only
# \n \t \r, which is the shape that looks thorough and is not: measured, ESC,
# BEL, backspace, VT and DEL all survived it. A directory can legally be named
# $'\033[2K\033[1Aoverwritten', and printing that erases the line above it in
# the operator's terminal — audit forgery in the tool whose output is the only
# evidence of what it did. LC_ALL=C so the class is byte-wise; the cost is that
# non-ASCII path bytes are masked too, which is the right trade here.
# `printf | tr`, NOT a herestring: `<<<` appends a newline, which is itself
# non-printing and so became a spurious trailing `?` on every path.
_proc_sanitize() { printf '%s' "$1" | LC_ALL=C tr -c '[:print:]' '?'; }

# The cwd of a pid, re-read and sanitized, for DISPLAY only.
_proc_show_cwd() {
  local pid="$1" cwd
  cwd=$(readlink "$PROC_SH_ROOT/$pid/cwd" 2>/dev/null) || cwd=""
  [[ -n "$cwd" ]] || { printf '<unreadable>'; return 0; }
  _proc_sanitize "$cwd"
}

# --- Matching --------------------------------------------------------------

# Does this /proc/<pid> match PATTERN, by ARGV POSITION rather than by substring
# anywhere in the joined command line (cq-assert-anchor-not-bare-token applied
# to process matching)?
#
# A substring over the joined cmdline matches any process that merely MENTIONS
# the target — including `grep -rn test-all.sh scripts/`, so `kill_mine
# test-all.sh` would kill the operator's own grep.
_proc_is_match() {
  local d="$1" pat="$2"
  [[ -r "$d/cmdline" ]] || return 1

  # Portable NUL-separated argv read. NOT `mapfile -d ''` — see PORTABILITY.
  #
  # The `|| [[ -n "$arg" ]]` is load-bearing: `read` returns non-zero at EOF
  # when the final field has no delimiter, so without it the last argv element
  # is silently DISCARDED. Processes that rewrite argv in place (Perl `$0=`,
  # Python setproctitle, several daemons) routinely leave the trailing NUL off,
  # and measured, such a process was invisible to both verbs — a silent
  # `killed=0`, which is the failure this construct was chosen to avoid.
  local -a argv=()
  local arg
  while IFS= read -r -d '' arg || [[ -n "$arg" ]]; do
    argv+=("$arg")
  done < "$d/cmdline"
  (( ${#argv[@]} > 0 )) || return 1

  # Step over leading wrapper commands AND their own arguments, so
  # `timeout 600 bash suite.sh` is not invisible.
  #
  # A PREVIOUS REVISION GOT THIS WRONG IN THE DANGEROUS DIRECTION and it is
  # recorded here because the failure is subtle: it tolerated arbitrary tokens
  # after any wrapper, which degenerated the whole rule into a bare basename
  # match over every argv element. Measured — `timeout 600 grep -rn test-all.sh
  # scripts/` classified as OURS, so `kill_mine test-all.sh` would have killed
  # the operator's own grep from inside their own worktree, where the cwd test
  # cannot save them. That is exactly the harm the argv-position rule exists to
  # prevent, reintroduced by the fix for wrapper invisibility.
  #
  # So the wrapper walk consumes only what a wrapper can plausibly take —
  # options, VAR=value assignments, bare numeric durations — and then the STRICT
  # rule is re-applied to whatever it lands on. Anything unrecognized ends the
  # walk rather than being skipped: an unmatched run is invisible (fail closed),
  # while a wrongly-matched one is a kill.
  local i=0 b
  while (( i < ${#argv[@]} )); do
    b="${argv[i]##*/}"
    case " $_PROC_WRAPPERS " in
      *" $b "*)
        i=$(( i + 1 ))
        while (( i < ${#argv[@]} )); do
          case "${argv[i]}" in
            -* | *=* | [0-9]*) i=$(( i + 1 )) ;;
            *) break ;;
          esac
        done
        continue
        ;;
    esac
    break
  done
  (( i < ${#argv[@]} )) || return 1

  # The effective command. STRICT from here: it is the target itself, or a
  # shell whose later arguments may name the target. Never an arbitrary command
  # that merely mentions the pattern somewhere in its argv.
  b="${argv[i]##*/}"
  [[ "$b" == "$pat" ]] && return 0
  case " $_PROC_SHELLS " in
    *" $b "*) ;;
    *) return 1 ;;
  esac

  local tok j
  for (( j = i + 1; j < ${#argv[@]}; j++ )); do
    tok="${argv[j]}"
    [[ "$tok" == *[[:space:]]* ]] && continue
    [[ "${tok##*/}" == "$pat" ]] && return 0
  done
  return 1
}

# --- The single walk -------------------------------------------------------
#
# ONE walk, shared by both verbs, so there is exactly one place where a pid can
# be classified. Emits `<class><TAB><pid>` where class is one of the literals
# below and pid is numeric — NO PATHS (see the header). `total` carries a count
# rather than a pid.
_proc_scan() {
  local pat="$1" root="$2"
  local excluded self_pgrp d pid pgrp scanned=0

  excluded=" $(_proc_self_and_ancestors)"

  # Own process GROUP. The command-substitution subshells and `&`-backgrounded
  # forks of THIS very invocation share its pgid but are NOT in the ancestor
  # chain, so ancestry alone lets proc.sh select a transient fork of itself. A
  # genuinely separate session has a DIFFERENT pgid, so pgid is the exact
  # discriminator.
  self_pgrp=$(_proc_pgrp "$PROC_SH_ROOT/$PROC_SH_SELF_PID/stat" 2>/dev/null) || self_pgrp=""
  [[ "$self_pgrp" =~ ^[0-9]+$ ]] || self_pgrp=""

  for d in "$PROC_SH_ROOT"/[0-9]*; do
    [[ -d "$d" ]] || continue
    pid="${d##*/}"
    # The glob only guarantees a LEADING digit: `12abc` and `0` both match it,
    # and `kill -TERM 0` signals the caller's whole process group. Validated
    # here so no non-pid can reach the signal site.
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || continue
    scanned=$(( scanned + 1 ))

    [[ "$excluded" == *" $pid "* ]] && continue
    _proc_is_match "$d" "$pat" || continue

    pgrp=$(_proc_pgrp "$d/stat") || pgrp=""
    if [[ -n "$self_pgrp" ]] && [[ "$pgrp" == "$self_pgrp" ]]; then
      printf 'skip\t%s\n' "$pid"
      continue
    fi

    if _proc_owns "$pid" "$root"; then
      printf 'signal\t%s\n' "$pid"
    else
      printf 'refuse\t%s\n' "$pid"
    fi
  done

  printf 'total\t%s\n' "$scanned"
}

# Reject a pattern that can never match, loudly. Both comparisons are against a
# BASENAME, so a pattern containing `/` matches nothing — and would print
# `killed=0`, which reads as "nothing to kill" and sends the operator back to
# pkill.
_proc_check_pattern() {
  local pat="$1" verb="$2"
  if [[ -z "$pat" ]]; then
    echo "usage: $verb <pattern> [signal]" >&2
    return 2
  fi
  if [[ "$pat" == */* ]]; then
    echo "proc.sh: pattern '$pat' contains '/' and can never match — matching is on the BASENAME." >&2
    echo "proc.sh: use '${pat##*/}' instead." >&2
    return 2
  fi
  return 0
}

# --- Verbs -----------------------------------------------------------------

# list_runs <pattern>
#
# Enumerate every matching process, each labelled with the worktree that owns
# it. Signals nothing — this is the dry run, and the thing to reach for first.
list_runs() {
  local pat="${1:-}"
  _proc_check_pattern "$pat" list_runs || return $?
  local root
  root=$(_proc_worktree) || return 1
  _proc_load_nested "$root"

  local cls pid n=0
  while IFS=$'\t' read -r cls pid; do
    case "$cls" in
      signal) printf '%s\tmine\t%s\n' "$pid" "$(_proc_show_cwd "$pid")"; n=$(( n + 1 )) ;;
      refuse) printf '%s\tforeign\t%s\n' "$pid" "$(_proc_show_cwd "$pid")"; n=$(( n + 1 )) ;;
      skip) printf '%s\tskipped\tsame-process-group\n' "$pid"; n=$(( n + 1 )) ;;
      *) ;;
    esac
  done < <(_proc_scan "$pat" "$root")

  (( n > 0 )) || echo "no processes match '$pat'"
  return 0
}

# kill_mine <pattern> [signal]
#
# Signal ONLY the matching processes whose own cwd is inside the current
# worktree. Everything else is refused AND printed — a refusal you cannot see
# is indistinguishable from a match that never happened.
#
# Individual pids are signalled, never a process group: `kill -TERM 0` can
# reach the parent. Default TERM; the caller may pass another signal, and no
# escalation to KILL happens on its own.
kill_mine() {
  local pat="${1:-}" sig="${2:-TERM}"
  _proc_check_pattern "$pat" kill_mine || return $?
  local root
  root=$(_proc_worktree) || return 1
  _proc_load_nested "$root"

  # Fail SAFE, not open: anything other than an explicit off value means dry
  # run. The previous form matched only the literal `1`, so PROC_SH_DRY_RUN=true
  # performed a REAL kill on an operator who had asked for a rehearsal.
  local dry=0
  case "${PROC_SH_DRY_RUN:-0}" in
    0 | false | "") dry=0 ;;
    *) dry=1 ;;
  esac

  local killed=0 would=0 refused=0 late=0 skipped=0 failed=0 scanned=0
  local cls pid rc shown
  while IFS=$'\t' read -r cls pid; do
    case "$cls" in
      signal)
        # Re-verify ownership at the signal site. The walk's verdict is about a
        # pid at scan time; a pid can die and be recycled onto an unrelated
        # process before this line runs. One extra readlink narrows that window.
        if ! _proc_owns "$pid" "$root"; then
          late=$(( late + 1 ))
          printf 'refused   pid=%s reason=%s\n' "$pid" "ownership-changed-before-signal"
          continue
        fi
        # Capture the display path from the SAME check that authorized the
        # signal, BEFORE sending it. Re-reading afterwards loses the path
        # exactly when the kill succeeds — the process is gone, readlink fails,
        # and the record degrades to `<unreadable>`. Measured: a live run
        # printed `signalled pid=954752 cwd=<unreadable>` while the dry run
        # printed the real path, so the rehearsal showed what the real run hid.
        shown=$(_proc_sanitize "$_PROC_OWNS_CWD")
        if (( dry )); then
          would=$(( would + 1 ))
          printf 'would-signal pid=%s cwd=%s\n' "$pid" "$shown"
          continue
        fi
        rc=0
        kill -"$sig" "$pid" 2>/dev/null || rc=$?
        if (( rc == 0 )); then
          killed=$(( killed + 1 ))
          printf 'signalled pid=%s cwd=%s\n' "$pid" "$shown"
        else
          # A swallowed failure counted as a kill is a lie in the direction
          # that matters: the operator reads killed=1 and stops looking.
          failed=$(( failed + 1 ))
          printf 'FAILED    pid=%s rc=%s (signal not delivered)\n' "$pid" "$rc"
        fi
        ;;
      refuse)
        refused=$(( refused + 1 ))
        printf 'refused   pid=%s cwd=%s\n' "$pid" "$(_proc_show_cwd "$pid")"
        ;;
      skip)
        skipped=$(( skipped + 1 ))
        printf 'refused   pid=%s reason=%s\n' "$pid" "same-process-group"
        ;;
      total) scanned="$pid" ;;
      *) ;;
    esac
  done < <(_proc_scan "$pat" "$root")

  # Printed on EVERY invocation. `skipped_same_pgroup` is counted SEPARATELY
  # because the pgid exclusion can legitimately suppress a real target — under
  # a non-interactive shell without job control, a run launched with `&` from
  # the same shell shares this pgid. A bare `killed=0` would then read as
  # "nothing to kill" and send the operator straight back to pkill, which is
  # the precise failure this file exists to prevent, one level down. The
  # documented workaround is to launch under `setsid`, which creates a new pgid.
  # `mode` is on the line because output alone could not previously distinguish
  # a rehearsal from a real kill.
  # `would_signal` is separate from `killed` so a rehearsal never reports kills
  # it did not perform, and `late_refused` is separate from `refused` so the
  # signal-site re-check is visible as its own enforcement point rather than
  # being folded into the walk's verdict.
  printf 'killed=%s would_signal=%s failed=%s refused=%s late_refused=%s skipped_same_pgroup=%s scanned=%s mode=%s\n' \
    "$killed" "$would" "$failed" "$refused" "$late" "$skipped" "$scanned" \
    "$( (( dry )) && printf 'dry-run' || printf 'live' )"
  return 0
}

# Allow `bash proc.sh <fn> <args>` as a CLI shim (used by SKILL.md pointers and
# ad-hoc operator invocations), mirroring session-state.sh's dispatch.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"
  shift || true
  case "$fn" in
    list_runs | kill_mine)
      "$fn" "$@"
      ;;
    "")
      echo "usage: $0 {list_runs|kill_mine} <pattern> [signal]" >&2
      exit 2
      ;;
    *)
      echo "proc.sh: unknown function: $fn" >&2
      exit 2
      ;;
  esac
fi
