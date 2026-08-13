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
# SELECTION CRITERION (why this one command is encoded and most are not). All
# three must hold: (1) it has recurred across sessions; (2) getting it wrong is
# silent or destructive; (3) the correct form is counterintuitive. Most fumbled
# incantations hit at most one and should stay prose.
#
# WHY BRACKET-SAFETY IS A CATEGORY ERROR HERE. `[t]est-all` is a pgrep/`ps|grep`
# idiom: it stops the MATCHER from matching itself. A /proc walk has no pattern
# for a bracket to fool, and the invoker's own command line still contains the
# literal pattern either way. The property ("never reports the process
# performing the enumeration") is bought by the three exclusions below instead.
#
# HIDDEN ASSUMPTION, stated because the design depends on it: proc.sh's own
# command line MATCHES proc.sh's own predicate. `bash …/proc.sh kill_mine
# test-all.sh` carries `test-all.sh` as a whitespace-free later token under a
# shell argv[0]. That is the entire reason the process-group exclusion is
# required — proc.sh's command-substitution forks match the predicate and are
# NOT ancestors. Do not remove it on the grounds that ancestry already covers
# the invoking shell.
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

# Guard against double-source within a single shell.
if [[ "${_SOLEUR_PROC_LOADED:-}" == "1" ]]; then
  return 0 2>/dev/null || true
fi
_SOLEUR_PROC_LOADED=1

# Test seams. Namespace-prefixed because scripts/tmpfs-guard.sh already binds a
# bare PROC_ROOT and this file is sourceable.
PROC_SH_ROOT="${PROC_SH_ROOT:-/proc}"
PROC_SH_SELF_PID="${PROC_SH_SELF_PID:-$$}"

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
# looks correct; the positive control in the suite is what catches that.
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
  if [[ -n "${PROC_SH_WORKTREE:-}" ]]; then
    _proc_canon "$PROC_SH_WORKTREE"
    return 0
  fi
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || root=""
  if [[ -z "$root" ]]; then
    echo "proc.sh: cannot resolve the current worktree (not inside a git repository and PROC_SH_WORKTREE is unset)." >&2
    echo "proc.sh: refusing to scan — without an ownership boundary this cannot tell your processes from another session's." >&2
    return 1
  fi
  _proc_canon "$root"
}

# --- Matching --------------------------------------------------------------

