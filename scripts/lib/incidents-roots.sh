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
#   stdin : output of `git worktree list --porcelain -z` (NUL-terminated records)
#   stdout: one worktree path per record, NUL-terminated, in input order
#
# NUL framing is load-bearing, not a nicety. Without `-z` git prints the path RAW,
# and a worktree whose path contains a newline followed by `worktree /any/dir`
# injects an arbitrary root into every consumer (reproduced at review, git 2.55:
# the forged path was enumerated as a worktree). `-z` is the interface git
# provides for exactly this; under it a path with an embedded newline round-trips
# intact. Consumers MUST read with `read -r -d ''`.
#
# Keys on the `worktree ` record prefix rather than on whitespace: the stream also
# carries `HEAD <sha>`, `branch <ref>`, `bare` and `detached` records, and a branch
# named e.g. refs/heads/worktree-ish must not be mistaken for a path.
incidents_roots_from_porcelain() {
  local rec
  while IFS= read -r -d '' rec || [[ -n "$rec" ]]; do
    case "$rec" in
      "worktree "*) printf '%s\0' "${rec#worktree }" ;;
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
    # NUL-terminated, like the porcelain stage above it. Review found the
    # newline framing defended at stage 1 was re-split here: a root named
    # ".../x\n/FORGED/.claude" passed dedupe and the consumer's newline reader
    # yielded two roots, the second forged. Consumers MUST read with -d ''.
    printf '%s\0' "$d"
  done
  return 0
}

# incidents_enumerate_log_roots <repo-root> [<extra-root>...]
#   stdout: NUL-terminated, inode-deduped list of `<worktree>/.claude` dirs to
#           read, FIRST ARGUMENT'S .claude FIRST (rotation pins element 0).
#
# The one composition both consumers run: repo root, any caller-supplied extra
# roots (the aggregator passes the shared checkout beside --git-common-dir),
# then every registered worktree, deduped by inode with first-seen order kept.
# Extracted because the two hand copies had already diverged once -- the
# aggregator gained an unreadable-root sentinel the classifier's copy lacked.
incidents_enumerate_log_roots() {
  local repo_root="${1-}" extra wt
  [[ -n "$repo_root" ]] || return 1
  shift
  local -a cands=("$repo_root/.claude")
  for extra in "$@"; do [[ -n "$extra" ]] && cands+=("$extra/.claude"); done
  while IFS= read -r -d '' wt; do
    [[ -n "$wt" ]] || continue
    cands+=("$wt/.claude")
  done < <(git -C "$repo_root" worktree list --porcelain -z 2>/dev/null | incidents_roots_from_porcelain)
  incidents_dedupe_existing_dirs "${cands[@]}"
}
