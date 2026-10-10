#!/usr/bin/env bash
# soleur-sandbox.sh — thin CLI over soleur_sandbox_new / soleur_sandbox_rm
# (scripts/lib/scratch-root.sh). For agent seats that need a mutable copy of the tree.
#
#   SBX=$(bash scripts/soleur-sandbox.sh new <label> [--link-node-modules])   # prints the path
#   bash scripts/soleur-sandbox.sh rm "$SBX"                                  # takes the PATH
#   bash scripts/soleur-sandbox.sh run-isolated "$SBX" -- <cmd> [args...]     # cmd as PID 1 of a PID namespace
#
# `rm` takes the path (not a label/handle) because cleanup runs in a different Bash call than
# the allocation; the path is the only state that survives. See
# plugins/soleur/skills/work/references/work-scratch-sandboxes.md.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/scratch-root.sh
source "$HERE/lib/scratch-root.sh" || { echo "soleur-sandbox: cannot source scratch-root.sh" >&2; exit 2; }

usage() {
  echo "usage: soleur-sandbox.sh new <label> [--link-node-modules] | rm <path> | run-isolated <path> -- <cmd> [args...]" >&2
}

# run-isolated <sandbox-path> -- <cmd> [args...]: refuse (rc 2) unless the path is an allocated sandbox,
# then exec the PID-namespace helper with the sandbox as cwd. The helper comes from the live tree
# (HERE), never from the sandbox copy.
soleur_run_isolated() {
  local p="$1" real helper; shift
  while [[ "$p" == */ && "$p" != / ]]; do p="${p%/}"; done
  [[ "$p" == /* ]] || { echo "run-isolated: sandbox path must be absolute: $p" >&2; return 2; }
  real="$(cd -P -- "$p" 2>/dev/null && pwd -P)" || { echo "run-isolated: not a directory: $p" >&2; return 2; }
  [[ "$real" == "$p" ]] || { echo "run-isolated: path has a symlink component (resolves to $real): $p" >&2; return 2; }
  case "${p##*/}" in soleur-sbx.?*) ;; *) echo "run-isolated: not an allocated sandbox name (soleur-sbx.<label>.<id>): $p" >&2; return 2 ;; esac
  (cd -P -- "$p" && [[ -f .soleur-owned && ! -L .soleur-owned && -O . ]]) \
    || { echo "run-isolated: no valid .soleur-owned marker, or the directory is not owned by this user: $p" >&2; return 2; }
  helper="$HERE/../plugins/soleur/scripts/run-in-pid-namespace.sh"
  [[ -f "$helper" && -x "$helper" ]] || { echo "run-isolated: helper missing or not executable: $helper" >&2; return 2; }
  cd -P -- "$p" || return 2
  exec "$helper" -- "$@"
}

case "${1:-}" in
  new) shift; [[ $# -ge 1 ]] || { usage; exit 2; }; soleur_sandbox_new "$@" ;;
  rm)  shift; [[ $# -eq 1 ]] || { usage; exit 2; }; soleur_sandbox_rm "$1" ;;
  run-isolated)
    shift
    [[ $# -ge 3 && "${2:-}" == "--" ]] || { usage; exit 2; }
    soleur_run_isolated "$1" "${@:3}"; exit $? ;;
  *)   usage; exit 2 ;;
esac
