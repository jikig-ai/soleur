#!/usr/bin/env bash
# Incident-log root enumeration for scripts/rule-metrics-aggregate.sh.
#
# Source-only: defines two pure functions and runs nothing. Tests live in the
# sibling scripts/lib/incidents-roots.test.sh, which sources this file directly —
# that is the whole reason the logic is here rather than inline in the aggregator.
# The aggregator's one existing seam, INCIDENTS_REPO_ROOT, is defined as an
# EXCLUSIVE override ("the caller named the only root that may be read"), which is
# exactly what disables multi-root collection; exercising the enumeration through
# it would destroy the narrowing every existing fixture depends on.
#
# PROPERTY: the set of roots the aggregator reads contains each distinct on-disk
# directory exactly once, with the caller's first argument still first.
#
# Both halves are load-bearing:
#   - EXACTLY ONCE — `git worktree list` includes the MAIN worktree, which the
#     aggregator already adds separately via --git-common-dir. The two strings
#     differ; the inode does not. An un-deduped union cats one log twice, and
#     because the counts are a commutative reduce the inflation is invisible.
#   - FIRST STAYS FIRST — AGGREGATOR_ROTATE=1 truncates element 0 of the root
#     array. Sorting or prepending here would point rotation at a SIBLING
#     worktree's live log. Dedupe therefore preserves first-seen order and must
#     never sort.

# incidents_roots_from_porcelain
#   stdin : output of `git worktree list --porcelain`
#   stdout: one worktree path per line, in input order
#
# Keys on the `worktree ` line prefix rather than on whitespace: the porcelain
# stream also carries `HEAD <sha>`, `branch <ref>`, `bare` and `detached` lines,
# and a branch named e.g. refs/heads/worktree-ish must not be mistaken for a path.
incidents_roots_from_porcelain() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "worktree "*) printf '%s\n' "${line#worktree }" ;;
    esac
  done
  return 0
}

# _incidents_inode_key <dir>
#   stdout: "<device>:<inode>" for dir, or empty on failure.
#
# `-L` (dereference) is load-bearing and was a real defect caught by case 6 of the
# sibling suite. `stat` reports the SYMLINK's own inode by default, while
# `[[ -d ]]` follows the link — so an aliased path passes the existence check and
# then stats as a distinct identity, emitting the same directory twice. That is
# the exact double-count this module exists to prevent, so the two predicates must
# agree on what they are measuring.
#
# Two stat dialects: GNU (-c) and BSD (-f); both spell dereference `-L`. A
# directory whose mode is 000 still stats fine when its parent is searchable, so
# an unreadable sibling worktree yields a key here and is filtered later by the
# caller's own readability check — this function never aborts on one.
_incidents_inode_key() {
  local d="${1-}" key=""
  key=$(stat -L -c '%d:%i' -- "$d" 2>/dev/null) || key=""
  if [[ -z "$key" ]]; then
    key=$(stat -L -f '%d:%i' -- "$d" 2>/dev/null) || key=""
  fi
  printf '%s' "$key"
}

# incidents_dedupe_existing_dirs <dir>...
#   stdout: the existing directories among the arguments, each distinct inode
#           emitted once, in FIRST-SEEN order.
#
# Drops a path that does not exist, and drops one whose identity cannot be
# resolved (fail-closed for that entry rather than silently degrading the whole
# set to string keys, which would reintroduce the double-count this exists to
# prevent). Returns 0 even when every argument is dropped: the aggregator runs
# under `set -euo pipefail`, so a non-zero return here would abort the entire
# aggregation over one unreadable sibling worktree.
incidents_dedupe_existing_dirs() {
  local d key
  local -A _seen=()
  for d in "$@"; do
    [[ -n "$d" ]] || continue
    [[ -d "$d" ]] || continue
    key=$(_incidents_inode_key "$d")
    [[ -n "$key" ]] || continue
    [[ -n "${_seen[$key]+x}" ]] && continue
    _seen[$key]=1
    printf '%s\n' "$d"
  done
  return 0
}
