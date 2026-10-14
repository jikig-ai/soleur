#!/usr/bin/env bash
# SessionStart resolver shim — selects the NEWEST installed copy of
# memory-backstop.sh and execs it (#9239, ADR-261).
#
# WHAT PROBLEM. settings.json used to exec the hook file inside whichever
# checkout or worktree the session ran in, so a merged protection upgrade
# reached only sessions launched from a checkout containing it; a session
# resumed from a stale branch silently ran the stale hook (the 2026-09-29
# herdr pids.max crash ran exactly that shape). Plugin updates could not
# help: the plugin cache was not on the exec path.
#
# WHAT THIS DOES. Enumerates every installed copy of the hook — this
# checkout's, the managed copy under the user's data dir, and both plugin
# caches — orders them by the BACKSTOP_REVISION marker each file carries,
# syntax-checks the winner, self-publishes a strictly-newer winner to the
# managed path BEFORE exec, then `exec bash`es it. One fresh session upgrades
# the whole host; a plugin-less checkout keeps working because its own copy
# remains a candidate.
#
# TRUST POSTURE. Every candidate is a same-uid-writable file — the identical
# trust class to the checkout copy the status quo ran. A candidate's revision
# is learned by GREP ONLY: the shim never sources, evals, or runs a candidate
# to ask its version (ADR-156's untrusted-input posture applied to hook
# bodies). The winner is `bash -n` checked before exec; a candidate failing
# it demotes to the next.
#
# NEVER BLOCKS. exit 0 on every path, including total failure (no candidate
# execs): a `systemMessage` JSON line is emitted and the session proceeds
# unprotected rather than never starting. Deliberately no `set -e`.
#
# TIES. Equal revisions resolve to the FIRST candidate in precedence order —
# the checkout copy — so a local uncommitted edit wins over an installed copy
# of the same revision (dev flow preserved; the revision-bump guard keeps
# equal-revision divergence from surviving merge).
#
# THE STABLE CONTRACT. This shim is the one component that cannot
# self-upgrade — a stale checkout keeps its stale resolver — so the contract
# (candidate set, revision ordering, publish, exec) is deliberately minimal.
# RESOLVER_REVISION orders resolver copies for humans; nothing consumes it.
#
# PROBE. `--print-resolution` prints `resolved=<path> revision=<n>` and exits
# read-only — no publish, no exec.
#
# PORTABILITY. Runs on every host a checkout does, incl. macOS: grep -oE,
# mkdir -p, install -m, mv, and a command -v-guarded flock only. No timeout,
# sed -i, readlink -f, stat -c, namerefs, or assoc arrays (bash 3.2 safe).

# shellcheck disable=SC2034  # consumed by grep, not by shell expansion
readonly RESOLVER_REVISION=2

# ------------------------------------------------------------------ helpers

