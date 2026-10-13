#!/usr/bin/env bash
# S5 pair run (planning rehearsal form; the work phase may re-use it). Not wired into any runner.
# usage: pair-run.sh <base-root> <branch-root> <out-dir> suite...
#
# PRECONDITIONS (the two traps measured at planning):
#   1. <base-root> is a REAL clone checked out detached at the base SHA, never `git archive`:
#        git clone --local --no-hardlinks --no-checkout <worktree> <base-root> && git -C <base-root> checkout --detach <sha>
#   2. BOTH roots get BOTH links, or boundary.test.sh and bite-proof.test.sh print "SKIPPED at the toolchain probe" and exercise
#      only their always-on half (15 and 78 assertions instead of 37 and 96):
#        ln -s <worktree>/node_modules <root>/node_modules
#        ln -s <worktree>/apps/web-platform/node_modules <root>/apps/web-platform/node_modules
# Each suite runs sequentially under ulimit -v 6000000 (none of the 13 starts vitest), TMPDIR=/var/tmp, timeout 600 s.
# Compare rc and the last non-empty line; a timeout on both sides is inconclusive, never identical.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
BASE=$1; BR=$2; OUT=$3; shift 3
assert_fixture_dir "$OUT"
mkdir -p "$OUT"
for s in "$@"; do
  id=$(echo "$s" | tr '/' '_')
  for side in base branch; do
    root=$BASE; [ $side = branch ] && root=$BR
    ( cd "$root" && ulimit -v 6000000 && TMPDIR=/var/tmp timeout 600 bash "$s" > "$OUT/$id.$side.log" 2>&1; echo $? > "$OUT/$id.$side.rc" )
  done
  b=$(cat "$OUT/$id.base.rc"); r=$(cat "$OUT/$id.branch.rc")
  bl=$(grep -v '^[[:space:]]*$' "$OUT/$id.base.log" | tail -1 | cut -c1-120); rl=$(grep -v '^[[:space:]]*$' "$OUT/$id.branch.log" | tail -1 | cut -c1-120)
  echo "PAIR $s base_rc=$b branch_rc=$r same_last=$([ "$bl" = "$rl" ] && echo yes || echo NO) | $rl"
done
echo PAIR-DONE
