#!/usr/bin/env bash
# soleur-sandbox.sh — thin CLI over soleur_sandbox_new / soleur_sandbox_rm
# (scripts/lib/scratch-root.sh). For agent seats that need a mutable copy of the tree.
#
#   SBX=$(bash scripts/soleur-sandbox.sh new <label> [--link-node-modules])   # prints the path
#   bash scripts/soleur-sandbox.sh rm "$SBX"                                  # takes the PATH
#
# `rm` takes the path (not a label/handle) because cleanup runs in a different Bash call than
# the allocation; the path is the only state that survives. See
# plugins/soleur/skills/work/references/work-scratch-sandboxes.md.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/scratch-root.sh
source "$HERE/lib/scratch-root.sh" || { echo "soleur-sandbox: cannot source scratch-root.sh" >&2; exit 2; }

usage() {
  echo "usage: soleur-sandbox.sh new <label> [--link-node-modules] | rm <path>" >&2
}

case "${1:-}" in
  new) shift; [[ $# -ge 1 ]] || { usage; exit 2; }; soleur_sandbox_new "$@" ;;
  rm)  shift; [[ $# -eq 1 ]] || { usage; exit 2; }; soleur_sandbox_rm "$1" ;;
  *)   usage; exit 2 ;;
esac