# The managed-copy root: ${XDG_DATA_HOME:-$HOME/.local/share}. Absent-HOME
# safe — returns 1 rather than inventing a relative root.
resolver_data_home() {
  # Absolute-only: a relative XDG_DATA_HOME would make the managed candidate
  # resolve against the caller's CWD — admitting a stray same-named file into
  # bash -n/exec (PR #9241 review).
  if [[ -n "${XDG_DATA_HOME:-}" ]]; then
    case "$XDG_DATA_HOME" in /*) ;; *) return 1 ;; esac
    printf '%s\n' "$XDG_DATA_HOME"
  elif [[ -n "${HOME:-}" ]]; then
    printf '%s\n' "$HOME/.local/share"
  else
    return 1
  fi
}

# This file's own directory, canonicalized so a relative invocation still
# yields absolute candidates (cd -P / pwd -P precedent: _repo_root).
resolver_shim_dir() {
  local d
  d=$(dirname "${BASH_SOURCE[0]}")
  (cd -P "$d" 2>/dev/null && pwd -P) || printf '%s\n' "$d"
}

# Revision of ONE candidate, learned by grep — never by running it. Missing
# or non-numeric marker, unreadable or non-regular file: revision 0. The
# pattern is LINE-ANCHORED so a `# BACKSTOP_REVISION=99` comment above the
# real declaration cannot inflate a candidate's revision (PR #9241 review).
candidate_revision() {
  local p="${1:-}" m=""
  if [[ -n "$p" && -f "$p" && -r "$p" ]]; then
    m=$(grep -m1 -oE '^[[:space:]]*(readonly[[:space:]]+)?BACKSTOP_REVISION=[0-9]+' "$p" 2>/dev/null || true)
    m="${m#*BACKSTOP_REVISION=}"
  fi
  [[ "$m" =~ ^[0-9]+$ ]] || m=0
  printf '%s' "$m"
}

# Candidates in precedence order: the checkout copy, the managed copy, then
# both plugin caches. Cache lines are GLOBS — left unquoted so a non-match
# expands to itself and is dropped by the -f test (no nullglob dependency).
enumerate_candidates() {
  printf '%s\n' "$(resolver_shim_dir)/memory-backstop.sh"
  local dh p
  if dh=$(resolver_data_home); then
    # The managed copy is exec'd, so its DIRECTORY must be trustworthy: a
    # foreign-owned or foreign-writable dir under a steerable XDG_DATA_HOME
    # would let another uid plant the file every session then execs — the
    # only path out of the same-uid trust model. Ours gets group/other-write
    # stripped (idempotent); an absent dir can't hold a foreign file, so it
    # stays a candidate anyway (-f drops it until it exists).
    if managed_dir_trusted "$dh"; then
      printf '%s\n' "$dh/soleur/hooks/memory-backstop.sh"
    fi
  fi
  if [[ -n "${HOME:-}" ]]; then
    # The glob stays shape-based, but a candidate must live under a `soleur`
    # component INSIDE the cache — the caches are plugin-namespaced
    # (<marketplace>/<plugin>/<version>), and any plugin COULD ship a namesake
    # file (PR #9241 review). The check is applied to the path AFTER the
    # cache root: a full-path match would admit every candidate whenever an
    # ancestor dir happens to contain "soleur" (e.g. a `soleur-run.*` tmpdir).
    local crest drest
    for p in "$HOME"/.claude/plugins/cache/*/*/*/hooks/memory-backstop.sh; do
      [[ -f "$p" ]] || continue
      crest="${p#"$HOME"/.claude/plugins/cache/}"
      case "$crest" in *soleur*/*) printf '%s\n' "$p" ;; esac
    done
    for p in "$HOME"/.local/share/devin/cli/plugins/cache/*/*/hooks/memory-backstop.sh; do
      [[ -f "$p" ]] || continue
      drest="${p#"$HOME"/.local/share/devin/cli/plugins/cache/}"
      case "$drest" in *soleur*/*) printf '%s\n' "$p" ;; esac
    done
  fi
}

# The managed path's directory trust invariant, used by both enumeration
# (exec-side) and publish (write-side): refuse when a directory we rely on is
# owned by another uid; chmod 700 the ones that are ours so a loose umask or
# a steered data home can't admit a foreign writer. A failed chmod means the
# invariant could not be established → untrusted. Returns 0 when absent —
# nothing foreign can sit in a dir that does not exist.
managed_dir_trusted() {  # <data-home>
  local s="$1/soleur" h="$1/soleur/hooks"
  if [[ -d "$s" ]]; then
    # go-w, not 700: tighten away group/other writability WITHOUT granting
    # owner write — a deliberately read-only dir (operator freeze) must stay
    # read-only; publish just skips, exec of an existing copy is unaffected.
    [[ -O "$s" ]] || return 1
    chmod go-w "$s" 2>/dev/null || return 1
    if [[ -d "$h" ]]; then
      [[ -O "$h" ]] || return 1
      chmod go-w "$h" 2>/dev/null || return 1
    fi
  fi
  return 0
}

# Globals filled by collect_candidates: parallel arrays CAND_PATH / CAND_REV /
# CAND_ALIVE (1 = still selectable; a bash -n failure flips it to 0).
collect_candidates() {
  CAND_PATH=()
  CAND_REV=()
  CAND_ALIVE=()
  local p
  while IFS= read -r p; do
    [[ -f "$p" && -r "$p" ]] || continue
    CAND_PATH+=("$p")
    CAND_REV+=("$(candidate_revision "$p")")
    CAND_ALIVE+=(1)
  done < <(enumerate_candidates)
}

# Index of the highest-revision alive candidate in WINNER_IDX. Strict `>`
# keeps the FIRST in precedence order on a tie — checkout wins equal
# revisions. Returns 1 when nothing alive remains.
select_winner() {
  local i best=-1
  # `${!arr[@]}` on an EMPTY array trips `set -u` on bash <=4.3 (macOS 3.2) —
  # the zero-candidate path must still reach the never-blocks exit. The count
  # expansion is empty-safe on every supported bash.
  for (( i = 0; i < ${#CAND_PATH[@]}; i++ )); do
    (( CAND_ALIVE[i] == 0 )) && continue
    if (( best < 0 )) || (( CAND_REV[i] > CAND_REV[best] )); then
      best=$i
    fi
  done
  (( best < 0 )) && return 1
  WINNER_IDX=$best
  return 0
}

# install <src> to <dest>.tmp.$$ then mv — the tmp sibling is per-PID, so a
# half-written managed copy never exists and a failed step leaves the old
# copy plus a removable tmp. <dest> is a positional on purpose: it is always
# caller-derived fixture/managed state, never a literal this file invents.
publish_install() {  # <src> <dest> <mode>
  install -m "$3" "$1" "$2.tmp.$$" 2>/dev/null && mv "$2.tmp.$$" "$2" 2>/dev/null
  local rc=$?
  rm -f "$2.tmp.$$" 2>/dev/null
  return "$rc"
}

# Carry the hook's opportunistic siblings: it sources $(dirname BASH_SOURCE)/
# lib/<name>.sh when present, so a managed copy without them silently loses
# the lib behaviours (log rotation today). Glob all *.sh so a FUTURE sourced
# sibling rides along by existing — a hardcoded name would strand any new
# lib file on checkout copies only (PR #9241 review). Best-effort; absence
# is fine. Non-glob expansion is dropped by the -f test, as in enumeration.
publish_carry_lib() {  # <winner> <managed-hooks-dir>
  local src
  for src in "$(dirname "$1")"/lib/*.sh; do
    [[ -f "$src" ]] || continue
    publish_install "$src" "$2/lib/$(basename "$src")" 0644 || true
  done
  return 0
}

# The revision a managed copy is worth for PUBLISH purposes. A managed file
# that fails `bash -n` can never have been exec'd and vetoes nothing — treat
# it as 0 so a broken managed copy cannot starve every future publish (the
# selection demotion loop already refuses to exec it). PR #9241 review.
publish_managed_rev() {  # <managed-path>
  local r; r=$(candidate_revision "$1")
  if [[ -f "$1" ]] && ! bash -n "$1" 2>/dev/null; then r=0; fi
  printf '%s' "$r"
}

# Self-publish: when the winner is not the managed copy and is strictly
# newer, install it at the managed path. Serialized under flock on
# .publish.lock where flock exists, with the managed revision re-read INSIDE
# the lock (two SessionStarts can both pass the pre-check — TOCTOU). Without
# flock (macOS) the same re-check runs immediately before mv; the residual
# race self-heals because a strictly-newer loser re-publishes next run.
# A publish failure NEVER blocks exec — every path returns 0.
publish_candidate() {  # <winner-path> <winner-rev>
  local winner="$1" wrev="$2" dh
  dh=$(resolver_data_home) || return 0
  local dir="$dh/soleur/hooks"
  local managed="$dir/memory-backstop.sh"
  [[ "$winner" == "$managed" ]] && return 0
  case "$dir" in /*) ;; *) return 0 ;; esac
  local mrev; mrev=$(publish_managed_rev "$managed")
  (( wrev > mrev )) || return 0
  managed_dir_trusted "$dh" || return 0
  mkdir -p "$dir/lib" 2>/dev/null || return 0
  # -w 2, not a human-scale wait: publish is opportunistic (the winner execs
  # regardless and the next session retries), so a wedged lock holder must not
  # stall SessionStart.
  local lock="$dh/soleur/.publish.lock" cur
  if command -v flock >/dev/null 2>&1; then
    (
      exec 9>>"$lock" 2>/dev/null || exit 0
      flock -w 2 -x 9 2>/dev/null || exit 0
      cur=$(publish_managed_rev "$managed")
      (( wrev > cur )) || exit 0
      publish_install "$winner" "$managed" 0755 && publish_carry_lib "$winner" "$dir"
    ) || true
  else
    cur=$(publish_managed_rev "$managed")
    (( wrev > cur )) || return 0
    publish_install "$winner" "$managed" 0755 && publish_carry_lib "$winner" "$dir"
  fi
  return 0
}

# Operator-visible channel on total failure — the same systemMessage shape
# emit_message uses in the hook. printf fallback when jq is absent: the hook
# itself declines no_jq, but the resolver cannot decline — it must still say
# why no protection ran. The message is resolver-owned literal text, so the
# fallback only strips the two characters that would break the JSON line.
resolver_emit() {
  local msg="$1" clean
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg m "$msg" '{systemMessage:$m}' 2>/dev/null && return 0
  fi
  # The fallback strips \ and " (JSON quoting) and control chars (a newline
  # would tear the single-line record in two — same contract as the hook's
  # rfrom_sanitized fallback).
  clean="${msg//\\/}"; clean="${clean//\"/}"; clean="${clean//[[:cntrl:]]/}"
  printf '{"systemMessage":"%s"}\n' "$clean"
}

# ------------------------------------------------------------------ main
main() {
  # Deliberately NOT -e (never-blocks contract). `set` options are process-
  # global once executed — the containment is that main ends in exec/exit 0
  # and nothing runs after it, so callers/sourcers inherit nothing.
  set -uo pipefail

  local print_only=0
  [[ "${1:-}" == "--print-resolution" ]] && print_only=1

  collect_candidates

  local winner="" wrev=0
  while select_winner; do
    if bash -n "${CAND_PATH[WINNER_IDX]}" 2>/dev/null; then
      winner="${CAND_PATH[WINNER_IDX]}"
      wrev="${CAND_REV[WINNER_IDX]}"
      break
    fi
    CAND_ALIVE[WINNER_IDX]=0
  done

  if [[ -z "$winner" ]]; then
    resolver_emit "Soleur memory backstop resolver: no runnable hook copy could be selected (every candidate was missing, unreadable, or failed a syntax check). This session is UNPROTECTED — memory and task caps are NOT in effect."
    exit 0
  fi

  if (( print_only == 1 )); then
    # One line, fixed shape — the probe also exposes the publish channel's
    # state so a silently-skipped publish is directly visible (not just
    # inferable from ledger attribution gaps).
    local mdh managed_desc="managed=- managed_rev=-"
    if mdh=$(resolver_data_home); then
      managed_desc="managed=$mdh/soleur/hooks/memory-backstop.sh managed_rev=$(publish_managed_rev "$mdh/soleur/hooks/memory-backstop.sh")"
    fi
    printf 'resolved=%s revision=%s %s\n' "$winner" "$wrev" "$managed_desc"
    exit 0
  fi

  publish_candidate "$winner" "$wrev" || true

  # bash-prefixed exec: immune to a missing mode bit on the winner (#7151).
  # RESOLVED_FROM feeds the ledger's resolved_from field; RESOLVED_REVISION is
  # exported for probe/debug symmetry only — the ledger records the hook's own
  # BACKSTOP_REVISION, which equals this post-exec anyway.
  export SOLEUR_BACKSTOP_RESOLVED_FROM="$winner"
  export SOLEUR_BACKSTOP_RESOLVED_REVISION="$wrev"
  # `|| exit 0`: a winner deleted between bash -n and exec (plugin-cache GC)
  # fails exec non-zero, and a non-zero exit makes the harness discard even
  # the failure message — the residual race ends clean instead.
  exec bash "$winner" "$@" || exit 0
}

# `if`, not `[[ ... ]] && main`: as the file's LAST command the `&&` form
# returns 1 when the condition is false, so `source` itself would report
# failure to the test harness even though sourcing succeeded.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