# Does this /proc/<pid> match PATTERN, by ARGV POSITION rather than by substring
# anywhere in the joined command line (cq-assert-anchor-not-bare-token applied
# to process matching)? A process matches only when either:
#   (a) argv[0]'s basename IS the pattern (direct exec), or
#   (b) argv[0] is a shell AND some later argument is a whitespace-free path
#       whose basename is the pattern.
#
# Every weaker rule was tried and rejected against real command lines: a
# substring over the joined cmdline matches any process that merely MENTIONS
# the target — including `grep -rn test-all.sh scripts/`, so `kill_mine
# test-all.sh` would kill the operator's own grep.
_proc_is_match() {
  local d="$1" pat="$2"
  [[ -r "$d/cmdline" ]] || return 1
  local -a argv=()
  mapfile -t -d '' argv < "$d/cmdline" 2>/dev/null || true
  (( ${#argv[@]} > 0 )) || return 1

  local a0="${argv[0]##*/}"
  [[ "$a0" == "$pat" ]] && return 0
  case "$a0" in
    bash | sh | dash | zsh | ksh) ;;
    *) return 1 ;;
  esac

  local tok i
  for (( i = 1; i < ${#argv[@]}; i++ )); do
    tok="${argv[i]}"
    [[ "$tok" == *[[:space:]]* ]] && continue
    [[ "${tok##*/}" == "$pat" ]] && return 0
  done
  return 1
}

# --- The single walk -------------------------------------------------------
#
# ONE walk, shared by both verbs, so there is exactly one place where a pid can
# be classified. Emits tab-separated rows; every field is non-empty (refusal
# reasons are sentinelled) because tab is IFS-WHITESPACE, so a reader's
# `IFS=$'\t' read` would collapse runs and drop empty middle fields, shifting
# every later field one position left.
#
#   signal <TAB> <pid> <TAB> <cwd>      -- owned by this worktree
#   refuse <TAB> <pid> <TAB> <cwd>      -- owned by something else
#   skip   <TAB> <pid> <TAB> <reason>   -- excluded by our own guard
#   total  <TAB> <n>   <TAB> -          -- pids examined
_proc_scan() {
  local pat="$1" root="$2"
  local excluded self_pgrp d pid pgrp cwd scanned=0

  excluded=" $(_proc_self_and_ancestors)"

  # Own process GROUP. The command-substitution subshells and `&`-backgrounded
  # forks of THIS very invocation share its pgid but are NOT in the ancestor
  # chain, so ancestry alone lets proc.sh select a transient fork of itself. A
  # genuinely separate session — another worktree, another terminal — has a
  # DIFFERENT pgid, so pgid is the exact discriminator. Empty when self has no
  # readable stat (the synthetic-self test path), which correctly disables it.
  self_pgrp=$(_proc_pgrp "$PROC_SH_ROOT/$PROC_SH_SELF_PID/stat" 2>/dev/null) || self_pgrp=""
  [[ "$self_pgrp" =~ ^[0-9]+$ ]] || self_pgrp=""

  for d in "$PROC_SH_ROOT"/[0-9]*; do
    [[ -d "$d" ]] || continue
    pid="${d##*/}"
    scanned=$(( scanned + 1 ))

    [[ "$excluded" == *" $pid "* ]] && continue
    _proc_is_match "$d" "$pat" || continue

    pgrp=$(_proc_pgrp "$d/stat") || pgrp=""
    if [[ -n "$self_pgrp" ]] && [[ "$pgrp" == "$self_pgrp" ]]; then
      printf 'skip\t%s\t%s\n' "$pid" "same-process-group"
      continue
    fi

    cwd=$(readlink "$d/cwd" 2>/dev/null) || cwd="<unreadable>"
    [[ -n "$cwd" ]] || cwd="<unreadable>"
    if [[ "$cwd" != "<unreadable>" ]]; then
      cwd=$(_proc_canon "$cwd")
    fi

    # The trailing `/` is the whole prefix boundary: without it a sibling
    # worktree named `<ROOT>-two` is selected as ours. Highest-risk
    # one-character defect in this file.
    if [[ "$cwd" == "$root" || "$cwd" == "$root"/* ]]; then
      printf 'signal\t%s\t%s\n' "$pid" "$cwd"
    else
      printf 'refuse\t%s\t%s\n' "$pid" "$cwd"
    fi
  done

  printf 'total\t%s\t-\n' "$scanned"
}

# --- Verbs -----------------------------------------------------------------

# list_runs <pattern>
#
# Enumerate every matching process, each labelled with the worktree that owns
# it. Signals nothing — this is the dry run, and the thing to reach for first.
list_runs() {
  local pat="${1:-}"
  if [[ -z "$pat" ]]; then
    echo "usage: list_runs <pattern>" >&2
    return 2
  fi
  local root
  root=$(_proc_worktree) || return 1

  local cls pid info n=0
  while IFS=$'\t' read -r cls pid info; do
    case "$cls" in
      signal) printf '%s\tmine\t%s\n' "$pid" "$info"; n=$(( n + 1 )) ;;
      refuse) printf '%s\tforeign\t%s\n' "$pid" "$info"; n=$(( n + 1 )) ;;
      skip) printf '%s\tskipped\t%s\n' "$pid" "$info"; n=$(( n + 1 )) ;;
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
# reach the parent. Default TERM, no escalation to KILL.
kill_mine() {
  local pat="${1:-}" sig="${2:-TERM}"
  if [[ -z "$pat" ]]; then
    echo "usage: kill_mine <pattern> [signal]" >&2
    return 2
  fi
  local root
  root=$(_proc_worktree) || return 1

  local killed=0 refused=0 skipped=0 scanned=0
  local cls pid info
  while IFS=$'\t' read -r cls pid info; do
    case "$cls" in
      signal)
        if [[ "${PROC_SH_DRY_RUN:-0}" == "1" ]]; then
          printf 'would-signal %s %s\n' "$pid" "$info" >> "${PROC_SH_DRY_RUN_LOG:-/dev/null}"
        else
          kill -"$sig" "$pid" 2>/dev/null || true
        fi
        killed=$(( killed + 1 ))
        printf 'signalled pid=%s cwd=%s\n' "$pid" "$info"
        ;;
      refuse)
        refused=$(( refused + 1 ))
        printf 'refused   pid=%s cwd=%s\n' "$pid" "$info"
        ;;
      skip)
        skipped=$(( skipped + 1 ))
        printf 'refused   pid=%s reason=%s\n' "$pid" "$info"
        ;;
      total) scanned="$pid" ;;
      *) ;;
    esac
  done < <(_proc_scan "$pat" "$root")

  # Printed on EVERY invocation, and skipped_same_pgroup is counted SEPARATELY
  # on purpose. The pgid exclusion can legitimately suppress a real target —
  # under a non-interactive shell without job control, a run launched with `&`
  # from the same shell shares this pgid. A bare `killed=0` would then read as
  # "nothing to kill" and send the operator straight back to pkill, which is
  # the precise failure this file exists to prevent, one level down. The
  # documented workaround is to launch under `setsid`, which creates a new pgid.
  printf 'killed=%s refused=%s skipped_same_pgroup=%s scanned=%s\n' \
    "$killed" "$refused" "$skipped" "$scanned"
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
