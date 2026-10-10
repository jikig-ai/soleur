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

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/lib/scratch-root.sh
source "$HERE/lib/scratch-root.sh" || { echo "soleur-sandbox: cannot source scratch-root.sh" >&2; exit 2; }

usage() {
  echo "usage: soleur-sandbox.sh new <label> [--link-node-modules] | rm <path> | run-isolated <path> -- <cmd> [args...]" >&2
}

# run-isolated <sandbox-path> -- <cmd> [args...]: refuse (rc 2) unless the path is an allocated sandbox,
# then exec the PID-namespace helper with the sandbox as cwd. The helper comes from the live tree
# (HERE, physical), never from the sandbox copy. The conjuncts mirror soleur_sandbox_rm (marker content,
# directly under a scratch base, owner) because the lib that holds them is not shared with this verb; the
# one extra is the symlink-component refusal. The namespace bounds signals, not writes, so this check is
# working-directory hygiene (never run a mutant from the live tree), not part of the isolation property.
soleur_run_isolated() {
  local p="$1" helper cand rb ok=0; shift
  while [[ "$p" == */ && "$p" != / ]]; do p="${p%/}"; done
  [[ "$p" == /* ]] || { echo "run-isolated: sandbox path must be absolute: $p" >&2; return 2; }
  case "${p##*/}" in soleur-sbx.?*) ;; *) echo "run-isolated: not an allocated sandbox name (soleur-sbx.<label>.<id>): $p" >&2; return 2 ;; esac
  cd -P -- "$p" 2>/dev/null || { echo "run-isolated: not a directory: $p" >&2; return 2; }
  [[ "$PWD" == "$p" ]] || { echo "run-isolated: path has a symlink component (resolves to $PWD): $p" >&2; return 2; }
  if [[ ! -f .soleur-owned || -L .soleur-owned || ! -O . ]] \
     || ! grep -Eq '^pid=[0-9]+$' .soleur-owned 2>/dev/null \
     || ! grep -Fxq 'schema=1' .soleur-owned 2>/dev/null \
     || ! grep -Eq '^ns=.+$' .soleur-owned 2>/dev/null; then
    echo "run-isolated: no valid .soleur-owned marker (pid=, schema=1, ns=), or the directory is not owned by this user: $p" >&2; return 2
  fi
  while IFS= read -r cand; do
    rb="$(cd -P "$cand" 2>/dev/null && pwd -P)" || continue
    [[ "${p%/*}" == "$rb" ]] && { ok=1; break; }
  done < <(_soleur_sandbox_bases)
  [[ "$ok" == 1 ]] || { echo "run-isolated: not directly under a scratch base: $p" >&2; return 2; }
  helper="$HERE/../plugins/soleur/scripts/run-in-pid-namespace.sh"
  [[ -f "$helper" && -x "$helper" ]] || { echo "run-isolated: helper missing or not executable: $helper" >&2; return 2; }
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
