#!/usr/bin/env bash
# S6 pair run (planning rehearsal form; the work phase re-uses it). Not wired into any runner.
# usage: pair-run.sh <base-root> <branch-root> <out-dir> suite...      (suite paths are repo-relative, one run per side, sequential)
#
# PRECONDITIONS (the traps measured in S2 to S5):
#   1. <base-root> is a REAL clone checked out detached at the base SHA, never `git archive`:
#        git clone --local --no-hardlinks --no-checkout <worktree> <base-root> && git -C <base-root> checkout --detach <sha>
#   2. BOTH roots get BOTH links, or a toolchain-gated suite prints a SKIP verdict and exercises only its always-on half:
#        ln -s <worktree>/node_modules <root>/node_modules
#        ln -s <worktree>/apps/web-platform/node_modules <root>/apps/web-platform/node_modules
#   3. Run it from a shell that is NOT inside a PID namespace only for the UNMUTATED pair run. A MUTANT of any line in a suite that
#      lists a signalling site (python3 plugins/soleur/scripts/scan-ancestor-signal-helpers.py --list <suite>: in this slice
#      workspaces-boot-unlock, workspaces-luks-provision and ci-deploy) runs only through
#        bash scripts/soleur-sandbox.sh run-isolated "$SBX" -- <cmd>      under   timeout -k 5 <secs>
#      and exit 125 with RUN_IN_PID_NAMESPACE_REFUSED means: do not run it, list the row UNVERIFIED-NO-NAMESPACE.
# Each suite runs under ulimit -v 6000000 (no suite of this slice starts vitest: ci-deploy.test.sh names it only in a docker mock),
# TMPDIR=/var/tmp, nice -n 10, timeout 600 s unless PAIR_TIMEOUTS ("path=secs path=secs") names the suite. The infra runner's own bounds
# are the reference (apps/web-platform/infra/run-registered-suites.sh, _SUITE_BOUNDS: workspaces-boot-unlock and workspaces-luks-provision 900 s,
# its default 360 s); a suite that runs ~250 s serial on a quiet box needs the override on a loaded host. Compare rc and the last non-empty line; a timeout on both sides is inconclusive,
# never identical. Count the SKIP lines on both sides: an identical SKIP is not evidence for the arm it skipped.
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
assert_fixture_dir "$BASE"
assert_fixture_dir "$BR"
assert_fixture_dir "$OUT"
mkdir -p "$OUT"
for s in "$@"; do
  id=$(echo "$s" | tr '/' '_')
  for side in base branch; do
    root=$BASE; [ $side = branch ] && root=$BR
    cap=600; for kv in ${PAIR_TIMEOUTS-}; do [ "${kv%%=*}" = "$s" ] && cap="${kv##*=}"; done
    ( cd "$root" && ulimit -v 6000000 && TMPDIR=/var/tmp nice -n 10 timeout -k 5 "$cap" bash "$s" > "$OUT/$id.$side.log" 2>&1; echo $? > "$OUT/$id.$side.rc" )
  done
  b=$(cat "$OUT/$id.base.rc"); r=$(cat "$OUT/$id.branch.rc")
  bl=$(grep -v '^[[:space:]]*$' "$OUT/$id.base.log" | tail -1 | cut -c1-120); rl=$(grep -v '^[[:space:]]*$' "$OUT/$id.branch.log" | tail -1 | cut -c1-120)
  bs=$(grep -ci 'skip' "$OUT/$id.base.log"); rs=$(grep -ci 'skip' "$OUT/$id.branch.log")
  echo "PAIR $s base_rc=$b branch_rc=$r same_last=$([ "$bl" = "$rl" ] && echo yes || echo NO) skip_lines=$bs/$rs | $rl"
done
echo PAIR-DONE
